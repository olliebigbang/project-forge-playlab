"""Produce offline v1.4 affordance sidecars, without a model call.

This is the fallback counterpart to `estimate_real_mass.py`, exactly as
`author_v1_3_sidecars.py` was for length. Its inputs do not all have the same provenance;
the output manifest records that distinction explicitly.

Three provenance groups are written:

  upgrades -- the four shipped objects, read from their v1.3 sidecars under
      artifacts/real_scale_poc/affordance_v1_3/ (whose lengths ARE model output) and
      given a mass. The frozen v1.2 originals under data/ are SHA-256 pinned and are
      never edited in place.

  model-backed demo -- the chicken leg structure is copied verbatim from the frozen A10
      affordance estimator result. Its length and mass are the frozen model probe medians.

  hand-authored demo -- the sledgehammer is authored whole. It is not model evidence and
      remains only an offline P08 control.

Careful: this writes all three groups into the same directory, so running it over a directory
that already holds `estimate_real_mass.py` output replaces model estimates with these
guesses. The four upgrades under `artifacts/mass_axis_poc/affordance_v1_4/` are model
output and should be regenerated with the estimator, not with this.

Usage:
    python author_v1_4_sidecars.py <output_dir>
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from affordance_contract_v1_4 import (  # noqa: E402
    upgrade_profile_to_v1_4,
    validate_affordance_profile_v1_4,
)


REPO_ROOT = Path(__file__).resolve().parents[3]
V1_3_SIDECARS = REPO_ROOT / "artifacts" / "real_scale_poc" / "affordance_v1_3"
CHICKEN_LEG_MODEL_PROFILE = (
    REPO_ROOT
    / "tools"
    / "semantic"
    / "reports"
    / "affordance_combined_handoff_v1_2_1"
    / "affordance-combined-v1-2-1-20260808T132129343Z"
    / "affordance_profiles"
    / "A10.json"
)
CHICKEN_LEG_REAL_LENGTH_CM = 13.0
CHICKEN_LEG_REAL_MASS_KG = 0.12

# Hand-authored placeholders. Order-of-magnitude estimates of the real object.
HAND_AUTHORED_MASS_KG = {
    "frying_pan": 1.6,          # cast iron, the heaviest thing in a domestic kitchen
    "giant_wooden_spoon": 1.5,  # carved wood, oversized but still wood
    "shotgun_melee": 3.2,       # steel barrel and wooden furniture
    "old_mop": 1.0,             # a light pole and a wet head
}

# Authored whole because this object has no frozen semantic/affordance estimator result.
# It is deliberately retained as a clearly labelled offline control, not model evidence.
HAND_AUTHORED_DEMO_PROFILES = {
    "sledgehammer": {
        "handle_length": "long",
        "body_length": "medium",
        "grip_topology": "two_hand_handle",
        "rigidity": "rigid",
        "mass_distribution": "front",
        "contact_surface": "broad",
        "secondary_contact_surface": "none",
        "has_point": False,
        "has_edge": False,
        "has_broad_face": True,
        "has_barrel": False,
        "has_stock": False,
        "confidence": 1.0,
        "evidence_parts": ["heavy steel head", "long two-hand shaft"],
        "real_length_cm": 90.0,
        "real_mass_kg": 5.0,
    },
}


def model_backed_chicken_leg_profile() -> dict:
    """Return frozen estimator structure plus frozen model length/mass medians."""
    profile = json.loads(CHICKEN_LEG_MODEL_PROFILE.read_text(encoding="utf-8"))
    profile["real_length_cm"] = CHICKEN_LEG_REAL_LENGTH_CM
    profile["real_mass_kg"] = CHICKEN_LEG_REAL_MASS_KG
    return validate_affordance_profile_v1_4(profile)


def _write(target: Path, profile: dict) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    written = []
    for object_id, mass_kg in HAND_AUTHORED_MASS_KG.items():
        source = V1_3_SIDECARS / object_id / "object_affordance_profile.json"
        profile = json.loads(source.read_text(encoding="utf-8"))
        upgraded = upgrade_profile_to_v1_4(profile, mass_kg)
        target = args.output_dir / object_id / "object_affordance_profile.json"
        _write(target, upgraded)
        written.append({
            "object_id": object_id,
            "group": "upgrade",
            "real_length_cm": upgraded["real_length_cm"],
            "real_mass_kg": mass_kg,
            "length_provenance": "model_estimate",
            "mass_provenance": "hand_authored_placeholder",
            "path": str(target),
        })

    chicken_leg = model_backed_chicken_leg_profile()
    chicken_target = args.output_dir / "chicken_leg" / "object_affordance_profile.json"
    _write(chicken_target, chicken_leg)
    written.append({
        "object_id": "chicken_leg",
        "group": "model_backed_demo",
        "structure_provenance": "frozen_affordance_estimator_A10",
        "real_length_cm": chicken_leg["real_length_cm"],
        "real_mass_kg": chicken_leg["real_mass_kg"],
        "length_provenance": "model_probe_median",
        "mass_provenance": "model_probe_median",
        "path": str(chicken_target),
    })

    for object_id, profile in HAND_AUTHORED_DEMO_PROFILES.items():
        validated = validate_affordance_profile_v1_4(dict(profile))
        target = args.output_dir / object_id / "object_affordance_profile.json"
        _write(target, validated)
        written.append({
            "object_id": object_id,
            "group": "hand_authored_demo",
            "structure_provenance": "hand_authored_placeholder",
            "real_length_cm": validated["real_length_cm"],
            "real_mass_kg": validated["real_mass_kg"],
            "length_provenance": "hand_authored_placeholder",
            "mass_provenance": "hand_authored_placeholder",
            "path": str(target),
        })

    print(json.dumps({"status": "success", "written": written}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
