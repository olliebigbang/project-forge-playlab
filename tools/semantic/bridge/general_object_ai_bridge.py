#!/usr/bin/env python3
"""One-call, fail-closed general-object affordance bridge for Forge Playlab."""

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
SCHEMA_PATH = PLAYLAB_ROOT / "data" / "combat_feel" / "general_object_ai_response_schema_v1.json"
PROMPT_PATH = PLAYLAB_ROOT / "data" / "combat_feel" / "general_object_ai_prompt_v1.txt"
RESPONSE_SCHEMA = "forge-general-object-ai-response-v1"
REQUEST_SCHEMA = "forge-general-object-ai-request-v1"
RESULT_SCHEMA = "forge-general-object-ai-bridge-result-v1"
SUPPORTED_CLASSIFICATION = "improvised_object_supported"
CLASSIFICATIONS = frozenset(
    {
        SUPPORTED_CLASSIFICATION,
        "firearm_route_required",
        "powered_vehicle_actor_required",
        "living_actor_required",
        "unknown",
    }
)
MIN_ACCEPTED_CONFIDENCE = 0.72
MAX_IDENTITY_LENGTH = 160
MAX_MODEL_CARD_ATTEMPTS = 2
STRING_AXIS_KEYS = (
    "handle_length",
    "body_length",
    "grip_topology",
    "rigidity",
    "mass_distribution",
    "contact_surface",
    "secondary_contact_surface",
    "flex_topology",
    "tether_topology",
    "terminal_load",
    "tether_mode",
    "tether_deployment",
    "state_topology",
    "activation_mode",
    "functional_output",
)
FLAG_KEYS = ("has_point", "has_edge", "has_broad_face", "has_barrel", "has_stock")
DECLARATION_KEYS = STRING_AXIS_KEYS + FLAG_KEYS
LEGAL_VALUES = {
    "handle_length": frozenset({"none", "short", "medium", "long"}),
    "body_length": frozenset({"short", "medium", "long"}),
    "grip_topology": frozenset({"one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"}),
    "rigidity": frozenset({"rigid", "semi_rigid", "flexible"}),
    "mass_distribution": frozenset({"rear", "balanced", "front"}),
    "contact_surface": frozenset({"point", "edge", "broad", "whole_body"}),
    "secondary_contact_surface": frozenset({"none", "point", "edge", "broad", "whole_body"}),
    "flex_topology": frozenset({"none", "bending_shaft", "flexible_line", "linked_segments"}),
    "tether_topology": frozenset({"none", "flexible_line", "linked_segments"}),
    "terminal_load": frozenset({"none", "light", "heavy"}),
    "tether_mode": frozenset({"none", "wrap", "hook"}),
    "tether_deployment": frozenset({"none", "fixed_length", "cast_retract", "launch_tension"}),
    "state_topology": frozenset({"fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary"}),
    "activation_mode": frozenset({"passive", "momentary", "toggle", "charge_release", "continuous_hold"}),
    "functional_output": frozenset({"contact_only", "directed_stream", "radial_field", "pull_field"}),
}
_UNSUPPORTED_TRANSPORT_SCHEMA_KEYS = frozenset(
    {"$schema", "$id", "title", "minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems"}
)


