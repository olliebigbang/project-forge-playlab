from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest

BRIDGE_DIR = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE_DIR))

from affordance_contract_v1_2 import (  # noqa: E402
    AffordanceContractError,
    FIELDS as FIELDS_V1_2,
    validate_affordance_profile,
)
from affordance_contract_v1_3 import (  # noqa: E402
    CONTRACT_VERSION,
    FIELDS,
    MAX_REAL_LENGTH_CM,
    MIN_REAL_LENGTH_CM,
    REAL_LENGTH_FIELD,
    candidate_tool_schema_v1_3,
    read_real_length_cm,
    upgrade_profile_to_v1_3,
    validate_affordance_profile_v1_3,
    validate_candidate_blueprint_v1_3,
    validate_real_length_cm,
)


def valid_profile_v1_2() -> dict:
    return {
        "handle_length": "long",
        "body_length": "long",
        "grip_topology": "two_hand_handle",
        "rigidity": "semi_rigid",
        "mass_distribution": "front",
        "contact_surface": "whole_body",
        "secondary_contact_surface": "broad",
        "has_point": False,
        "has_edge": False,
        "has_broad_face": True,
        "has_barrel": False,
        "has_stock": False,
        "confidence": 1.0,
        "evidence_parts": ["long shaft", "broad mop head"],
    }


def valid_profile() -> dict:
    return {**valid_profile_v1_2(), REAL_LENGTH_FIELD: 150.0}


def valid_blueprint() -> dict:
    return {
        "identity": {
            "canonical_name_zh": "旧拖把",
            "canonical_name_en": "old mop",
            "display_name_zh": "旧拖把",
            "display_name_en": "Old Mop",
            "category": "household_object",
            "required_identity_parts": ["long wooden handle", "frayed mop head strands"],
            "material_hints": ["worn wood"],
            "silhouette_hints": ["long slender pole with a bulky fibrous head at one end"],
            "optional_decorations": ["water stains"],
        },
        "combat": {
            "behavior_family": "heavy_melee",
            "delivery": "melee_swing",
            "impact_mode": "strike_edge",
            "effect_type": "normal",
            "drawback": "slow_movement",
            "cadence_hint": "slow_heavy",
        },
        "visual": {
            "prompt_en": "An old mop, full object visible, long worn wooden handle with a bulky frayed cloth mop head at the end, side view, isolated on plain background, single object, complete silhouette",
            "negative_prompt_en": "not a sword, not a staff weapon, not a spear, no blade, no gun",
            "must_preserve": ["long wooden handle", "frayed mop head strands"],
            "must_not_replace_with": ["sword", "staff", "spear"],
        },
        "confidence": 0.9,
        "affordance": valid_profile(),
    }


class RealLengthFieldTest(unittest.TestCase):
    def test_version_is_distinct(self) -> None:
        self.assertEqual(CONTRACT_VERSION, "forge-semantic-v1.3-candidate")

    def test_v1_3_adds_exactly_one_field(self) -> None:
        self.assertEqual(FIELDS - FIELDS_V1_2, {REAL_LENGTH_FIELD})

    def test_accepts_valid_profile(self) -> None:
        self.assertEqual(validate_affordance_profile_v1_3(valid_profile())[REAL_LENGTH_FIELD], 150.0)

    def test_rejects_missing_length(self) -> None:
        profile = valid_profile()
        del profile[REAL_LENGTH_FIELD]
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_3(profile)

    def test_rejects_out_of_range(self) -> None:
        for value in (MIN_REAL_LENGTH_CM - 0.1, MAX_REAL_LENGTH_CM + 0.1, 0, -50):
            with self.subTest(value=value), self.assertRaises(AffordanceContractError):
                validate_real_length_cm(value)

    def test_rejects_non_finite_and_bool(self) -> None:
        for value in (float("nan"), float("inf"), True, "150", None):
            with self.subTest(value=value), self.assertRaises(AffordanceContractError):
                validate_real_length_cm(value)

    def test_accepts_range_bounds(self) -> None:
        self.assertEqual(validate_real_length_cm(MIN_REAL_LENGTH_CM), MIN_REAL_LENGTH_CM)
        self.assertEqual(validate_real_length_cm(MAX_REAL_LENGTH_CM), MAX_REAL_LENGTH_CM)

    def test_still_enforces_v1_2_cross_field_rules(self) -> None:
        profile = valid_profile()
        profile["handle_length"] = "none"  # requires body_grip or clamp_grip
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_3(profile)

    def test_rejects_extra_field(self) -> None:
        profile = valid_profile()
        profile["unexpected"] = 1
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_3(profile)

    def test_does_not_mutate_input(self) -> None:
        profile = valid_profile()
        snapshot = copy.deepcopy(profile)
        validate_affordance_profile_v1_3(profile)
        self.assertEqual(profile, snapshot)


