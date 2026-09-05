#!/usr/bin/env python3
"""Select an object identity for a missing capability; never author mechanics."""

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
from firearm_identity_ai_bridge import anthropic_transport_schema


PLAYLAB_ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = (
    PLAYLAB_ROOT / "data" / "combat_feel" / "automatic_armory_candidate_schema_v2.json"
)
PROMPT_PATH = (
    PLAYLAB_ROOT / "data" / "combat_feel" / "automatic_armory_candidate_prompt_v2.txt"
)
REQUEST_SCHEMA = "forge-automatic-armory-candidate-request-v2"
RESPONSE_SCHEMA = "forge-automatic-armory-candidate-v2"
RESULT_SCHEMA = "forge-automatic-armory-candidate-bridge-result-v2"
ROLES = frozenset(
    {"control", "defense", "area", "reach", "breach", "mobility"}
)
MIN_CONFIDENCE = 0.75
MAX_IDENTITIES = 64


class AutomaticArmoryCandidateError(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AutomaticArmoryCandidateError("INVALID_JSON_INPUT") from exc
    if not isinstance(value, dict):
        raise AutomaticArmoryCandidateError("JSON_INPUT_MUST_BE_OBJECT")
    return value


def _normalize(value: str) -> str:
    result = value.strip().casefold()
    for separator in (" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")", "&"):
        result = result.replace(separator, "")
    return result


def _identity_list(value: Any, code: str) -> list[str]:
    if not isinstance(value, list) or len(value) > MAX_IDENTITIES:
        raise AutomaticArmoryCandidateError(code)
    result: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise AutomaticArmoryCandidateError(code)
        text = item.strip()
        if not text or len(text) > 80:
            raise AutomaticArmoryCandidateError(code)
        if _normalize(text) not in {_normalize(existing) for existing in result}:
            result.append(text)
    return result


def read_request(path: Path) -> dict[str, Any]:
    request = _read_json(path)
    if set(request) != {
        "schema", "target_role", "existing_identities", "excluded_identities"
    } or request.get("schema") != REQUEST_SCHEMA:
        raise AutomaticArmoryCandidateError("REQUEST_SCHEMA_INVALID")
    role = request.get("target_role")
    if not isinstance(role, str) or role not in ROLES:
        raise AutomaticArmoryCandidateError("TARGET_ROLE_INVALID")
    return {
        "target_role": role,
        "existing_identities": _identity_list(
            request.get("existing_identities"), "EXISTING_IDENTITIES_INVALID"
        ),
        "excluded_identities": _identity_list(
            request.get("excluded_identities"), "EXCLUDED_IDENTITIES_INVALID"
        ),
    }


def _required_text(value: Any, minimum: int, maximum: int, code: str) -> str:
    if not isinstance(value, str):
        raise AutomaticArmoryCandidateError(code)
    text = value.strip()
    if len(text) < minimum or len(text) > maximum:
        raise AutomaticArmoryCandidateError(code)
    return text


def validate_candidate(request: Mapping[str, Any], payload: Mapping[str, Any]) -> dict[str, Any]:
    required = {
        "schema", "target_role", "canonical_name", "common_alias",
        "selection_reason_zh", "confidence",
    }
    if set(payload) != required or payload.get("schema") != RESPONSE_SCHEMA:
        raise AutomaticArmoryCandidateError("RESPONSE_SCHEMA_INVALID")
    role = payload.get("target_role")
    if role != request.get("target_role"):
        raise AutomaticArmoryCandidateError("TARGET_ROLE_ECHO_MISMATCH")
    canonical_name = _required_text(
        payload.get("canonical_name"), 2, 80, "CANONICAL_NAME_INVALID"
    )
    common_alias = _required_text(
        payload.get("common_alias"), 2, 80, "COMMON_ALIAS_INVALID"
    )
    reason = _required_text(
        payload.get("selection_reason_zh"), 8, 180, "SELECTION_REASON_INVALID"
    )
    confidence = payload.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        raise AutomaticArmoryCandidateError("CONFIDENCE_INVALID")
    confidence = float(confidence)
    if not MIN_CONFIDENCE <= confidence <= 1.0:
        raise AutomaticArmoryCandidateError("CONFIDENCE_TOO_LOW")
    forbidden = {
        _normalize(str(item))
        for key in ("existing_identities", "excluded_identities")
        for item in request.get(key, [])
    }
    if _normalize(canonical_name) in forbidden or _normalize(common_alias) in forbidden:
        raise AutomaticArmoryCandidateError("DUPLICATE_IDENTITY")
    generic_names = {
        "gun", "firearm", "pistol", "revolver", "rifle", "shotgun", "smg",
        "submachinegun", "machinegun", "枪", "手枪", "步枪", "霰弹枪", "冲锋枪",
        "weapon", "object", "item", "tool", "武器", "物品", "东西", "工具",
    }
    if _normalize(canonical_name) in generic_names:
        raise AutomaticArmoryCandidateError("GENERIC_IDENTITY_FORBIDDEN")
    return {
        "schema": RESPONSE_SCHEMA,
        "target_role": str(role),
        "canonical_name": canonical_name,
        "common_alias": common_alias,
        "selection_reason_zh": reason,
        "confidence": confidence,
    }


def _clarification_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["reason"],
        "properties": {"reason": {"type": "string", "enum": ["selection_unavailable"]}},
    }


