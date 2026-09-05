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
NAMED_IDENTITY_SCHEMA_PATH = PLAYLAB_ROOT / "data" / "combat_feel" / "named_object_identity_schema_v2.json"
NAMED_IDENTITY_PROMPT_PATH = PLAYLAB_ROOT / "data" / "combat_feel" / "named_object_identity_prompt_v2.txt"
RESPONSE_SCHEMA = "forge-general-object-ai-response-v1"
NAMED_IDENTITY_SCHEMA = "forge-named-object-identity-resolution-v2"
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
MIN_NAMED_IDENTITY_CONFIDENCE = 0.72
MIN_LITERAL_HEAD_NOUN_CONFIDENCE = 0.50
MAX_IDENTITY_LENGTH = 160
MAX_MODEL_CARD_ATTEMPTS = 3
MAX_NAMED_IDENTITY_ATTEMPTS = 2
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
MECHANISM_ROLE_KEYS = ("grip_part_zh", "activation_part_zh", "effect_origin_part_zh")
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
_GENERIC_SINGLE_CJK_SUFFIXES = frozenset("物器具件品体类装械机")


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
    no_soft_path = declaration.get("flex_topology") == "none" and declaration.get("tether_topology") == "none"
    if no_soft_path:
        # A rigid/no-tether object has exactly one legal inert state for these
        # soft-path axes. Clear any redundant model value before the closed
        # enum check. This cannot create a soft mechanic, change the rigid
        # structure, or choose an attack; it only removes an impossible path.
        for axis in ("terminal_load", "tether_mode", "tether_deployment"):
            declaration[axis] = "none"
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
    # A named flex topology is the more specific structural statement. It
    # deterministically implies a flexible assembled path, so repair the
    # redundant coarse rigidity axis. The reverse remains fail-closed: a model
    # may not claim generic flexibility without saying what physically bends.
    if flex != "none":
        declaration["rigidity"] = "flexible"
        rigidity = "flexible"
    if rigidity == "flexible" and flex == "none":
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


def _validate_mechanism_roles(
    value: Any,
    visible_parts: list[str],
    declaration: Mapping[str, Any],
    *,
    supported: bool,
) -> dict[str, str]:
    if not isinstance(value, Mapping) or set(value) != set(MECHANISM_ROLE_KEYS):
        raise GeneralObjectBridgeError("MECHANISM_ROLES_SHAPE_INVALID")
    roles: dict[str, str] = {}
    for key in MECHANISM_ROLE_KEYS:
        raw = value.get(key)
        if not isinstance(raw, str):
            raise GeneralObjectBridgeError("MECHANISM_ROLE_INVALID")
        role = raw.strip()
        if len(role) > 64:
            raise GeneralObjectBridgeError("MECHANISM_ROLE_INVALID")
        roles[key] = role
    if not supported:
        if any(roles.values()):
            raise GeneralObjectBridgeError("UNSUPPORTED_MECHANISM_ROLES_MUST_BE_INERT")
        return roles
    grip = roles["grip_part_zh"]
    activation = roles["activation_part_zh"]
    effect_origin = roles["effect_origin_part_zh"]
    if not grip or grip not in visible_parts:
        raise GeneralObjectBridgeError("MECHANISM_GRIP_ROLE_INVALID")
    if not effect_origin or effect_origin not in visible_parts:
        raise GeneralObjectBridgeError("MECHANISM_EFFECT_ROLE_INVALID")
    if declaration.get("activation_mode") == "passive":
        if activation:
            raise GeneralObjectBridgeError("MECHANISM_PASSIVE_ACTIVATION_ROLE_CONFLICT")
    elif not activation or activation not in visible_parts:
        raise GeneralObjectBridgeError("MECHANISM_ACTIVATION_ROLE_INVALID")
    if declaration.get("grip_topology") in {"one_hand_handle", "two_hand_handle"} and grip == effect_origin:
        raise GeneralObjectBridgeError("MECHANISM_HANDLE_EFFECT_ROLE_CONFLICT")
    return roles


def _canonical_inert_declaration() -> dict[str, Any]:
    declaration = {key: "not_applicable" for key in STRING_AXIS_KEYS}
    declaration.update({key: False for key in FLAG_KEYS})
    return declaration


