from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any

import psutil
from PIL import Image


COMFYUI_TOOLS_ROOT = Path(__file__).resolve().parents[2]
LEGACY_BRIDGE_DIRECTORY = COMFYUI_TOOLS_ROOT / "bridge"
sys.path.insert(0, str(LEGACY_BRIDGE_DIRECTORY))
import forge_comfy_bridge as legacy_bridge  # noqa: E402


PROFILE_DIRECTORY = COMFYUI_TOOLS_ROOT / "config" / "profiles"
PROFILE_CONTRACT = "forge-comfy-profile-v1"
WORKFLOW_CONTRACT = "forge-flux2-klein-4b-v1"
PROMPT_POLICY_VERSION = "forge-flux2-static-identity-v1"
GENERIC_POSITIVE = (
    "one isolated physical fantasy game prop, side view or slight three-quarter side view, "
    "facing right, complete object fully visible, centered with generous empty margin, "
    "flat high-contrast solid chroma key magenta background, readable silhouette, "
    "handcrafted fantasy toy aesthetic"
)
GENERIC_NEGATIVE = (
    "portrait, human, person, face, hand, hands, fingers, character holding object, text, "
    "label, logo, watermark, user interface, inventory grid, weapon sheet, multiple views, "
    "multiple objects, scenery, room, environment, pedestal, cropped object, cut off object"
)
EXPECTED_MODEL_NAMES = {
    "diffusion_model": "flux-2-klein-4b-fp8.safetensors",
    "text_encoder": "qwen_3_4b.safetensors",
    "vae": "flux2-vae.safetensors",
}
EXPECTED_MODEL_HASHES = {
    "diffusion_model": "97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6",
    "text_encoder": "6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a",
    "vae": "d64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5",
}
EXPECTED_COMFYUI_COMMIT = "b1693ecba9f5b65f8c80ab36b195ab963ec92413"
EXPECTED_POSTPROCESSOR_HASH = "f748c8e61dfd022d351d84c57c2d68b50b3dc39685403c7af20cc0402eebc0e9"


class Flux2BridgeError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_profile_path(profile_file: Path, value: str) -> Path:
    expanded = os.path.expandvars(value)
    candidate = Path(expanded)
    if not candidate.is_absolute():
        candidate = profile_file.parent / candidate
    return candidate.resolve()


def resolve_profile(profile: str | Path) -> dict[str, Any]:
    candidate = Path(profile)
    if candidate.suffix.lower() != ".json" and len(candidate.parts) == 1:
        candidate = PROFILE_DIRECTORY / f"{candidate.name}.json"
    candidate = candidate.resolve()
    if candidate.parent != PROFILE_DIRECTORY.resolve() and PROFILE_DIRECTORY.resolve() not in candidate.parents:
        raise Flux2BridgeError("PROFILE_PATH_OUTSIDE_PROFILE_DIRECTORY")
    try:
        data = json.loads(candidate.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise Flux2BridgeError(f"PROFILE_READ_FAILED:{candidate.name}") from exc
    if data.get("profile_contract") != PROFILE_CONTRACT:
        raise Flux2BridgeError("PROFILE_CONTRACT_INVALID")
    if data.get("profile_id") != candidate.stem:
        raise Flux2BridgeError("PROFILE_ID_FILENAME_MISMATCH")
    data["profile_file"] = str(candidate)
    data["api_base"] = legacy_bridge.validate_api_base(str(data.get("api_base", "")))
    for key in (
        "runtime_root",
        "comfyui_root",
        "python_executable",
        "t2i_workflow",
        "edit_workflow",
        "comfy_output_directory",
        "comfy_input_directory",
        "output_root",
        "postprocessor",
    ):
        if key in data:
            data[key] = str(_resolve_profile_path(candidate, str(data[key])))
    if data["profile_id"] == "flux2_klein_4b":
        if data.get("workflow_contract_version") != WORKFLOW_CONTRACT:
            raise Flux2BridgeError("WORKFLOW_CONTRACT_INVALID")
        generation = data.get("generation", {})
        expected = {"width": 512, "height": 512, "batch_size": 1, "steps": 4, "guidance": 1.0, "concurrency": 1}
        for key, value in expected.items():
            if generation.get(key) != value:
                raise Flux2BridgeError(f"PROFILE_GENERATION_DEFAULT_INVALID:{key}")
        if generation.get("sampler") != "euler":
            raise Flux2BridgeError("PROFILE_SAMPLER_INVALID")
        if data.get("model_filenames") != EXPECTED_MODEL_NAMES:
            raise Flux2BridgeError("PROFILE_MODEL_FILENAMES_INVALID")
        if data.get("model_sha256") != EXPECTED_MODEL_HASHES:
            raise Flux2BridgeError("PROFILE_MODEL_HASHES_INVALID")
        if data.get("comfyui_commit") != EXPECTED_COMFYUI_COMMIT:
            raise Flux2BridgeError("PROFILE_COMFYUI_COMMIT_INVALID")
        postprocessor = Path(str(data.get("postprocessor", "")))
        if not postprocessor.is_file() or sha256_file(postprocessor) != EXPECTED_POSTPROCESSOR_HASH:
            raise Flux2BridgeError("ACTIVE_POSTPROCESSOR_HASH_INVALID")
        if data.get("postprocessor_sha256") != EXPECTED_POSTPROCESSOR_HASH:
            raise Flux2BridgeError("PROFILE_POSTPROCESSOR_HASH_INVALID")
    return data


def _is_path_list(value: Any) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) for item in value)


