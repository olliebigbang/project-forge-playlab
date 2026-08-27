from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import sys
import time
import unicodedata
import uuid
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from PIL import Image, ImageOps

POSTPROCESS_DIRECTORY = Path(__file__).resolve().parents[1] / "postprocess"
sys.path.insert(0, str(POSTPROCESS_DIRECTORY))
from process_sprite import SpritePostprocessError, process_sprite  # noqa: E402


SYSTEM_POSITIVE = (
    "one isolated fantasy game prop, side view, facing right, complete object visible, "
    "clear handle or holdable region, clear functional front or effect-emission region, "
    "no person, no hand, no character, no text, no watermark, no UI, no environment scene, "
    "flat high-contrast solid chroma key magenta background, readable silhouette, "
    "handcrafted fantasy toy aesthetic, centered object, generous empty margin"
)
SYSTEM_NEGATIVE = (
    "portrait, human, face, hands, fingers, character holding object, person, weapon sheet, "
    "multiple views, multiple objects, inventory grid, text, label, letters, logo, watermark, "
    "UI, scenery, room, landscape, environment, pedestal, cropped object, cut off, border"
)
FIREARM_SYSTEM_POSITIVE = (
    "one isolated recognisable firearm game sprite, strict flat side view facing right, "
    "complete firearm visible, authentic model-defining silhouette and proportions, "
    "separate stock receiver grip magazine handguard barrel and muzzle structures, "
    "crisp handcrafted pixel art, limited dark metal palette, hard pixel clusters, "
    "no person, no hand, no character, no text, no watermark, no UI, no scene, "
    "flat high-contrast solid chroma key magenta background, generous empty margin"
)
FIREARM_SYSTEM_NEGATIVE = (
    "generic gun, block scaffold, rectangular placeholder, toy gun, fantasy redesign, sci-fi redesign, "
    "wrong stock, wrong magazine position, merged grip and magazine, portrait, human, hands, fingers, "
    "character holding object, weapon sheet, multiple views, multiple objects, text, label, letters, "
    "logo, watermark, UI, scenery, cropped object, cut off, photorealistic scene, smooth 3D render"
)
PROMPT_POLICY_VERSION = "forge-open-identity-v3"
REQUIRED_MANIFEST_FIELDS = {
    "case_id",
    "prompt",
    "seed",
    "workflow_file",
    "workflow_hash",
    "selected_comfyui_install",
    "checkpoint",
    "control_type",
    "control_strength",
    "generation_seconds",
    "postprocess_seconds",
    "raw_dimensions",
    "processed_dimensions",
    "alpha_coverage",
    "opaque_bounds",
    "status",
    "failure_reason",
}


class BridgeError(RuntimeError):
    pass


def sanitize_model_prompt(value: str, maximum: int = 1400) -> str:
    """Create a bounded CLIP-facing projection without changing manifest evidence."""
    normalized = unicodedata.normalize("NFC", value)
    projected: list[str] = []
    for character in normalized:
        codepoint = ord(character)
        if character in "\r\n\t":
            projected.append(" ")
        elif codepoint < 32 or 127 <= codepoint <= 159:
            continue
        elif character in "()[]{}<>:":
            projected.append(" ")
        else:
            projected.append(character)
    safe = " ".join("".join(projected).split()).strip()
    if not safe:
        raise BridgeError("GENERATION_PROMPT_EMPTY")
    if len(safe) > maximum:
        safe = safe[:maximum].rstrip()
    return safe


def compose_positive_prompt(model_generation_prompt: str, visual_kind: str = "generic") -> str:
    system_prompt = FIREARM_SYSTEM_POSITIVE if visual_kind == "firearm" else SYSTEM_POSITIVE
    return f"{model_generation_prompt}. {system_prompt}"


def compose_negative_prompt(visual_kind: str = "generic") -> str:
    return FIREARM_SYSTEM_NEGATIVE if visual_kind == "firearm" else SYSTEM_NEGATIVE


def _expand(value: str) -> str:
    return os.path.expandvars(value)


def validate_api_base(value: str) -> str:
    """Return a canonical loopback URL or reject non-local/misleading forms."""
    candidate = value.strip()
    try:
        parsed = urlsplit(candidate)
        port = parsed.port
    except ValueError as exc:
        raise BridgeError("API_BASE_MUST_USE_127_0_0_1") from exc
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
        or port is None
        or not 1 <= port <= 65535
        or parsed.netloc != f"127.0.0.1:{port}"
    ):
        raise BridgeError("API_BASE_MUST_USE_127_0_0_1")
    return f"http://127.0.0.1:{port}"