def validate_response(identity: str, value: Mapping[str, Any]) -> dict[str, Any]:
    expected_keys = {
        "schema", "requested_identity", "classification", "canonical_name", "confidence",
        "identity_evidence", "visual_description_en", "required_identity_parts_zh",
        "confusable_exclusions_en", "mechanism_roles", "behavior_family", "scale_treatment", "declaration",
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
        mechanism_roles = _validate_mechanism_roles(value.get("mechanism_roles"), visible_parts, declaration, supported=True)
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
        mechanism_roles = {key: "" for key in MECHANISM_ROLE_KEYS}
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
        "mechanism_roles": mechanism_roles,
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
    repair_hints = {
        "CONFIDENCE_TOO_LOW": (
            "For this exact error: first distinguish a literal physical description from a proper name. "
            "When the player's own text explicitly supplies ordinary parts, material, connectivity, or shape, "
            "score confidence in that supplied class-level structure; a catalog name is not required. Do not "
            "invent any absent part. For a proper name or titled artifact, separate the exact title from any "
            "clearly established physical head noun or public object class. If that class is reliable, preserve "
            "the title but declare only stable class-level geometry and score confidence on that declared "
            "structure, not on unknown lore or ornament. If no physical class is reliable, return unknown. "
            "Never invent title-specific mechanics or substitute another identity."
        ),
        "DECLARATION_FLEX_RIGIDITY_CONFLICT": (
            "For this exact error: flex_topology none requires rigidity rigid or semi_rigid; "
            "any non-none flex_topology requires rigidity flexible. Judge the assembled path."
        ),
        "DECLARATION_HANDLE_GRIP_CONFLICT": (
            "For this exact error: handle_length none requires body_grip or clamp_grip. "
            "Use one_hand_handle or two_hand_handle only when a distinct handle exists and give it a non-none length."
        ),
        "DECLARATION_BODY_GRIP_CONFLICT": (
            "For this exact error: body_grip requires handle_length none. If a distinct handle exists, "
            "keep its non-none length and choose one_hand_handle or two_hand_handle instead."
        ),
        "DECLARATION_SOFT_FACTOR_CONFLICT": (
            "For this exact error: terminal_load, tether_mode, and tether_deployment describe only a load or "
            "behavior carried by a real flexible or tether path. When both flex_topology and tether_topology "
            "are none, set all three soft-path fields to none. A rigid end fixture, clamp, head, or attachment "
            "is ordinary rigid body structure, not a terminal_load. Do not add a cord or tether to justify it."
        ),
        "NAMED_IDENTITY_BODY_SPAN_CONFLICT": (
            "For this exact error: the constrained named-class resolver supplied a locked class-level "
            "body span. Preserve it exactly in declaration.body_length. Do not shrink an extended physical "
            "class because the sprite is small or handheld, and do not change any attack or balance field to compensate."
        ),
        "NORMALIZED_CLASS_CONFIDENCE_TOO_LOW": (
            "For this exact error: the current user content is already the resolved ordinary physical class, "
            "not the original proper title. Score confidence only in this generic class and its large visible "
            "structure. Do not carry uncertainty about lore, ownership, ornament, or the original title into "
            "the class-level confidence. Do not invent missing decorative details."
        ),
    }
    repair_hint = repair_hints.get(error_code, "Recheck every cross-field rule in the base prompt.")
    if error_code.startswith("MECHANISM_"):
        repair_hint = (
            "For this exact error: copy each non-empty mechanism_roles value exactly from "
            "required_identity_parts_zh. Always name grip and effect-origin parts; name an "
            "activation part for every non-passive activation. A distinct handle cannot also "
            "be the effect origin. Re-evaluate the real native function before choosing contact_only."
        )
    return (
        f"{base_prompt}\n\n"
        "Automatic local validation rejected the previous object card with "
        f"error code {error_code}. Rebuild the complete card for the exact same "
        "requested_identity. Correct the schema or physical-axis consistency; "
        "do not change the identity, ask the player a question, or invent a named template. "
        f"{repair_hint}"
    )


def validate_named_identity_resolution(identity: str, value: Mapping[str, Any]) -> dict[str, Any]:
    expected = {
        "schema", "requested_identity", "status", "physical_class_zh", "body_span", "confidence",
        "identity_evidence",
    }
    if set(value) != expected or value.get("schema") != NAMED_IDENTITY_SCHEMA:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_RESPONSE_SCHEMA_INVALID")
    if value.get("requested_identity") != identity:
        raise GeneralObjectBridgeError("IDENTITY_ECHO_MISMATCH")
    status = value.get("status")
    if status not in {"resolved", "unknown"}:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_STATUS_INVALID")
    confidence = value.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        raise GeneralObjectBridgeError("NAMED_IDENTITY_CONFIDENCE_INVALID")
    confidence = float(confidence)
    if not 0.0 <= confidence <= 1.0:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_CONFIDENCE_INVALID")
    evidence = _require_text_list(
        value.get("identity_evidence"), minimum=1, maximum=4, item_maximum=180,
        code="NAMED_IDENTITY_EVIDENCE_INVALID",
    )
    raw_class = value.get("physical_class_zh")
    if not isinstance(raw_class, str):
        raise GeneralObjectBridgeError("NAMED_IDENTITY_CLASS_INVALID")
    physical_class = raw_class.strip()
    body_span = value.get("body_span")
    if body_span not in {"unknown", "short", "medium", "long"}:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_BODY_SPAN_INVALID")
    forbidden = set("\r\n\t`{}[]<>:;|\\/\"")
    if status == "resolved":
        if not 1 <= len(physical_class) <= 48 or any(character in forbidden for character in physical_class):
            raise GeneralObjectBridgeError("NAMED_IDENTITY_CLASS_INVALID")
        literal_head_noun = _has_literal_class_suffix(identity, physical_class)
        if confidence < MIN_NAMED_IDENTITY_CONFIDENCE and not (
            literal_head_noun and confidence >= MIN_LITERAL_HEAD_NOUN_CONFIDENCE
        ):
            raise GeneralObjectBridgeError("NAMED_IDENTITY_CONFIDENCE_TOO_LOW")
    elif physical_class:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_UNKNOWN_CLASS_MUST_BE_EMPTY")
    if status == "unknown" and body_span != "unknown":
        raise GeneralObjectBridgeError("NAMED_IDENTITY_UNKNOWN_SPAN_MUST_BE_UNKNOWN")
    return {
        "schema": NAMED_IDENTITY_SCHEMA,
        "requested_identity": identity,
        "status": status,
        "physical_class_zh": physical_class,
        "body_span": body_span,
        "confidence": confidence,
        "identity_evidence": evidence,
    }


def _has_literal_class_suffix(identity: str, physical_class: str) -> bool:
    identity_text = identity.strip().casefold()
    class_text = physical_class.strip().casefold()
    if not identity_text or not class_text:
        return False
    common_length = 0
    for identity_character, class_character in zip(reversed(identity_text), reversed(class_text)):
        if identity_character != class_character:
            break
        common_length += 1
    if common_length == 0:
        return False
    common_suffix = class_text[-common_length:]
    if all("\u4e00" <= character <= "\u9fff" for character in common_suffix):
        return common_length >= 2 or common_suffix not in _GENERIC_SINGLE_CJK_SUFFIXES
    if common_length < 3:
        return False
    start = len(identity_text) - common_length
    return start == 0 or not identity_text[start - 1].isalnum()


def resolve_named_identity_with_anthropic(identity: str) -> tuple[dict[str, Any], str, dict[str, int]]:
    try:
        schema = anthropic_transport_schema(_read_json(NAMED_IDENTITY_SCHEMA_PATH))
        prompt = NAMED_IDENTITY_PROMPT_PATH.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_CONFIGURATION_READ_FAILED") from exc
    compiler = AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=schema,
        clarification_schema=_clarification_schema(),
        strict_blueprint_tool=True,
    )
    compiled = compiler.compile(identity)
    if compiled.get("tool_name") != BLUEPRINT_TOOL_NAME:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_MODEL_DID_NOT_RETURN_CARD")
    tool_input = compiled.get("tool_input")
    if not isinstance(tool_input, Mapping):
        raise GeneralObjectBridgeError("NAMED_IDENTITY_MODEL_TOOL_INPUT_INVALID")
    response = validate_named_identity_resolution(identity, tool_input)
    raw_usage = compiled.get("usage", {})
    usage: dict[str, int] = {}
    if isinstance(raw_usage, Mapping):
        _merge_usage(usage, raw_usage)
    return response, str(compiled.get("model_id", "")), usage


