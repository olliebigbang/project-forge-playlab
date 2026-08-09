"""Produce v1.4 affordance sidecars, without a model call.

This stands in for `estimate_real_mass.py` so the compiler can be wired and playtested
offline, exactly as `author_v1_3_sidecars.py` did for length. The masses below are
hand-authored estimates, NOT model output. Replace them with real output before treating
any number here as evidence about what the model can estimate -- for length that
replacement happened in P06, and the hand-authored 60cm giant spoon turned out to be 120.

Two groups are written:

  upgrades -- the four shipped objects, read from their v1.3 sidecars under
      artifacts/real_scale_poc/affordance_v1_3/ (whose lengths ARE model output) and
      given a mass. The frozen v1.2 originals under data/ are SHA-256 pinned and are
      never edited in place.

  demos -- a chicken leg and a sledgehammer, authored whole. Neither is a shipped asset,
      and they exist to make decision P08's defect visible by hand: both are
      front-weighted and both therefore compiled to the same mass axis of 1.0 and the
      same `heavy` label, a 33x difference in real mass that the compiler could not see.

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

# Hand-authored placeholders. Order-of-magnitude estimates of the real object.
HAND_AUTHORED_MASS_KG = {
    "frying_pan": 1.6,          # cast iron, the heaviest thing in a domestic kitchen
    "giant_wooden_spoon": 1.5,  # carved wood, oversized but still wood
    "shotgun_melee": 3.2,       # steel barrel and wooden furniture
    "old_mop": 1.0,             # a light pole and a wet head
}

# Authored whole rather than upgraded, because neither is a shipped asset. Both are
# deliberately `front` weighted and `broad` faced: under the pre-v1.4 compiler that made
# them identical on every mass signal available.
DEMO_PROFILES = {
    "chicken_leg": {
        "handle_length": "short",
        "body_length": "short",
        "grip_topology": "one_hand_handle",
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
        "evidence_parts": ["meaty drumstick end", "narrow bone handle"],
        "real_length_cm": 13.0,
        "real_mass_kg": 0.15,
    },
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

    for object_id, profile in DEMO_PROFILES.items():
        validated = validate_affordance_profile_v1_4(dict(profile))
        target = args.output_dir / object_id / "object_affordance_profile.json"
        _write(target, validated)
        written.append({
            "object_id": object_id,
            "group": "demo",
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
