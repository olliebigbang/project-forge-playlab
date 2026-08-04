from __future__ import annotations

import argparse
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path


_SECRET_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("anthropic_key_shape", re.compile(r"sk-ant-[A-Za-z0-9_-]{16,}")),
    ("semantic_dummy_marker", re.compile(r"SEMANTIC_SECRET_TEST_[A-Za-z0-9_-]{8,}")),
    (
        "literal_anthropic_env_assignment",
        re.compile(
            r"""(?ix)
            ANTHROPIC_API_KEY\s*=\s*
            (?P<quote>["'])
            (?!\$\{|<|environment|process|os\.)
            [^"'\r\n]{12,}
            (?P=quote)
            """
        ),
    ),
)

_JSON_UNICODE_ESCAPE_PATTERN = re.compile(r"\\+u([0-9A-Fa-f]{4})")
_MAX_UNICODE_PROJECTION_DEPTH = 8


@dataclass(frozen=True)
class SecretFinding:
    path: str
    rule: str


def _git_child_environment() -> dict[str, str]:
    child_environment = dict(os.environ)
    for name in tuple(child_environment):
        if name.upper().startswith("GIT_") or name in {
            "ANTHROPIC_API_KEY",
            "FORGE_SEMANTIC_MODEL",
        }:
            child_environment.pop(name, None)
    return child_environment


def _matching_rules(text: str) -> set[str]:
    matched_rules: set[str] = set()
    current = text
    for depth in range(_MAX_UNICODE_PROJECTION_DEPTH + 1):
        for rule, pattern in _SECRET_PATTERNS:
            if pattern.search(current):
                matched_rules.add(rule)
        if depth == _MAX_UNICODE_PROJECTION_DEPTH:
            if _JSON_UNICODE_ESCAPE_PATTERN.search(current):
                matched_rules.add("unicode_projection_depth_exceeded")
            break
        decoded = _JSON_UNICODE_ESCAPE_PATTERN.sub(
            lambda match: chr(int(match.group(1), 16)), current
        )
        if decoded == current:
            break
        current = decoded
    return matched_rules


def _safe_display_path(display_path: str) -> tuple[str, bool]:
    if _matching_rules(display_path):
        return "<redacted-sensitive-path>", True
    return display_path, False


def _scan_bytes(display_path: str, raw: bytes) -> list[SecretFinding]:
    if b"\0" in raw:
        return []
    text = raw.decode("utf-8", errors="replace")
    matched_rules = _matching_rules(text)
    return [SecretFinding(display_path, rule) for rule in sorted(matched_rules)]