def _normalized_class_system_prompt(base_prompt: str, resolution: Mapping[str, Any]) -> str:
    if resolution.get("status") != "resolved":
        return base_prompt
    physical_class = str(resolution.get("physical_class_zh", "")).strip()
    if not physical_class:
        return base_prompt
    body_span = str(resolution.get("body_span", "unknown")).strip()
    span_clause = (
        f" The named-class resolver also locked the class-level body_span to '{body_span}'; "
        f"declaration.body_length must therefore be exactly '{body_span}'."
        if body_span in {"short", "medium", "long"}
        else " No class-level body span was locked; infer body_length from the generic physical class."
    )
    return (
        f"{base_prompt}\n\n"
        "This is an internal normalized physical-class pass after a separate constrained identity resolver. "
        "The user content in this call is the exact generic physical class, not the original proper title. "
        "Independently score confidence in the ordinary class-level structure shown in the user content; do not copy or "
        "inherit the earlier proper-name confidence. Do not reconstruct the title, lore, ornament, powers, or a named attack recipe. "
        "All normal schema, confidence, physical-consistency, and fail-closed rules remain unchanged."
        f"{span_clause} Pixel resolution and handheld scale treatment never authorize changing that locked span."
    )


def _validate_named_body_span(
    response: Mapping[str, Any], resolution: Mapping[str, Any]
) -> None:
    body_span = str(resolution.get("body_span", "unknown")).strip()
    if body_span not in {"short", "medium", "long"}:
        return
    declaration = response.get("declaration")
    if not isinstance(declaration, Mapping) or declaration.get("body_length") != body_span:
        raise GeneralObjectBridgeError("NAMED_IDENTITY_BODY_SPAN_CONFLICT")