def _set_path(graph: dict[str, Any], path: list[str], value: Any) -> None:
    cursor: Any = graph
    try:
        for key in path[:-1]:
            cursor = cursor[key]
        cursor[path[-1]] = value
    except (KeyError, TypeError, IndexError) as exc:
        raise Flux2BridgeError(f"WORKFLOW_BINDING_PATH_INVALID:{'/'.join(path)}") from exc


def inject_profile_workflow(workflow: dict[str, Any], values: dict[str, Any]) -> tuple[dict[str, Any], str]:
    graph = copy.deepcopy(workflow)
    forge = graph.pop("_forge", None)
    if not isinstance(forge, dict) or not isinstance(forge.get("bindings"), dict):
        raise Flux2BridgeError("WORKFLOW_BINDINGS_MISSING")
    output_node_id = str(forge.get("output_node_id", ""))
    if not output_node_id or output_node_id not in graph:
        raise Flux2BridgeError("WORKFLOW_OUTPUT_NODE_INVALID")
    for name, value in values.items():
        binding = forge["bindings"].get(name)
        if _is_path_list(binding):
            paths = [binding]
        elif isinstance(binding, list) and binding and all(_is_path_list(path) for path in binding):
            paths = binding
        else:
            raise Flux2BridgeError(f"WORKFLOW_BINDING_MISSING:{name}")
        for path in paths:
            _set_path(graph, path, value)
    return graph, output_node_id


def _assert_workflow_models(workflow: dict[str, Any]) -> None:
    found: dict[str, str] = {}
    for node in workflow.values():
        if not isinstance(node, dict):
            continue
        class_type = node.get("class_type")
        inputs = node.get("inputs", {})
        if class_type == "UNETLoader":
            found["diffusion_model"] = str(inputs.get("unet_name", ""))
        elif class_type == "CLIPLoader":
            found["text_encoder"] = str(inputs.get("clip_name", ""))
            if inputs.get("type") != "flux2":
                raise Flux2BridgeError("WORKFLOW_CLIP_TYPE_NOT_FLUX2")
        elif class_type == "VAELoader":
            found["vae"] = str(inputs.get("vae_name", ""))
    if found != EXPECTED_MODEL_NAMES:
        raise Flux2BridgeError(f"WORKFLOW_MODEL_SET_INVALID:{json.dumps(found, sort_keys=True)}")


def load_workflow(profile: dict[str, Any], mode: str) -> tuple[dict[str, Any], Path, str]:
    key = "t2i_workflow" if mode == "t2i" else "edit_workflow"
    path = Path(profile[key])
    try:
        raw = path.read_bytes()
        workflow = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Flux2BridgeError(f"WORKFLOW_READ_FAILED:{mode}") from exc
    _assert_workflow_models(workflow)
    forge = workflow.get("_forge", {})
    if forge.get("profile") != "flux2_klein_4b" or forge.get("version") != 1:
        raise Flux2BridgeError("WORKFLOW_FORGE_CONTRACT_INVALID")
    if mode == "edit" and forge.get("capabilities", {}).get("quality_gate_passed") is not False:
        raise Flux2BridgeError("EDIT_QUALITY_STATE_INVALID")
    return workflow, path, hashlib.sha256(raw).hexdigest()


