from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


OPEN_IDENTITY_ROOT = Path(__file__).resolve().parent
COMFY_ROOT = OPEN_IDENTITY_ROOT.parent
sys.path.insert(0, str(COMFY_ROOT / "bridge"))
from forge_comfy_bridge import BridgeError, PROMPT_POLICY_VERSION, generate  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the five text-only Spike 2 identity cases once each.")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument(
        "--compiled-cases",
        type=Path,
        default=OPEN_IDENTITY_ROOT / "reports" / "compiled_cases.json",
    )
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--seed", type=int, default=52002)
    default_label = PROMPT_POLICY_VERSION.replace("forge-open-identity-v", "policy")
    parser.add_argument("--run-label", default=default_label)
    parser.add_argument("--prompt-policy-version", default=PROMPT_POLICY_VERSION)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--overwrite-summary", action="store_true")
    args = parser.parse_args()
    payload = json.loads(args.compiled_cases.read_text(encoding="utf-8"))
    selected = set(args.only)
    # Resolve and protect the summary before any generation request. The immutable
    # policy-v1 evidence must never be replaced by failed rerun bookkeeping.
    safe_label = "".join(char for char in args.run_label.lower() if char.isalnum() or char in "_-")
    if not safe_label:
        raise SystemExit("run label must contain at least one safe character")
    report_path = args.summary or OPEN_IDENTITY_ROOT / "reports" / f"generation_summary_{safe_label}.json"
    if report_path.exists() and not args.overwrite_summary:
        raise SystemExit(f"summary already exists; choose --summary or explicitly pass --overwrite-summary: {report_path}")
    attempts = 0
    succeeded = 0
    results: list[dict[str, object]] = []
    started = time.perf_counter()
    for test_case in payload["cases"]:
        if not test_case.get("generate_visual", False):
            results.append(
                {
                    "case_id": test_case["case_id"],
                    "status": "clarification_expected",
                    "question": test_case.get("question", ""),
                }
            )
            continue
        case_id = str(test_case["case_id"])
        if selected and case_id not in selected:
            continue
        blueprint = test_case["blueprint"]
        attempts += 1
        seed = args.seed
        run_id = f"seed_{seed}_{safe_label}"
        print(f"SPIKE2 RUN {attempts} | {case_id} | {blueprint['player_identity_text']}", flush=True)
        try:
            output = generate(
                args.config.resolve(),
                case_id=case_id,
                run_id=run_id,
                prompt=blueprint["player_identity_text"],
                generation_prompt=blueprint["visual_prompt"],
                prompt_policy_version=args.prompt_policy_version,
                seed=seed,
                control_strength=0.0,
                sketch_path=None,
            )
            succeeded += 1
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            results.append(
                {
                    "case_id": case_id,
                    "status": "success",
                    "output_directory": output.relative_to(COMFY_ROOT.parent.parent).as_posix(),
                    "generation_seconds": manifest["generation_seconds"],
                    "postprocess_seconds": manifest["postprocess_seconds"],
                    "generation_prompt_sha256": manifest["generation_prompt_sha256"],
                }
            )
            print(f"PASS {case_id} | {output}", flush=True)
        except BridgeError as exc:
            results.append({"case_id": case_id, "status": "failed", "reason": str(exc)})
            print(f"FAIL {case_id} | {exc}", flush=True)
    summary = {
        "attempts": attempts,
        "succeeded": succeeded,
        "failed": attempts - succeeded,
        "elapsed_seconds": round(time.perf_counter() - started, 3),
        "results": results,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if succeeded == attempts else 2


if __name__ == "__main__":
    raise SystemExit(main())
