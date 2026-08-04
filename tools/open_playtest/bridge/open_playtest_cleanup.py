#!/usr/bin/env python3
"""Post-run cleanup attestation for Open Playtest Mode."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import subprocess
import sys
from pathlib import Path


BRIDGE_DIR = Path(__file__).resolve().parent
OPEN_ROOT = BRIDGE_DIR.parent
PLAYLAB = OPEN_ROOT.parents[1]
LIVE_BRIDGE = PLAYLAB / "tools" / "live_e2e" / "bridge"
SEMANTIC_BRIDGE = PLAYLAB / "tools" / "semantic" / "bridge"
for root in (BRIDGE_DIR, LIVE_BRIDGE, SEMANTIC_BRIDGE):
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

from live_preflight import verify_history  # noqa: E402
from open_playtest_session import _atomic_replace, _json_bytes, evidence_hashes  # noqa: E402
from secret_scan import scan_repository  # noqa: E402


class CleanupError(RuntimeError):
    pass


def _port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.2)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def _git_state(root: Path) -> tuple[str, str]:
    def run(*args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(root), *args], text=True, encoding="utf-8",
            errors="replace", capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise CleanupError(f"GIT_CHECK_FAILED:{root.name}:{args[0]}")
        return result.stdout.strip()
    head = run("rev-parse", "HEAD")
    status_hash = hashlib.sha256(run("status", "--porcelain=v1", "-uall").encode("utf-8")).hexdigest()
    return head, status_hash


def _residual_processes(session_id: str) -> list[int]:
    try:
        import psutil  # type: ignore
    except ImportError as exc:
        raise CleanupError("PSUTIL_REQUIRED") from exc
    result: list[int] = []
    for process in psutil.process_iter(["pid", "cmdline"]):
        try:
            command = " ".join(process.info.get("cmdline") or [])
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
        if session_id in command and ("main.py" in command or "open_playtest_server.py" in command):
            result.append(int(process.info["pid"]))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--preflight-file", type=Path, required=True)
    parser.add_argument("--session-output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("FORGE_SEMANTIC_MODEL"):
            raise CleanupError("SEMANTIC_ENVIRONMENT_NOT_CLEARED")
        for port in (8188, 8190, 8771):
            if _port_open(port):
                raise CleanupError(f"PORT_STILL_LISTENING:{port}")
        residual = _residual_processes(args.session_id)
        if residual:
            raise CleanupError("OWNED_PROCESS_REMAINS")
        preflight = json.loads(args.preflight_file.read_text(encoding="utf-8"))
        history = preflight.get("historical_evidence")
        if not isinstance(history, dict):
            raise CleanupError("HISTORICAL_BASELINE_MISSING")
        verify_history(PLAYLAB, history)
        for repository in preflight.get("formal_repositories", []):
            head, status_hash = _git_state(Path(repository["path"]))
            if head != repository["head"] or status_hash != repository["status_sha256"]:
                raise CleanupError("FORMAL_REPOSITORY_CHANGED")
        project = (PLAYLAB / "project.godot").read_text(encoding="utf-8")
        provider = (PLAYLAB / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
        if 'run/main_scene="res://scenes/open_identity_spike.tscn"' not in project or "var provider_mode := MODE_MOCK" not in provider:
            raise CleanupError("DEFAULT_MOCK_BOUNDARY_CHANGED")
        findings = scan_repository(PLAYLAB)
        if findings:
            raise CleanupError(f"SECRET_SCAN_FAILED:{len(findings)}")
        cleanup = {
            "contract": "forge-open-playtest-cleanup-v1",
            "status": "PASS",
            "session_id": args.session_id,
            "anthropic_environment_cleared": True,
            "ports_closed": {"8188": True, "8190": True, "8771": True},
            "owned_process_residual_count": 0,
            "historical_spike_evidence_unchanged": True,
            "formal_repositories_unchanged": True,
            "default_player_mode": "MOCK",
            "secret_scan_findings": 0,
        }
        output = args.session_output.resolve()
        output.mkdir(parents=True, exist_ok=True)
        cleanup_path = output / "post_run_cleanup.json"
        if cleanup_path.exists():
            raise CleanupError("CLEANUP_EVIDENCE_ALREADY_EXISTS")
        cleanup_path.write_bytes(_json_bytes(cleanup))
        _atomic_replace(output / "evidence_hashes.json", _json_bytes(evidence_hashes(output)))
    except (CleanupError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps({"status": "PASS", "cleanup": str(cleanup_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
