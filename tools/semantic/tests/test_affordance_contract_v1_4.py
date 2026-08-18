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
    validate_affordance_profile,
)
from affordance_contract_v1_3 import (  # noqa: E402
    FIELDS as FIELDS_V1_3,
    REAL_LENGTH_FIELD,
    validate_affordance_profile_v1_3,
)
from affordance_contract_v1_4 import (  # noqa: E402
    CONTRACT_VERSION,
    FIELDS,
    MAX_REAL_MASS_KG,
    MIN_REAL_MASS_KG,
    REAL_MASS_FIELD,
    candidate_tool_schema_v1_4,
    read_real_mass_kg,
    upgrade_profile_to_v1_4,
    validate_affordance_profile_v1_4,
    validate_candidate_blueprint_v1_4,
    validate_real_mass_kg,
)
from author_v1_4_sidecars import (  # noqa: E402
    CHICKEN_LEG_MODEL_PROFILE,
    CHICKEN_LEG_REAL_LENGTH_CM,
    CHICKEN_LEG_REAL_MASS_KG,
    REPO_ROOT,
    model_backed_chicken_leg_profile,
)


def valid_profile_v1_3() -> dict:
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
        REAL_LENGTH_FIELD: 140.0,
    }


def valid_profile() -> dict:
    return {**valid_profile_v1_3(), REAL_MASS_FIELD: 1.0}


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


class RealMassFieldTest(unittest.TestCase):
    def test_version_is_distinct(self) -> None:
        self.assertEqual(CONTRACT_VERSION, "forge-semantic-v1.4-candidate")

    def test_v1_4_adds_exactly_one_field(self) -> None:
        self.assertEqual(FIELDS - FIELDS_V1_3, {REAL_MASS_FIELD})

    def test_accepts_valid_profile(self) -> None:
        self.assertEqual(validate_affordance_profile_v1_4(valid_profile())[REAL_MASS_FIELD], 1.0)

    def test_rejects_missing_mass(self) -> None:
        profile = valid_profile()
        del profile[REAL_MASS_FIELD]
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_4(profile)

    def test_rejects_out_of_range(self) -> None:
        for value in (MIN_REAL_MASS_KG - 0.01, MAX_REAL_MASS_KG + 0.1, 0, -5):
            with self.subTest(value=value), self.assertRaises(AffordanceContractError):
                validate_real_mass_kg(value)

    def test_rejects_non_finite_and_bool(self) -> None:
        for value in (float("nan"), float("inf"), True, "1.0", None):
            with self.subTest(value=value), self.assertRaises(AffordanceContractError):
                validate_real_mass_kg(value)

    def test_accepts_range_bounds(self) -> None:
        self.assertEqual(validate_real_mass_kg(MIN_REAL_MASS_KG), MIN_REAL_MASS_KG)
        self.assertEqual(validate_real_mass_kg(MAX_REAL_MASS_KG), MAX_REAL_MASS_KG)

    def test_still_enforces_v1_3_length_rules(self) -> None:
        profile = valid_profile()
        profile[REAL_LENGTH_FIELD] = 10_000.0
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_4(profile)

    def test_still_enforces_v1_2_cross_field_rules(self) -> None:
        profile = valid_profile()
        profile["handle_length"] = "none"  # requires body_grip or clamp_grip
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_4(profile)

    def test_rejects_extra_field(self) -> None:
        profile = valid_profile()
        profile["unexpected"] = 1
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_4(profile)

    def test_does_not_mutate_input(self) -> None:
        profile = valid_profile()
        snapshot = copy.deepcopy(profile)
        validate_affordance_profile_v1_4(profile)
        self.assertEqual(profile, snapshot)