def _require_string_list(value: Any, field: str, *, allow_empty: bool = True) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise Flux2BridgeError(f"BLUEPRINT_FIELD_INVALID:{field}")
    if not allow_empty and not value:
        raise Flux2BridgeError(f"BLUEPRINT_FIELD_EMPTY:{field}")
    return [item.strip() for item in value]


def compose_prompts(blueprint: dict[str, Any]) -> tuple[str, str, dict[str, Any]]:
    identity = blueprint.get("identity")
    visual = blueprint.get("visual")
    if not isinstance(identity, dict) or not isinstance(visual, dict):
        raise Flux2BridgeError("BLUEPRINT_IDENTITY_OR_VISUAL_MISSING")
    canonical = str(identity.get("canonical_name_en", "")).strip()
    if not canonical:
        raise Flux2BridgeError("BLUEPRINT_CANONICAL_IDENTITY_MISSING")
    required_parts = _require_string_list(identity.get("required_identity_parts"), "required_identity_parts", allow_empty=False)
    materials = _require_string_list(identity.get("material_hints", []), "material_hints")
    silhouettes = _require_string_list(identity.get("silhouette_hints", []), "silhouette_hints")
    decorations = _require_string_list(identity.get("optional_decorations", []), "optional_decorations")
    prompt_en = str(visual.get("prompt_en", "")).strip()
    negative_en = str(visual.get("negative_prompt_en", "")).strip()
    if not prompt_en or not negative_en:
        raise Flux2BridgeError("BLUEPRINT_VISUAL_PROMPTS_MISSING")
    must_preserve = _require_string_list(visual.get("must_preserve", required_parts), "must_preserve", allow_empty=False)
    replacements = _require_string_list(visual.get("must_not_replace_with", []), "must_not_replace_with")
    all_text = [canonical, prompt_en, negative_en, *required_parts, *materials, *silhouettes, *decorations, *must_preserve, *replacements]
    if any(any(ord(character) > 127 for character in text) for text in all_text):
        raise Flux2BridgeError("NON_ASCII_TEXT_REJECTED_FROM_MODEL_HANDOFF")
    positive_sections = [
        prompt_en.rstrip(". "),
        f"canonical object identity: {canonical}",
        f"required physical identity structures: {'; '.join(required_parts)}",
    ]
    if materials:
        positive_sections.append(f"material cues: {'; '.join(materials)}")
    if silhouettes:
        positive_sections.append(f"silhouette cues: {'; '.join(silhouettes)}")
    if decorations:
        positive_sections.append(f"subtle optional forge decorations: {'; '.join(decorations)}")
    positive_sections.append(f"identity-preservation cues: {'; '.join(must_preserve)}")
    positive_sections.append(GENERIC_POSITIVE)
    positive = ". ".join(section for section in positive_sections if section) + "."
    negative_sections = [negative_en.rstrip(". ")]
    if replacements:
        negative_sections.append("forbidden substitutions: " + "; ".join(replacements))
    negative_sections.append(GENERIC_NEGATIVE)
    negative = ". ".join(section for section in negative_sections if section) + "."
    evidence = {
        "canonical_name_en": canonical,
        "required_identity_parts": required_parts,
        "material_hints": materials,
        "silhouette_hints": silhouettes,
        "optional_decorations": decorations,
        "visual_prompt_en": prompt_en,
        "visual_negative_prompt_en": negative_en,
        "must_preserve": must_preserve,
        "must_not_replace_with": replacements,
    }
    return positive, negative, evidence


