from __future__ import annotations

import argparse
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


TEST_MODULES = (
    "tools.comfyui.flux2.birefnet.test_spike6_runner",
    "tools.comfyui.flux2.birefnet.test_process_birefnet_sprite",
    "tools.comfyui.flux2.birefnet.test_spike6_security",
)

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[3]
sys.path.insert(0, str(REPO_ROOT))


def run(output: Path) -> dict[str, object]:
    output = output.resolve(strict=False)
    if output.exists():
        raise RuntimeError("TEST_RESULT_ALREADY_EXISTS")
    suite = unittest.TestLoader().loadTestsFromNames(TEST_MODULES)
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    document: dict[str, object] = {
        "contract": "forge-birefnet-spike6-automated-test-result-v1",
        "status": "PASS" if result.wasSuccessful() else "FAIL",
        "modules": list(TEST_MODULES),
        "tests_run": result.testsRun,
        "failures": len(result.failures),
        "errors": len(result.errors),
        "skipped": len(result.skipped),
        "successful": result.wasSuccessful(),
        "output": stream.getvalue(),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=str(output.parent)))
    try:
        payload = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        staged = stage / output.name
        staged.write_text(payload, encoding="utf-8")
        if output.exists():
            raise RuntimeError("TEST_RESULT_ALREADY_EXISTS")
        os.rename(staged, output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    if not result.wasSuccessful():
        raise RuntimeError("AUTOMATED_TESTS_FAILED")
    return document


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = run(args.output)
    except RuntimeError as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}))
        return 2
    print(json.dumps({"status": result["status"], "tests_run": result["tests_run"], "output": str(args.output.resolve())}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
