from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[4]
MATRIX_TOOL = "res://tools/comfyui/flux2/bridge/mechanism_visual_matrix_tool.gd"
MATRIX_CONTRACT = "forge-mechanism-visual-flux-matrix-v1"
SUMMARY_CONTRACT = "forge-mechanism-pixel-provider-matrix-summary-v1"
PROVIDERS = ("scaffold", "retro", "pixellab")
MAX_REDRAWS = 2
CANVAS_SIZE = (96, 96)
MIN_ALPHA_IOU = 0.18
MAX_OPAQUE_RATIO = 0.48
RETRO_URL = "https://api.retrodiffusion.ai/v1/inferences"
PIXELLAB_URL = "https://api.pixellab.ai/v2/create-image-pixflux"


class ProviderMatrixError(RuntimeError):
    pass


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ProviderMatrixError(f"JSON_ROOT_INVALID:{path.name}")
    return value


def _atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _atomic_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(payload)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _run_godot(godot: Path, workspace: Path, *user_args: str) -> None:
    completed = subprocess.run(
        [
            str(godot),
            "--headless",
            "--path",
            str(workspace),
            "--script",
            MATRIX_TOOL,
            "--",
            *user_args,
        ],
        cwd=workspace,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=300,
        check=False,
    )
    combined = f"{completed.stdout}\n{completed.stderr}"
    if completed.returncode != 0 or any(
        token in combined for token in ("SCRIPT ERROR", "Parse Error", "Compile Error")
    ):
        raise ProviderMatrixError(f"GODOT_MATRIX_TOOL_FAILED:{combined[-2000:]}")


def _raw_base64(payload: bytes) -> str:
    return base64.b64encode(payload).decode("ascii")


def _base64_image(payload: bytes) -> dict[str, str]:
    return {"type": "base64", "base64": _raw_base64(payload), "format": "png"}


def _retro_init_png(scaffold_path: Path) -> bytes:
    with Image.open(scaffold_path) as source:
        rgba = source.convert("RGBA")
    background = Image.new("RGB", rgba.size, (255, 0, 255))
    background.paste(rgba.convert("RGB"), mask=rgba.getchannel("A"))
    output = io.BytesIO()
    background.save(output, format="PNG", optimize=False)
    return output.getvalue()


def _rgb_png(image_path: Path) -> bytes:
    with Image.open(image_path) as source:
        rgb = source.convert("RGB")
    output = io.BytesIO()
    rgb.save(output, format="PNG", optimize=False)
    return output.getvalue()


def build_retro_payload(
    prompt: str,
    seed: int,
    scaffold_path: Path,
    palette_path: Path,
    strength: float = 0.38,
) -> dict[str, Any]:
    return {
        "prompt": prompt,
        "prompt_style": "rd_plus__topdown_item",
        "width": CANVAS_SIZE[0],
        "height": CANVAS_SIZE[1],
        "num_images": 1,
        "seed": seed,
        "input_image": _raw_base64(_retro_init_png(scaffold_path)),
        "strength": strength,
        "input_palette": _raw_base64(_rgb_png(palette_path)),
        "remove_bg": True,
        "upscale_output_factor": 1,
        "bypass_prompt_expansion": True,
    }


def build_pixellab_payload(
    prompt: str,
    seed: int,
    scaffold_path: Path,
    palette_path: Path,
    init_strength: int = 800,
) -> dict[str, Any]:
    return {
        "description": prompt,
        "image_size": {"width": CANVAS_SIZE[0], "height": CANVAS_SIZE[1]},
        "no_background": True,
        "outline": "single color outline",
        "shading": "basic shading",
        "detail": "low detail",
        "view": "side",
        "init_image": _base64_image(scaffold_path.read_bytes()),
        "init_image_strength": init_strength,
        "color_image": _base64_image(palette_path.read_bytes()),
        "seed": seed,
        "text_guidance_scale": 7.0,
    }


