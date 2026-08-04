"""Read-only scope guard for the isolated Gate A runner."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


_EXCLUDED_TOP_LEVEL = {
    ".git",
    ".godot",
    ".tools",
    ".playwright-cli",
    "artifacts",
    "build",
}


class ScopeGuardError(RuntimeError):
    pass


def protected_files(repository_root: Path) -> list[Path]:
    root = repository_root.resolve()
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if not relative.parts:
            continue
        if relative.parts[0] in _EXCLUDED_TOP_LEVEL:
            continue
        if relative.as_posix() == ".gitignore":
            # Gate A is explicitly authorised to add its ignore rules.
            continue
        if len(relative.parts) >= 2 and relative.parts[:2] == ("tools", "semantic"):
            continue
        files.append(path)
    return sorted(files, key=lambda item: item.relative_to(root).as_posix())


def protected_scope_snapshot(repository_root: Path) -> dict[str, Any]:
    root = repository_root.resolve()
    records: list[str] = []
    for path in protected_files(root):
        relative = path.relative_to(root).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
        records.append(f"{relative}={digest}")
    aggregate = hashlib.sha256("\n".join(records).encode("utf-8")).hexdigest()
    return {
        "algorithm": "SHA-256(path=uppercase-file-sha256 records)",
        "file_count": len(records),
        "aggregate_sha256": aggregate,
    }


def verify_scope_baseline(repository_root: Path, baseline_path: Path) -> dict[str, Any]:
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ScopeGuardError("Gate A scope baseline is unreadable.") from exc
    expected = baseline.get("pre_execution_protected_scope")
    if not isinstance(expected, dict):
        raise ScopeGuardError("Gate A protected-scope baseline is missing.")
    actual = protected_scope_snapshot(repository_root)
    if (
        expected.get("algorithm") != actual["algorithm"]
        or expected.get("file_count") != actual["file_count"]
        or expected.get("aggregate_sha256") != actual["aggregate_sha256"]
    ):
        raise ScopeGuardError(
            "Protected gameplay/Web/ComfyUI scope differs from the pre-execution baseline."
        )
    return actual


__all__ = [
    "ScopeGuardError",
    "protected_files",
    "protected_scope_snapshot",
    "verify_scope_baseline",
]
