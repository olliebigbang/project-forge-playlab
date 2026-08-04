from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent.parent
FROZEN_PATH = ROOT / "frozen_4a_evidence.json"
FROZEN_SHA256 = "95b4e4141e241e723bffa9c8a0dc22cbd19b1780c7ef1f02e39c80ac0574709d"
OUTPUT = ROOT / "v1_postmortem"
sys.path.insert(0, str(ROOT))

from v1_alpha_postmortem import analyze_v1  # noqa: E402


def sha256_file(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main() -> int:
    try:
        if OUTPUT.exists():
            raise RuntimeError(f"V1_POSTMORTEM_ALREADY_EXISTS:{OUTPUT}")
        if sha256_file(FROZEN_PATH) != FROZEN_SHA256:
            raise RuntimeError("FROZEN_4A_MANIFEST_HASH_MISMATCH")
        frozen = json.loads(FROZEN_PATH.read_text(encoding="utf-8"))
        stage = ROOT / f".v1-postmortem-{uuid.uuid4().hex}.tmp"
        stage.mkdir(parents=False, exist_ok=False)
        results = []
        try:
            for case in frozen["case_matrix"]:
                raw = PROJECT_ROOT / case["raw"]["path"]
                manifest = PROJECT_ROOT / case["manifest"]["path"]
                if sha256_file(raw) != case["raw"]["sha256"]:
                    raise RuntimeError(f"RAW_HASH_CHANGED:{case['case_id']}:{case['seed']}")
                if sha256_file(manifest) != case["manifest"]["sha256"]:
                    raise RuntimeError(f"MANIFEST_HASH_CHANGED:{case['case_id']}:{case['seed']}")
                target = stage / case["case_id"] / f"seed_{case['seed']}"
                result = analyze_v1(raw, manifest, target)
                if result["recorded_v1_failure_reason"] != case["v1_failure_reason"]:
                    raise RuntimeError(f"V1_FAILURE_REASON_DIVERGED:{case['case_id']}:{case['seed']}")
                results.append(
                    {
                        "ordinal": case["ordinal"],
                        "case_id": case["case_id"],
                        "seed": case["seed"],
                        "recorded_v1_status": result["recorded_v1_status"],
                        "recorded_v1_failure_reason": result["recorded_v1_failure_reason"],
                        "expected_background_match_ratio": result["expected_background_match_ratio"],
                        "candidate_foreground_coverage": result["candidate_foreground_coverage"],
                        "largest_component_coverage": result["largest_component_coverage"],
                        "rejected_edge_pixel_count": result["rejected_edge_pixel_count"],
                    }
                )
            summary = {
                "status": "V1_POSTMORTEM_COMPLETE",
                "source_frozen_4a_evidence_sha256": FROZEN_SHA256,
                "result_count": len(results),
                "failure_reason_counts": {
                    reason: sum(int(item["recorded_v1_failure_reason"] == reason) for item in results)
                    for reason in sorted({item["recorded_v1_failure_reason"] for item in results})
                },
                "results": results,
            }
            (stage / "v1_postmortem_summary.json").write_text(
                json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            os.replace(stage, OUTPUT)
        finally:
            if stage.exists():
                shutil.rmtree(stage)
        print(json.dumps(summary, ensure_ascii=False))
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "NEEDS WORK", "failure_reason": str(exc)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