def _restore_named_identity(
    identity: str,
    response: Mapping[str, Any],
    resolution: Mapping[str, Any],
) -> dict[str, Any]:
    _validate_named_body_span(response, resolution)
    restored = dict(response)
    restored["requested_identity"] = identity
    restored["canonical_name"] = identity
    evidence: list[str] = []
    for item in list(resolution.get("identity_evidence", [])) + list(response.get("identity_evidence", [])):
        text = str(item).strip()
        if text and text not in evidence:
            evidence.append(text)
        if len(evidence) >= 6:
            break
    restored["identity_evidence"] = evidence
    return restored


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
    named_resolution: dict[str, Any] | None = None
    usage: dict[str, int] = {}
    for attempt in range(MAX_MODEL_CARD_ATTEMPTS):
        compile_identity = identity
        if named_resolution is not None and named_resolution.get("status") == "resolved":
            compile_identity = str(named_resolution["physical_class_zh"])
            prompt = _normalized_class_system_prompt(base_prompt, named_resolution)
            if previous_error:
                prompt = _repair_system_prompt(prompt, previous_error)
        else:
            prompt = base_prompt if not previous_error else _repair_system_prompt(base_prompt, previous_error)
        compiler = AnthropicSemanticCompiler(
            system_prompt=prompt,
            blueprint_schema=schema,
            clarification_schema=_clarification_schema(),
            strict_blueprint_tool=True,
        )
        compiled = compiler.compile(compile_identity)
        raw_usage = compiled.get("usage", {})
        if isinstance(raw_usage, Mapping):
            _merge_usage(usage, raw_usage)
        try:
            if compiled.get("tool_name") != BLUEPRINT_TOOL_NAME:
                raise GeneralObjectBridgeError("MODEL_DID_NOT_RETURN_OBJECT_CARD")
            tool_input = compiled.get("tool_input")
            if not isinstance(tool_input, Mapping):
                raise GeneralObjectBridgeError("MODEL_TOOL_INPUT_INVALID")
            response = validate_response(compile_identity, tool_input)
            if compile_identity != identity:
                if named_resolution is None:
                    raise GeneralObjectBridgeError("NAMED_IDENTITY_STATE_INVALID")
                response = _restore_named_identity(identity, response, named_resolution)
            return response, str(compiled.get("model_id", "")), usage
        except GeneralObjectBridgeError as exc:
            # Identity substitution is a security boundary, not a repair hint.
            # All other model-card shape/axis failures get one bounded automatic
            # regeneration before the bridge fails closed.
            error_code = exc.code
            if (
                error_code == "CONFIDENCE_TOO_LOW"
                and named_resolution is not None
                and compile_identity != identity
            ):
                error_code = "NORMALIZED_CLASS_CONFIDENCE_TOO_LOW"
            if error_code == "IDENTITY_ECHO_MISMATCH" or attempt + 1 >= MAX_MODEL_CARD_ATTEMPTS:
                if error_code == exc.code:
                    raise
                raise GeneralObjectBridgeError(error_code) from exc
            if error_code == "CONFIDENCE_TOO_LOW":
                named_resolution = None
                for _ in range(MAX_NAMED_IDENTITY_ATTEMPTS):
                    try:
                        resolution, _, resolution_usage = resolve_named_identity_with_anthropic(identity)
                        _merge_usage(usage, resolution_usage)
                        if resolution.get("status") == "resolved":
                            named_resolution = resolution
                            break
                    except (GeneralObjectBridgeError, SemanticCompilerError):
                        continue
            previous_error = error_code
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
