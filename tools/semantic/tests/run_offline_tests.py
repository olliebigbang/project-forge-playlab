#!/usr/bin/env python3
"""Run offline tests after removing inherited semantic credentials."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path


def main() -> int:
    os.environ.pop("ANTHROPIC_API_KEY", None)
    os.environ.pop("FORGE_SEMANTIC_MODEL", None)
    tests_root = Path(__file__).resolve().parent
    suite = unittest.defaultTestLoader.discover(
        str(tests_root), pattern="test_*.py"
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
