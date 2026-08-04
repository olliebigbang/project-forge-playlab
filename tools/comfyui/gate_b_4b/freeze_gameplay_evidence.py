from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent.parent
TARGET = ROOT / "frozen_gameplay_evidence.json"
ROOT_FILES = ("project.godot", "export_presets.cfg")
GAMEPLAY_DIRECTORIES = ("scenes", "scripts", "tests")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main() -> int:
    if TARGET.exists():
        print(json.dumps({"status": "NEEDS WORK", "failure_reason": "GAMEPLAY_FREEZE_ALREADY_EXISTS"}), file=sys.stderr)
        return 2
    paths = [PROJECT_ROOT / name for name in ROOT_FILES]
    for directory in GAMEPLAY_DIRECTORIES:
        paths.extend(path for path in (PROJECT_ROOT / directory).rglob("*") if path.is_file())
    files = {
        path.relative_to(PROJECT_ROOT).as_posix(): {"size": path.stat().st_size, "sha256": digest(path)}
        for path in sorted(paths)
    }
    payload = {
        "purpose": "Prove Gate B 4B did not modify gameplay, rooms, anchors, tests, or project configuration.",
        "file_count": len(files),
        "files": files,
    }
    descriptor = os.open(TARGET, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
        stream.flush()
        os.fsync(stream.fileno())
    print(json.dumps({"status": "GAMEPLAY_EVIDENCE_FROZEN", "file_count": len(files), "sha256": digest(TARGET)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