class LengthSeparatesWhereBucketsCollideTest(unittest.TestCase):
    """The reason the field exists: body_length cannot tell these two apart."""

    def test_mop_and_spoon_share_a_bucket_but_not_a_length(self) -> None:
        mop = {**valid_profile_v1_2(), REAL_LENGTH_FIELD: 150.0}
        spoon = {**valid_profile_v1_2(), "rigidity": "rigid", "contact_surface": "broad",
                 "secondary_contact_surface": "none", REAL_LENGTH_FIELD: 60.0}
        validate_affordance_profile_v1_3(mop)
        validate_affordance_profile_v1_3(spoon)
        self.assertEqual(mop["body_length"], spoon["body_length"])
        self.assertAlmostEqual(mop[REAL_LENGTH_FIELD] / spoon[REAL_LENGTH_FIELD], 2.5)


class FrozenVersionsUntouchedTest(unittest.TestCase):
    def test_v1_2_still_rejects_the_new_field(self) -> None:
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile(valid_profile())

    def test_v1_2_still_accepts_its_own_profiles(self) -> None:
        self.assertEqual(validate_affordance_profile(valid_profile_v1_2())["body_length"], "long")

    def test_frozen_sidecars_remain_valid_under_v1_2(self) -> None:
        """The four shipped assets are SHA-256 pinned and must not need editing."""
        root = Path(__file__).resolve().parents[3] / "data" / "combat_feel" / "live_assets"
        sidecars = sorted(root.glob("*/*/object_affordance_profile.json"))
        self.assertGreaterEqual(len(sidecars), 4)
        for sidecar in sidecars:
            with self.subTest(sidecar=sidecar.name):
                validate_affordance_profile(json.loads(sidecar.read_text(encoding="utf-8")))


class UpgradeTest(unittest.TestCase):
    def test_upgrade_adds_length_and_keeps_the_rest(self) -> None:
        base = valid_profile_v1_2()
        upgraded = upgrade_profile_to_v1_3(base, 150.0)
        self.assertEqual(upgraded[REAL_LENGTH_FIELD], 150.0)
        self.assertEqual({k: v for k, v in upgraded.items() if k != REAL_LENGTH_FIELD}, base)

    def test_upgrade_does_not_mutate_source(self) -> None:
        base = valid_profile_v1_2()
        upgrade_profile_to_v1_3(base, 150.0)
        self.assertNotIn(REAL_LENGTH_FIELD, base)

    def test_upgrade_rejects_bad_length(self) -> None:
        with self.assertRaises(AffordanceContractError):
            upgrade_profile_to_v1_3(valid_profile_v1_2(), 10_000.0)


class BlueprintAndSchemaTest(unittest.TestCase):
    def test_accepts_valid_blueprint(self) -> None:
        validate_candidate_blueprint_v1_3(valid_blueprint())

    def test_rejects_blueprint_whose_affordance_lacks_length(self) -> None:
        blueprint = valid_blueprint()
        del blueprint["affordance"][REAL_LENGTH_FIELD]
        with self.assertRaises(AffordanceContractError):
            validate_candidate_blueprint_v1_3(blueprint)

    def test_tool_schema_requires_the_field(self) -> None:
        schema = candidate_tool_schema_v1_3()
        affordance = schema["properties"]["affordance"]
        self.assertIn(REAL_LENGTH_FIELD, affordance["required"])
        self.assertIn(REAL_LENGTH_FIELD, affordance["properties"])
        self.assertFalse(affordance["additionalProperties"])
        self.assertIn("affordance", schema["required"])


class ReadFromDiskTest(unittest.TestCase):
    def test_reads_validated_length(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "object_affordance_profile.json"
            path.write_text(json.dumps(valid_profile()), encoding="utf-8")
            self.assertEqual(read_real_length_cm(path), 150.0)

    def test_rejects_profile_without_length(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "object_affordance_profile.json"
            path.write_text(json.dumps(valid_profile_v1_2()), encoding="utf-8")
            with self.assertRaises(AffordanceContractError):
                read_real_length_cm(path)


if __name__ == "__main__":
    unittest.main()
