#!/usr/bin/env python3
"""No-retry, serial ComfyUI orchestration scaffold for Spike 6.

The runner consumes only the eight raw PNGs frozen from Spike 5.  It does not
download models, start services, run FLUX sampling, or process images locally.
It remains fail-closed until a separately audited BiRefNet API workflow and its
SHA-256 are placed in configuration.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import http.client
import io
import json
import os
import socket
import time
import urllib.parse
import uuid
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol

from PIL import Image

from freeze_spike5_evidence import Spike5FreezeError, sha256_file, verify_freeze


CONFIG_CONTRACT = "forge-birefnet-spike6-runner-config-v1"
WORKFLOW_CONTRACT = "forge-birefnet-remove-background-api-v1"
APPROVED_API_BASE = "http://127.0.0.1:8190"
FORBIDDEN_PORT = 8188
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class Spike6RunnerError(RuntimeError):
    pass


class Transport(Protocol):
    def get_json(self, path: str) -> dict[str, Any]: ...
    def post_json(self, path: str, payload: Mapping[str, Any]) -> dict[str, Any]: ...
    def post_file(self, path: str, *, filename: str, payload: bytes) -> dict[str, Any]: ...
    def get_bytes(self, path: str) -> bytes: ...


def _json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Spike6RunnerError(f"JSON_READ_FAILED:{path}") from exc
    if not isinstance(value, dict):
        raise Spike6RunnerError(f"JSON_OBJECT_REQUIRED:{path}")
    return value


def _resolve_from(config_file: Path, raw: Any, field: str) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise Spike6RunnerError(f"CONFIG_PATH_INVALID:{field}")
    path = Path(os.path.expandvars(raw))
    if not path.is_absolute():
        path = config_file.parent / path
    return path.resolve(strict=False)


def load_config(config_file: Path) -> dict[str, Any]:
    config_file = config_file.resolve(strict=True)
    value = _json_object(config_file)
    required = {
        "contract",
        "api_base",
        "refuse_if_port_8188_open",
        "timeout_seconds",
        "poll_interval_seconds",
        "source_freeze_file",
        "source_freeze_sha256",
        "workflow_file",
        "workflow_sha256",
        "workflow_audit_status",
        "output_root",
    }
    if set(value) != required:
        raise Spike6RunnerError("CONFIG_KEYS_INVALID")
    if value.get("contract") != CONFIG_CONTRACT:
        raise Spike6RunnerError("CONFIG_CONTRACT_INVALID")
    if value.get("api_base") != APPROVED_API_BASE:
        raise Spike6RunnerError("API_BASE_MUST_BE_127_0_0_1_8190")
    if value.get("refuse_if_port_8188_open") is not True:
        raise Spike6RunnerError("PORT_8188_REFUSAL_MUST_BE_ENABLED")
    if value.get("workflow_audit_status") != "APPROVED":
        raise Spike6RunnerError("BIREFNET_WORKFLOW_AUDIT_NOT_APPROVED")
    workflow_hash = value.get("workflow_sha256")
    if not isinstance(workflow_hash, str) or len(workflow_hash) != 64 or any(character not in "0123456789abcdef" for character in workflow_hash):
        raise Spike6RunnerError("WORKFLOW_SHA256_INVALID")
    freeze_hash = value.get("source_freeze_sha256")
    if not isinstance(freeze_hash, str) or len(freeze_hash) != 64 or any(character not in "0123456789abcdef" for character in freeze_hash):
        raise Spike6RunnerError("SOURCE_FREEZE_SHA256_INVALID")
    timeout = value.get("timeout_seconds")
    interval = value.get("poll_interval_seconds")
    if not isinstance(timeout, (int, float)) or isinstance(timeout, bool) or not 1 <= float(timeout) <= 600:
        raise Spike6RunnerError("TIMEOUT_INVALID")
    if not isinstance(interval, (int, float)) or isinstance(interval, bool) or not 0 <= float(interval) <= 10:
        raise Spike6RunnerError("POLL_INTERVAL_INVALID")
    value["config_file"] = str(config_file)
    for field in ("source_freeze_file", "workflow_file", "output_root"):
        value[field] = str(_resolve_from(config_file, value[field], field))
    return value


class LoopbackHttpTransport:
    """Minimal stdlib transport; each method performs exactly one HTTP request."""

    def __init__(self, api_base: str, timeout: float) -> None:
        if api_base != APPROVED_API_BASE:
            raise Spike6RunnerError("TRANSPORT_API_BASE_INVALID")
        self.timeout = timeout

    def _request(self, method: str, path: str, body: bytes | None = None, headers: Mapping[str, str] | None = None) -> bytes:
        connection = http.client.HTTPConnection("127.0.0.1", 8190, timeout=self.timeout)
        try:
            connection.request(method, path, body=body, headers=dict(headers or {}))
            response = connection.getresponse()
            payload = response.read()
            if response.status < 200 or response.status >= 300:
                raise Spike6RunnerError(f"COMFYUI_HTTP_{response.status}:{method}:{path.split('?', 1)[0]}")
            return payload
        except (OSError, http.client.HTTPException) as exc:
            raise Spike6RunnerError(f"COMFYUI_REQUEST_FAILED:{method}:{path.split('?', 1)[0]}") from exc
        finally:
            connection.close()

    @staticmethod
    def _decode_json(payload: bytes) -> dict[str, Any]:
        try:
            value = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise Spike6RunnerError("COMFYUI_JSON_INVALID") from exc
        if not isinstance(value, dict):
            raise Spike6RunnerError("COMFYUI_JSON_OBJECT_REQUIRED")
        return value

    def get_json(self, path: str) -> dict[str, Any]:
        return self._decode_json(self._request("GET", path))

    def post_json(self, path: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        return self._decode_json(self._request("POST", path, body, {"Content-Type": "application/json"}))

    def post_file(self, path: str, *, filename: str, payload: bytes) -> dict[str, Any]:
        boundary = "forge" + uuid.uuid4().hex
        safe_name = Path(filename).name
        prefix = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{safe_name}\"\r\n"
            "Content-Type: image/png\r\n\r\n"
        ).encode("ascii")
        suffix = f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\nfalse\r\n--{boundary}--\r\n".encode("ascii")
        body = prefix + payload + suffix
        return self._decode_json(
            self._request("POST", path, body, {"Content-Type": f"multipart/form-data; boundary={boundary}"})
        )

    def get_bytes(self, path: str) -> bytes:
        return self._request("GET", path)


def is_loopback_port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.2)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def _set_path(graph: dict[str, Any], path: list[str], value: Any) -> None:
    cursor: Any = graph
    try:
        for key in path[:-1]:
            cursor = cursor[key]
        cursor[path[-1]] = value
    except (KeyError, TypeError, IndexError) as exc:
        raise Spike6RunnerError("WORKFLOW_BINDING_PATH_INVALID") from exc


def load_approved_workflow(config: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    path = Path(str(config["workflow_file"]))
    if path.is_symlink() or not path.is_file():
        raise Spike6RunnerError("WORKFLOW_FILE_MISSING")
    actual_hash = sha256_file(path)
    if actual_hash != config.get("workflow_sha256"):
        raise Spike6RunnerError("WORKFLOW_HASH_MISMATCH")
    workflow = _json_object(path)
    forge = workflow.pop("_forge", None)
    if not isinstance(forge, dict) or forge.get("contract") != WORKFLOW_CONTRACT:
        raise Spike6RunnerError("WORKFLOW_CONTRACT_INVALID")
    if forge.get("audit_status") != "APPROVED" or forge.get("runnable") is not True:
        raise Spike6RunnerError("WORKFLOW_NOT_AUDITED_OR_RUNNABLE")
    input_binding = forge.get("input_image_binding")
    rgba_binding = forge.get("rgba_output_prefix_binding")
    mask_binding = forge.get("mask_output_prefix_binding")
    rgba_node_id = str(forge.get("rgba_output_node_id", ""))
    mask_node_id = str(forge.get("mask_output_node_id", ""))
    if not isinstance(input_binding, list) or not input_binding or not all(isinstance(item, str) and item for item in input_binding):
        raise Spike6RunnerError("WORKFLOW_INPUT_BINDING_INVALID")
    for name, binding in (("RGBA", rgba_binding), ("MASK", mask_binding)):
        if not isinstance(binding, list) or not binding or not all(isinstance(item, str) and item for item in binding):
            raise Spike6RunnerError(f"WORKFLOW_{name}_OUTPUT_BINDING_INVALID")
    if not rgba_node_id or rgba_node_id not in workflow or not mask_node_id or mask_node_id not in workflow or rgba_node_id == mask_node_id:
        raise Spike6RunnerError("WORKFLOW_OUTPUT_NODES_INVALID")
    if any(not isinstance(node, dict) or "class_type" not in node for node in workflow.values()):
        raise Spike6RunnerError("WORKFLOW_GRAPH_INVALID")
    class_types = [str(node.get("class_type")) for node in workflow.values()]
    required_counts = {
        "LoadImage": 1,
        "LoadBackgroundRemovalModel": 1,
        "RemoveBackground": 1,
        "MaskToImage": 1,
        "InvertMask": 1,
        "JoinImageWithAlpha": 1,
        "SaveImage": 2,
    }
    if len(class_types) != 8 or any(class_types.count(name) != count for name, count in required_counts.items()):
        raise Spike6RunnerError("WORKFLOW_NATIVE_BIREFNET_CHAIN_INVALID")
    model_nodes = [node for node in workflow.values() if node.get("class_type") == "LoadBackgroundRemovalModel"]
    if model_nodes[0].get("inputs", {}).get("bg_removal_name") != "birefnet.safetensors":
        raise Spike6RunnerError("WORKFLOW_BIREFNET_MODEL_INVALID")
    return workflow, {
        "sha256": actual_hash,
        "input_image_binding": input_binding,
        "rgba_output_prefix_binding": rgba_binding,
        "mask_output_prefix_binding": mask_binding,
        "rgba_output_node_id": rgba_node_id,
        "mask_output_node_id": mask_node_id,
    }


def _history_image(entry: Mapping[str, Any], output_node_id: str) -> Mapping[str, Any] | None:
    outputs = entry.get("outputs")
    node = outputs.get(output_node_id) if isinstance(outputs, Mapping) else None
    images = node.get("images") if isinstance(node, Mapping) else None
    if images is None:
        return None
    if not isinstance(images, list) or len(images) != 1 or not isinstance(images[0], Mapping):
        raise Spike6RunnerError("EXPECTED_EXACTLY_ONE_BIREFNET_OUTPUT")
    return images[0]


def _history_outputs(entry: Mapping[str, Any], workflow_meta: Mapping[str, Any]) -> tuple[Mapping[str, Any], Mapping[str, Any]] | None:
    rgba = _history_image(entry, str(workflow_meta["rgba_output_node_id"]))
    mask = _history_image(entry, str(workflow_meta["mask_output_node_id"]))
    if rgba is None or mask is None:
        return None
    return rgba, mask


def _download_output(transport: Transport, descriptor: Mapping[str, Any], label: str) -> bytes:
    filename = descriptor.get("filename")
    subfolder = descriptor.get("subfolder", "")
    image_type = descriptor.get("type", "output")
    if not isinstance(filename, str) or not filename or not isinstance(subfolder, str) or image_type != "output":
        raise Spike6RunnerError(f"COMFYUI_{label}_OUTPUT_DESCRIPTOR_INVALID")
    query = urllib.parse.urlencode({"filename": filename, "subfolder": subfolder, "type": "output"})
    payload = transport.get_bytes(f"/view?{query}")
    if not payload.startswith(PNG_SIGNATURE):
        raise Spike6RunnerError(f"BIREFNET_{label}_OUTPUT_NOT_PNG")
    return payload


def _decode_png(payload: bytes, label: str) -> Image.Image:
    try:
        with Image.open(io.BytesIO(payload)) as opened:
            if opened.format != "PNG":
                raise Spike6RunnerError(f"BIREFNET_{label}_OUTPUT_NOT_PNG")
            opened.load()
            return opened.copy()
    except (OSError, ValueError) as exc:
        raise Spike6RunnerError(f"BIREFNET_{label}_OUTPUT_PNG_INVALID") from exc


def _validate_rgba_png(payload: bytes) -> bytes:
    image = _decode_png(payload, "RGBA")
    if image.mode != "RGBA":
        raise Spike6RunnerError(f"BIREFNET_RGBA_MODE_INVALID:{image.mode}")
    return payload


def _normalise_mask_png(payload: bytes) -> bytes:
    """Losslessly map Comfy's grayscale RGB(A) mask representation to mode L."""

    image = _decode_png(payload, "MASK")
    if image.mode == "L":
        mask = image
    elif image.mode in {"RGB", "RGBA"}:
        channels = image.split()
        if channels[0].tobytes() != channels[1].tobytes() or channels[0].tobytes() != channels[2].tobytes():
            raise Spike6RunnerError("BIREFNET_MASK_NOT_GRAYSCALE")
        mask = channels[0]
    else:
        raise Spike6RunnerError(f"BIREFNET_MASK_MODE_INVALID:{image.mode}")
    output = io.BytesIO()
    mask.save(output, format="PNG")
    normalised = output.getvalue()
    check = _decode_png(normalised, "MASK_NORMALISED")
    if check.mode != "L" or check.tobytes() != mask.tobytes():
        raise Spike6RunnerError("BIREFNET_MASK_NORMALISATION_FAILED")
    return normalised