def load_config(path: Path) -> dict[str, Any]:
    config_path = path.resolve()
    data = json.loads(config_path.read_text(encoding="utf-8"))
    base = config_path.parent
    for key in (
        "comfyui_install",
        "python_executable",
        "workflow_file",
        "bridge_script",
        "postprocess_script",
        "input_directory",
        "comfy_output_directory",
        "output_root",
    ):
        value = _expand(str(data.get(key, "")))
        if value and not value.startswith("${"):
            candidate = Path(value)
            data[key] = str((base / candidate).resolve() if not candidate.is_absolute() else candidate.resolve())
        else:
            data[key] = value
    data["api_base"] = validate_api_base(str(data.get("api_base", "")))
    return data


def _json_request(base: str, route: str, payload: dict[str, Any] | None = None, timeout: float = 10.0) -> Any:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        base + route,
        data=body,
        headers={"Content-Type": "application/json"} if body is not None else {},
        method="POST" if body is not None else "GET",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise BridgeError(f"COMFYUI_HTTP_{exc.code}:{details[:800]}") from exc
    except (URLError, TimeoutError) as exc:
        raise BridgeError(f"COMFYUI_UNAVAILABLE:{exc}") from exc


def health_check(config: dict[str, Any]) -> dict[str, Any]:
    stats = _json_request(config["api_base"], "/system_stats", timeout=5.0)
    system = stats.get("system", {})
    argv = system.get("argv", [])
    listen_ok = "127.0.0.1" in argv
    return {
        "ok": bool(system) and listen_ok,
        "listen_is_loopback": listen_ok,
        "comfyui_version": system.get("comfyui_version", "unknown"),
        "python_version": system.get("python_version", "unknown"),
        "devices": stats.get("devices", []),
    }


def _set_binding(graph: dict[str, Any], binding: list[str], value: Any) -> None:
    cursor: Any = graph
    for key in binding[:-1]:
        cursor = cursor[key]
    cursor[binding[-1]] = value


def inject_workflow(
    workflow: dict[str, Any],
    *,
    checkpoint: str,
    positive_prompt: str,
    negative_prompt: str,
    input_image: str,
    seed: int,
    denoise: float,
    output_prefix: str,
) -> dict[str, Any]:
    graph = copy.deepcopy(workflow)
    metadata = graph.pop("_forge", None)
    if not isinstance(metadata, dict) or not isinstance(metadata.get("bindings"), dict):
        raise BridgeError("WORKFLOW_BINDINGS_MISSING")
    values = {
        "checkpoint": checkpoint,
        "positive_prompt": positive_prompt,
        "negative_prompt": negative_prompt,
        "optional_sketch_png": input_image,
        "seed": int(seed),
        "denoise": float(denoise),
        "output_subfolder": output_prefix,
    }
    for name, value in values.items():
        binding = metadata["bindings"].get(name)
        if not isinstance(binding, list):
            raise BridgeError(f"WORKFLOW_BINDING_MISSING:{name}")
        _set_binding(graph, binding, value)
    return graph