def _safe_service_error(payload: bytes) -> str:
    try:
        value: Any = json.loads(payload.decode("utf-8", errors="replace"))
    except json.JSONDecodeError:
        return "service_error"
    if isinstance(value, dict):
        for key in ("detail", "message", "error"):
            candidate = value.get(key)
            if isinstance(candidate, str) and candidate.strip():
                return " ".join(candidate.split())[:300]
            if isinstance(candidate, dict):
                nested = candidate.get("message")
                if isinstance(nested, str) and nested.strip():
                    return " ".join(nested.split())[:300]
    return "service_error"


def _post_json(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    timeout: float,
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json", **headers},
        method="POST",
    )
    try:
        with opener(request, timeout=timeout) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        detail = _safe_service_error(exc.read(16_384))
        raise ProviderMatrixError(f"HTTP_{exc.code}:{detail}") from exc
    except urllib.error.URLError as exc:
        raise ProviderMatrixError(f"NETWORK_ERROR:{type(exc.reason).__name__}") from exc
    try:
        decoded = json.loads(response_body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProviderMatrixError("PROVIDER_RESPONSE_NOT_JSON") from exc
    if not isinstance(decoded, dict):
        raise ProviderMatrixError("PROVIDER_RESPONSE_ROOT_INVALID")
    return decoded


def _decode_image_value(value: Any) -> bytes:
    if not isinstance(value, str) or not value.strip():
        raise ProviderMatrixError("PROVIDER_IMAGE_BASE64_MISSING")
    encoded = value.strip()
    if encoded.startswith("data:"):
        marker = encoded.find(",")
        if marker < 0:
            raise ProviderMatrixError("PROVIDER_IMAGE_DATA_URI_INVALID")
        encoded = encoded[marker + 1 :]
    try:
        return base64.b64decode(encoded, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise ProviderMatrixError("PROVIDER_IMAGE_BASE64_INVALID") from exc


def extract_retro_image(
    response: dict[str, Any],
    timeout: float,
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> bytes:
    base64_images = response.get("base64_images")
    if isinstance(base64_images, list) and base64_images:
        return _decode_image_value(base64_images[0])
    output_urls = response.get("output_urls")
    if isinstance(output_urls, list) and output_urls and isinstance(output_urls[0], str):
        try:
            with opener(output_urls[0], timeout=timeout) as downloaded:
                return downloaded.read()
        except urllib.error.URLError as exc:
            raise ProviderMatrixError("RETRO_OUTPUT_DOWNLOAD_FAILED") from exc
    raise ProviderMatrixError("RETRO_OUTPUT_IMAGE_MISSING")


def extract_pixellab_image(response: dict[str, Any]) -> bytes:
    image = response.get("image")
    if isinstance(image, dict):
        return _decode_image_value(image.get("base64"))
    raise ProviderMatrixError("PIXELLAB_OUTPUT_IMAGE_MISSING")


def _provider_token(provider: str) -> str:
    names = {
        "retro": ("RD_API_KEY", "RETRO_DIFFUSION_API_KEY"),
        "pixellab": ("PIXELLAB_API_TOKEN", "PIXELLAB_API_KEY"),
    }.get(provider, ())
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return ""


def _generate_provider(
    provider: str,
    token: str,
    prompt: str,
    seed: int,
    scaffold_path: Path,
    palette_path: Path,
    timeout: float,
    retro_strength: float,
    pixellab_init_strength: int,
) -> tuple[bytes, dict[str, Any]]:
    if provider == "scaffold":
        return scaffold_path.read_bytes(), {"mode": "deterministic_structure_reference"}
    if provider == "retro":
        payload = build_retro_payload(prompt, seed, scaffold_path, palette_path, retro_strength)
        response = _post_json(RETRO_URL, {"X-RD-Token": token}, payload, timeout)
        return extract_retro_image(response, timeout), {
            "prompt_style": payload["prompt_style"],
            "strength": payload["strength"],
            "remove_bg": payload["remove_bg"],
        }
    if provider == "pixellab":
        payload = build_pixellab_payload(prompt, seed, scaffold_path, palette_path, pixellab_init_strength)
        response = _post_json(PIXELLAB_URL, {"Authorization": f"Bearer {token}"}, payload, timeout)
        return extract_pixellab_image(response), {
            "model": "pixflux",
            "init_image_strength": payload["init_image_strength"],
            "no_background": payload["no_background"],
            "detail": payload["detail"],
            "view": payload["view"],
        }
    raise ProviderMatrixError(f"PROVIDER_UNKNOWN:{provider}")


def _alpha_mask(image: Image.Image) -> list[bool]:
    return [alpha >= 32 for alpha in image.getchannel("A").tobytes()]


def _alpha_iou(generated: Image.Image, scaffold: Image.Image) -> float:
    generated_mask = _alpha_mask(generated)
    scaffold_mask = _alpha_mask(scaffold)
    intersection = sum(1 for left, right in zip(generated_mask, scaffold_mask) if left and right)
    union = sum(1 for left, right in zip(generated_mask, scaffold_mask) if left or right)
    return intersection / max(1, union)


def normalize_and_validate_png(raw: bytes, scaffold_path: Path) -> tuple[bytes, dict[str, Any]]:
    try:
        with Image.open(io.BytesIO(raw)) as loaded:
            loaded.load()
            generated = loaded.convert("RGBA")
    except (OSError, ValueError) as exc:
        raise ProviderMatrixError("PROVIDER_OUTPUT_NOT_PNG") from exc
    if generated.size != CANVAS_SIZE:
        raise ProviderMatrixError(f"PROVIDER_OUTPUT_SIZE_INVALID:{generated.width}x{generated.height}")
    with Image.open(scaffold_path) as loaded_scaffold:
        scaffold = loaded_scaffold.convert("RGBA")
    alpha_values = list(generated.getchannel("A").tobytes())
    opaque_count = sum(1 for alpha in alpha_values if alpha >= 32)
    transparent_count = len(alpha_values) - opaque_count
    partial_alpha_count = sum(1 for alpha in alpha_values if 0 < alpha < 255)
    opaque_ratio = opaque_count / len(alpha_values)
    if opaque_count < 24:
        raise ProviderMatrixError("PROVIDER_OUTPUT_OBJECT_TOO_SMALL")
    if transparent_count == 0 or opaque_ratio > MAX_OPAQUE_RATIO:
        raise ProviderMatrixError("PROVIDER_OUTPUT_BACKGROUND_NOT_TRANSPARENT")
    scaffold_iou = _alpha_iou(generated, scaffold)
    if scaffold_iou < MIN_ALPHA_IOU:
        raise ProviderMatrixError(f"PROVIDER_OUTPUT_SCAFFOLD_DRIFT:{scaffold_iou:.4f}")
    raw_pixels = generated.tobytes()
    unique_opaque_colors = len(
        {
            raw_pixels[index : index + 3]
            for index in range(0, len(raw_pixels), 4)
            if raw_pixels[index + 3] >= 32
        }
    )
    crisp_pixels = bytearray(raw_pixels)
    for index in range(3, len(crisp_pixels), 4):
        crisp_pixels[index] = 255 if crisp_pixels[index] >= 32 else 0
    generated.frombytes(bytes(crisp_pixels))
    encoded = io.BytesIO()
    generated.save(encoded, format="PNG", optimize=False)
    normalized = encoded.getvalue()
    return normalized, {
        "width": generated.width,
        "height": generated.height,
        "opaque_pixel_count": opaque_count,
        "opaque_ratio": opaque_ratio,
        "partial_alpha_pixel_count_before_normalization": partial_alpha_count,
        "unique_opaque_color_count": unique_opaque_colors,
        "scaffold_alpha_iou": scaffold_iou,
        "binary_alpha": True,
    }


def _retry_prompt(base_prompt: str, instruction: str) -> str:
    cleaned = " ".join(instruction.split()).strip()
    if not cleaned:
        cleaned = "Preserve every attached structural region and keep the background transparent"
    return f"{base_prompt.rstrip()} Automatic redraw: {cleaned.rstrip('. ')}."


def _is_permanent_provider_failure(reason: str) -> bool:
    return reason.startswith(
        (
            "HTTP_400:",
            "HTTP_401:",
            "HTTP_402:",
            "HTTP_403:",
            "HTTP_404:",
            "HTTP_422:",
            "PROVIDER_UNKNOWN:",
        )
    )


def _attempt_record(
    provider: str,
    case_id: str,
    attempt: int,
    seed: int,
    result_directory: Path,
    manifest: dict[str, Any],
    gate: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "provider": provider,
        "case_id": case_id,
        "attempt": attempt,
        "seed": seed,
        "generation_status": str(manifest.get("status", "missing_manifest")),
        "generation_failure_reason": str(manifest.get("failure_reason", "")),
        "gate_ok": bool(gate.get("ok", False)) if gate else False,
        "gate_error": str(gate.get("error", "")) if gate else "",
        "scaffold_alpha_iou": float((manifest.get("preflight", {}) or {}).get("scaffold_alpha_iou", 0.0)),
        "generation_seconds": float(manifest.get("generation_seconds", 0.0)),
        "output_directory": str(result_directory),
    }


def _write_csv(path: Path, records: list[dict[str, Any]]) -> None:
    fields = [
        "provider",
        "case_id",
        "attempt",
        "seed",
        "generation_status",
        "generation_failure_reason",
        "gate_ok",
        "gate_error",
        "scaffold_alpha_iou",
        "generation_seconds",
        "output_directory",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows({field: record.get(field, "") for field in fields} for record in records)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def run_matrix(
    godot: Path,
    workspace: Path,
    providers: tuple[str, ...],
    matrix_root: Path | None,
    timeout: float,
    retro_strength: float,
    pixellab_init_strength: int,
) -> Path:
    unknown = sorted(set(providers) - set(PROVIDERS))
    if unknown:
        raise ProviderMatrixError(f"PROVIDER_UNKNOWN:{','.join(unknown)}")
    run_id = datetime.now(timezone.utc).strftime("mechanism-pixel-%Y%m%dT%H%M%S%fZ")
    evidence_root = (matrix_root or workspace / "output" / "mechanism_pixel_provider_matrix" / run_id).resolve()
    evidence_root.mkdir(parents=True, exist_ok=False)
    _run_godot(godot, workspace, "--mode=prepare", f"--matrix-root={evidence_root}")
    matrix_path = evidence_root / "matrix_contract.json"
    matrix = _read_json(matrix_path)
    cases = matrix.get("cases", [])
    if matrix.get("contract") != MATRIX_CONTRACT or not isinstance(cases, list):
        raise ProviderMatrixError("MECHANISM_VISUAL_MATRIX_CONTRACT_INVALID")

    attempts: list[dict[str, Any]] = []
    case_results: list[dict[str, Any]] = []
    for provider in providers:
        token = _provider_token(provider)
        if provider != "scaffold" and not token:
            for case in cases:
                case_results.append(
                    {
                        "provider": provider,
                        "case_id": str(case["case_id"]),
                        "status": "skipped_missing_credential",
                        "redraw_count": 0,
                        "final_gate_error": "",
                    }
                )
            print(json.dumps({"event": "provider_skipped", "provider": provider, "reason": "missing_credential"}))
            continue
        for case in cases:
            if not isinstance(case, dict):
                raise ProviderMatrixError("MECHANISM_VISUAL_MATRIX_CASE_INVALID")
            case_id = str(case["case_id"])
            base_seed = int(case["seed"])
            request_path = evidence_root / str(case["request"])
            request = _read_json(request_path)
            scaffold_path = evidence_root / str(case["structure_scaffold"])
            palette_path = evidence_root / str(case["palette"])
            base_prompt = str(request["provider_prompt"])
            retry_instruction = ""
            final_gate: dict[str, Any] | None = None
            final_error = ""
            final_status = "failed"
            redraw_count = 0
            attempt_limit = 0 if provider == "scaffold" else MAX_REDRAWS
            for attempt in range(attempt_limit + 1):
                seed = base_seed + attempt
                prompt = base_prompt if attempt == 0 else _retry_prompt(base_prompt, retry_instruction)
                result_directory = evidence_root / "results" / provider / case_id / f"attempt_{attempt}_seed_{seed}"
                result_directory.mkdir(parents=True, exist_ok=False)
                started = time.monotonic()
                manifest: dict[str, Any]
                gate: dict[str, Any] | None = None
                try:
                    raw, provider_settings = _generate_provider(
                        provider,
                        token,
                        prompt,
                        seed,
                        scaffold_path,
                        palette_path,
                        timeout,
                        retro_strength,
                        pixellab_init_strength,
                    )
                    normalized, preflight = normalize_and_validate_png(raw, scaffold_path)
                    _atomic_bytes(result_directory / "processed_sprite.png", normalized)
                    manifest = {
                        "contract": "forge-mechanism-pixel-provider-result-v1",
                        "status": "success",
                        "provider": provider,
                        "case_id": case_id,
                        "seed": seed,
                        "retry_count": attempt,
                        "prompt_sha256": _sha256(prompt.encode("utf-8")),
                        "structure_scaffold_sha256": _sha256(scaffold_path.read_bytes()),
                        "palette_sha256": _sha256(palette_path.read_bytes()),
                        "output_sha256": _sha256(normalized),
                        "provider_settings": provider_settings,
                        "preflight": preflight,
                        "generation_seconds": time.monotonic() - started,
                        "automatic": True,
                        "player_confirmation_required": False,
                    }
                except (ProviderMatrixError, OSError, ValueError, json.JSONDecodeError) as exc:
                    final_error = str(exc)
                    manifest = {
                        "contract": "forge-mechanism-pixel-provider-result-v1",
                        "status": "failed",
                        "provider": provider,
                        "case_id": case_id,
                        "seed": seed,
                        "retry_count": attempt,
                        "failure_reason": final_error,
                        "generation_seconds": time.monotonic() - started,
                        "automatic": True,
                        "player_confirmation_required": False,
                    }
                _atomic_json(result_directory / "manifest.json", manifest)
                if manifest["status"] == "success":
                    _run_godot(
                        godot,
                        workspace,
                        "--mode=evaluate",
                        f"--request={request_path}",
                        f"--result={result_directory}",
                    )
                    gate = _read_json(result_directory / "mechanism_visual_gate.json")
                    final_gate = gate
                    final_error = str(gate.get("error", ""))
                record = _attempt_record(
                    provider, case_id, attempt, seed, result_directory, manifest, gate
                )
                attempts.append(record)
                print(
                    json.dumps(
                        {
                            "event": "attempt_complete",
                            "provider": provider,
                            "case_id": case_id,
                            "attempt": attempt,
                            "generation_status": record["generation_status"],
                            "gate_ok": record["gate_ok"],
                            "gate_error": record["gate_error"],
                        },
                        ensure_ascii=False,
                    ),
                    flush=True,
                )
                redraw_count = attempt
                if gate and gate.get("ok") is True:
                    final_status = "passed"
                    break
                if provider == "scaffold" or attempt >= attempt_limit or _is_permanent_provider_failure(final_error):
                    break
                retry_instruction = (
                    str(gate.get("retry_prompt", ""))
                    if gate
                    else "Keep all scaffold regions in place and leave the background fully transparent"
                )
            case_results.append(
                {
                    "provider": provider,
                    "case_id": case_id,
                    "status": final_status,
                    "redraw_count": redraw_count,
                    "final_gate_error": final_error,
                    "final_gate_path": (
                        str(attempts[-1]["output_directory"]) + "/mechanism_visual_gate.json"
                        if final_gate
                        else ""
                    ),
                }
            )

    provider_results: dict[str, Any] = {}
    for provider in providers:
        provider_cases = [item for item in case_results if item["provider"] == provider]
        attempted_cases = [item for item in provider_cases if not str(item["status"]).startswith("skipped_")]
        provider_attempts = [item for item in attempts if item["provider"] == provider]
        first_pass_count = sum(1 for item in provider_attempts if item["attempt"] == 0 and item["gate_ok"])
        final_pass_count = sum(1 for item in attempted_cases if item["status"] == "passed")
        provider_results[provider] = {
            "planned_case_count": len(provider_cases),
            "attempted_case_count": len(attempted_cases),
            "skipped_case_count": len(provider_cases) - len(attempted_cases),
            "attempt_count": len(provider_attempts),
            "first_pass_count": first_pass_count,
            "first_pass_rate": first_pass_count / max(1, len(attempted_cases)),
            "final_pass_count": final_pass_count,
            "final_pass_rate": final_pass_count / max(1, len(attempted_cases)),
        }
    external_providers = [provider for provider in providers if provider != "scaffold"]
    external_comparison_complete = bool(external_providers) and all(
        int(provider_results[provider]["attempted_case_count"]) == len(cases)
        for provider in external_providers
    )
    summary = {
        "contract": SUMMARY_CONTRACT,
        "run_id": run_id,
        "matrix_contract": str(matrix_path),
        "providers": list(providers),
        "provider_configuration": {
            "scaffold": {"mode": "exact_deterministic_reference"},
            "retro": {
                "endpoint": RETRO_URL,
                "prompt_style": "rd_plus__topdown_item",
                "strength": retro_strength,
                "remove_bg": True,
            },
            "pixellab": {
                "endpoint": PIXELLAB_URL,
                "model": "pixflux",
                "init_image_strength": pixellab_init_strength,
                "detail": "low detail",
                "shading": "basic shading",
                "outline": "single color outline",
                "view": "side",
                "no_background": True,
            },
        },
        "provider_results": provider_results,
        "external_comparison_complete": external_comparison_complete,
        "result_status": "complete" if external_comparison_complete else "partial_missing_or_unfinished_external_provider",
        "case_results": case_results,
        "attempts": attempts,
        "structure_source": "deterministic_mechanism_axes",
        "generator_authority": "style_and_color_only",
        "maximum_redraws_per_external_provider_case": MAX_REDRAWS,
        "minimum_scaffold_alpha_iou": MIN_ALPHA_IOU,
        "player_confirmation_required": False,
        "playtest_performed": False,
        "feel_tuning_performed": False,
        "completed_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    summary_path = evidence_root / "matrix_summary.json"
    _atomic_json(summary_path, summary)
    _write_csv(evidence_root / "matrix_attempts.csv", attempts)
    return summary_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare deterministic, Retro Diffusion, and PixelLab Pixflux renders against one mechanism gate."
    )
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--workspace", type=Path, default=REPO_ROOT)
    parser.add_argument("--matrix-root", type=Path)
    parser.add_argument("--providers", default=",".join(PROVIDERS))
    parser.add_argument("--http-timeout", type=float, default=240.0)
    parser.add_argument("--retro-strength", type=float, default=0.38)
    parser.add_argument("--pixellab-init-strength", type=int, default=800)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        godot = args.godot.resolve()
        workspace = args.workspace.resolve()
        providers = tuple(item.strip().lower() for item in args.providers.split(",") if item.strip())
        if not godot.is_file():
            raise ProviderMatrixError("GODOT_EXECUTABLE_MISSING")
        if workspace != REPO_ROOT.resolve():
            raise ProviderMatrixError("MECHANISM_PIXEL_MATRIX_WORKSPACE_MISMATCH")
        if not providers:
            raise ProviderMatrixError("PROVIDER_LIST_EMPTY")
        if not 0.0 <= args.retro_strength <= 1.0:
            raise ProviderMatrixError("RETRO_STRENGTH_OUT_OF_RANGE")
        if not 1 <= args.pixellab_init_strength <= 999:
            raise ProviderMatrixError("PIXELLAB_INIT_STRENGTH_OUT_OF_RANGE")
        summary = run_matrix(
            godot,
            workspace,
            providers,
            args.matrix_root,
            args.http_timeout,
            args.retro_strength,
            args.pixellab_init_strength,
        )
        print(json.dumps({"status": "COMPLETE", "summary": str(summary)}, ensure_ascii=False, indent=2))
        return 0
    except (ProviderMatrixError, OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