def resolve_with_anthropic(request: Mapping[str, Any]) -> tuple[dict[str, Any], str, dict[str, int]]:
    try:
        prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise AutomaticArmoryCandidateError("PROMPT_READ_FAILED") from exc
    schema = anthropic_transport_schema(_read_json(SCHEMA_PATH))
    compiler = AnthropicSemanticCompiler(
        system_prompt=prompt,
        blueprint_schema=schema,
        clarification_schema=_clarification_schema(),
        strict_blueprint_tool=True,
    )
    compiled = compiler.compile(json.dumps(dict(request), ensure_ascii=False, sort_keys=True))
    if compiled.get("tool_name") != BLUEPRINT_TOOL_NAME:
        raise AutomaticArmoryCandidateError("MODEL_DID_NOT_RETURN_CANDIDATE")
    tool_input = compiled.get("tool_input")
    if not isinstance(tool_input, Mapping):
        raise AutomaticArmoryCandidateError("MODEL_TOOL_INPUT_INVALID")
    return (
        validate_candidate(request, tool_input),
        str(compiled.get("model_id", "")),
        dict(compiled.get("usage", {})),
    )


def _atomic_write(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def _failure(code: str) -> dict[str, Any]:
    return {
        "schema": RESULT_SCHEMA,
        "status": "failed",
        "failure_reason": f"AUTOMATIC_ARMORY_CANDIDATE_{code}",
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
        request = read_request(args.request.resolve())
        if args.offline_fixture is not None:
            candidate = validate_candidate(request, _read_json(args.offline_fixture.resolve()))
            provider = "offline-fixture"
            model_id = "offline-fixture"
            usage: Mapping[str, Any] = {"input_tokens": 0, "output_tokens": 0}
            source = "AI_TEST_FIXTURE_AUTOMATIC_ARMORY_CANDIDATE_V2"
        else:
            candidate, model_id, usage = resolve_with_anthropic(request)
            provider = "anthropic"
            source = "AI_ANTHROPIC_AUTOMATIC_ARMORY_CANDIDATE_V2"
        record = {
            "schema": RESULT_SCHEMA,
            "status": "success",
            "source": source,
            "provider": provider,
            "model_id": model_id,
            "usage": dict(usage),
            "candidate": candidate,
            "player_confirmation_required": False,
        }
        exit_code = 0
    except AutomaticArmoryCandidateError as exc:
        record = _failure(exc.code)
    except SemanticCompilerError as exc:
        record = _failure(exc.code)
    except Exception:
        record = _failure("UNEXPECTED_FAILURE")
    _atomic_write(output_path, record)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
