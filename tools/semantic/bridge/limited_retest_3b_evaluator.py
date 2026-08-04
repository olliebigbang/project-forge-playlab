#!/usr/bin/env python3
"""Offline-only evaluator for the six-case Semantic Contract v1.1 retest.

Expected labels are evaluator data.  This module is never imported by the
Anthropic request builder and performs no network I/O.  It validates the exact
tool input again through the live v1.1 contract and never repairs, unwraps,
coerces, or defaults model output.
"""

from __future__ import annotations

import copy
import json
import re
import unicodedata
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from anthropic_semantic_compiler import (
    ALLOWED_TOOL_NAMES,
    ANTHROPIC_MESSAGES_URL,
    BLUEPRINT_TOOL_NAME,
    CLARIFICATION_TOOL_NAME,
)
from semantic_contract import (
    CLARIFICATION_REQUEST_SCHEMA,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    ContractValidationError,
    validate_tool_input,
)


EXPECTED_VERSION = "forge-semantic-limited-retest-3b-expected-v1"
CASE_ORDER = ("10", "13", "17", "18", "04", "01")
COMPILED_CASES = frozenset({"10", "13", "04", "01"})
CLARIFICATION_CASES = frozenset({"17", "18"})

_FIXED_ENGLISH = (
    "gatling gun",
    "gatling",
    "machine gun",
    "machinegun",
    "minigun",
    "mini gun",
    "firearm",
    "rifle",
    "pistol",
    "cannon",
    "autocannon",
    "auto cannon",
    "chainsaw",
    "chain saw",
    "greatsword",
    "great sword",
    "claymore",
    "sword",
    "umbrella",
    "parasol",
    "brolly",
    "gun",
)
_FIXED_CHINESE = (
    "加特林",
    "机关枪",
    "机枪",
    "手枪",
    "步枪",
    "火炮",
    "大炮",
    "大剑",
    "巨剑",
    "阔剑",
    "链锯",
    "电锯",
    "雨伞",
)
_PART_EFFECT_WORDS = frozenset(
    {
        "electric",
        "electricity",
        "emitter",
        "fire",
        "flame",
        "forge",
        "frost",
        "ice",
        "lifesteal",
        "lightning",
        "mist",
        "projectile",
        "return",
        "returning",
        "rune",
        "shockwave",
        "sound",
        "steam",
    }
)
_PART_EFFECT_CJK = re.compile(
    r"吸血|电流|闪电|带电|火焰|喷火|冰雾|冰霜|蒸汽|回旋|返回|发射|射弹|符文|锻造夹具|发射器|音波|冲击波"
)


class LimitedRetestEvaluationError(ValueError):
    """Fail-closed error for malformed local evidence or evaluator labels."""


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise LimitedRetestEvaluationError(f"cannot read JSON object: {path}") from exc
    if not isinstance(value, dict):
        raise LimitedRetestEvaluationError(f"expected JSON object: {path}")
    return value


def load_expected(path: str | Path) -> dict[str, dict[str, Any]]:
    document = _read_json_object(Path(path))
    if set(document) != {"contract_version", "case_order", "cases"}:
        raise LimitedRetestEvaluationError("unexpected keys in 3B expected labels")
    if document["contract_version"] != EXPECTED_VERSION:
        raise LimitedRetestEvaluationError("unsupported 3B expected-label version")
    if document["case_order"] != list(CASE_ORDER):
        raise LimitedRetestEvaluationError("3B expected case order differs from approval")
    cases = document["cases"]
    if not isinstance(cases, dict) or tuple(cases) != CASE_ORDER:
        raise LimitedRetestEvaluationError("3B expected cases must use approved order")
    for case_id, item in cases.items():
        if not isinstance(item, dict):
            raise LimitedRetestEvaluationError(f"3B expected case {case_id} is invalid")
        expected_type = (
            "compiled" if case_id in COMPILED_CASES else "needs_clarification"
        )
        if item.get("result_type") != expected_type:
            raise LimitedRetestEvaluationError(
                f"3B expected case {case_id} has wrong result_type"
            )
    return cases