def _git_index_blobs(root: Path) -> tuple[list[tuple[str, bytes]], SecretFinding | None]:
    if not (root / ".git").exists():
        return [], None
    try:
        completed = subprocess.run(
            ["git", "ls-files", "--stage", "-z"],
            cwd=root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_git_child_environment(),
        )
    except (OSError, subprocess.CalledProcessError):
        return [], SecretFinding("<git-index>", "git_index_unreadable")

    entries: list[tuple[str, str]] = []
    for raw_entry in completed.stdout.split(b"\0"):
        if not raw_entry:
            continue
        try:
            metadata, raw_path = raw_entry.split(b"\t", 1)
            fields = metadata.split()
            if len(fields) != 3:
                raise ValueError
            object_id = fields[1].decode("ascii")
            display_path = raw_path.decode("utf-8", errors="replace")
        except (ValueError, UnicodeDecodeError):
            return [], SecretFinding("<git-index>", "git_index_unreadable")
        entries.append((display_path, object_id))

    unique_ids = list(dict.fromkeys(object_id for _, object_id in entries))
    if not unique_ids:
        return [], None
    try:
        batch = subprocess.run(
            ["git", "--no-replace-objects", "cat-file", "--batch"],
            cwd=root,
            check=True,
            input=("\n".join(unique_ids) + "\n").encode("ascii"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_git_child_environment(),
        ).stdout
        by_id: dict[str, bytes] = {}
        offset = 0
        for expected_id in unique_ids:
            header_end = batch.find(b"\n", offset)
            if header_end < 0:
                raise ValueError
            header = batch[offset:header_end].split()
            if len(header) != 3 or header[0].decode("ascii") != expected_id or header[1] != b"blob":
                raise ValueError
            size = int(header[2])
            start = header_end + 1
            end = start + size
            if size < 0 or end >= len(batch) or batch[end:end + 1] != b"\n":
                raise ValueError
            by_id[expected_id] = batch[start:end]
            offset = end + 1
        if offset != len(batch):
            raise ValueError
    except (OSError, subprocess.CalledProcessError, ValueError, UnicodeDecodeError):
        return [], SecretFinding("<git-index>", "git_index_unreadable")
    return [(f"git-index:{path}", by_id[object_id]) for path, object_id in entries], None


def _worktree_files(root: Path) -> tuple[list[Path], list[SecretFinding]]:
    files: list[Path] = []
    errors: list[SecretFinding] = []

    def record_walk_error(_error: OSError) -> None:
        errors.append(SecretFinding("<working-tree>", "directory_unreadable"))

    for current, directories, names in os.walk(root, topdown=True, onerror=record_walk_error, followlinks=False):
        directories[:] = [name for name in directories if name != ".git"]
        current_path = Path(current)
        for name in names:
            path = current_path / name
            try:
                relative = path.relative_to(root).as_posix()
            except ValueError:
                errors.append(SecretFinding("<working-tree>", "outside_repository_path"))
                continue
            if relative == ".git" or relative.startswith(".git/"):
                continue
            files.append(path)
    return files, errors


def scan_repository(root: Path) -> list[SecretFinding]:
    resolved_root = root.resolve()
    findings: list[SecretFinding] = []
    candidates, walk_errors = _worktree_files(resolved_root)
    findings.extend(walk_errors)
    for path in sorted(candidates, key=str):
        try:
            relative = path.relative_to(resolved_root)
        except ValueError:
            findings.append(SecretFinding("<working-tree>", "outside_repository_path"))
            continue
        display_path, sensitive_path = _safe_display_path(relative.as_posix())
        if sensitive_path:
            findings.append(SecretFinding(display_path, "sensitive_path_name"))
        try:
            resolved_path = path.resolve(strict=True)
            resolved_path.relative_to(resolved_root)
        except (OSError, ValueError):
            findings.append(SecretFinding(display_path, "file_unreadable_or_outside_repository"))
            continue
        try:
            raw = resolved_path.read_bytes()
        except OSError:
            findings.append(SecretFinding(display_path, "file_unreadable"))
            continue
        findings.extend(_scan_bytes(display_path, raw))

    index_blobs, index_error = _git_index_blobs(resolved_root)
    if index_error is not None:
        findings.append(index_error)
    for display_path, raw in index_blobs:
        safe_path, sensitive_path = _safe_display_path(display_path)
        if sensitive_path:
            findings.append(SecretFinding(safe_path, "sensitive_path_name"))
        findings.extend(_scan_bytes(safe_path, raw))
    return sorted(set(findings), key=lambda finding: (finding.path, finding.rule))


def main() -> int:
    # CLI scans are offline preflight subprocesses and do not need inherited
    # semantic credentials. Imported runner calls use scan_repository directly.
    os.environ.pop("ANTHROPIC_API_KEY", None)
    os.environ.pop("FORGE_SEMANTIC_MODEL", None)
    parser = argparse.ArgumentParser(description="High-confidence secret scan without printing matched values.")
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    findings = scan_repository(args.root)
    if findings:
        print(f"SEMANTIC_SECRET_SCAN=FAIL count={len(findings)}")
        for finding in findings:
            print(f"path={finding.path} rule={finding.rule}")
        return 2
    print("SEMANTIC_SECRET_SCAN=PASS findings=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