class MassSeparatesWhereDistributionCollidesTest(unittest.TestCase):
    """The reason the field exists, pinned so decision P08's reasoning cannot rot.

    `mass_distribution` says where the weight sits, never how much of it there is. A
    chicken leg and a sledgehammer are both front-weighted; before this field the
    compiler classified both `heavy` and swung the chicken leg no faster.
    """

    def test_chicken_leg_and_sledgehammer_share_a_bucket_but_not_a_mass(self) -> None:
        chicken_leg = {
            **valid_profile_v1_3(),
            "handle_length": "short", "body_length": "short", "grip_topology": "one_hand_handle",
            "rigidity": "rigid", "contact_surface": "broad", "secondary_contact_surface": "none",
            "evidence_parts": ["meaty drumstick end", "narrow bone handle"],
            REAL_LENGTH_FIELD: 13.0, REAL_MASS_FIELD: 0.15,
        }
        sledgehammer = {
            **valid_profile_v1_3(),
            "rigidity": "rigid", "contact_surface": "broad", "secondary_contact_surface": "none",
            "evidence_parts": ["heavy steel head", "long two-hand shaft"],
            REAL_LENGTH_FIELD: 90.0, REAL_MASS_FIELD: 5.0,
        }
        validate_affordance_profile_v1_4(chicken_leg)
        validate_affordance_profile_v1_4(sledgehammer)
        # Same categorical answer on the only mass field the contract had before v1.4...
        self.assertEqual(chicken_leg["mass_distribution"], sledgehammer["mass_distribution"])
        # ...while the quantity it stands in for differs by more than thirtyfold.
        self.assertGreater(
            sledgehammer[REAL_MASS_FIELD] / chicken_leg[REAL_MASS_FIELD], 30.0
        )

    def test_mass_is_not_recoverable_from_length(self) -> None:
        """Same length, an order of magnitude apart in mass -- so this is a new axis."""
        wooden_spoon = {**valid_profile_v1_3(), REAL_LENGTH_FIELD: 100.0, REAL_MASS_FIELD: 0.3}
        iron_bar = {**valid_profile_v1_3(), REAL_LENGTH_FIELD: 100.0, REAL_MASS_FIELD: 9.0}
        validate_affordance_profile_v1_4(wooden_spoon)
        validate_affordance_profile_v1_4(iron_bar)
        self.assertEqual(wooden_spoon[REAL_LENGTH_FIELD], iron_bar[REAL_LENGTH_FIELD])
        self.assertGreater(iron_bar[REAL_MASS_FIELD] / wooden_spoon[REAL_MASS_FIELD], 10.0)


