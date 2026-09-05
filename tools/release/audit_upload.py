"""Offline upload preflight. Report file/rule only, never matched secret values.

Use --staged to inspect the actual Git index rather than the working copy.
This is a conservative heuristic gate, not a proof that arbitrary data is safe.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/semantic/bridge"))
import secret_scan

PATTERNS = {
    "provider_key": re.compile(r"\bsk-(?:proj-|ant-(?:api\d+-)?|svcacct-)?[A-Za-z0-9_-]{20,}"),
    "github_token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{35,})"),
    "private_key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "aws_access_key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "fal_key_shape": re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[A-Za-z0-9_-]{24,}\b"),
    "credential_in_url": re.compile(r"https?://[^\s/@:'\"]+:[^\s/@'\"]+@"),
    "personal_windows_path": re.compile(r"(?i)[A-Z]:[\\/]+Users[\\/]+(?!Public\b|Default\b|<|USER\b|example\b)[^\\/\s\"'`]+"),
}
BLOCKED_ROOTS = {".tools", ".godot", "sessions", "weapons", "sunny-expedition-v1", "church-expedition-v1", "build"}


def path_rules(path: str) -> set[str]:
    relative = path.removeprefix("git-index:")
    parts = Path(relative).parts
    name = Path(relative).name.lower()
    rules = set()
    if parts and parts[0] in BLOCKED_ROOTS:
        rules.add("local_only_directory")
    if name == ".env" or (name.startswith(".env.") and name not in {".env.example", ".env.template"}):
        rules.add("credential_file")
    if name.endswith((".import", ".pyc", ".zip", ".exe", ".pck", ".log", ".local.json")):
        rules.add("generated_or_local_file")
    return rules


def content_rules(raw: bytes) -> set[str]:
    rules = set()
    if b"\0" in raw[:8192]:
        return rules
    text = raw.decode("utf-8", errors="replace")
    for _ in range(3):
        # Exact synthetic SSRF fixture used by the existing provider tests.
        # Do not exempt test files or arbitrary user:password URLs.
        scan_text = text.replace("http://127.0.0.1:8188@evil.example", "SYNTHETIC_SSRF_FIXTURE")
        rules.update(name for name, pattern in PATTERNS.items() if pattern.search(scan_text))
        decoded = re.sub(r"\\+u([0-9a-fA-F]{4})", lambda m: chr(int(m[1], 16)), text)
        if decoded == text:
            break
        text = decoded
    return rules


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true")
    args = parser.parse_args()
    if args.staged:
        entries, error = secret_scan._git_index_blobs(ROOT)
        if error:
            print(json.dumps({"ok": False, "error": error.rule}))
            return 1
    else:
        result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT, check=True, capture_output=True)
        names = sorted(set(p.decode("utf-8") for p in result.stdout.split(b"\0") if p))
        entries = [(name, (ROOT / name).read_bytes()) for name in names if (ROOT / name).is_file()]
    findings = []
    total_bytes = 0
    for path, raw in entries:
        total_bytes += len(raw)
        rules = path_rules(path) | content_rules(raw)
        rules.update(f.rule for f in secret_scan._scan_bytes(path, raw))
        if len(raw) >= 95 * 1024 * 1024:
            rules.add("oversized_git_blob")
        for rule in sorted(rules):
            safe_path, _ = secret_scan._safe_display_path(path)
            findings.append({"path": safe_path, "rule": rule})
    print(json.dumps({"ok": not findings, "scope": "git-index" if args.staged else "candidate-worktree", "files": len(entries), "bytes": total_bytes, "findings": findings}, ensure_ascii=True, indent=2))
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