def _extract_output(profile: dict[str, Any], entry: dict[str, Any], output_node_id: str) -> Path:
    images = entry.get("outputs", {}).get(output_node_id, {}).get("images", [])
    if len(images) != 1:
        raise Flux2BridgeError(f"EXPECTED_ONE_OUTPUT_IMAGE:{len(images)}")
    image = images[0]
    root = Path(profile["comfy_output_directory"]).resolve()
    candidate = (root / str(image.get("subfolder", "")) / str(image.get("filename", ""))).resolve()
    if root not in candidate.parents or not candidate.is_file():
        raise Flux2BridgeError("COMFYUI_OUTPUT_FILE_INVALID")
    return candidate


def _validate_raw_png(path: Path, expected: tuple[int, int]) -> list[int]:
    try:
        with Image.open(path) as opened:
            if opened.format != "PNG":
                raise Flux2BridgeError("RAW_NOT_PNG")
            opened.verify()
        with Image.open(path) as opened:
            opened.load()
            dimensions = [opened.width, opened.height]
    except (OSError, ValueError) as exc:
        raise Flux2BridgeError("RAW_PNG_INVALID") from exc
    if tuple(dimensions) != expected:
        raise Flux2BridgeError(f"RAW_DIMENSIONS_INVALID:{dimensions}")
    return dimensions


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class ResourceMonitor:
    def __init__(self, runtime_state: Path) -> None:
        self.runtime_state = runtime_state
        self.stop_event = threading.Event()
        self.peak_vram_mb = 0.0
        self.peak_ram_mb = 0.0
        self._thread = threading.Thread(target=self._poll, daemon=True)

    def _runtime_pid(self) -> int | None:
        try:
            state = json.loads(self.runtime_state.read_text(encoding="utf-8"))
            return int(state.get("pid", 0)) or None
        except (OSError, ValueError, json.JSONDecodeError):
            return None

    def _poll(self) -> None:
        pid = self._runtime_pid()
        process = None
        if pid is not None:
            try:
                process = psutil.Process(pid)
            except psutil.Error:
                process = None
        while not self.stop_event.wait(0.25):
            if process is not None:
                try:
                    rss = process.memory_info().rss
                    for child in process.children(recursive=True):
                        rss += child.memory_info().rss
                    self.peak_ram_mb = max(self.peak_ram_mb, rss / (1024 * 1024))
                except psutil.Error:
                    pass
            try:
                probe = subprocess.run(
                    ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                    capture_output=True,
                    text=True,
                    timeout=2,
                    check=False,
                )
                if probe.returncode == 0:
                    value = float(probe.stdout.strip().splitlines()[0])
                    self.peak_vram_mb = max(self.peak_vram_mb, value)
            except (OSError, ValueError, subprocess.SubprocessError):
                pass

    def __enter__(self) -> "ResourceMonitor":
        self._thread.start()
        return self

    def __exit__(self, *_: Any) -> None:
        self.stop_event.set()
        self._thread.join(timeout=3)


def health(profile: dict[str, Any]) -> dict[str, Any]:
    result = legacy_bridge.health_check(profile)
    result["profile_id"] = profile["profile_id"]
    result["api_base"] = profile["api_base"]
    result["workflow_contract_version"] = profile.get("workflow_contract_version")
    return result


