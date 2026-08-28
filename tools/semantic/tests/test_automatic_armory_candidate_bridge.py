from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


PLAYLAB = Path(__file__).resolve().parents[3]
BRIDGE_ROOT = PLAYLAB / "tools" / "semantic" / "bridge"
sys.path.insert(0, str(BRIDGE_ROOT))

import automatic_armory_candidate_bridge as bridge  # noqa: E402


def request(role: str = "close_quarters") -> dict:
    return {
        "target_role": role,
        "existing_identities": ["M4A1", "M249"],
        "excluded_identities": ["Uzi"],
    }


def candidate(role: str = "close_quarters") -> dict:
    return {
        "schema": bridge.RESPONSE_SCHEMA,
        "target_role": role,
        "canonical_name": "Heckler & Koch MP5A3",
        "common_alias": "MP5A3",
        "selection_reason_zh": "短枪管与伸缩枪托形成清楚的近距离冲锋枪轮廓。",
        "confidence": 0.93,
    }


class AutomaticArmoryCandidateBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ.pop("FORGE_SEMANTIC_MODEL", None)

    def test_specific_non_duplicate_candidate_passes(self) -> None:
        result = bridge.validate_candidate(request(), candidate())
        self.assertEqual(result["target_role"], "close_quarters")
        self.assertEqual(result["canonical_name"], "Heckler & Koch MP5A3")

    def test_target_role_cannot_be_changed_by_model(self) -> None:
        with self.assertRaisesRegex(
            bridge.AutomaticArmoryCandidateError, "TARGET_ROLE_ECHO_MISMATCH"
        ):
            bridge.validate_candidate(request(), candidate("precision"))

    def test_existing_or_excluded_alias_is_rejected(self) -> None:
        value = candidate()
        value["common_alias"] = "Uzi"
        with self.assertRaisesRegex(
            bridge.AutomaticArmoryCandidateError, "DUPLICATE_IDENTITY"
        ):
            bridge.validate_candidate(request(), value)

    def test_generic_category_name_is_rejected(self) -> None:
        value = candidate()
        value["canonical_name"] = "submachine gun"
        with self.assertRaisesRegex(
            bridge.AutomaticArmoryCandidateError, "GENERIC_IDENTITY_FORBIDDEN"
        ):
            bridge.validate_candidate(request(), value)

    def test_offline_cli_writes_atomic_success_record(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            request_path = root / "request.json"
            fixture_path = root / "fixture.json"
            output = root / "output"
            request_path.write_text(
                json.dumps(
                    {
                        "schema": bridge.REQUEST_SCHEMA,
                        "target_role": "close_quarters",
                        "existing_identities": ["M4A1"],
                        "excluded_identities": ["Uzi"],
                    }
                ),
                encoding="utf-8",
            )
            fixture_path.write_text(json.dumps(candidate()), encoding="utf-8")
            code = bridge.main(
                [
                    "--request", str(request_path),
                    "--output-dir", str(output),
                    "--offline-fixture", str(fixture_path),
                ]
            )
            result = json.loads((output / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(code, 0)
            self.assertEqual(result["status"], "success")
            self.assertFalse(result["player_confirmation_required"])


if __name__ == "__main__":
    unittest.main()
