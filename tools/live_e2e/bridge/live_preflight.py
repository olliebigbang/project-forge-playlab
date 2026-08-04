#!/usr/bin/env python3
"""Fail-closed preflight and immutable-scope baseline for Live E2E Spike 7."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import socket
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


APPROVED_MODEL_ID = "claude-sonnet-5"
MINIMUM_FREE_BYTES = 50 * 1024**3
MODEL_FILES = {
    Path(r"C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\diffusion_models\flux-2-klein-4b-fp8.safetensors"): "97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6",
    Path(r"C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\text_encoders\qwen_3_4b.safetensors"): "6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a",
    Path(r"C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\vae\flux2-vae.safetensors"): "d64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5",
    Path(r"C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\background_removal\birefnet.safetensors"): "9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154",
}


class LivePreflightError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.25)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def _git(root: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(root), *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise LivePreflightError(f"GIT_COMMAND_FAILED:{root.name}:{args[0]}")
    return completed.stdout.strip()


def _history_files(playlab: Path) -> list[Path]:
    roots = [playlab / "tools" / "semantic" / "reports", playlab / "tools" / "comfyui"]
    selected: set[Path] = set()
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or "live_e2e" in path.parts:
                continue
            lowered = path.name.lower()
            if lowered == "evidence_hashes.json" or lowered.endswith("summary.json") or lowered.endswith("report.md"):
                selected.add(path.resolve())
            elif lowered in {"model_download_manifest.json", "official_source_manifest.json", "spike5_evidence.freeze.json"}:
                selected.add(path.resolve())
    if not selected:
        raise LivePreflightError("HISTORICAL_EVIDENCE_NOT_FOUND")
    return sorted(selected, key=lambda value: value.as_posix().lower())


def capture_history(playlab: Path) -> dict[str, str]:
    return {
        path.relative_to(playlab).as_posix(): sha256_file(path)
        for path in _history_files(playlab)
    }


def verify_history(playlab: Path, expected: dict[str, str]) -> None:
    for relative, wanted in expected.items():
        path = (playlab / relative).resolve()
        if not path.is_file() or sha256_file(path) != wanted:
            raise LivePreflightError(f"HISTORICAL_EVIDENCE_CHANGED:{relative}")


def _assert_default_mock(playlab: Path) -> None:
    project_text = (playlab / "project.godot").read_text(encoding="utf-8")
    script_text = (playlab / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
    if 'run/main_scene="res://scenes/open_identity_spike.tscn"' not in project_text:
        raise LivePreflightError("DEFAULT_MAIN_SCENE_CHANGED")
    if "var provider_mode := MODE_MOCK" not in script_text:
        raise LivePreflightError("DEFAULT_PROVIDER_IS_NOT_MOCK")


def _assert_gpu() -> dict[str, Any]:
    executable = shutil.which("nvidia-smi")
    if not executable:
        raise LivePreflightError("NVIDIA_SMI_NOT_FOUND")
    completed = subprocess.run(
        [executable, "--query-gpu=name,memory.total,memory.free", "--format=csv,noheader,nounits"],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    line = completed.stdout.strip().splitlines()[0] if completed.stdout.strip() else ""
    fields = [part.strip() for part in line.split(",")]
    if completed.returncode != 0 or len(fields) != 3:
        raise LivePreflightError("GPU_PROBE_FAILED")
    try:
        total = int(fields[1])
        free = int(fields[2])
    except ValueError as exc:
        raise LivePreflightError("GPU_PROBE_INVALID") from exc
    if total <= 0 or free <= 0:
        raise LivePreflightError("GPU_NOT_AVAILABLE")
    return {"name": fields[0], "memory_total_mb": total, "memory_free_mb": free}


def _model_records() -> list[dict[str, Any]]:
    records = []
    for path, wanted in MODEL_FILES.items():
        if not path.is_file():
            raise LivePreflightError(f"MODEL_FILE_MISSING:{path.name}")
        actual = sha256_file(path)
        if actual != wanted:
            raise LivePreflightError(f"MODEL_SHA256_MISMATCH:{path.name}")
        records.append({"path": str(path), "bytes": path.stat().st_size, "sha256": actual})
    return records


def _formal_state(roots: Iterable[Path]) -> list[dict[str, str]]:
    states = []
    for root in roots:
        if not (root / ".git").exists():
            raise LivePreflightError(f"FORMAL_REPOSITORY_MISSING:{root}")
        states.append(
            {
                "path": str(root.resolve()),
                "head": _git(root, "rev-parse", "HEAD"),
                "status_sha256": hashlib.sha256(_git(root, "status", "--porcelain=v1", "-uall").encode("utf-8")).hexdigest(),
            }
        )
    return states


def build_preflight(playlab: Path, formal_roots: list[Path]) -> dict[str, Any]:
    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise LivePreflightError("ANTHROPIC_API_KEY_MISSING")
    model_id = os.environ.get("FORGE_SEMANTIC_MODEL", "")
    if model_id != APPROVED_MODEL_ID:
        raise LivePreflightError("FORGE_SEMANTIC_MODEL_NOT_APPROVED")
    if port_open(8188):
        raise LivePreflightError("PORT_8188_MUST_BE_CLOSED")
    if port_open(8190):
        raise LivePreflightError("PORT_8190_ALREADY_IN_USE")
    _assert_default_mock(playlab)
    free_bytes = shutil.disk_usage(Path("C:/")).free
    if free_bytes < MINIMUM_FREE_BYTES:
        raise LivePreflightError("INSUFFICIENT_C_DRIVE_SPACE")
    return {
        "contract": "forge-live-e2e-spike7-preflight-v1",
        "status": "PASS",
        "checked_at_utc": utc_now(),
        "anthropic_key_present": True,
        "anthropic_key_persisted": False,
        "model_id": model_id,
        "semantic_contract": "forge-semantic-v1.1",
        "port_8188_closed": True,
        "port_8190_closed_before_start": True,
        "default_player_mode": "MOCK",
        "c_drive_free_bytes": free_bytes,
        "gpu": _assert_gpu(),
        "models": _model_records(),
        "historical_evidence": capture_history(playlab),
        "formal_repositories": _formal_state(formal_roots),
        "playlab_head": _git(playlab, "rev-parse", "HEAD"),
    }


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False, suffix=".tmp") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
        temp = Path(handle.name)
    if path.exists():
        temp.unlink(missing_ok=True)
        raise LivePreflightError(f"REFUSING_TO_OVERWRITE_PREFLIGHT:{path}")
    os.replace(temp, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--playlab", type=Path, required=True)
    parser.add_argument("--formal-repo", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build_preflight(args.playlab.resolve(), [path.resolve() for path in args.formal_repo])
        write_json_atomic(args.output.resolve(), result)
    except LivePreflightError as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps({"status": "PASS", "output": str(args.output.resolve())}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
