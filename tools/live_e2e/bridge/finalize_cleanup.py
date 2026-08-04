#!/usr/bin/env python3
"""Finalize Spike 7 evidence only after credentials and local services are gone."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


BRIDGE_DIR = Path(__file__).resolve().parent
LIVE_ROOT = BRIDGE_DIR.parent
PLAYLAB = LIVE_ROOT.parents[1]
SEMANTIC_BRIDGE = PLAYLAB / "tools" / "semantic" / "bridge"
for root in (BRIDGE_DIR, SEMANTIC_BRIDGE):
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

from live_preflight import verify_history  # noqa: E402
from secret_scan import scan_repository  # noqa: E402


class CleanupError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.25)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_replace_json(path: Path, value: Any) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False, suffix=".tmp") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
        temporary = Path(handle.name)
    os.replace(temporary, path)


def atomic_replace_text(path: Path, value: str) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False, suffix=".tmp") as handle:
        handle.write(value)
        handle.flush()
        os.fsync(handle.fileno())
        temporary = Path(handle.name)
    os.replace(temporary, path)


def git_state(root: Path) -> tuple[str, str]:
    def run(*args: str) -> str:
        completed = subprocess.run(
            ["git", "-C", str(root), *args], text=True, encoding="utf-8", errors="replace",
            capture_output=True, check=False,
        )
        if completed.returncode != 0:
            raise CleanupError(f"GIT_CHECK_FAILED:{root.name}:{args[0]}")
        return completed.stdout.strip()
    head = run("rev-parse", "HEAD")
    status_hash = hashlib.sha256(run("status", "--porcelain=v1", "-uall").encode("utf-8")).hexdigest()
    return head, status_hash


def residual_processes(session_id: str) -> list[int]:
    try:
        import psutil  # type: ignore
    except ImportError as exc:
        raise CleanupError("PSUTIL_REQUIRED_FOR_PROCESS_ATTESTATION") from exc
    result = []
    for process in psutil.process_iter(["pid", "cmdline"]):
        try:
            command = " ".join(process.info.get("cmdline") or [])
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
        if session_id in command and ("main.py" in command or "live_server.py" in command):
            result.append(int(process.info["pid"]))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--preflight-file", type=Path, required=True)
    args = parser.parse_args()
    report_root = LIVE_ROOT / "reports" / args.run_id
    output_root = LIVE_ROOT / "output" / "runs" / args.run_id
    summary_path = report_root / "live_e2e_summary.json"
    report_path = report_root / "LIVE_E2E_REPORT.md"
    final_hashes = report_root / "evidence_hashes.json"
    cleanup_path = report_root / "post_run_cleanup.json"
    try:
        if final_hashes.exists() or cleanup_path.exists():
            raise CleanupError("FINAL_CLEANUP_EVIDENCE_ALREADY_EXISTS")
        if not summary_path.is_file() or not report_path.is_file() or not output_root.is_dir():
            raise CleanupError("PIPELINE_REPORTS_MISSING")
        if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("FORGE_SEMANTIC_MODEL"):
            raise CleanupError("SEMANTIC_ENVIRONMENT_NOT_CLEARED")
        for port in (8188, 8190, 8767):
            if port_open(port):
                raise CleanupError(f"PORT_STILL_LISTENING:{port}")
        residual = residual_processes(args.session_id)
        if residual:
            raise CleanupError("OWNED_PROCESS_REMAINS")
        preflight = json.loads(args.preflight_file.read_text(encoding="utf-8"))
        history = preflight.get("historical_evidence")
        if not isinstance(history, dict):
            raise CleanupError("HISTORICAL_BASELINE_MISSING")
        verify_history(PLAYLAB, history)
        for repository in preflight.get("formal_repositories", []):
            head, status_hash = git_state(Path(repository["path"]))
            if head != repository["head"] or status_hash != repository["status_sha256"]:
                raise CleanupError("FORMAL_REPOSITORY_CHANGED")
        findings = scan_repository(PLAYLAB)
        if findings:
            raise CleanupError(f"SECRET_SCAN_FAILED:{len(findings)}")
        cleanup = {
            "contract": "forge-live-e2e-spike7-post-run-cleanup-v1",
            "status": "PASS",
            "run_id": args.run_id,
            "session_id": args.session_id,
            "anthropic_environment_cleared": True,
            "port_8190_closed": True,
            "port_8188_closed": True,
            "bridge_port_8767_closed": True,
            "owned_process_residual_count": 0,
            "historical_evidence_unchanged": True,
            "formal_repositories_unchanged": True,
            "secret_scan_pass": True,
            "secret_findings": 0,
            "verified_at_utc": utc_now(),
        }
        cleanup_path.write_bytes((json.dumps(cleanup, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        summary["post_run_cleanup_status"] = "PASS"
        summary["post_run_cleanup"] = cleanup
        atomic_replace_json(summary_path, summary)
        report = report_path.read_text(encoding="utf-8")
        marker = "## 最终清理证明"
        if marker in report:
            raise CleanupError("REPORT_CLEANUP_SECTION_ALREADY_EXISTS")
        report += f"""

## 最终清理证明

- ANTHROPIC_API_KEY 与 FORGE_SEMANTIC_MODEL 已从入口进程环境清除。
- 127.0.0.1:8190、8188、127.0.0.1:8767 均已关闭。
- 隔离 ComfyUI 与 Live bridge 残留进程：0。
- 历史 Spike 证据哈希与正式仓库状态：未改变。
- Secret scan：PASS，0 findings。
- 验证时间：{cleanup['verified_at_utc']}。
"""
        atomic_replace_text(report_path, report)
        hashes = {}
        for root in (output_root, report_root):
            for path in sorted(root.rglob("*")):
                if path.is_file() and path.name != "evidence_hashes.json":
                    hashes[str(path.relative_to(LIVE_ROOT)).replace("\\", "/")] = sha256_file(path)
        final_hashes.write_bytes((json.dumps({"algorithm": "SHA-256", "files": hashes}, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    except (CleanupError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps({"status": "PASS", "report_path": str(report_path), "evidence_hashes": str(final_hashes)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
