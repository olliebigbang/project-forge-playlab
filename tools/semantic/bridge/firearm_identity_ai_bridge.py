#!/usr/bin/env python3
"""One-call, fail-closed firearm identity bridge for Forge Playlab.

The language model may only fill the frozen firearm identity schema.  This
module validates the answer again before Godot receives it and never asks the
player to choose combat mechanics.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Mapping

from anthropic_semantic_compiler import (
    BLUEPRINT_TOOL_NAME,
    AnthropicSemanticCompiler,
    SemanticCompilerError,
)


PLAYLAB_ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = (
    PLAYLAB_ROOT / "data" / "combat_feel" / "firearm_identity_ai_response_schema_v4.json"
)
PROMPT_PATH = (
    PLAYLAB_ROOT / "data" / "combat_feel" / "firearm_identity_ai_prompt_v4.txt"
)
RESPONSE_SCHEMA = "forge-firearm-identity-ai-response-v4"
REQUEST_SCHEMA = "forge-firearm-identity-ai-request-v1"
RESULT_SCHEMA = "forge-firearm-identity-ai-bridge-result-v1"
SUPPORTED_CLASSIFICATION = "handheld_firearm_supported"
CLASSIFICATIONS = frozenset(
    {
        SUPPORTED_CLASSIFICATION,
        "handheld_firearm_unsupported",
        "vehicle_weapon_platform",
        "not_firearm",
        "unknown",
    }
)
MIN_ACCEPTED_CONFIDENCE = 0.72
MAX_IDENTITY_LENGTH = 160
DECLARATION_KEYS = (
    "weapon_domain",
    "firearm_family",
    "layout",
    "stock_structure",
    "feed_position",
    "magazine_shape",
    "barrel_length",
    "upper_profile",
    "support_mode",
    "fire_control",
    "action_mechanism",
    "feed_system",
    "shot_pattern",
    "sustained_climb",
    "cadence",
    "recoil",
    "recoil_recovery",
    "muzzle_climb",
    "accuracy",
    "impact_force",
    "penetration",
    "reload",
    "effective_range",
    "handling",
    "magazine_capacity",
    "finish_palette",
)
VISUAL_AXIS_KEYS = (
    "stock_profile",
    "upper_landmark",
    "magazine_profile",
    "fore_end_profile",
    "receiver_profile",
)
LEGAL_VALUES = {
    "weapon_domain": frozenset({"handheld_firearm"}),
    "firearm_family": frozenset({"semi_auto_pistol", "revolver", "submachine_gun", "rifle", "precision_rifle", "shotgun", "light_machine_gun"}),
    "layout": frozenset({"bullpup", "conventional_rifle", "pistol", "conventional_shotgun", "revolver", "belt_fed_support"}),
    "stock_structure": frozenset({"integrated", "telescoping", "fixed", "none"}),
    "feed_position": frozenset({"behind_grip", "ahead_of_grip", "in_grip", "under_barrel", "cylinder_center", "side_feed"}),
    "magazine_shape": frozenset({"straight", "curved", "in_grip", "tube", "cylinder", "belt_box"}),
    "barrel_length": frozenset({"short", "medium", "long"}),
    "upper_profile": frozenset({"carry_handle", "top_rail", "raised_gas_tube", "slide", "ribbed_barrel", "revolver_frame", "feed_cover"}),
    "support_mode": frozenset({"one_hand", "two_hand_shouldered"}),
    "fire_control": frozenset({"semi_auto", "three_round_burst", "select_fire_auto"}),
    "action_mechanism": frozenset({"self_loading", "bolt_action", "pump_action", "revolving_cylinder"}),
    "feed_system": frozenset({"detachable_box", "internal_tube", "revolving_cylinder", "belt_box"}),
    "shot_pattern": frozenset({"single_projectile", "pellet_cloud"}),
    "sustained_climb": frozenset({"none", "controlled", "progressive"}),
    "cadence": frozenset({"deliberate", "balanced", "rapid"}),
    "recoil": frozenset({"light", "medium", "strong"}),
    "recoil_recovery": frozenset({"quick", "balanced", "slow"}),
    "muzzle_climb": frozenset({"low", "medium", "high"}),
    "accuracy": frozenset({"precise", "controlled", "loose"}),
    "impact_force": frozenset({"light", "medium", "strong"}),
    "penetration": frozenset({"light", "medium", "strong"}),
    "reload": frozenset({"quick", "standard", "slow"}),
    "effective_range": frozenset({"short", "medium", "long"}),
    "handling": frozenset({"agile", "balanced", "heavy"}),
    "magazine_capacity": frozenset({"very_low", "compact", "standard", "extended", "belt"}),
    "finish_palette": frozenset({"gunmetal_black", "olive_black", "wood_steel", "dark_polymer"}),
}
_UNSUPPORTED_TRANSPORT_SCHEMA_KEYS = frozenset(
    {
        "$schema",
        "$id",
        "title",
        "minimum",
        "maximum",
        "minLength",
        "maxLength",
        "minItems",
        "maxItems",
    }
)


class FirearmIdentityBridgeError(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise FirearmIdentityBridgeError("INVALID_JSON_INPUT") from exc
    if not isinstance(value, dict):
        raise FirearmIdentityBridgeError("JSON_INPUT_MUST_BE_OBJECT")
    return value


def _read_identity(request_path: Path) -> str:
    request = _read_json(request_path)
    if set(request) != {"schema", "identity"} or request.get("schema") != REQUEST_SCHEMA:
        raise FirearmIdentityBridgeError("REQUEST_SCHEMA_INVALID")
    identity = request.get("identity")
    if not isinstance(identity, str):
        raise FirearmIdentityBridgeError("IDENTITY_INVALID")
    identity = identity.strip()
    if not identity or len(identity) > MAX_IDENTITY_LENGTH:
        raise FirearmIdentityBridgeError("IDENTITY_INVALID")
    return identity


def anthropic_transport_schema(value: Any) -> Any:
    """Project the frozen local schema onto Anthropic's strict-tool subset.

    Length, count, and numeric bounds remain enforced by both local validators;
    the API currently rejects those validation keywords for strict custom tools.
    """

    if isinstance(value, list):
        return [anthropic_transport_schema(item) for item in value]
    if not isinstance(value, Mapping):
        return value
    projected: dict[str, Any] = {}
    for key, item in value.items():
        if key in _UNSUPPORTED_TRANSPORT_SCHEMA_KEYS:
            continue
        if key == "const":
            projected["enum"] = [anthropic_transport_schema(item)]
            continue
        projected[key] = anthropic_transport_schema(item)
    return projected


def _require_text(value: Any, *, minimum: int, maximum: int, code: str) -> str:
    if not isinstance(value, str):
        raise FirearmIdentityBridgeError(code)
    text = value.strip()
    if len(text) < minimum or len(text) > maximum:
        raise FirearmIdentityBridgeError(code)
    return text


def _require_text_list(
    value: Any, *, minimum: int, maximum: int, item_maximum: int, code: str
) -> list[str]:
    if not isinstance(value, list) or not minimum <= len(value) <= maximum:
        raise FirearmIdentityBridgeError(code)
    result: list[str] = []
    for item in value:
        result.append(
            _require_text(item, minimum=1, maximum=item_maximum, code=code)
        )
    return result


def _validate_declaration(value: Any, classification: str) -> dict[str, str]:
    if not isinstance(value, Mapping) or set(value) != set(DECLARATION_KEYS):
        raise FirearmIdentityBridgeError("DECLARATION_SHAPE_INVALID")
    declaration = {key: value.get(key) for key in DECLARATION_KEYS}
    if not all(isinstance(axis_value, str) for axis_value in declaration.values()):
        raise FirearmIdentityBridgeError("DECLARATION_VALUE_INVALID")
    if classification != SUPPORTED_CLASSIFICATION:
        if any(axis_value != "not_applicable" for axis_value in declaration.values()):
            raise FirearmIdentityBridgeError("NON_FIREARM_DECLARATION_MUST_BE_EMPTY")
        return dict(declaration)
    for axis, legal in LEGAL_VALUES.items():
        if declaration[axis] not in legal:
            raise FirearmIdentityBridgeError(f"DECLARATION_AXIS_INVALID_{axis.upper()}")
    family = declaration["firearm_family"]
    layout = declaration["layout"]
    stock = declaration["stock_structure"]
    feed = declaration["feed_position"]
    magazine = declaration["magazine_shape"]
    support = declaration["support_mode"]
    barrel = declaration["barrel_length"]
    upper = declaration["upper_profile"]
    action = declaration["action_mechanism"]
    feed_system = declaration["feed_system"]
    shot_pattern = declaration["shot_pattern"]
    sustained_climb = declaration["sustained_climb"]
    legal_layouts = {
        "semi_auto_pistol": {"pistol"},
        "shotgun": {"conventional_shotgun"},
        "revolver": {"revolver"},
        "submachine_gun": {"conventional_rifle"},
        "rifle": {"bullpup", "conventional_rifle"},
        "precision_rifle": {"conventional_rifle"},
        "light_machine_gun": {"belt_fed_support"},
    }
    if layout not in legal_layouts[family]:
        raise FirearmIdentityBridgeError("DECLARATION_FIREARM_FAMILY_CONFLICT")
    if layout == "bullpup" and not (
        feed == "behind_grip" and stock == "integrated" and support == "two_hand_shouldered"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_BULLPUP_CONFLICT")
    if layout == "conventional_rifle" and not (
        feed == "ahead_of_grip" and stock != "none" and support == "two_hand_shouldered"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_CONVENTIONAL_CONFLICT")
    if layout == "pistol" and not (
        feed == "in_grip"
        and magazine == "in_grip"
        and stock == "none"
        and support == "one_hand"
        and barrel == "short"
        and upper == "slide"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_PISTOL_CONFLICT")
    if layout == "conventional_shotgun" and not (
        feed == "under_barrel"
        and magazine == "tube"
        and stock != "none"
        and support == "two_hand_shouldered"
        and upper == "ribbed_barrel"
        and action == "pump_action"
        and feed_system == "internal_tube"
        and shot_pattern == "pellet_cloud"
        and declaration["fire_control"] == "semi_auto"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_SHOTGUN_CONFLICT")
    if layout == "revolver" and not (
        feed == "cylinder_center"
        and magazine == "cylinder"
        and stock == "none"
        and support == "one_hand"
        and barrel != "long"
        and upper == "revolver_frame"
        and action == "revolving_cylinder"
        and feed_system == "revolving_cylinder"
        and shot_pattern == "single_projectile"
        and declaration["fire_control"] == "semi_auto"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_REVOLVER_CONFLICT")
    if layout == "belt_fed_support" and not (
        feed == "side_feed"
        and magazine == "belt_box"
        and stock != "none"
        and support == "two_hand_shouldered"
        and upper == "feed_cover"
        and action == "self_loading"
        and feed_system == "belt_box"
        and shot_pattern == "single_projectile"
        and sustained_climb == "progressive"
        and declaration["fire_control"] == "select_fire_auto"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_BELT_FED_SUPPORT_CONFLICT")
    if layout in {"bullpup", "conventional_rifle", "pistol"} and not (
        feed_system == "detachable_box" and shot_pattern == "single_projectile"
    ):
        raise FirearmIdentityBridgeError("DECLARATION_MAGAZINE_FED_CONFLICT")
    if layout in {"bullpup", "conventional_rifle", "pistol"} and action not in {
        "self_loading", "bolt_action"
    }:
        raise FirearmIdentityBridgeError("DECLARATION_ACTION_CONFLICT")
    if action == "bolt_action" and layout != "conventional_rifle":
        raise FirearmIdentityBridgeError("DECLARATION_BOLT_ACTION_CONFLICT")
    return dict(declaration)


def _validate_visual_identity(
    axes_value: Any,
    landmarks_value: Any,
    exclusions_value: Any,
    classification: str,
) -> tuple[dict[str, str], list[str], list[str]]:
    if not isinstance(axes_value, Mapping) or set(axes_value) != set(VISUAL_AXIS_KEYS):
        raise FirearmIdentityBridgeError("VISUAL_IDENTITY_AXES_SHAPE_INVALID")
    if classification != SUPPORTED_CLASSIFICATION:
        return (
            {key: "not_applicable" for key in VISUAL_AXIS_KEYS},
            [],
            [],
        )
    axes: dict[str, str] = {}
    for key in VISUAL_AXIS_KEYS:
        axis_value = _require_text(
            axes_value.get(key),
            minimum=3,
            maximum=96,
            code=f"VISUAL_IDENTITY_AXIS_INVALID_{key.upper()}",
        )
        if axis_value == "not_applicable" or "identity_specific" in axis_value.lower():
            raise FirearmIdentityBridgeError(
                f"VISUAL_IDENTITY_AXIS_TOO_GENERIC_{key.upper()}"
            )
        axes[key] = axis_value
    landmarks = _require_text_list(
        landmarks_value,
        minimum=2,
        maximum=8,
        item_maximum=180,
        code="VISUAL_IDENTITY_LANDMARKS_INVALID",
    )
    exclusions = _require_text_list(
        exclusions_value,
        minimum=1,
        maximum=8,
        item_maximum=220,
        code="VISUAL_IDENTITY_EXCLUSIONS_INVALID",
    )
    if len(set(landmarks)) != len(landmarks) or len(set(exclusions)) != len(exclusions):
        raise FirearmIdentityBridgeError("VISUAL_IDENTITY_DUPLICATE_ITEM")
    return axes, landmarks, exclusions


def validate_response(identity: str, value: Mapping[str, Any]) -> dict[str, Any]:
    expected_keys = {
        "schema",
        "requested_identity",
        "classification",
        "canonical_name",
        "confidence",
        "identity_evidence",
        "visual_description_en",
        "required_identity_parts_zh",
        "visual_identity_axes",
        "required_landmarks_en",
        "confusable_exclusions_en",
        "declaration",
    }
    if set(value) != expected_keys or value.get("schema") != RESPONSE_SCHEMA:
        raise FirearmIdentityBridgeError("RESPONSE_SCHEMA_INVALID")
    if value.get("requested_identity") != identity:
        raise FirearmIdentityBridgeError("IDENTITY_ECHO_MISMATCH")
    classification = value.get("classification")
    if classification not in CLASSIFICATIONS:
        raise FirearmIdentityBridgeError("CLASSIFICATION_INVALID")
    confidence = value.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        raise FirearmIdentityBridgeError("CONFIDENCE_INVALID")
    confidence = float(confidence)
    if not 0.0 <= confidence <= 1.0:
        raise FirearmIdentityBridgeError("CONFIDENCE_INVALID")
    canonical_name = _require_text(
        value.get("canonical_name"), minimum=1, maximum=96, code="CANONICAL_NAME_INVALID"
    )
    identity_evidence = _require_text_list(
        value.get("identity_evidence"),
        minimum=1,
        maximum=6,
        item_maximum=240,
        code="IDENTITY_EVIDENCE_INVALID",
    )
    declaration = _validate_declaration(value.get("declaration"), classification)
    visual_axes, landmarks, exclusions = _validate_visual_identity(
        value.get("visual_identity_axes"),
        value.get("required_landmarks_en"),
        value.get("confusable_exclusions_en"),
        classification,
    )
    if classification == SUPPORTED_CLASSIFICATION:
        if confidence < MIN_ACCEPTED_CONFIDENCE:
            raise FirearmIdentityBridgeError("CONFIDENCE_TOO_LOW")
        visual_description = _require_text(
            value.get("visual_description_en"),
            minimum=12,
            maximum=360,
            code="VISUAL_DESCRIPTION_INVALID",
        )
        visible_parts = _require_text_list(
            value.get("required_identity_parts_zh"),
            minimum=2,
            maximum=6,
            item_maximum=64,
            code="VISIBLE_PARTS_INVALID",
        )
    else:
        # These fields never control gameplay for a non-supported class.  Some
        # models still populate required string/array fields despite the prompt;
        # discard that inert text instead of losing the safe classification.
        visual_description = ""
        visible_parts = []
    return {
        "schema": RESPONSE_SCHEMA,
        "requested_identity": identity,
        "classification": classification,
        "canonical_name": canonical_name,
        "confidence": confidence,
        "identity_evidence": identity_evidence,
        "visual_description_en": visual_description,
        "required_identity_parts_zh": visible_parts,
        "visual_identity_axes": visual_axes,
        "required_landmarks_en": landmarks,
        "confusable_exclusions_en": exclusions,
        "declaration": declaration,
    }


def _clarification_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["reason"],
        "properties": {
            "reason": {"type": "string", "enum": ["identity_unreadable"]}
        },
    }


def resolve_with_anthropic(identity: str) -> tuple[dict[str, Any], str, dict[str, int]]:
    schema = anthropic_transport_schema(_read_json(SCHEMA_PATH))
    try:
        prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise FirearmIdentityBridgeError("PROMPT_READ_FAILED") from exc
    compiler = AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=schema,
        clarification_schema=_clarification_schema(),
        strict_blueprint_tool=True,
    )
    compiled = compiler.compile(identity)
    if compiled.get("tool_name") != BLUEPRINT_TOOL_NAME:
        raise FirearmIdentityBridgeError("MODEL_DID_NOT_RETURN_IDENTITY_CARD")
    tool_input = compiled.get("tool_input")
    if not isinstance(tool_input, Mapping):
        raise FirearmIdentityBridgeError("MODEL_TOOL_INPUT_INVALID")
    validated = validate_response(identity, tool_input)
    return validated, str(compiled.get("model_id", "")), dict(compiled.get("usage", {}))


def _atomic_write(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    os.replace(temporary, path)


def _success_record(
    response: dict[str, Any], *, source: str, provider: str, model_id: str, usage: Mapping[str, Any]
) -> dict[str, Any]:
    delivered = dict(response)
    delivered["model_id"] = model_id
    return {
        "schema": RESULT_SCHEMA,
        "status": "success",
        "source": source,
        "provider": provider,
        "model_id": model_id,
        "usage": dict(usage),
        "response": delivered,
        "player_confirmation_required": False,
    }


def _failure_record(code: str) -> dict[str, Any]:
    return {
        "schema": RESULT_SCHEMA,
        "status": "failed",
        "failure_reason": f"AI_FIREARM_BRIDGE_{code}",
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
        identity = _read_identity(args.request.resolve())
        if args.offline_fixture is not None:
            response = validate_response(identity, _read_json(args.offline_fixture.resolve()))
            record = _success_record(
                response,
                source="AI_TEST_FIXTURE_FIREARM_IDENTITY_V4",
                provider="offline-fixture",
                model_id="offline-fixture",
                usage={"input_tokens": 0, "output_tokens": 0},
            )
        else:
            response, model_id, usage = resolve_with_anthropic(identity)
            record = _success_record(
                response,
                source="AI_ANTHROPIC_FIREARM_IDENTITY_V4",
                provider="anthropic",
                model_id=model_id,
                usage=usage,
            )
        exit_code = 0
    except FirearmIdentityBridgeError as exc:
        record = _failure_record(exc.code)
    except SemanticCompilerError as exc:
        record = _failure_record(exc.code)
    except Exception:
        record = _failure_record("UNEXPECTED_FAILURE")
    _atomic_write(output_path, record)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