def _write_new(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _safe_run_id(run_id: str) -> str:
    if not run_id or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for character in run_id):
        raise Spike6RunnerError("RUN_ID_INVALID")
    return run_id


def _require_child(path: Path, parent: Path, field: str) -> None:
    try:
        path.resolve(strict=False).relative_to(parent.resolve(strict=False))
    except (OSError, ValueError) as exc:
        raise Spike6RunnerError(f"{field}_OUTSIDE_SPIKE6_BOUNDARY") from exc


def run(
    config_file: Path,
    run_id: str,
    *,
    transport: Transport | None = None,
    port_probe: Callable[[int], bool] = is_loopback_port_open,
    monotonic: Callable[[], float] = time.monotonic,
    sleeper: Callable[[float], None] = time.sleep,
    flux2_root: Path | None = None,
) -> Path:
    """Submit exactly eight jobs serially, with no retry, then atomically publish."""

    safe_run = _safe_run_id(run_id)
    config = load_config(config_file)
    flux2_root = (flux2_root or Path(__file__).resolve().parents[1]).resolve(strict=True)
    freeze_path = Path(config["source_freeze_file"])
    _require_child(freeze_path, flux2_root / "birefnet" / "config", "SOURCE_FREEZE")
    _require_child(Path(config["workflow_file"]), flux2_root / "workflows", "WORKFLOW")
    _require_child(Path(config["output_root"]), flux2_root / "birefnet" / "output", "OUTPUT_ROOT")
    if freeze_path.is_symlink() or not freeze_path.is_file() or sha256_file(freeze_path) != config["source_freeze_sha256"]:
        raise Spike6RunnerError("SOURCE_FREEZE_HASH_MISMATCH")
    freeze = verify_freeze(flux2_root, freeze_path)
    workflow, workflow_meta = load_approved_workflow(config)
    if port_probe(FORBIDDEN_PORT):
        raise Spike6RunnerError("PORT_8188_IS_LISTENING")
    active_transport = transport or LoopbackHttpTransport(APPROVED_API_BASE, float(config["timeout_seconds"]))
    health = active_transport.get_json("/system_stats")
    if not health:
        raise Spike6RunnerError("COMFYUI_8190_HEALTH_FAILED")

    output_root = Path(config["output_root"])
    final = output_root / safe_run
    if os.path.lexists(final):
        raise Spike6RunnerError("SPIKE6_RUN_ALREADY_EXISTS")
    stage = output_root / ".tmp" / f"{safe_run}-{uuid.uuid4().hex}"
    stage.mkdir(parents=True, exist_ok=False)
    results: list[dict[str, Any]] = []
    client_id = uuid.uuid4().hex
    try:
        for expected_ordinal, job in enumerate(freeze["jobs"], 1):
            if job.get("ordinal") != expected_ordinal:
                raise Spike6RunnerError("FROZEN_JOB_ORDER_CHANGED")
            verify_freeze(flux2_root, freeze)
            if sha256_file(freeze_path) != config["source_freeze_sha256"]:
                raise Spike6RunnerError("SOURCE_FREEZE_CHANGED_DURING_RUN")
            case_id = str(job["case_id"])
            seed_id = str(job["seed_id"])
            raw_entry = job["raw"]
            raw_path = (flux2_root / raw_entry["path"]).resolve(strict=True)
            raw_bytes = raw_path.read_bytes()
            if hashlib.sha256(raw_bytes).hexdigest() != raw_entry["sha256"]:
                raise Spike6RunnerError("FROZEN_RAW_CHANGED_DURING_READ")

            upload_name = f"ForgeSpike6_{safe_run}_{expected_ordinal:02d}.png"
            uploaded = active_transport.post_file("/upload/image", filename=upload_name, payload=raw_bytes)
            uploaded_name = uploaded.get("name")
            if not isinstance(uploaded_name, str) or not uploaded_name:
                raise Spike6RunnerError("COMFYUI_UPLOAD_RESPONSE_INVALID")
            uploaded_subfolder = uploaded.get("subfolder", "")
            if not isinstance(uploaded_subfolder, str):
                raise Spike6RunnerError("COMFYUI_UPLOAD_SUBFOLDER_INVALID")
            input_reference = f"{uploaded_subfolder}/{uploaded_name}".lstrip("/")
            graph = copy.deepcopy(workflow)
            _set_path(graph, workflow_meta["input_image_binding"], input_reference)
            _set_path(
                graph,
                workflow_meta["rgba_output_prefix_binding"],
                f"ForgeSpike6/{safe_run}/{expected_ordinal:02d}_{case_id}_{seed_id}/rgba",
            )
            _set_path(
                graph,
                workflow_meta["mask_output_prefix_binding"],
                f"ForgeSpike6/{safe_run}/{expected_ordinal:02d}_{case_id}_{seed_id}/mask",
            )
            request = {"prompt": graph, "client_id": client_id}
            submitted = active_transport.post_json("/prompt", request)
            prompt_id = submitted.get("prompt_id")
            if not isinstance(prompt_id, str) or not prompt_id:
                raise Spike6RunnerError("COMFYUI_PROMPT_ID_INVALID")
            started = monotonic()
            outputs: tuple[Mapping[str, Any], Mapping[str, Any]] | None = None
            while outputs is None:
                if monotonic() - started > float(config["timeout_seconds"]):
                    raise Spike6RunnerError(f"COMFYUI_TIMEOUT:{expected_ordinal}")
                history = active_transport.get_json(f"/history/{urllib.parse.quote(prompt_id, safe='')}")
                entry = history.get(prompt_id)
                if isinstance(entry, Mapping):
                    status = entry.get("status")
                    if isinstance(status, Mapping) and status.get("status_str") in {"error", "failed"}:
                        raise Spike6RunnerError(f"COMFYUI_JOB_FAILED:{expected_ordinal}")
                    outputs = _history_outputs(entry, workflow_meta)
                if outputs is None:
                    sleeper(float(config["poll_interval_seconds"]))
            rgba_download = _download_output(active_transport, outputs[0], "RGBA")
            mask_download = _download_output(active_transport, outputs[1], "MASK")
            rgba_bytes = _validate_rgba_png(rgba_download)
            mask_bytes = _normalise_mask_png(mask_download)
            job_dir = stage / f"{expected_ordinal:02d}_{case_id}_{seed_id}"
            _write_new(job_dir / "rgba.png", rgba_bytes)
            _write_new(job_dir / "mask.png", mask_bytes)
            _write_new(job_dir / "request_workflow.json", _json_bytes(graph))
            job_manifest = {
                "contract": "forge-birefnet-spike6-job-v1",
                "ordinal": expected_ordinal,
                "case_id": case_id,
                "seed_id": seed_id,
                "source_raw_path": raw_entry["path"],
                "source_raw_sha256": raw_entry["sha256"],
                "workflow_sha256": workflow_meta["sha256"],
                "prompt_id": prompt_id,
                "retry_count": 0,
                "rgba_file": "rgba.png",
                "rgba_sha256": hashlib.sha256(rgba_bytes).hexdigest(),
                "rgba_comfy_descriptor": dict(outputs[0]),
                "mask_file": "mask.png",
                "mask_sha256": hashlib.sha256(mask_bytes).hexdigest(),
                "mask_download_sha256": hashlib.sha256(mask_download).hexdigest(),
                "mask_comfy_descriptor": dict(outputs[1]),
                "mask_representation": "L",
                "status": "success",
            }
            _write_new(job_dir / "manifest.json", _json_bytes(job_manifest))
            results.append(job_manifest)

        verify_freeze(flux2_root, freeze)
        if sha256_file(freeze_path) != config["source_freeze_sha256"]:
            raise Spike6RunnerError("SOURCE_FREEZE_CHANGED_DURING_RUN")
        run_manifest = {
            "contract": "forge-birefnet-spike6-run-v1",
            "run_id": safe_run,
            "api_base": APPROVED_API_BASE,
            "source_freeze_file": freeze_path.relative_to(flux2_root).as_posix(),
            "source_freeze_sha256": config["source_freeze_sha256"],
            "source_matrix_run_id": freeze["source_matrix_run_id"],
            "workflow_sha256": workflow_meta["sha256"],
            "planned_job_count": 8,
            "completed_job_count": len(results),
            "retry_count": 0,
            "serial_execution": True,
            "jobs": results,
            "status": "success",
        }
        _write_new(stage / "run_manifest.json", _json_bytes(run_manifest))
        hashes = {
            path.relative_to(stage).as_posix(): sha256_file(path)
            for path in sorted(stage.rglob("*"))
            if path.is_file()
        }
        _write_new(stage / "evidence_hashes.json", _json_bytes({"algorithm": "SHA-256", "files": hashes}))
        verify_freeze(flux2_root, freeze)
        final.parent.mkdir(parents=True, exist_ok=True)
        if os.path.lexists(final):
            raise Spike6RunnerError("SPIKE6_RUN_ALREADY_EXISTS")
        os.rename(stage, final)
        return final
    except Exception:
        # A failed run remains only under .tmp; no consumer-visible final directory
        # is published, and no request is retried.
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    try:
        output = run(args.config, args.run_id)
        print(json.dumps({"status": "success", "output_directory": str(output)}, ensure_ascii=False))
        return 0
    except (Spike6RunnerError, Spike5FreezeError) as exc:
        print(json.dumps({"status": "failed", "failure_reason": str(exc)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