def _normalise(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = re.sub(r"[_\-]+", " ", value)
    value = re.sub(r"[^a-z0-9\u3400-\u9fff]+", " ", value)
    return " ".join(value.split())


def _compact(value: str) -> str:
    return _normalise(value).replace(" ", "")


def _canonical_equal(value: Any, aliases: Iterable[Any]) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    actual = _normalise(value)
    actual = re.sub(r"^(?:a|an|the)\s+", "", actual)
    for raw_alias in aliases:
        if not isinstance(raw_alias, str):
            continue
        alias = re.sub(r"^(?:a|an|the)\s+", "", _normalise(raw_alias))
        if actual == alias:
            return True
    return False


def _phrase_occurs(text: str, phrase: str) -> bool:
    normal_text = _normalise(text)
    normal_phrase = _normalise(phrase)
    if not normal_phrase:
        return False
    if re.search(r"[\u3400-\u9fff]", normal_phrase):
        return normal_phrase.replace(" ", "") in normal_text.replace(" ", "")
    return (
        re.search(
            r"(?<![a-z0-9])" + re.escape(normal_phrase) + r"(?![a-z0-9])",
            normal_text,
        )
        is not None
    )


def _contains_any(text: str, aliases: Iterable[Any]) -> bool:
    return any(
        isinstance(alias, str) and _phrase_occurs(text, alias) for alias in aliases
    )


def _positive_strings(result: Mapping[str, Any]) -> list[str]:
    values: list[str] = []
    identity = result.get("identity")
    if isinstance(identity, Mapping):
        for field in (
            "canonical_name_zh",
            "canonical_name_en",
            "display_name_zh",
            "display_name_en",
        ):
            value = identity.get(field)
            if isinstance(value, str):
                values.append(value)
        for field in (
            "required_identity_parts",
            "material_hints",
            "silhouette_hints",
            "optional_decorations",
        ):
            value = identity.get(field)
            if isinstance(value, list):
                values.extend(item for item in value if isinstance(item, str))
    visual = result.get("visual")
    if isinstance(visual, Mapping):
        prompt = visual.get("prompt_en")
        if isinstance(prompt, str):
            values.append(prompt)
        must_preserve = visual.get("must_preserve")
        if isinstance(must_preserve, list):
            values.extend(item for item in must_preserve if isinstance(item, str))
    return values


def _fixed_substitutions(result: Any) -> list[str]:
    if not isinstance(result, Mapping):
        return []
    corpus = "\n".join(_positive_strings(result))
    found = [term for term in _FIXED_ENGLISH if _phrase_occurs(corpus, term)]
    compact = _compact(corpus)
    found.extend(term for term in _FIXED_CHINESE if term in compact)
    return sorted(set(found))


def _part_is_effect_polluted(value: str) -> bool:
    words = set(re.findall(r"[a-z0-9]+", _normalise(value)))
    return bool(words.intersection(_PART_EFFECT_WORDS) or _PART_EFFECT_CJK.search(value))


def _concept_matches(candidate: Any, aliases: Sequence[Any]) -> bool:
    if not isinstance(candidate, str) or not candidate.strip():
        return False
    if _part_is_effect_polluted(candidate):
        return False
    return _contains_any(candidate, aliases)


def _feature_quality(
    result: Mapping[str, Any], expected: Mapping[str, Any], *, eligible: bool
) -> tuple[int, list[str], list[str]]:
    identity = result.get("identity")
    visual = result.get("visual")
    if not eligible or not isinstance(identity, Mapping) or not isinstance(visual, Mapping):
        names = [
            str(item.get("name"))
            for item in expected.get("required_concepts", [])
            if isinstance(item, Mapping)
        ]
        return 0, [], names
    parts = identity.get("required_identity_parts")
    preserved = visual.get("must_preserve")
    if not isinstance(parts, list) or not isinstance(preserved, list):
        return 0, [], ["required_identity_parts or must_preserve missing"]
    approved_concepts = [
        concept
        for concept in (
            list(expected.get("required_concepts", []))
            + list(expected.get("allowed_additional_parts", []))
        )
        if isinstance(concept, Mapping) and isinstance(concept.get("aliases"), list)
    ]
    invalid_parts = [
        part
        for part in parts
        if not any(
            _concept_matches(part, concept["aliases"])
            for concept in approved_concepts
        )
    ]
    matched: list[str] = []
    missing: list[str] = []
    for concept in expected.get("required_concepts", []):
        if not isinstance(concept, Mapping):
            missing.append("invalid expected concept")
            continue
        name = str(concept.get("name", "unnamed"))
        aliases = concept.get("aliases")
        if not isinstance(aliases, list):
            missing.append(name)
            continue
        in_parts = any(_concept_matches(candidate, aliases) for candidate in parts)
        in_visual = any(_concept_matches(candidate, aliases) for candidate in preserved)
        if in_parts and in_visual:
            matched.append(name)
        else:
            missing.append(name)
    if invalid_parts:
        missing.extend(f"invalid_required_part:{part}" for part in invalid_parts)
    if not matched:
        return 0, matched, missing
    return (2 if not missing else 1), matched, missing


def _validation_flags(tool_name: Any, tool_input: Any) -> tuple[bool, bool, str, list[str]]:
    if tool_name not in ALLOWED_TOOL_NAMES or not isinstance(tool_input, dict):
        return False, False, "transport_or_parser", ["tool input unavailable"]
    snapshot = copy.deepcopy(tool_input)
    try:
        returned = validate_tool_input(str(tool_name), tool_input)
    except ContractValidationError as exc:
        if tool_input != snapshot:
            raise LimitedRetestEvaluationError("live validator mutated rejected input")
        schema_valid = exc.stage in {"cross_field"}
        cross_valid = False if exc.stage == "cross_field" else False
        return (
            schema_valid,
            cross_valid,
            exc.stage,
            [f"{issue.json_pointer}: {issue.message}" for issue in exc.issues],
        )
    if returned is not tool_input or tool_input != snapshot:
        raise LimitedRetestEvaluationError("live validator repaired or replaced tool input")
    return True, True, "complete", []


def _root_keys(tool_name: Any, tool_input: Any) -> tuple[list[str], list[str], list[str]]:
    if not isinstance(tool_input, dict):
        return [], [], []
    if tool_name == BLUEPRINT_TOOL_NAME:
        expected = set(FORGE_SEMANTIC_BLUEPRINT_SCHEMA["properties"])
    elif tool_name == CLARIFICATION_TOOL_NAME:
        expected = set(CLARIFICATION_REQUEST_SCHEMA["properties"])
    else:
        return sorted(str(key) for key in tool_input), [], []
    actual = {str(key) for key in tool_input}
    return sorted(actual), sorted(actual - expected), sorted(expected - actual)


def _identity_correct(result: Any, expected: Mapping[str, Any]) -> tuple[bool, str]:
    if not isinstance(result, Mapping) or not isinstance(result.get("identity"), Mapping):
        return False, "identity missing"
    identity = result["identity"]
    zh_ok = _canonical_equal(
        identity.get("canonical_name_zh"), expected.get("canonical_name_zh_aliases", [])
    )
    en_ok = _canonical_equal(
        identity.get("canonical_name_en"), expected.get("canonical_name_en_aliases", [])
    )
    display_zh = identity.get("display_name_zh")
    display_en = identity.get("display_name_en")
    display_ok = (
        isinstance(display_zh, str)
        and _contains_any(display_zh, expected.get("display_identity_zh", []))
        and isinstance(display_en, str)
        and _contains_any(display_en, expected.get("display_identity_en", []))
    )
    category_ok = identity.get("category") in expected.get("category_values", [])
    return (
        zh_ok and en_ok and display_ok and category_ok,
        f"canonical_zh={zh_ok}, canonical_en={en_ok}, display_identity={display_ok}, category={category_ok}",
    )


def _behavior_correct(result: Any, expected: Mapping[str, Any]) -> tuple[bool, str]:
    if not isinstance(result, Mapping) or not isinstance(result.get("combat"), Mapping):
        return False, "combat missing"
    combat = result["combat"]
    family = combat.get("behavior_family")
    effect = combat.get("effect_type")
    correct = family == expected.get("behavior_family") and effect == expected.get("effect_type")
    return correct, f"family={family!r}, effect={effect!r}"


def _hints_corpus(value: Any) -> str:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        return ""
    return " ".join(value)


def _identity_question(question: str) -> bool:
    compact = _compact(question)
    return bool(
        re.search(
            r"(?:是什么|叫什么|哪种物件|哪一种物件|哪个物件|什么物件|哪种物品|哪一种物品|什么物品|什么东西|是什么东西|哪一类|哪种类别|具体名称|物件身份|物体身份|它的身份)",
            compact,
        )
    )


def _secondary_question_focus(question: str) -> bool:
    return bool(
        re.search(
            r"多快|速度.{0,10}(?:吗|呢|多少|多快|如何|怎样|怎么|应该)"
            r"|快(?:速)?(?:近战|远程)?吗"
            r"|什么颜色|哪种颜色|颜色.{0,10}(?:吗|呢|要|应该|什么|哪)"
            r"|伤害.{0,10}(?:高|大|多少|吗|呢|哪个|哪种)"
            r"|哪个.{0,8}伤害|什么效果|哪种效果|效果.{0,8}(?:吗|呢|什么|哪)",
            question,
        )
    )


def _continuous_fire_evidence(text: str) -> bool:
    normal = _normalise(text)
    compact = normal.replace(" ", "")
    cjk = any(term in compact for term in ("持续", "一直", "不断", "连续")) and any(
        term in compact
        for term in ("喷火", "喷出火", "释放火", "发出火", "放出火", "喷射火")
    )
    english = (
        any(word in normal.split() for word in ("continuous", "continuously", "held"))
        and any(word in normal.split() for word in ("fire", "flame", "spray", "emit", "emission"))
    )
    return cjk or english


def _returning_throw_evidence(text: str) -> bool:
    normal = _normalise(text)
    compact = normal.replace(" ", "")
    cjk = any(
        term in compact for term in ("飞出", "飞出去", "扔出", "投出", "投掷", "抛出")
    ) and any(term in compact for term in ("回来", "返回", "飞回", "回手"))
    words = set(normal.split())
    english = bool(words.intersection({"fly", "flies", "throw", "thrown", "toss", "tossed", "launch", "launched"})) and bool(
        words.intersection({"return", "returns", "returned", "back"})
    )
    return cjk or english


def _speed_evidence(text: str) -> bool:
    normal = _normalise(text)
    compact = normal.replace(" ", "")
    return any(term in compact for term in ("非常快", "速度很快", "很快", "快速", "高速")) or bool(
        set(normal.split()).intersection({"fast", "rapid", "quick", "speed"})
    )


def _clarification_correct(
    result: Any, expected: Mapping[str, Any]
) -> tuple[bool, str]:
    if not isinstance(result, Mapping):
        return False, "clarification input missing"
    ambiguity_ok = result.get("ambiguity_type") == expected.get("ambiguity_type")
    identity_hint = result.get("known_identity_hint")
    if "known_identity_hint_aliases" in expected:
        identity_hint_ok = isinstance(identity_hint, str) and any(
            _normalise(identity_hint) == _normalise(alias)
            for alias in expected.get("known_identity_hint_aliases", [])
            if isinstance(alias, str)
        )
    else:
        identity_hint_ok = identity_hint == expected.get("known_identity_hint")
    hints = result.get("known_action_hints")
    array_ok = isinstance(hints, list) and all(
        isinstance(item, str) and bool(item.strip()) for item in hints
    )
    hint_corpus = _hints_corpus(hints)
    question = result.get("question_zh")
    if not isinstance(question, str):
        return False, "question_zh missing"
    identity_focus = _identity_question(question)
    secondary_focus = _secondary_question_focus(question)
    if expected.get("question_focus") == "identity":
        focus_ok = identity_focus and not (
            _continuous_fire_evidence(question) or _returning_throw_evidence(question)
        ) and not secondary_focus
        evidence_ok = _speed_evidence(hint_corpus)
        hints_faithful = array_ok and all(
            _speed_evidence(item)
            and not re.search(
                r"近战|远程|投掷|返回|喷火|发射|melee|ranged|throw|return|fire",
                item,
                re.I,
            )
            for item in hints
        )
    else:
        connector = any(term in question for term in ("还是", "或是", "或者"))
        focus_ok = (
            not identity_focus
            and connector
            and _continuous_fire_evidence(question)
            and _returning_throw_evidence(question)
            and not secondary_focus
        )
        evidence_ok = _continuous_fire_evidence(hint_corpus) and _returning_throw_evidence(
            hint_corpus
        )
        hints_faithful = array_ok and all(
            _continuous_fire_evidence(item) or _returning_throw_evidence(item)
            for item in hints
        )
    correct = ambiguity_ok and identity_hint_ok and array_ok and focus_ok and evidence_ok and hints_faithful
    return (
        correct,
        "ambiguity=%s, identity_hint=%s, hints_array=%s, focus=%s, evidence=%s, hints_faithful=%s"
        % (ambiguity_ok, identity_hint_ok, array_ok, focus_ok, evidence_ok, hints_faithful),
    )


def evaluate_case(record: Any, expected: Mapping[str, Any]) -> dict[str, Any]:
    case_id = str(expected.get("case_id", ""))
    if not isinstance(record, Mapping):
        return {
            "case_id": case_id,
            "api_success": False,
            "exactly_one_legal_tool_use": False,
            "schema_valid": False,
            "cross_field_valid": False,
            "clarification_correct": False,
            "identity_correct": False,
            "behavior_correct": False,
            "required_identity_parts_quality": 0,
            "fixed_weapon_substitution": False,
            "automatic_retry_count": 0,
            "extra_root_wrapper": False,
            "reviewer_reason": "result record missing",
            "matched_features": [],
            "missing_features": [],
        }

    tool_name = record.get("tool_name")
    tool_input = record.get("tool_input_received")
    schema_valid, cross_valid, validation_stage, issues = _validation_flags(
        tool_name, tool_input
    )
    root_keys, extra_keys, missing_keys = _root_keys(tool_name, tool_input)
    attestation = record.get("response_attestation")
    one_tool = bool(
        isinstance(attestation, Mapping)
        and attestation.get("exactly_one_legal_tool_use") is True
        and attestation.get("sole_content_is_tool_use") is True
        and attestation.get("stop_reason_is_tool_use") is True
        and tool_name in ALLOWED_TOOL_NAMES
    )
    api_success = bool(
        record.get("api_status") == 200
        and record.get("provider") == "anthropic"
        and record.get("endpoint") == ANTHROPIC_MESSAGES_URL
        and record.get("api_request_performed") is True
        and record.get("ai_interpretation_used") is True
    )
    envelope_valid = bool(
        isinstance(record.get("model_id"), str)
        and record.get("response_model_id") == record.get("model_id")
        and isinstance(record.get("request_id"), str)
        and bool(record.get("request_id"))
        and record.get("case_id") == case_id
    )
    result = tool_input if schema_valid and cross_valid else None
    substitutions = _fixed_substitutions(result)
    result_type = "compiled" if tool_name == BLUEPRINT_TOOL_NAME else "needs_clarification" if tool_name == CLARIFICATION_TOOL_NAME else "failed"

    identity_correct = False
    behavior_correct = False
    clarification_correct = False
    identity_reason = "not a compiled case"
    behavior_reason = "not a compiled case"
    clarification_reason = "not a clarification case"
    quality = 0
    matched: list[str] = []
    missing: list[str] = []

    eligible = api_success and envelope_valid and one_tool and schema_valid and cross_valid and not extra_keys and not missing_keys
    if expected.get("result_type") == "compiled":
        correct_tool = result_type == "compiled"
        if eligible and correct_tool and isinstance(result, Mapping):
            identity_correct, identity_reason = _identity_correct(result, expected)
            behavior_correct, behavior_reason = _behavior_correct(result, expected)
            if substitutions:
                identity_correct = False
                identity_reason += ", fixed substitution present"
            quality, matched, missing = _feature_quality(
                result,
                expected,
                eligible=identity_correct and not substitutions,
            )
        else:
            missing = [
                str(item.get("name"))
                for item in expected.get("required_concepts", [])
                if isinstance(item, Mapping)
            ]
    else:
        correct_tool = result_type == "needs_clarification"
        if eligible and correct_tool:
            clarification_correct, clarification_reason = _clarification_correct(
                result, expected
            )

    retry = record.get("retry_count")
    retry_count = retry if isinstance(retry, int) and not isinstance(retry, bool) and retry >= 0 else 1
    reasons = [
        f"api_success={api_success}",
        f"envelope_valid={envelope_valid}",
        f"one_tool={one_tool}",
        f"validation={validation_stage}",
        f"root_keys={root_keys}",
    ]
    if issues:
        reasons.append("issues=" + " | ".join(issues))
    if extra_keys:
        reasons.append("extra_root_keys=" + ",".join(extra_keys))
    if missing_keys:
        reasons.append("missing_root_keys=" + ",".join(missing_keys))
    if expected.get("result_type") == "compiled":
        reasons.extend(
            [
                "identity=" + identity_reason,
                "behavior=" + behavior_reason,
                f"parts_quality={quality}",
            ]
        )
    else:
        reasons.append("clarification=" + clarification_reason)
    if substitutions:
        reasons.append("fixed_substitutions=" + ",".join(substitutions))

    return {
        "case_id": case_id,
        "api_success": api_success,
        "exactly_one_legal_tool_use": one_tool,
        "schema_valid": schema_valid,
        "cross_field_valid": cross_valid,
        "clarification_correct": clarification_correct,
        "identity_correct": identity_correct,
        "behavior_correct": behavior_correct,
        "required_identity_parts_quality": quality,
        "fixed_weapon_substitution": bool(substitutions),
        "automatic_retry_count": retry_count,
        "extra_root_wrapper": bool(extra_keys),
        "reviewer_reason": "; ".join(reasons),
        "matched_features": matched,
        "missing_features": missing,
        "elapsed_ms": record.get("elapsed_ms"),
        "input_tokens": record.get("input_tokens"),
        "output_tokens": record.get("output_tokens"),
    }


def evaluate_run(
    output_run_directory: str | Path, expected_path: str | Path
) -> list[dict[str, Any]]:
    run_root = Path(output_run_directory).resolve()
    if ".tmp" in run_root.parts or not run_root.is_dir():
        raise LimitedRetestEvaluationError("3B evaluator requires one final run directory")
    expected_by_id = load_expected(expected_path)
    scores: list[dict[str, Any]] = []
    for case_id in CASE_ORDER:
        expected = dict(expected_by_id[case_id])
        expected["case_id"] = case_id
        result_path = run_root / case_id / "result.json"
        record = _read_json_object(result_path) if result_path.is_file() else None
        scores.append(evaluate_case(record, expected))
    return scores


def aggregate(scores: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    if [str(score.get("case_id")) for score in scores] != list(CASE_ORDER):
        raise LimitedRetestEvaluationError("3B scores are missing or out of order")
    compiled = [score for score in scores if score["case_id"] in COMPILED_CASES]
    clarifications = [score for score in scores if score["case_id"] in CLARIFICATION_CASES]
    metrics = {
        "api_success_count": sum(score.get("api_success") is True for score in scores),
        "exactly_one_legal_tool_use_count": sum(
            score.get("exactly_one_legal_tool_use") is True for score in scores
        ),
        "schema_and_cross_field_valid_count": sum(
            score.get("schema_valid") is True and score.get("cross_field_valid") is True
            for score in scores
        ),
        "clarification_correct_count": sum(
            score.get("clarification_correct") is True for score in clarifications
        ),
        "compiled_identity_correct_count": sum(
            score.get("identity_correct") is True for score in compiled
        ),
        "compiled_behavior_correct_count": sum(
            score.get("behavior_correct") is True for score in compiled
        ),
        "required_identity_parts_quality_2_count": sum(
            score.get("required_identity_parts_quality") == 2 for score in compiled
        ),
        "fixed_weapon_substitution_count": sum(
            score.get("fixed_weapon_substitution") is True for score in scores
        ),
        "automatic_retry_count": sum(
            int(score.get("automatic_retry_count", 0)) for score in scores
        ),
        "extra_root_wrapper_count": sum(
            score.get("extra_root_wrapper") is True for score in scores
        ),
    }
    thresholds = {
        "api_success_count": 6,
        "exactly_one_legal_tool_use_count": 6,
        "schema_and_cross_field_valid_count": 6,
        "clarification_correct_count": 2,
        "compiled_identity_correct_count": 4,
        "compiled_behavior_correct_count": 4,
        "required_identity_parts_quality_2_count": 4,
        "fixed_weapon_substitution_count": 0,
        "automatic_retry_count": 0,
        "extra_root_wrapper_count": 0,
    }
    metrics["thresholds"] = thresholds
    metrics["semantic_thresholds_passed"] = all(
        metrics[name] == expected for name, expected in thresholds.items()
    )
    return metrics


__all__ = [
    "CASE_ORDER",
    "CLARIFICATION_CASES",
    "COMPILED_CASES",
    "EXPECTED_VERSION",
    "LimitedRetestEvaluationError",
    "aggregate",
    "evaluate_case",
    "evaluate_run",
    "load_expected",
]
