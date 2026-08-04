from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

BRIDGE_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(BRIDGE_DIRECTORY))
from forge_comfy_bridge import BridgeError, generate  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the five-case, three-seed Forge Sprite Spike matrix.")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--cases", type=Path, default=BRIDGE_DIRECTORY.parent / "test_cases" / "cases.json")
    parser.add_argument("--only", action="append", default=[])
    args = parser.parse_args()
    case_file = args.cases.resolve()
    matrix = json.loads(case_file.read_text(encoding="utf-8"))
    seeds = matrix["seeds"]
    strengths = matrix["strengths"]
    selected = set(args.only)
    attempts = 0
    succeeded = 0
    started = time.perf_counter()
    for case in matrix["cases"]:
        case_id = case["case_id"]
        if selected and case_id not in selected:
            continue
        sketch_text = str(case.get("sketch", ""))
        sketch_path = (case_file.parent / sketch_text).resolve() if sketch_text else None
        for index, seed in enumerate(seeds):
            attempts += 1
            strength = float(strengths[index]) if sketch_path else 0.0
            run_id = f"seed_{seed}_s{int(round(strength * 100)):02d}"
            print(f"RUN {attempts} | {case_id} | seed={seed} | strength={strength:.2f}", flush=True)
            try:
                output = generate(
                    args.config,
                    case_id=case_id,
                    run_id=run_id,
                    prompt=case["prompt"],
                    generation_prompt=case["generation_prompt"],
                    seed=int(seed),
                    control_strength=strength,
                    sketch_path=sketch_path,
                )
                succeeded += 1
                print(f"PASS {case_id}/{run_id} | {output}", flush=True)
            except BridgeError as exc:
                print(f"FAIL {case_id}/{run_id} | {exc}", flush=True)
    print(
        json.dumps(
            {
                "attempts": attempts,
                "succeeded": succeeded,
                "failed": attempts - succeeded,
                "elapsed_seconds": round(time.perf_counter() - started, 3),
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    return 0 if succeeded == attempts else 2


if __name__ == "__main__":
    raise SystemExit(main())
