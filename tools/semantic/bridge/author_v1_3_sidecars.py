"""Produce v1.3 affordance sidecars for the four known objects, without a model call.

This stands in for the semantic compiler so the pipeline can be wired and tested
offline. The lengths below are hand-authored estimates, NOT model output -- they are a
placeholder for `estimate_real_length.py`, which asks the model the same question and
writes the same file. Replace them with real output before treating any number here as
evidence about what the model can estimate.

Reads the frozen v1.2 sidecars under data/ and writes upgraded copies elsewhere: those
originals are SHA-256 pinned in index.json and are never edited in place.

Usage:
    python author_v1_3_sidecars.py <output_dir>
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from affordance_contract_v1_3 import upgrade_profile_to_v1_3  # noqa: E402


REPO_ROOT = Path(__file__).resolve().parents[3]
LIVE_ASSETS = REPO_ROOT / "data" / "combat_feel" / "live_assets"

# Hand-authored placeholders. Order-of-magnitude estimates of the real object.
HAND_AUTHORED_LENGTH_CM = {
    "frying_pan": 40.0,
    "giant_wooden_spoon": 60.0,
    "shotgun_melee": 100.0,
    "old_mop": 150.0,
}

SOURCE_SIDECAR = {
    "frying_pan": LIVE_ASSETS / "recipe_slice_1b" / "frying_pan",
    "giant_wooden_spoon": LIVE_ASSETS / "revision_a" / "giant_wooden_spoon",
    "shotgun_melee": LIVE_ASSETS / "motion_grammar_slice_1a" / "shotgun_melee",
    "old_mop": LIVE_ASSETS / "recipe_slice_1b" / "old_mop",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    written = []
    for object_id, length_cm in HAND_AUTHORED_LENGTH_CM.items():
        source = SOURCE_SIDECAR[object_id] / "object_affordance_profile.json"
        profile = json.loads(source.read_text(encoding="utf-8"))
        upgraded = upgrade_profile_to_v1_3(profile, length_cm)
        target = args.output_dir / object_id / "object_affordance_profile.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(upgraded, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        written.append({"object_id": object_id, "real_length_cm": length_cm, "path": str(target)})

    print(json.dumps({"status": "success", "provenance": "hand_authored_placeholder", "written": written},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