class ModelBackedChickenLegFixtureTest(unittest.TestCase):
    """The 1B chicken fixture must preserve the frozen estimator's structure."""

    def test_fixture_structure_matches_frozen_a10_estimator_output(self) -> None:
        source = json.loads(CHICKEN_LEG_MODEL_PROFILE.read_text(encoding="utf-8"))
        fixture_path = (
            REPO_ROOT
            / "artifacts"
            / "mass_axis_poc"
            / "affordance_v1_4"
            / "chicken_leg"
            / "object_affordance_profile.json"
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        for field, expected in source.items():
            self.assertEqual(fixture[field], expected, field)
        self.assertEqual(fixture[REAL_LENGTH_FIELD], CHICKEN_LEG_REAL_LENGTH_CM)
        self.assertEqual(fixture[REAL_MASS_FIELD], CHICKEN_LEG_REAL_MASS_KG)

    def test_offline_authoring_cannot_restore_the_hand_authored_rigid_profile(self) -> None:
        fixture_path = (
            REPO_ROOT
            / "artifacts"
            / "mass_axis_poc"
            / "affordance_v1_4"
            / "chicken_leg"
            / "object_affordance_profile.json"
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        self.assertEqual(model_backed_chicken_leg_profile(), fixture)
        self.assertEqual(fixture["rigidity"], "semi_rigid")


class RealMassSpanExceedsTheDamageBandTest(unittest.TestCase):
    """Decision P08's red line, stated as arithmetic rather than as prose.

    Damage is keyed off a three-value tempo class spanning 22..34 -- 1.55x by design.
    The legal mass range spans a thousandfold. Multiplying one by the other is what P08
    forbids, and the ratio is the reason: it would swamp every deliberate design choice.
    """

    def test_mass_range_dwarfs_the_designed_damage_band(self) -> None:
        damage_span = 34.0 / 22.0
        mass_span = MAX_REAL_MASS_KG / MIN_REAL_MASS_KG
        self.assertAlmostEqual(damage_span, 1.545, places=2)
        self.assertGreater(mass_span / damage_span, 100.0)


class FrozenVersionsUntouchedTest(unittest.TestCase):
    def test_v1_3_still_rejects_the_new_field(self) -> None:
        with self.assertRaises(AffordanceContractError):
            validate_affordance_profile_v1_3(valid_profile())

    def test_v1_3_still_accepts_its_own_profiles(self) -> None:
        self.assertEqual(
            validate_affordance_profile_v1_3(valid_profile_v1_3())[REAL_LENGTH_FIELD], 140.0
        )

    def test_v1_2_still_rejects_both_added_fields(self) -> None:
        for profile in (valid_profile_v1_3(), valid_profile()):
            with self.subTest(fields=len(profile)), self.assertRaises(AffordanceContractError):
                validate_affordance_profile(profile)

    def test_frozen_sidecars_remain_valid_under_v1_2(self) -> None:
        """The four shipped assets are SHA-256 pinned and must not need editing."""
        root = Path(__file__).resolve().parents[3] / "data" / "combat_feel" / "live_assets"
        sidecars = sorted(root.glob("*/*/object_affordance_profile.json"))
        self.assertGreaterEqual(len(sidecars), 4)
        for sidecar in sidecars:
            with self.subTest(sidecar=sidecar.name):
                validate_affordance_profile(json.loads(sidecar.read_text(encoding="utf-8")))


class UpgradeTest(unittest.TestCase):
    def test_upgrade_adds_mass_and_keeps_the_rest(self) -> None:
        base = valid_profile_v1_3()
        upgraded = upgrade_profile_to_v1_4(base, 1.0)
        self.assertEqual(upgraded[REAL_MASS_FIELD], 1.0)
        self.assertEqual({k: v for k, v in upgraded.items() if k != REAL_MASS_FIELD}, base)

    def test_upgrade_does_not_mutate_source(self) -> None:
        base = valid_profile_v1_3()
        upgrade_profile_to_v1_4(base, 1.0)
        self.assertNotIn(REAL_MASS_FIELD, base)

    def test_upgrade_rejects_bad_mass(self) -> None:
        with self.assertRaises(AffordanceContractError):
            upgrade_profile_to_v1_4(valid_profile_v1_3(), 500.0)

    def test_upgrade_requires_a_v1_3_source(self) -> None:
        """A v1.2 profile has no length, so it cannot skip a version on the way up."""
        base = valid_profile_v1_3()
        del base[REAL_LENGTH_FIELD]
        with self.assertRaises(AffordanceContractError):
            upgrade_profile_to_v1_4(base, 1.0)


class BlueprintAndSchemaTest(unittest.TestCase):
    def test_accepts_valid_blueprint(self) -> None:
        validate_candidate_blueprint_v1_4(valid_blueprint())

    def test_rejects_blueprint_whose_affordance_lacks_mass(self) -> None:
        blueprint = valid_blueprint()
        del blueprint["affordance"][REAL_MASS_FIELD]
        with self.assertRaises(AffordanceContractError):
            validate_candidate_blueprint_v1_4(blueprint)

    def test_tool_schema_requires_both_real_quantities(self) -> None:
        schema = candidate_tool_schema_v1_4()
        affordance = schema["properties"]["affordance"]
        for field in (REAL_MASS_FIELD, REAL_LENGTH_FIELD):
            self.assertIn(field, affordance["required"])
            self.assertIn(field, affordance["properties"])
        self.assertFalse(affordance["additionalProperties"])
        self.assertIn("affordance", schema["required"])

    def test_tool_schema_bounds_match_the_validator(self) -> None:
        affordance = candidate_tool_schema_v1_4()["properties"]["affordance"]
        self.assertEqual(affordance["properties"][REAL_MASS_FIELD]["minimum"], MIN_REAL_MASS_KG)
        self.assertEqual(affordance["properties"][REAL_MASS_FIELD]["maximum"], MAX_REAL_MASS_KG)


class ReadFromDiskTest(unittest.TestCase):
    def test_reads_validated_mass(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "object_affordance_profile.json"
            path.write_text(json.dumps(valid_profile()), encoding="utf-8")
            self.assertEqual(read_real_mass_kg(path), 1.0)

    def test_rejects_profile_without_mass(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "object_affordance_profile.json"
            path.write_text(json.dumps(valid_profile_v1_3()), encoding="utf-8")
            with self.assertRaises(AffordanceContractError):
                read_real_mass_kg(path)


if __name__ == "__main__":
    unittest.main()
