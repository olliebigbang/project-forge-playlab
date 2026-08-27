#!/usr/bin/env python3
"""One-call, fail-closed AI enemy blueprint bridge for Forge Playlab."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Mapping

from anthropic_semantic_compiler import (
    BLUEPRINT_TOOL_NAME,
    AnthropicSemanticCompiler,
    SemanticCompilerError,
)


PLAYLAB_ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = PLAYLAB_ROOT / "data" / "enemy_attack" / "enemy_ai_response_schema_v1.json"
PROMPT_PATH = PLAYLAB_ROOT / "data" / "enemy_attack" / "enemy_ai_prompt_v1.txt"
REQUEST_SCHEMA = "forge-enemy-ai-blueprint-request-v1"
RESPONSE_SCHEMA = "forge-enemy-ai-blueprint-response-v1"
RESULT_SCHEMA = "forge-enemy-ai-blueprint-bridge-result-v1"
MAX_CONCEPT_LENGTH = 160

VISUAL_KEYS = ("body_plan", "scale", "material", "palette", "signature_feature")
MECHANICAL_KEYS = ("mass_class", "armor_class", "durability", "mobility")
ATTACK_KEYS = ("slot_label_zh", "axes", "selection")
AXIS_KEYS = (
    "delivery", "target_lock", "hit_shape", "depth_path", "tempo", "stability", "recovery"
)
SELECTION_KEYS = (
    "preferred_range", "depth_fit", "base_priority", "coordination_cost",
    "requires_clear_path", "selection_rank",
)
LEGAL = {
    "body_plan": {"biped", "quadruped", "arachnid", "serpentine", "floating", "tracked"},
    "scale": {"small", "medium", "large"},
    "material": {"flesh", "chitin", "metal", "stone", "spectral"},
    "palette": {"ember", "venom", "frost", "arcane", "electric", "industrial"},
    "signature_feature": {"mandibles", "horns", "dorsal_spines", "halo", "tail", "shoulder_core"},
    "mass_class": {"light", "medium", "heavy"},
    "armor_class": {"none", "light", "heavy"},
    "durability": {"fragile", "standard", "sturdy"},
    "mobility": {"slow", "steady", "fast"},
    "delivery": {"contact", "rush", "projectile", "marked_impact"},
    "target_lock": {"live_until_active", "direction_on_commit", "point_on_commit"},
    "hit_shape": {"capsule", "arc", "circle", "strip"},
    "depth_path": {"same_lane", "cross_depth", "depth_band"},
    "tempo": {"quick", "standard", "committed"},
    "stability": {"fragile", "tell_interruptible", "armored_commit"},
    "recovery": {"brief", "punishable", "extended"},
    "preferred_range": {"close", "mid", "far", "any"},
    "depth_fit": {"aligned", "tolerant", "any"},
}
_UNSUPPORTED_TRANSPORT_KEYS = {
    "$schema", "$id", "title", "minimum", "maximum", "minLength", "maxLength",
    "minItems", "maxItems",
}


class EnemyBlueprintBridgeError(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EnemyBlueprintBridgeError("INVALID_JSON_INPUT") from exc
    if not isinstance(value, dict):
        raise EnemyBlueprintBridgeError("JSON_INPUT_MUST_BE_OBJECT")
    return value


def _read_concept(path: Path) -> str:
    request = _read_json(path)
    if set(request) != {"schema", "concept"} or request.get("schema") != REQUEST_SCHEMA:
        raise EnemyBlueprintBridgeError("REQUEST_SCHEMA_INVALID")
    concept = request.get("concept")
    if not isinstance(concept, str):
        raise EnemyBlueprintBridgeError("CONCEPT_INVALID")
    concept = concept.strip()
    if not concept or len(concept) > MAX_CONCEPT_LENGTH:
        raise EnemyBlueprintBridgeError("CONCEPT_INVALID")
    return concept


def _transport_schema(value: Any) -> Any:
    if isinstance(value, list):
        return [_transport_schema(item) for item in value]
    if not isinstance(value, Mapping):
        return value
    projected: dict[str, Any] = {}
    for key, item in value.items():
        if key in _UNSUPPORTED_TRANSPORT_KEYS:
            continue
        if key == "const":
            projected["enum"] = [_transport_schema(item)]
        else:
            projected[key] = _transport_schema(item)
    return projected


def _require_text(value: Any, minimum: int, maximum: int, code: str) -> str:
    if not isinstance(value, str):
        raise EnemyBlueprintBridgeError(code)
    text = value.strip()
    if len(text) < minimum or len(text) > maximum:
        raise EnemyBlueprintBridgeError(code)
    return text


def _validate_enum_object(value: Any, keys: tuple[str, ...], code: str) -> dict[str, str]:
    if not isinstance(value, Mapping) or set(value) != set(keys):
        raise EnemyBlueprintBridgeError(f"{code}_SHAPE_INVALID")
    result: dict[str, str] = {}
    for key in keys:
        item = value.get(key)
        if not isinstance(item, str) or item not in LEGAL[key]:
            raise EnemyBlueprintBridgeError(f"{code}_{key.upper()}_INVALID")
        result[key] = item
    return result


def _validate_attack(value: Any, index: int) -> dict[str, Any]:
    code = f"ATTACK_{index}"
    if not isinstance(value, Mapping) or set(value) != set(ATTACK_KEYS):
        raise EnemyBlueprintBridgeError(f"{code}_SHAPE_INVALID")
    label = _require_text(value.get("slot_label_zh"), 2, 32, f"{code}_LABEL_INVALID")
    axes = _validate_enum_object(value.get("axes"), AXIS_KEYS, f"{code}_AXES")
    selection_value = value.get("selection")
    if not isinstance(selection_value, Mapping) or set(selection_value) != set(SELECTION_KEYS):
        raise EnemyBlueprintBridgeError(f"{code}_SELECTION_SHAPE_INVALID")
    selection: dict[str, Any] = {}
    for key in ("preferred_range", "depth_fit"):
        item = selection_value.get(key)
        if not isinstance(item, str) or item not in LEGAL[key]:
            raise EnemyBlueprintBridgeError(f"{code}_SELECTION_{key.upper()}_INVALID")
        selection[key] = item
    for key, minimum, maximum in (
        ("base_priority", 0, 100),
        ("coordination_cost", 1, 3),
        ("selection_rank", 0, 999),
    ):
        item = selection_value.get(key)
        if isinstance(item, bool) or not isinstance(item, int) or not minimum <= item <= maximum:
            raise EnemyBlueprintBridgeError(f"{code}_SELECTION_{key.upper()}_INVALID")
        selection[key] = item
    clear_path = selection_value.get("requires_clear_path")
    if type(clear_path) is not bool:
        raise EnemyBlueprintBridgeError(f"{code}_SELECTION_CLEAR_PATH_INVALID")
    selection["requires_clear_path"] = clear_path

    delivery = axes["delivery"]
    target_lock = axes["target_lock"]
    hit_shape = axes["hit_shape"]
    legal_shapes = {
        "contact": {"capsule", "arc", "circle"},
        "rush": {"capsule", "strip"},
        "projectile": {"capsule"},
        "marked_impact": {"circle", "strip"},
    }
    if hit_shape not in legal_shapes[delivery]:
        raise EnemyBlueprintBridgeError(f"{code}_DELIVERY_SHAPE_CONFLICT")
    if delivery == "rush" and target_lock != "direction_on_commit":
        raise EnemyBlueprintBridgeError(f"{code}_RUSH_LOCK_CONFLICT")
    if delivery == "marked_impact" and target_lock != "point_on_commit":
        raise EnemyBlueprintBridgeError(f"{code}_MARKED_LOCK_CONFLICT")
    if delivery == "projectile" and target_lock == "point_on_commit":
        raise EnemyBlueprintBridgeError(f"{code}_PROJECTILE_LOCK_CONFLICT")
    if target_lock == "live_until_active" and delivery not in {"contact", "projectile"}:
        raise EnemyBlueprintBridgeError(f"{code}_LIVE_LOCK_CONFLICT")
    return {"slot_label_zh": label, "axes": axes, "selection": selection}


def validate_response(concept: str, value: Mapping[str, Any]) -> dict[str, Any]:
    expected = {
        "schema", "requested_concept", "canonical_name_zh", "battle_role_zh", "confidence",
        "visual_axes", "mechanical_profile", "attacks",
    }
    if set(value) != expected or value.get("schema") != RESPONSE_SCHEMA:
        raise EnemyBlueprintBridgeError("RESPONSE_SCHEMA_INVALID")
    if value.get("requested_concept") != concept:
        raise EnemyBlueprintBridgeError("CONCEPT_ECHO_MISMATCH")
    name = _require_text(value.get("canonical_name_zh"), 1, 48, "CANONICAL_NAME_INVALID")
    role = _require_text(value.get("battle_role_zh"), 2, 80, "BATTLE_ROLE_INVALID")
    confidence = value.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        raise EnemyBlueprintBridgeError("CONFIDENCE_INVALID")
    confidence = float(confidence)
    if not 0.0 <= confidence <= 1.0:
        raise EnemyBlueprintBridgeError("CONFIDENCE_INVALID")
    visual = _validate_enum_object(value.get("visual_axes"), VISUAL_KEYS, "VISUAL")
    mechanical = _validate_enum_object(value.get("mechanical_profile"), MECHANICAL_KEYS, "MECHANICAL")
    attacks_value = value.get("attacks")
    if not isinstance(attacks_value, list) or len(attacks_value) != 2:
        raise EnemyBlueprintBridgeError("ATTACK_COUNT_INVALID")
    attacks = [_validate_attack(item, index) for index, item in enumerate(attacks_value)]
    deliveries = [attack["axes"]["delivery"] for attack in attacks]
    if len(set(deliveries)) != 2:
        raise EnemyBlueprintBridgeError("ATTACK_DELIVERY_DUPLICATE")
    engagement = [attack for attack in attacks if attack["axes"]["delivery"] in {"contact", "rush"}]
    pressure = [attack for attack in attacks if attack["axes"]["delivery"] in {"projectile", "marked_impact"}]
    if len(engagement) != 1 or engagement[0]["selection"]["preferred_range"] not in {"close", "mid"}:
        raise EnemyBlueprintBridgeError("ENGAGEMENT_ATTACK_COVERAGE_INVALID")
    if len(pressure) != 1 or pressure[0]["selection"]["preferred_range"] != "far":
        raise EnemyBlueprintBridgeError("PRESSURE_ATTACK_COVERAGE_INVALID")
    if attacks[0]["selection"]["selection_rank"] == attacks[1]["selection"]["selection_rank"]:
        raise EnemyBlueprintBridgeError("ATTACK_SELECTION_RANK_DUPLICATE")
    return {
        "schema": RESPONSE_SCHEMA,
        "requested_concept": concept,
        "canonical_name_zh": name,
        "battle_role_zh": role,
        "confidence": confidence,
        "visual_axes": visual,
        "mechanical_profile": mechanical,
        "attacks": attacks,
    }


def _clarification_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["reason"],
        "properties": {"reason": {"type": "string", "enum": ["not_permitted"]}},
    }


def resolve_with_anthropic(concept: str) -> tuple[dict[str, Any], str, dict[str, int]]:
    schema = _transport_schema(_read_json(SCHEMA_PATH))
    try:
        prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise EnemyBlueprintBridgeError("PROMPT_READ_FAILED") from exc
    compiler = AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=schema,
        clarification_schema=_clarification_schema(),
        strict_blueprint_tool=True,
    )
    compiled = compiler.compile(concept)
    if compiled.get("tool_name") != BLUEPRINT_TOOL_NAME:
        raise EnemyBlueprintBridgeError("MODEL_DID_NOT_RETURN_BLUEPRINT")
    tool_input = compiled.get("tool_input")
    if not isinstance(tool_input, Mapping):
        raise EnemyBlueprintBridgeError("MODEL_TOOL_INPUT_INVALID")
    return validate_response(concept, tool_input), str(compiled.get("model_id", "")), dict(compiled.get("usage", {}))


def _atomic_write(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def _success(response: dict[str, Any], model_id: str, provider: str, source: str, usage: Mapping[str, Any]) -> dict[str, Any]:
    delivered = dict(response)
    delivered["model_id"] = model_id
    return {
        "schema": RESULT_SCHEMA,
        "status": "success",
        "provider": provider,
        "source": source,
        "model_id": model_id,
        "usage": dict(usage),
        "response": delivered,
        "player_confirmation_required": False,
    }


def _failure(code: str) -> dict[str, Any]:
    return {
        "schema": RESULT_SCHEMA,
        "status": "failed",
        "failure_reason": f"AI_ENEMY_BRIDGE_{code}",
        "player_confirmation_required": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--offline-fixture", type=Path)
    args = parser.parse_args(argv)
    output_path = args.output_dir.resolve() / "result.json"
    exit_code = 1
    try:
        concept = _read_concept(args.request.resolve())
        if args.offline_fixture is not None:
            response = validate_response(concept, _read_json(args.offline_fixture.resolve()))
            record = _success(response, "offline-fixture", "offline-fixture", "AI_TEST_FIXTURE_ENEMY_V1", {"input_tokens": 0, "output_tokens": 0})
        else:
            response, model_id, usage = resolve_with_anthropic(concept)
            record = _success(response, model_id, "anthropic", "AI_ANTHROPIC_ENEMY_BLUEPRINT_V1", usage)
        exit_code = 0
    except EnemyBlueprintBridgeError as exc:
        record = _failure(exc.code)
    except SemanticCompilerError as exc:
        record = _failure(exc.code)
    except Exception:
        record = _failure("UNEXPECTED_FAILURE")
    _atomic_write(output_path, record)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