def generate(
    profile: dict[str, Any],
    *,
    case_id: str,
    run_id: str,
    blueprint: dict[str, Any],
    seed: int,
    output_group: str = "interactive",
    mode: str = "t2i",
    reference_image: Path | None = None,
    raw_only: bool = False,
    exact_positive_prompt: str | None = None,
) -> Path:
    if profile.get("profile_id") != "flux2_klein_4b":
        raise Flux2BridgeError("FLUX2_BRIDGE_REQUIRES_FLUX2_PROFILE")
    if mode not in {"t2i", "edit"}:
        raise Flux2BridgeError("GENERATION_MODE_INVALID")
    if mode == "edit" and reference_image is None:
        raise Flux2BridgeError("EDIT_REFERENCE_REQUIRED")
    safe_case = "".join(character for character in case_id.lower() if character.isalnum() or character in "_-")
    safe_run = "".join(character for character in run_id.lower() if character.isalnum() or character in "_-")
    safe_group = "".join(character for character in output_group.lower() if character.isalnum() or character in "_-")
    if not safe_case or not safe_run or not safe_group:
        raise Flux2BridgeError("OUTPUT_IDENTIFIER_INVALID")
    positive, negative, blueprint_evidence = compose_prompts(blueprint)
    if exact_positive_prompt is not None:
        if output_group != "smoke" or case_id != "smoke_t2i":
            raise Flux2BridgeError("EXACT_PROMPT_OVERRIDE_RESERVED_FOR_FIXED_SMOKE")
        positive = exact_positive_prompt.strip()
        if not positive:
            raise Flux2BridgeError("FIXED_SMOKE_PROMPT_EMPTY")
    workflow, workflow_path, workflow_hash = load_workflow(profile, mode)
    generation = profile["generation"]
    values: dict[str, Any] = {
        "positive_prompt": positive,
        "negative_prompt": negative,
        "seed": int(seed),
        "width": int(generation["width"]),
        "height": int(generation["height"]),
        "steps": int(generation["steps"]),
        "guidance": float(generation["guidance"]),
        "output_subfolder": f"ForgeFlux2/{safe_group}/{safe_case}/{safe_run}/raw",
    }
    copied_reference: Path | None = None
    if mode == "edit":
        reference = reference_image.resolve()
        _validate_raw_png(reference, (512, 512))
        input_root = Path(profile["comfy_input_directory"]).resolve()
        reference_relative = Path("ForgeFlux2") / safe_group / safe_case / safe_run / f"{uuid.uuid4().hex}.png"
        copied_reference = (input_root / reference_relative).resolve()
        if input_root not in copied_reference.parents:
            raise Flux2BridgeError("REFERENCE_INPUT_PATH_INVALID")
        copied_reference.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(reference, copied_reference)
        values["optional_reference_image"] = reference_relative.as_posix()
    graph, output_node_id = inject_profile_workflow(workflow, values)

    output_root = Path(profile["output_root"]).resolve()
    final_directory = output_root / safe_group / safe_case / safe_run
    if final_directory.exists():
        raise Flux2BridgeError(f"FINAL_DIRECTORY_ALREADY_EXISTS:{final_directory}")
    stage = output_root / ".tmp" / f"{safe_group}-{safe_case}-{safe_run}-{uuid.uuid4().hex}"
    stage.mkdir(parents=True, exist_ok=False)
    manifest: dict[str, Any] = {
        "contract": "forge-flux2-generation-v1",
        "profile_id": profile["profile_id"],
        "workflow_contract_version": profile["workflow_contract_version"],
        "prompt_policy_version": PROMPT_POLICY_VERSION,
        "case_id": safe_case,
        "run_id": safe_run,
        "output_group": safe_group,
        "mode": mode,
        "seed": int(seed),
        "positive_prompt": positive,
        "negative_prompt": negative,
        "positive_prompt_sha256": hashlib.sha256(positive.encode("utf-8")).hexdigest(),
        "negative_prompt_sha256": hashlib.sha256(negative.encode("utf-8")).hexdigest(),
        "blueprint_projection": blueprint_evidence,
        "workflow_file": workflow_path.name,
        "workflow_sha256": workflow_hash,
        "models": profile["model_filenames"],
        "model_sha256": profile["model_sha256"],
        "selected_install_label": profile["selected_install_label"],
        "comfyui_commit": profile["comfyui_commit"],
        "postprocessor_file": Path(profile["postprocessor"]).name,
        "postprocessor_sha256": profile["postprocessor_sha256"],
        "width": int(generation["width"]),
        "height": int(generation["height"]),
        "batch_size": int(generation["batch_size"]),
        "steps": int(generation["steps"]),
        "guidance": float(generation["guidance"]),
        "sampler": generation["sampler"],
        "retry_count": 0,
        "prompt_id": "",
        "generation_seconds": 0.0,
        "total_wall_seconds": 0.0,
        "postprocess_seconds": 0.0,
        "peak_vram_mb": 0.0,
        "peak_ram_mb": 0.0,
        "raw_dimensions": [],
        "processed_dimensions": [],
        "alpha_valid": False,
        "status": "failed",
        "failure_reason": "UNFINISHED",
    }
    wall_start = time.perf_counter()
    monitor_path = Path(__file__).resolve().parents[1] / "logs" / "runtime_state.json"
    try:
        if not health(profile).get("ok"):
            raise Flux2BridgeError("COMFYUI_HEALTH_CHECK_FAILED")
        _write_json(stage / "blueprint_projection.json", blueprint_evidence)
        _write_json(stage / "request_workflow.json", graph)
        if copied_reference is not None:
            shutil.copy2(copied_reference, stage / "reference_image.png")
        generation_start = time.perf_counter()
        with ResourceMonitor(monitor_path) as monitor:
            prompt_id, entry = legacy_bridge._submit_and_wait(  # noqa: SLF001
                profile, graph, float(profile.get("timeout_seconds", 120))
            )
        manifest["prompt_id"] = prompt_id
        manifest["generation_seconds"] = round(time.perf_counter() - generation_start, 3)
        manifest["peak_vram_mb"] = round(monitor.peak_vram_mb, 1)
        manifest["peak_ram_mb"] = round(monitor.peak_ram_mb, 1)
        raw_source = _extract_output(profile, entry, output_node_id)
        raw_target = stage / "raw.png"
        shutil.copy2(raw_source, raw_target)
        manifest["raw_dimensions"] = _validate_raw_png(
            raw_target, (int(generation["width"]), int(generation["height"]))
        )
        if raw_only:
            manifest["status"] = "raw_success"
            manifest["failure_reason"] = ""
        else:
            post_start = time.perf_counter()
            try:
                result = legacy_bridge.process_sprite(
                    raw_target,
                    stage / "processed_sprite.png",
                    stage / "alpha_mask.png",
                    expected_background=tuple(int(value) for value in profile.get("background_rgb", [255, 0, 255])),
                    sprite_size=int(profile.get("sprite_size", 96)),
                    max_colors=int(profile.get("max_colors", 32)),
                    outline=bool(profile.get("outline", True)),
                )
                manifest.update(result)
                manifest["alpha_valid"] = True
                manifest["status"] = "success"
                manifest["failure_reason"] = ""
            except legacy_bridge.SpritePostprocessError as exc:
                for name in ("processed_sprite.png", "alpha_mask.png"):
                    rejected = stage / name
                    if rejected.exists():
                        rejected.unlink()
                manifest["status"] = "raw_success_alpha_failed"
                manifest["failure_reason"] = str(exc)
            finally:
                manifest["postprocess_seconds"] = round(time.perf_counter() - post_start, 3)
    except (Flux2BridgeError, legacy_bridge.BridgeError, OSError, ValueError, json.JSONDecodeError) as exc:
        manifest["status"] = "failed"
        manifest["failure_reason"] = str(exc)
    finally:
        manifest["total_wall_seconds"] = round(time.perf_counter() - wall_start, 3)
        _write_json(stage / "manifest.json", manifest)
        (stage / "generation.log").write_text(
            "\n".join(
                [
                    f"profile_id={profile['profile_id']}",
                    f"case_id={safe_case}",
                    f"run_id={safe_run}",
                    f"mode={mode}",
                    f"seed={seed}",
                    "retry_count=0",
                    f"prompt_id={manifest['prompt_id']}",
                    f"status={manifest['status']}",
                    f"failure_reason={manifest['failure_reason']}",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        final_directory.parent.mkdir(parents=True, exist_ok=True)
        os.replace(stage, final_directory)
    if manifest["status"] == "failed":
        raise Flux2BridgeError(f"GENERATION_FAILED:{manifest['failure_reason']}:{final_directory}")
    return final_directory


def _load_blueprint(path: Path | None, generation_prompt: str | None) -> dict[str, Any]:
    if path is not None:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise Flux2BridgeError("BLUEPRINT_FILE_INVALID") from exc
        if not isinstance(value, dict):
            raise Flux2BridgeError("BLUEPRINT_ROOT_INVALID")
        return value
    prompt = str(generation_prompt or "").strip()
    if not prompt:
        raise Flux2BridgeError("BLUEPRINT_OR_GENERATION_PROMPT_REQUIRED")
    return {
        "identity": {
            "canonical_name_en": prompt,
            "required_identity_parts": [prompt],
            "material_hints": [],
            "silhouette_hints": [],
            "optional_decorations": [],
        },
        "visual": {
            "prompt_en": prompt,
            "negative_prompt_en": GENERIC_NEGATIVE,
            "must_preserve": [prompt],
            "must_not_replace_with": [],
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Profile-driven FLUX.2 adapter over the existing local bridge.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--profile")
    source.add_argument("--config", type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("health")
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--case-id", required=True)
    generate_parser.add_argument("--run-id", required=True)
    generate_parser.add_argument("--output-group", default="interactive")
    generate_parser.add_argument("--blueprint", type=Path)
    generate_parser.add_argument("--prompt")
    generate_parser.add_argument("--generation-prompt")
    generate_parser.add_argument("--prompt-policy-version", default=PROMPT_POLICY_VERSION)
    generate_parser.add_argument("--seed", required=True, type=int)
    generate_parser.add_argument("--control-strength", type=float, default=0.0)
    generate_parser.add_argument("--sketch", type=Path)
    generate_parser.add_argument("--mode", choices=("t2i", "edit"), default="t2i")
    generate_parser.add_argument("--reference", type=Path)
    generate_parser.add_argument("--flux2-enable-sketch-edit", action="store_true")
    generate_parser.add_argument("--raw-only", action="store_true")
    return parser.parse_args()


def _profile_from_args(args: argparse.Namespace) -> dict[str, Any]:
    if args.profile:
        return resolve_profile(args.profile)
    config_path = args.config.resolve()
    allowed_config_roots = {
        (Path(__file__).resolve().parents[1] / "config").resolve(),
        PROFILE_DIRECTORY.resolve(),
    }
    if config_path.parent not in allowed_config_roots:
        raise Flux2BridgeError("FLUX2_CONFIG_OUTSIDE_SPIKE_CONFIG_DIRECTORY")
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise Flux2BridgeError("FLUX2_CONFIG_READ_FAILED") from exc
    if not isinstance(config, dict):
        raise Flux2BridgeError("FLUX2_CONFIG_ROOT_INVALID")
    profile_reference = str(config.get("profile_file") or config.get("comfy_profile") or "").strip()
    if not profile_reference:
        raise Flux2BridgeError("FLUX2_CONFIG_PROFILE_MISSING")
    if profile_reference.endswith(".json"):
        profile_reference = str((config_path.parent / profile_reference).resolve())
    profile = resolve_profile(profile_reference)
    expected_pairs = {
        "api_base": profile["api_base"],
        "python_executable": profile["python_executable"],
        "output_root": profile["output_root"],
        "timeout_seconds": profile["timeout_seconds"],
    }
    for key, expected in expected_pairs.items():
        actual: Any = config.get(key)
        if key in {"python_executable", "output_root"} and isinstance(actual, str):
            actual = str(_resolve_profile_path(config_path, actual))
        if actual != expected:
            raise Flux2BridgeError(f"FLUX2_CONFIG_PROFILE_MISMATCH:{key}")
    return profile


def main() -> int:
    args = parse_args()
    try:
        profile = _profile_from_args(args)
        if args.command == "health":
            print(json.dumps(health(profile), ensure_ascii=False, indent=2))
            return 0
        if args.prompt_policy_version not in {PROMPT_POLICY_VERSION, "forge-open-identity-v2"}:
            raise Flux2BridgeError("PROMPT_POLICY_VERSION_INVALID")
        if args.mode == "edit" and not args.flux2_enable_sketch_edit:
            raise Flux2BridgeError("SKETCH_EDIT_DEVELOPER_SWITCH_REQUIRED")
        if args.mode == "t2i" and (args.sketch is not None or args.reference is not None):
            raise Flux2BridgeError("REFERENCE_INPUT_REQUIRES_EDIT_MODE")
        blueprint = _load_blueprint(args.blueprint, args.generation_prompt)
        result = generate(
            profile,
            case_id=args.case_id,
            run_id=args.run_id,
            output_group=args.output_group,
            blueprint=blueprint,
            seed=args.seed,
            mode=args.mode,
            reference_image=args.reference or args.sketch,
            raw_only=args.raw_only,
        )
        print(json.dumps({"status": "success", "output_directory": str(result)}, ensure_ascii=False))
        return 0
    except (Flux2BridgeError, legacy_bridge.BridgeError) as exc:
        print(json.dumps({"status": "failed", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