class GeneralObjectBridgeError(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GeneralObjectBridgeError("INVALID_JSON_INPUT") from exc
    if not isinstance(value, dict):
        raise GeneralObjectBridgeError("JSON_INPUT_MUST_BE_OBJECT")
    return value


def _read_identity(request_path: Path) -> str:
    request = _read_json(request_path)
    if set(request) != {"schema", "identity"} or request.get("schema") != REQUEST_SCHEMA:
        raise GeneralObjectBridgeError("REQUEST_SCHEMA_INVALID")
    identity = request.get("identity")
    if not isinstance(identity, str):
        raise GeneralObjectBridgeError("IDENTITY_INVALID")
    identity = identity.strip()
    if not identity or len(identity) > MAX_IDENTITY_LENGTH:
        raise GeneralObjectBridgeError("IDENTITY_INVALID")
    return identity


def anthropic_transport_schema(value: Any) -> Any:
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
        raise GeneralObjectBridgeError(code)
    text = value.strip()
    if len(text) < minimum or len(text) > maximum:
        raise GeneralObjectBridgeError(code)
    return text


def _require_text_list(value: Any, *, minimum: int, maximum: int, item_maximum: int, code: str) -> list[str]:
    if not isinstance(value, list) or not minimum <= len(value) <= maximum:
        raise GeneralObjectBridgeError(code)
    result = [_require_text(item, minimum=1, maximum=item_maximum, code=code) for item in value]
    if len(set(result)) != len(result):
        raise GeneralObjectBridgeError(code)
    return result


def _validate_supported_declaration(value: Any) -> dict[str, Any]:
    if not isinstance(value, Mapping) or set(value) != set(DECLARATION_KEYS):
        raise GeneralObjectBridgeError("DECLARATION_SHAPE_INVALID")
    declaration = dict(value)
    for axis in STRING_AXIS_KEYS:
        axis_value = declaration.get(axis)
        if not isinstance(axis_value, str) or axis_value not in LEGAL_VALUES[axis]:
            raise GeneralObjectBridgeError(f"DECLARATION_AXIS_INVALID_{axis.upper()}")
    for flag in FLAG_KEYS:
        if not isinstance(declaration.get(flag), bool):
            raise GeneralObjectBridgeError(f"DECLARATION_FLAG_INVALID_{flag.upper()}")
    handle = declaration["handle_length"]
    grip = declaration["grip_topology"]
    rigidity = declaration["rigidity"]
    flex = declaration["flex_topology"]
    tether = declaration["tether_topology"]
    terminal = declaration["terminal_load"]
    mode = declaration["tether_mode"]
    deployment = declaration["tether_deployment"]
    state = declaration["state_topology"]
    activation = declaration["activation_mode"]
    output = declaration["functional_output"]
    if handle == "none" and grip not in {"body_grip", "clamp_grip"}:
        raise GeneralObjectBridgeError("DECLARATION_HANDLE_GRIP_CONFLICT")
    if handle != "none" and grip == "body_grip":
        raise GeneralObjectBridgeError("DECLARATION_BODY_GRIP_CONFLICT")
    if (rigidity == "flexible") != (flex != "none"):
        raise GeneralObjectBridgeError("DECLARATION_FLEX_RIGIDITY_CONFLICT")
    has_soft_path = flex != "none" or tether != "none"
    if not has_soft_path and (terminal != "none" or mode != "none"):
        raise GeneralObjectBridgeError("DECLARATION_SOFT_FACTOR_CONFLICT")
    if mode != "none" and flex not in {"flexible_line", "linked_segments"} and tether == "none":
        raise GeneralObjectBridgeError("DECLARATION_TETHER_MODE_CONFLICT")
    if mode == "hook" and not (declaration["has_point"] or declaration["contact_surface"] == "point" or declaration["secondary_contact_surface"] == "point"):
        raise GeneralObjectBridgeError("DECLARATION_HOOK_POINT_CONFLICT")
    if (tether == "none") != (deployment == "none"):
        raise GeneralObjectBridgeError("DECLARATION_TETHER_DEPLOYMENT_CONFLICT")
    if activation == "passive" and (state != "fixed" or output != "contact_only"):
        raise GeneralObjectBridgeError("DECLARATION_ACTIVE_MECHANISM_REQUIRES_ACTIVATION")
    surfaces = {declaration["contact_surface"], declaration["secondary_contact_surface"]}
    for surface, flag in (("point", "has_point"), ("edge", "has_edge"), ("broad", "has_broad_face")):
        # The selected contact surfaces are the authoritative mechanical axes.
        # Capability flags repeat a directly implied physical fact, so repair a
        # missing flag deterministically instead of rejecting an otherwise
        # complete card or asking the player to resolve model bookkeeping.
        if surface in surfaces:
            declaration[flag] = True
    return declaration


def _validate_inert_declaration(value: Any) -> dict[str, Any]:
    if not isinstance(value, Mapping) or set(value) != set(DECLARATION_KEYS):
        raise GeneralObjectBridgeError("DECLARATION_SHAPE_INVALID")
    for axis in STRING_AXIS_KEYS:
        if value.get(axis) != "not_applicable":
            raise GeneralObjectBridgeError("UNSUPPORTED_DECLARATION_MUST_BE_INERT")
    for flag in FLAG_KEYS:
        if value.get(flag) is not False:
            raise GeneralObjectBridgeError("UNSUPPORTED_DECLARATION_MUST_BE_INERT")
    return dict(value)


def _canonical_inert_declaration() -> dict[str, Any]:
    declaration = {key: "not_applicable" for key in STRING_AXIS_KEYS}
    declaration.update({key: False for key in FLAG_KEYS})
    return declaration


def validate_response(identity: str, value: Mapping[str, Any]) -> dict[str, Any]:
    expected_keys = {
        "schema", "requested_identity", "classification", "canonical_name", "confidence",
        "identity_evidence", "visual_description_en", "required_identity_parts_zh",
        "confusable_exclusions_en", "behavior_family", "scale_treatment", "declaration",
    }
    if set(value) != expected_keys or value.get("schema") != RESPONSE_SCHEMA:
        raise GeneralObjectBridgeError("RESPONSE_SCHEMA_INVALID")
    if value.get("requested_identity") != identity:
        raise GeneralObjectBridgeError("IDENTITY_ECHO_MISMATCH")
    classification = value.get("classification")
    if classification not in CLASSIFICATIONS:
        raise GeneralObjectBridgeError("CLASSIFICATION_INVALID")
    confidence = value.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        raise GeneralObjectBridgeError("CONFIDENCE_INVALID")
    confidence = float(confidence)
    if not 0.0 <= confidence <= 1.0:
        raise GeneralObjectBridgeError("CONFIDENCE_INVALID")
    canonical_name = _require_text(value.get("canonical_name"), minimum=1, maximum=96, code="CANONICAL_NAME_INVALID")
    evidence = _require_text_list(value.get("identity_evidence"), minimum=1, maximum=6, item_maximum=240, code="IDENTITY_EVIDENCE_INVALID")
    supported = classification == SUPPORTED_CLASSIFICATION
    if supported:
        if confidence < MIN_ACCEPTED_CONFIDENCE:
            raise GeneralObjectBridgeError("CONFIDENCE_TOO_LOW")
        if value.get("behavior_family") != "heavy_melee":
            raise GeneralObjectBridgeError("BEHAVIOR_FAMILY_INVALID")
        if value.get("scale_treatment") not in {"handheld", "bulky_two_hand", "oversized_fantasy"}:
            raise GeneralObjectBridgeError("SCALE_TREATMENT_INVALID")
        visual_description = _require_text(value.get("visual_description_en"), minimum=12, maximum=360, code="VISUAL_DESCRIPTION_INVALID")
        visible_parts = _require_text_list(value.get("required_identity_parts_zh"), minimum=2, maximum=6, item_maximum=64, code="VISIBLE_PARTS_INVALID")
        exclusions = _require_text_list(value.get("confusable_exclusions_en"), minimum=1, maximum=8, item_maximum=220, code="VISUAL_EXCLUSIONS_INVALID")
        declaration = _validate_supported_declaration(value.get("declaration"))
        behavior_family = "heavy_melee"
        scale_treatment = str(value.get("scale_treatment"))
    else:
        # Only the routing classification is consumed for firearms, actors, and
        # vehicles. Models sometimes fill the irrelevant visual/mechanism fields
        # despite the prompt. Discard those fields instead of blocking the safe
        # handoff to the dedicated compiler.
        visual_description = ""
        visible_parts = []
        exclusions = []
        declaration = _canonical_inert_declaration()
        behavior_family = "not_applicable"
        scale_treatment = "not_applicable"
    return {
        "schema": RESPONSE_SCHEMA,
        "requested_identity": identity,
        "classification": classification,
        "canonical_name": canonical_name,
        "confidence": confidence,
        "identity_evidence": evidence,
        "visual_description_en": visual_description,
        "required_identity_parts_zh": visible_parts,
        "confusable_exclusions_en": exclusions,
        "behavior_family": behavior_family,
        "scale_treatment": scale_treatment,
        "declaration": declaration,
    }


def _clarification_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["reason"],
        "properties": {"reason": {"type": "string", "enum": ["identity_unreadable"]}},
    }