def _prepare_input(source: Path | None, target: Path, size: tuple[int, int], background: tuple[int, int, int]) -> bool:
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGB", size, background)
    if source is None:
        canvas.save(target, format="PNG")
        return False
    try:
        with Image.open(source) as opened:
            rgba = opened.convert("RGBA")
            rgba.load()
    except (OSError, ValueError) as exc:
        raise BridgeError("INVALID_SKETCH_PNG") from exc
    # Player sketches are commonly exported as black ink on transparent pixels.
    # Converting RGBA straight to L treats transparent RGB=0 as opaque black and
    # destroys the silhouette. Composite on white before grayscale extraction.
    white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
    sketch = Image.alpha_composite(white, rgba).convert("L")
    sketch = ImageOps.contain(sketch, (int(size[0] * 0.82), int(size[1] * 0.82)), Image.Resampling.LANCZOS)
    ink = ImageOps.invert(sketch).point(lambda value: 255 if value > 32 else 0)
    black = Image.new("RGB", sketch.size, (20, 20, 24))
    offset = ((size[0] - sketch.width) // 2, (size[1] - sketch.height) // 2)
    canvas.paste(black, offset, ink)
    canvas.save(target, format="PNG")
    return True


def _cancel(config: dict[str, Any], prompt_id: str) -> None:
    for route, payload in (("/queue", {"delete": [prompt_id]}), ("/interrupt", {"prompt_id": prompt_id})):
        try:
            _json_request(config["api_base"], route, payload, timeout=3.0)
        except BridgeError:
            pass


def _submit_and_wait(config: dict[str, Any], graph: dict[str, Any], timeout_seconds: float) -> tuple[str, dict[str, Any]]:
    client_id = str(uuid.uuid4())
    response = _json_request(config["api_base"], "/prompt", {"prompt": graph, "client_id": client_id}, timeout=15.0)
    prompt_id = str(response.get("prompt_id", ""))
    if not prompt_id:
        raise BridgeError("PROMPT_ID_MISSING")
    started = time.monotonic()
    interval = float(config.get("poll_interval_seconds", 0.5))
    while time.monotonic() - started < timeout_seconds:
        history = _json_request(config["api_base"], f"/history/{prompt_id}", timeout=10.0)
        if prompt_id in history:
            entry = history[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error" or not status.get("completed", False):
                messages = status.get("messages", [])
                raise BridgeError(f"COMFYUI_EXECUTION_FAILED:{json.dumps(messages, ensure_ascii=False)[:1200]}")
            return prompt_id, entry
        time.sleep(interval)
    _cancel(config, prompt_id)
    raise BridgeError(f"COMFYUI_TIMEOUT:{timeout_seconds}")


def _output_path(config: dict[str, Any], entry: dict[str, Any]) -> Path:
    outputs = entry.get("outputs", {})
    save_output = outputs.get("8", {})
    images = save_output.get("images", [])
    if len(images) != 1:
        raise BridgeError(f"EXPECTED_ONE_OUTPUT_IMAGE:{len(images)}")
    image = images[0]
    root = Path(config["comfy_output_directory"]).resolve()
    candidate = (root / str(image.get("subfolder", "")) / str(image.get("filename", ""))).resolve()
    if root not in candidate.parents or not candidate.is_file():
        raise BridgeError("COMFYUI_OUTPUT_FILE_INVALID")
    return candidate


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _load_visual_structure_brief(path: Path | None) -> tuple[dict[str, Any], str]:
    if path is None:
        return {}, ""
    resolved = path.resolve()
    if not resolved.is_file() or resolved.stat().st_size > 65536:
        raise BridgeError("VISUAL_STRUCTURE_BRIEF_FILE_INVALID")
    raw = resolved.read_bytes()
    parsed = json.loads(raw.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise BridgeError("VISUAL_STRUCTURE_BRIEF_JSON_INVALID")
    common_valid = (
        parsed.get("automatic") is True
        and parsed.get("player_confirmation_required") is False
        and isinstance(parsed.get("axes"), dict)
        and isinstance(parsed.get("required_roles"), list)
        and bool(parsed.get("required_roles"))
    )
    mechanism_valid = (
        parsed.get("schema") == "forge-mechanism-visual-brief-v1"
        and parsed.get("source") == "ai_mechanism_axes_visual_compiler_v1"
    )
    firearm_valid = (
        parsed.get("schema") == "forge-firearm-visual-brief-v1"
        and isinstance(parsed.get("source"), str)
        and bool(parsed.get("source"))
        and parsed.get("scaffold_presentable") is False
        and parsed.get("finished_art_requires_external_generator") is True
    )
    if not common_valid or not (mechanism_valid or firearm_valid):
        raise BridgeError("VISUAL_STRUCTURE_BRIEF_CONTRACT_INVALID")
    return parsed, hashlib.sha256(raw).hexdigest()


def generate(
    config_path: Path,
    *,
    case_id: str,
    run_id: str,
    prompt: str,
    generation_prompt: str,
    seed: int,
    control_strength: float,
    sketch_path: Path | None,
    prompt_policy_version: str = PROMPT_POLICY_VERSION,
    visual_structure_brief_path: Path | None = None,
    visual_retry_count: int = 0,
) -> Path:
    # Kept explicit in every manifest so a later prompt-policy edit cannot be
    # confused with the bounded visual evidence already delivered by this Spike.
    policy_prefix = "forge-open-identity-v"
    policy_suffix = prompt_policy_version.removeprefix(policy_prefix)
    if not prompt_policy_version.startswith(policy_prefix) or not policy_suffix.isdigit():
        raise BridgeError("PROMPT_POLICY_VERSION_INVALID")
    if not prompt.strip():
        raise BridgeError("PLAYER_IDENTITY_PROMPT_EMPTY")
    if len(prompt) > 1200:
        raise BridgeError("PLAYER_IDENTITY_PROMPT_TOO_LONG")
    if visual_retry_count < 0 or visual_retry_count > 2:
        raise BridgeError("VISUAL_RETRY_COUNT_INVALID")
    model_generation_prompt = sanitize_model_prompt(generation_prompt)
    visual_structure_brief, visual_structure_brief_sha256 = _load_visual_structure_brief(visual_structure_brief_path)
    visual_kind = (
        "firearm"
        if visual_structure_brief.get("schema") == "forge-firearm-visual-brief-v1"
        else "mechanism" if visual_structure_brief else "generic"
    )
    config = load_config(config_path)
    workflow_path = Path(config["workflow_file"])
    workflow_bytes = workflow_path.read_bytes()
    workflow = json.loads(workflow_bytes.decode("utf-8"))
    workflow_hash = hashlib.sha256(workflow_bytes).hexdigest()
    safe_case = "".join(char for char in case_id.lower() if char.isalnum() or char in "_-")
    safe_run = "".join(char for char in run_id.lower() if char.isalnum() or char in "_-")
    if not safe_case or not safe_run:
        raise BridgeError("INVALID_CASE_OR_RUN_ID")
    output_root = Path(config["output_root"]).resolve()
    final_directory = output_root / safe_case / safe_run
    if final_directory.exists():
        raise BridgeError(f"FINAL_DIRECTORY_ALREADY_EXISTS:{final_directory}")
    temp_directory = output_root / ".tmp" / f"{safe_case}-{safe_run}-{uuid.uuid4().hex}"
    temp_directory.mkdir(parents=True, exist_ok=False)
    generation_started = time.perf_counter()
    manifest: dict[str, Any] = {
        "case_id": safe_case,
        "prompt": prompt,
        "player_identity_text": prompt,
        "generation_prompt": model_generation_prompt,
        "generation_prompt_sha256": hashlib.sha256(model_generation_prompt.encode("utf-8")).hexdigest(),
        "prompt_policy_version": prompt_policy_version,
        "seed": int(seed),
        "workflow_file": workflow_path.name,
        "workflow_hash": workflow_hash,
        "selected_comfyui_install": config.get("selected_install_label", "unknown"),
        "checkpoint": config["checkpoint"],
        "control_type": "none",
        "control_strength": float(control_strength),
        "generation_seconds": 0.0,
        "postprocess_seconds": 0.0,
        "raw_dimensions": [],
        "processed_dimensions": [],
        "alpha_coverage": 0.0,
        "opaque_bounds": [],
        "status": "failed",
        "failure_reason": "UNFINISHED",
        "prompt_id": "",
        "run_id": safe_run,
        "request_id": uuid.uuid4().hex,
        "retry_count": int(visual_retry_count),
        "visual_structure_brief_sha256": visual_structure_brief_sha256,
        "visual_kind": visual_kind,
        "mechanism_visual_gate": "pending_godot_alpha_and_rig_evaluation" if visual_structure_brief else "not_requested",
        "generation_size": [int(config["generation_width"]), int(config["generation_height"])],
    }
    log_lines = [
        f"case_id={safe_case}",
        f"run_id={safe_run}",
        f"seed={seed}",
        f"prompt_policy_version={prompt_policy_version}",
        f"retry_count={visual_retry_count}",
    ]
    try:
        if visual_structure_brief:
            _write_json(temp_directory / "visual_structure_brief.json", visual_structure_brief)
        health = health_check(config)
        if not health.get("ok", False):
            raise BridgeError("COMFYUI_HEALTH_CHECK_FAILED")
        background = tuple(int(value) for value in config.get("background_rgb", [255, 0, 255]))
        input_relative = Path("forge") / safe_case / safe_run / f"{uuid.uuid4().hex}.png"
        input_path = Path(config["input_directory"]) / input_relative
        has_sketch = _prepare_input(
            sketch_path,
            input_path,
            (int(config["generation_width"]), int(config["generation_height"])),
            background,
        )
        shutil.copy2(input_path, temp_directory / "input_sketch.png")
        manifest["control_type"] = "img2img_sketch_fallback" if has_sketch else "none"
        denoise = 1.0 if not has_sketch else max(0.45, min(0.82, 1.0 - float(control_strength) * 0.62))
        manifest["img2img_denoise"] = round(denoise, 4)
        # Identity evidence comes first so the behavior/composition scaffold cannot
        # silently replace the player's object with a familiar weapon archetype.
        positive = compose_positive_prompt(model_generation_prompt, visual_kind)
        output_prefix = f"ForgeSpike/{safe_case}/{safe_run}/raw"
        graph = inject_workflow(
            workflow,
            checkpoint=str(config["checkpoint"]),
            positive_prompt=positive,
            negative_prompt=compose_negative_prompt(visual_kind),
            input_image=input_relative.as_posix(),
            seed=seed,
            denoise=denoise,
            output_prefix=output_prefix,
        )
        prompt_id, entry = _submit_and_wait(config, graph, float(config.get("timeout_seconds", 120)))
        manifest["prompt_id"] = prompt_id
        manifest["generation_seconds"] = round(time.perf_counter() - generation_started, 3)
        raw_source = _output_path(config, entry)
        raw_target = temp_directory / "raw.png"
        shutil.copy2(raw_source, raw_target)
        postprocess_result = process_sprite(
            raw_target,
            temp_directory / "processed_sprite.png",
            temp_directory / "alpha_mask.png",
            expected_background=background,
            sprite_size=int(config.get("sprite_size", 96)),
            max_colors=int(config.get("max_colors", 32)),
            outline=bool(config.get("outline", True)),
        )
        manifest.update(postprocess_result)
        manifest["status"] = "success"
        manifest["failure_reason"] = ""
        _write_json(
            temp_directory / "anchors.json",
            {
                "status": "pending_godot_resolution",
                "source": "WeaponBlueprint grip profile + processed_sprite alpha + Godot AnchorResolver local search",
            },
        )
        log_lines.extend((f"prompt_id={prompt_id}", "status=success"))
    except (BridgeError, SpritePostprocessError, OSError, ValueError, json.JSONDecodeError) as exc:
        manifest["generation_seconds"] = round(time.perf_counter() - generation_started, 3)
        manifest["status"] = "failed"
        manifest["failure_reason"] = str(exc)
        log_lines.extend(("status=failed", f"failure_reason={exc}"))
    finally:
        log_lines.extend(
            (
                f"control_type={manifest['control_type']}",
                f"control_strength={manifest['control_strength']}",
                f"generation_seconds={manifest['generation_seconds']}",
                f"postprocess_seconds={manifest['postprocess_seconds']}",
            )
        )
        missing = sorted(REQUIRED_MANIFEST_FIELDS - set(manifest))
        if missing:
            manifest["status"] = "failed"
            manifest["failure_reason"] = f"MANIFEST_FIELDS_MISSING:{','.join(missing)}"
        _write_json(temp_directory / "manifest.json", manifest)
        (temp_directory / "generation.log").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
        final_directory.parent.mkdir(parents=True, exist_ok=True)
        os.replace(temp_directory, final_directory)
    if manifest["status"] != "success":
        raise BridgeError(f"GENERATION_FAILED:{manifest['failure_reason']}:{final_directory}")
    return final_directory


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local-only Forge to ComfyUI bridge.")
    parser.add_argument("--config", required=True, type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("health")
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--case-id", required=True)
    generate_parser.add_argument("--run-id", required=True)
    generate_parser.add_argument("--prompt", required=True)
    generate_parser.add_argument("--generation-prompt", required=True)
    generate_parser.add_argument("--prompt-policy-version", default=PROMPT_POLICY_VERSION)
    generate_parser.add_argument("--seed", type=int, required=True)
    generate_parser.add_argument("--control-strength", type=float, default=0.45)
    generate_parser.add_argument("--sketch", type=Path)
    generate_parser.add_argument("--visual-structure-brief", type=Path)
    generate_parser.add_argument("--visual-retry-count", type=int, default=0)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        if args.command == "health":
            print(json.dumps(health_check(load_config(args.config)), ensure_ascii=False, indent=2))
            return 0
        result = generate(
            args.config,
            case_id=args.case_id,
            run_id=args.run_id,
            prompt=args.prompt,
            generation_prompt=args.generation_prompt,
            prompt_policy_version=args.prompt_policy_version,
            seed=args.seed,
            control_strength=args.control_strength,
            sketch_path=args.sketch,
            visual_structure_brief_path=args.visual_structure_brief,
            visual_retry_count=args.visual_retry_count,
        )
        print(json.dumps({"status": "success", "output_directory": str(result)}, ensure_ascii=False))
        return 0
    except BridgeError as exc:
        print(json.dumps({"status": "failed", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
