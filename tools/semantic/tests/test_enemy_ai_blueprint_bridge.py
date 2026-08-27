from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path


PLAYLAB_ROOT = Path(__file__).resolve().parents[3]
BRIDGE_ROOT = PLAYLAB_ROOT / "tools" / "semantic" / "bridge"
sys.path.insert(0, str(BRIDGE_ROOT))

import enemy_ai_blueprint_bridge as bridge  # noqa: E402


FIXTURE = PLAYLAB_ROOT / "tests" / "fixtures" / "enemy_ai_mechanical_spider_response.json"
REQUEST = PLAYLAB_ROOT / "tests" / "fixtures" / "enemy_ai_mechanical_spider_request.json"


class EnemyAIBlueprintBridgeTests(unittest.TestCase):
    def fixture(self) -> dict:
        return json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_fixture_passes_strict_validation(self) -> None:
        result = bridge.validate_response("机械蜘蛛", self.fixture())
        self.assertEqual("织网猎蛛", result["canonical_name_zh"])
        self.assertEqual(["rush", "projectile"], [item["axes"]["delivery"] for item in result["attacks"]])

    def test_illegal_coverage_fails_closed(self) -> None:
        payload = copy.deepcopy(self.fixture())
        payload["attacks"][1]["selection"]["preferred_range"] = "mid"
        with self.assertRaisesRegex(bridge.EnemyBlueprintBridgeError, "PRESSURE_ATTACK_COVERAGE_INVALID"):
            bridge.validate_response("机械蜘蛛", payload)

    def test_model_cannot_add_uncontracted_fields(self) -> None:
        payload = copy.deepcopy(self.fixture())
        payload["attacks"][0]["damage"] = 999999
        with self.assertRaisesRegex(bridge.EnemyBlueprintBridgeError, "ATTACK_0_SHAPE_INVALID"):
            bridge.validate_response("机械蜘蛛", payload)

    def test_offline_cli_writes_complete_atomic_result(self) -> None:
        with tempfile.TemporaryDirectory(prefix="enemy-ai-blueprint-") as temporary:
            output = Path(temporary)
            exit_code = bridge.main([
                "--request", str(REQUEST),
                "--output-dir", str(output),
                "--offline-fixture", str(FIXTURE),
            ])
            self.assertEqual(0, exit_code)
            record = json.loads((output / "result.json").read_text(encoding="utf-8"))
            self.assertEqual("success", record["status"])
            self.assertFalse(record["player_confirmation_required"])
            self.assertFalse((output / "result.json.tmp").exists())

    def test_transport_schema_removes_only_unsupported_constraints(self) -> None:
        source = json.loads(bridge.SCHEMA_PATH.read_text(encoding="utf-8"))
        projected = bridge._transport_schema(source)
        serialized = json.dumps(projected, ensure_ascii=False)
        self.assertNotIn('"minItems"', serialized)
        self.assertNotIn('"maxLength"', serialized)
        self.assertIn('"additionalProperties": false', serialized)
        self.assertEqual([bridge.RESPONSE_SCHEMA], projected["properties"]["schema"]["enum"])


if __name__ == "__main__":
    unittest.main()