def _repair_system_prompt(base_prompt: str, error_code: str) -> str:
    return (
        f"{base_prompt}\n\n"
        "Automatic local validation rejected the previous object card with "
        f"error code {error_code}. Rebuild the complete card for the exact same "
        "requested_identity. Correct the schema or physical-axis consistency; "
        "do not change the identity, ask the player a question, or invent a named template."
    )


def _merge_usage(total: dict[str, int], value: Mapping[str, Any]) -> None:
    for key, item in value.items():
        if isinstance(item, int) and not isinstance(item, bool):
            total[key] = total.get(key, 0) + item


def resolve_with_anthropic(identity: str) -> tuple[dict[str, Any], str, dict[str, int]]:
    schema = anthropic_transport_schema(_read_json(SCHEMA_PATH))
    try:
        base_prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise GeneralObjectBridgeError("PROMPT_READ_FAILED") from exc
    previous_error = ""
    usage: dict[str, int] = {}
    for attempt in range(MAX_MODEL_CARD_ATTEMPTS):
        prompt = base_prompt if not previous_error else _repair_system_prompt(base_prompt, previous_error)
        compiler = AnthropicSemanticCompiler(
            system_prompt=prompt,
            blueprint_schema=schema,
            clarification_schema=_clarification_schema(),
            strict_blueprint_tool=True,
        )
        compiled = compiler.compile(identity)
        raw_usage = compiled.get("usage", {})
        if isinstance(raw_usage, Mapping):
            _merge_usage(usage, raw_usage)
        try:
            if compiled.get("tool_name") != BLUEPRINT_TOOL_NAME:
                raise GeneralObjectBridgeError("MODEL_DID_NOT_RETURN_OBJECT_CARD")
            tool_input = compiled.get("tool_input")
            if not isinstance(tool_input, Mapping):
                raise GeneralObjectBridgeError("MODEL_TOOL_INPUT_INVALID")
            response = validate_response(identity, tool_input)
            return response, str(compiled.get("model_id", "")), usage
        except GeneralObjectBridgeError as exc:
            # Identity substitution is a security boundary, not a repair hint.
            # All other model-card shape/axis failures get one bounded automatic
            # regeneration before the bridge fails closed.
            if exc.code == "IDENTITY_ECHO_MISMATCH" or attempt + 1 >= MAX_MODEL_CARD_ATTEMPTS:
                raise
            previous_error = exc.code
    raise GeneralObjectBridgeError("MODEL_CARD_RETRY_EXHAUSTED")


def _atomic_write(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def _success_record(response: dict[str, Any], *, source: str, provider: str, model_id: str, usage: Mapping[str, Any]) -> dict[str, Any]:
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
        "failure_reason": f"AI_GENERAL_OBJECT_BRIDGE_{code}",
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
            record = _success_record(response, source="AI_TEST_FIXTURE_GENERAL_OBJECT_V1", provider="offline-fixture", model_id="offline-fixture", usage={"input_tokens": 0, "output_tokens": 0})
        else:
            response, model_id, usage = resolve_with_anthropic(identity)
            record = _success_record(response, source="AI_ANTHROPIC_GENERAL_OBJECT_V1", provider="anthropic", model_id=model_id, usage=usage)
        exit_code = 0
    except GeneralObjectBridgeError as exc:
        record = _failure_record(exc.code)
    except SemanticCompilerError as exc:
        record = _failure_record(exc.code)
    except Exception:
        record = _failure_record("UNEXPECTED_FAILURE")
    _atomic_write(output_path, record)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
