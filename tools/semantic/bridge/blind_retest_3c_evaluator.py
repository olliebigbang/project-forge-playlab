#!/usr/bin/env python3
"""Offline evaluator for Forge Semantic Blind Retest 3C.

The four player inputs and all evaluator-only labels are pre-frozen JSON files.
Nothing in this module builds a provider prompt or performs network I/O.  Base
identity and behavior family are scored automatically.  Open-language
structural evidence is deliberately handed to a separately bound human review
whose quotes must come verbatim from the model's two structural arrays.
"""

from __future__ import annotations

import copy
import hashlib
import json
import re
import unicodedata
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from anthropic_semantic_compiler import (
    ALLOWED_TOOL_NAMES,
    ANTHROPIC_MESSAGES_URL,
    BLUEPRINT_TOOL_NAME,
)
from semantic_contract import (
    CONTRACT_VERSION,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    ContractValidationError,
    validate_tool_input,
)


CASES_VERSION = "forge-semantic-blind-retest-3c-cases-v1"
EXPECTED_VERSION = "forge-semantic-blind-retest-3c-expected-v1"
REVIEW_RUBRIC_VERSION = "forge-semantic-blind-retest-3c-manual-structure-v1"
REVIEW_PACKET_VERSION = "forge-semantic-blind-retest-3c-review-packet-v1"
REVIEW_SUBMISSION_VERSION = "forge-semantic-blind-retest-3c-review-submission-v1"
FREEZE_POLICY = (
    "expected_and_review_rubric_sha256_must_be_reserved_before_any_provider_call"
)
CASE_ORDER = ("B01", "B02", "B03", "B04")

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
    "autocannon",
    "auto cannon",
    "cannon",
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


class BlindRetest3CEvaluationError(ValueError):
    """Fail-closed error for malformed 3C evidence or pre-frozen labels."""


class ManualStructureReviewError(ValueError):
    """Fail-closed error for a malformed or unbound human review."""


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BlindRetest3CEvaluationError(f"cannot read JSON object: {path}") from exc
    if not isinstance(value, dict):
        raise BlindRetest3CEvaluationError(f"expected JSON object: {path}")
    return value


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: Any, *, minimum: int = 1) -> bool:
    return (
        isinstance(value, list)
        and len(value) >= minimum
        and all(_nonempty_string(item) for item in value)
    )


def load_cases(path: str | Path) -> list[dict[str, str]]:
    """Load the exact, approved player inputs in their fixed call order."""

    document = _read_json_object(Path(path))
    if set(document) != {"contract_version", "case_order", "cases"}:
        raise BlindRetest3CEvaluationError("unexpected keys in 3C cases file")
    if document["contract_version"] != CASES_VERSION:
        raise BlindRetest3CEvaluationError("unsupported 3C cases version")
    if document["case_order"] != list(CASE_ORDER):
        raise BlindRetest3CEvaluationError("3C case order differs from approval")
    cases = document["cases"]
    if not isinstance(cases, list) or len(cases) != len(CASE_ORDER):
        raise BlindRetest3CEvaluationError("3C requires exactly four cases")
    result: list[dict[str, str]] = []
    for expected_id, item in zip(CASE_ORDER, cases):
        if not isinstance(item, dict) or set(item) != {"case_id", "input_text"}:
            raise BlindRetest3CEvaluationError(f"invalid 3C case {expected_id}")
        if item.get("case_id") != expected_id or not _nonempty_string(
            item.get("input_text")
        ):
            raise BlindRetest3CEvaluationError(f"invalid 3C case {expected_id}")
        result.append({"case_id": expected_id, "input_text": item["input_text"]})
    return result


def load_review_rubric(path: str | Path) -> dict[str, Any]:
    """Load and strictly validate the pre-call manual-review policy."""

    document = _read_json_object(Path(path))
    required = {
        "review_rubric_version",
        "case_order",
        "quality_policy",
        "review_rules",
        "concept_ids_by_case",
    }
    if set(document) != required:
        raise BlindRetest3CEvaluationError("unexpected keys in 3C review rubric")
    if document["review_rubric_version"] != REVIEW_RUBRIC_VERSION:
        raise BlindRetest3CEvaluationError("unsupported 3C review rubric version")
    if document["case_order"] != list(CASE_ORDER):
        raise BlindRetest3CEvaluationError("3C review case order differs from approval")
    policy = document["quality_policy"]
    expected_policy = {
        "quality_2_minimum_confirmed_concepts": 2,
        "quality_2_requires_all_declared_parts_structural": True,
        "quality_1_minimum_confirmed_concepts": 1,
        "quality_0_confirmed_concepts": 0,
    }
    if policy != expected_policy:
        raise BlindRetest3CEvaluationError("3C review quality policy changed")
    if not _string_list(document["review_rules"]):
        raise BlindRetest3CEvaluationError("3C review rules are missing")
    registry = document["concept_ids_by_case"]
    if not isinstance(registry, dict) or tuple(registry) != CASE_ORDER:
        raise BlindRetest3CEvaluationError("3C concept registry is missing or reordered")
    all_ids: list[str] = []
    for case_id in CASE_ORDER:
        concept_ids = registry[case_id]
        if not _string_list(concept_ids) or len(concept_ids) != 3:
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} must have exactly three concept IDs"
            )
        if len(set(concept_ids)) != len(concept_ids):
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} has duplicate concept IDs"
            )
        all_ids.extend(concept_ids)
    if len(all_ids) != 12 or len(set(all_ids)) != 12:
        raise BlindRetest3CEvaluationError(
            "3C review rubric must freeze twelve globally unique concept IDs"
        )
    return copy.deepcopy(document)


def load_expected(
    path: str | Path, review_rubric_path: str | Path | None = None
) -> dict[str, dict[str, Any]]:
    """Load evaluator-only labels and bind them to the frozen review rubric."""

    expected_path = Path(path)
    rubric_path = (
        Path(review_rubric_path)
        if review_rubric_path is not None
        else expected_path.with_name("blind_retest_3c_review_rubric.json")
    )
    rubric = load_review_rubric(rubric_path)
    document = _read_json_object(expected_path)
    required = {"contract_version", "case_order", "freeze_policy", "cases"}
    if set(document) != required:
        raise BlindRetest3CEvaluationError("unexpected keys in 3C expected labels")
    if document["contract_version"] != EXPECTED_VERSION:
        raise BlindRetest3CEvaluationError("unsupported 3C expected-label version")
    if document["case_order"] != list(CASE_ORDER):
        raise BlindRetest3CEvaluationError("3C expected case order differs from approval")
    if document["freeze_policy"] != FREEZE_POLICY:
        raise BlindRetest3CEvaluationError("3C expected-label freeze policy changed")
    cases = document["cases"]
    if not isinstance(cases, dict) or tuple(cases) != CASE_ORDER:
        raise BlindRetest3CEvaluationError("3C expected cases are missing or reordered")

    loaded: dict[str, dict[str, Any]] = {}
    registry = rubric["concept_ids_by_case"]
    for case_id in CASE_ORDER:
        item = cases[case_id]
        required_case_keys = {
            "result_type",
            "canonical_base_zh_aliases",
            "canonical_base_en_aliases",
            "behavior_family",
            "manual_structure_review",
        }
        if not isinstance(item, dict) or set(item) != required_case_keys:
            raise BlindRetest3CEvaluationError(
                f"unexpected expected-label keys for 3C case {case_id}"
            )
        if item["result_type"] != "compiled":
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} must expect a compiled result"
            )
        if not _string_list(item["canonical_base_zh_aliases"]):
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} has no Chinese base identity aliases"
            )
        if not _string_list(item["canonical_base_en_aliases"]):
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} has no English base identity aliases"
            )
        if item["behavior_family"] not in {
            "sustained_ranged",
            "returning_thrown",
            "heavy_melee",
        }:
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} has an invalid behavior family"
            )
        manual = item["manual_structure_review"]
        if not isinstance(manual, dict) or set(manual) != {"concepts"}:
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} has an invalid manual-review label"
            )
        concepts = manual["concepts"]
        if not isinstance(concepts, list) or len(concepts) != 3:
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} must freeze exactly three concepts"
            )
        ids: list[str] = []
        for concept in concepts:
            if not isinstance(concept, dict) or set(concept) != {
                "concept_id",
                "label_zh",
                "label_en",
            }:
                raise BlindRetest3CEvaluationError(
                    f"3C case {case_id} has an invalid concept"
                )
            if not all(_nonempty_string(concept[field]) for field in concept):
                raise BlindRetest3CEvaluationError(
                    f"3C case {case_id} has an empty concept field"
                )
            ids.append(concept["concept_id"])
        if ids != registry[case_id]:
            raise BlindRetest3CEvaluationError(
                f"3C case {case_id} concepts differ from frozen rubric"
            )
        copied = copy.deepcopy(item)
        copied["_review_rubric"] = {
            "review_rubric_version": rubric["review_rubric_version"],
            "quality_policy": copy.deepcopy(rubric["quality_policy"]),
            "review_rules": copy.deepcopy(rubric["review_rules"]),
        }
        loaded[case_id] = copied
    return loaded


def _normalise(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = re.sub(r"[_\-]+", " ", value)
    value = re.sub(r"[^a-z0-9\u3400-\u9fff]+", " ", value)
    return " ".join(value.split())


def _canonical_equal(value: Any, aliases: Iterable[Any]) -> bool:
    if not _nonempty_string(value):
        return False
    actual = re.sub(r"^(?:a|an|the)\s+", "", _normalise(value))
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
        preserved = visual.get("must_preserve")
        if isinstance(preserved, list):
            values.extend(item for item in preserved if isinstance(item, str))
    return values


def _fixed_substitutions(result: Any) -> list[str]:
    if not isinstance(result, Mapping):
        return []
    corpus = "\n".join(_positive_strings(result))
    found = [term for term in _FIXED_ENGLISH if _phrase_occurs(corpus, term)]
    compact = _normalise(corpus).replace(" ", "")
    found.extend(term for term in _FIXED_CHINESE if term in compact)
    return sorted(set(found))


def _sha256_json(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _validation_flags(tool_name: Any, tool_input: Any) -> tuple[bool, bool, str, list[str]]:
    if tool_name not in ALLOWED_TOOL_NAMES or not isinstance(tool_input, dict):
        return False, False, "transport_or_parser", ["tool input unavailable"]
    snapshot = copy.deepcopy(tool_input)
    try:
        returned = validate_tool_input(str(tool_name), tool_input)
    except ContractValidationError as exc:
        if tool_input != snapshot:
            raise BlindRetest3CEvaluationError("live validator mutated rejected input")
        return (
            exc.stage == "cross_field",
            False,
            exc.stage,
            [f"{issue.json_pointer}: {issue.message}" for issue in exc.issues],
        )
    if returned is not tool_input or tool_input != snapshot:
        raise BlindRetest3CEvaluationError("live validator repaired or replaced input")
    return True, True, "complete", []


def _root_keys(tool_name: Any, tool_input: Any) -> tuple[list[str], list[str], list[str]]:
    if not isinstance(tool_input, dict):
        return [], [], []
    if tool_name != BLUEPRINT_TOOL_NAME:
        return sorted(str(key) for key in tool_input), [], []
    expected = set(FORGE_SEMANTIC_BLUEPRINT_SCHEMA["properties"])
    actual = {str(key) for key in tool_input}
    return sorted(actual), sorted(actual - expected), sorted(expected - actual)


def _base_identity_correct(
    result: Any, expected: Mapping[str, Any]
) -> tuple[bool, str]:
    if not isinstance(result, Mapping) or not isinstance(result.get("identity"), Mapping):
        return False, "identity missing"
    identity = result["identity"]
    zh_ok = _canonical_equal(
        identity.get("canonical_name_zh"),
        expected.get("canonical_base_zh_aliases", []),
    )
    en_ok = _canonical_equal(
        identity.get("canonical_name_en"),
        expected.get("canonical_base_en_aliases", []),
    )
    return zh_ok and en_ok, f"canonical_base_zh={zh_ok}, canonical_base_en={en_ok}"


def _behavior_correct(result: Any, expected: Mapping[str, Any]) -> tuple[bool, str]:
    if not isinstance(result, Mapping) or not isinstance(result.get("combat"), Mapping):
        return False, "combat missing"
    combat = result["combat"]
    family = combat.get("behavior_family")
    effect = combat.get("effect_type")
    correct = family == expected.get("behavior_family")
    return correct, f"family={family!r}, observed_effect_not_scored={effect!r}"


def build_manual_structure_review_packet(
    case_id: str,
    tool_input: Any,
    expected: Mapping[str, Any],
    *,
    reviewable: bool = True,
    reason: str = "",
) -> dict[str, Any]:
    """Create a human-review packet bound to exact model strings and labels."""

    manual = expected.get("manual_structure_review")
    rubric = expected.get("_review_rubric")
    if not isinstance(manual, Mapping) or not isinstance(manual.get("concepts"), list):
        raise BlindRetest3CEvaluationError("manual-review concepts are unavailable")
    if not isinstance(rubric, Mapping):
        raise BlindRetest3CEvaluationError("manual-review rubric is not bound")
    concepts = copy.deepcopy(manual["concepts"])
    identity = tool_input.get("identity") if isinstance(tool_input, Mapping) else None
    visual = tool_input.get("visual") if isinstance(tool_input, Mapping) else None
    parts = identity.get("required_identity_parts") if isinstance(identity, Mapping) else None
    preserved = visual.get("must_preserve") if isinstance(visual, Mapping) else None
    actual_parts = copy.deepcopy(parts) if isinstance(parts, list) else []
    actual_preserved = copy.deepcopy(preserved) if isinstance(preserved, list) else []
    arrays_valid = all(
        isinstance(value, list) and all(_nonempty_string(item) for item in value)
        for value in (parts, preserved)
    )
    status = "PENDING" if reviewable and arrays_valid else "NOT_REVIEWABLE"
    unavailable_reason = "" if status == "PENDING" else (
        reason or "validated structural arrays unavailable"
    )
    policy = rubric.get("quality_policy", {})
    return {
        "review_packet_version": REVIEW_PACKET_VERSION,
        "case_id": case_id,
        "status": status,
        "tool_input_sha256": _sha256_json(tool_input) if isinstance(tool_input, Mapping) else "",
        "expected_concepts_sha256": _sha256_json(concepts),
        "expected_concepts": concepts,
        "actual_required_identity_parts": actual_parts,
        "actual_must_preserve": actual_preserved,
        "minimum_confirmed_concepts_for_quality_2": policy.get(
            "quality_2_minimum_confirmed_concepts"
        ),
        "reviewer_instructions": copy.deepcopy(rubric.get("review_rules", [])),
        "not_reviewable_reason": unavailable_reason,
    }


def _exact_quote_list(value: Any, allowed: Sequence[Any], field: str) -> list[str]:
    if not isinstance(value, list) or not all(_nonempty_string(item) for item in value):
        raise ManualStructureReviewError(f"{field} must be a list of exact non-empty quotes")
    if len(set(value)) != len(value):
        raise ManualStructureReviewError(f"{field} contains duplicate quotes")
    allowed_strings = {item for item in allowed if isinstance(item, str)}
    if any(item not in allowed_strings for item in value):
        raise ManualStructureReviewError(
            f"{field} contains text not present in the bound model output"
        )
    return list(value)


def validate_manual_structure_review_submission(
    packet: Mapping[str, Any], submission: Mapping[str, Any]
) -> dict[str, Any]:
    """Validate a human decision without performing semantic matching itself."""

    if not isinstance(packet, Mapping) or packet.get("status") != "PENDING":
        raise ManualStructureReviewError("manual review packet is not pending")
    concepts = packet.get("expected_concepts")
    if not isinstance(concepts, list) or packet.get("expected_concepts_sha256") != _sha256_json(
        concepts
    ):
        raise ManualStructureReviewError("manual review packet concepts are not intact")
    expected_ids = [
        concept.get("concept_id") if isinstance(concept, Mapping) else None
        for concept in concepts
    ]
    if len(expected_ids) != 3 or not all(_nonempty_string(item) for item in expected_ids):
        raise ManualStructureReviewError("manual review packet concept IDs are invalid")

    required_submission_keys = {
        "review_submission_version",
        "case_id",
        "tool_input_sha256",
        "expected_concepts_sha256",
        "concept_reviews",
        "all_required_parts_are_structural",
        "non_structural_required_identity_part_quotes",
        "reviewer_reason",
    }
    if not isinstance(submission, Mapping) or set(submission) != required_submission_keys:
        raise ManualStructureReviewError("manual review submission has unexpected keys")
    if submission["review_submission_version"] != REVIEW_SUBMISSION_VERSION:
        raise ManualStructureReviewError("manual review submission version differs")
    for field in ("case_id", "tool_input_sha256", "expected_concepts_sha256"):
        if submission[field] != packet.get(field):
            raise ManualStructureReviewError(f"manual review {field} is not bound to packet")
    if not isinstance(submission["all_required_parts_are_structural"], bool):
        raise ManualStructureReviewError(
            "all_required_parts_are_structural must be boolean"
        )
    if not isinstance(submission["reviewer_reason"], str):
        raise ManualStructureReviewError("reviewer_reason must be a string")

    actual_parts = packet.get("actual_required_identity_parts")
    actual_preserved = packet.get("actual_must_preserve")
    if not isinstance(actual_parts, list) or not isinstance(actual_preserved, list):
        raise ManualStructureReviewError("manual review packet evidence is invalid")
    non_structural = _exact_quote_list(
        submission["non_structural_required_identity_part_quotes"],
        actual_parts,
        "non_structural_required_identity_part_quotes",
    )
    if submission["all_required_parts_are_structural"] == bool(non_structural):
        raise ManualStructureReviewError(
            "structural-parts boolean and non-structural quotes disagree"
        )

    reviews = submission["concept_reviews"]
    if not isinstance(reviews, list):
        raise ManualStructureReviewError("concept_reviews must be an array")
    review_by_id: dict[str, Mapping[str, Any]] = {}
    required_review_keys = {
        "concept_id",
        "required_identity_part_quotes",
        "must_preserve_quotes",
        "same_structure_concept",
        "structural_not_material_or_decoration",
        "notes",
    }
    for review in reviews:
        if not isinstance(review, Mapping) or set(review) != required_review_keys:
            raise ManualStructureReviewError("concept review has unexpected keys")
        concept_id = review.get("concept_id")
        if concept_id not in expected_ids:
            raise ManualStructureReviewError(f"unknown concept_id: {concept_id!r}")
        if concept_id in review_by_id:
            raise ManualStructureReviewError(f"duplicate concept_id: {concept_id}")
        if not isinstance(review["same_structure_concept"], bool) or not isinstance(
            review["structural_not_material_or_decoration"], bool
        ):
            raise ManualStructureReviewError("concept judgments must be boolean")
        if not isinstance(review["notes"], str):
            raise ManualStructureReviewError("concept notes must be a string")
        review_by_id[str(concept_id)] = review
    missing_ids = [item for item in expected_ids if item not in review_by_id]
    if missing_ids:
        raise ManualStructureReviewError(
            "missing concept_id values: " + ", ".join(str(item) for item in missing_ids)
        )

    confirmed: list[str] = []
    used_part_quotes: set[str] = set()
    for concept_id in expected_ids:
        review = review_by_id[str(concept_id)]
        part_quotes = _exact_quote_list(
            review["required_identity_part_quotes"],
            actual_parts,
            f"{concept_id}.required_identity_part_quotes",
        )
        preserve_quotes = _exact_quote_list(
            review["must_preserve_quotes"],
            actual_preserved,
            f"{concept_id}.must_preserve_quotes",
        )
        same = review["same_structure_concept"]
        structural = review["structural_not_material_or_decoration"]
        if same and not part_quotes:
            raise ManualStructureReviewError(
                f"confirmed concept {concept_id} needs a required_identity_parts quote"
            )
        if same and structural:
            if used_part_quotes.intersection(part_quotes):
                raise ManualStructureReviewError(
                    "one model phrase cannot confirm multiple frozen concepts"
                )
            used_part_quotes.update(part_quotes)
            confirmed.append(str(concept_id))

    if used_part_quotes.intersection(non_structural):
        raise ManualStructureReviewError(
            "one required_identity_parts quote cannot be both structural and non-structural"
        )

    minimum = packet.get("minimum_confirmed_concepts_for_quality_2")
    if minimum != 2:
        raise ManualStructureReviewError("manual review quality threshold is not intact")
    all_structural = submission["all_required_parts_are_structural"]
    if len(confirmed) >= minimum and all_structural:
        quality = 2
    elif confirmed:
        quality = 1
    else:
        quality = 0
    return {
        "status": "COMPLETE",
        "case_id": packet["case_id"],
        "tool_input_sha256": packet["tool_input_sha256"],
        "expected_concepts_sha256": packet["expected_concepts_sha256"],
        "structure_quality": quality,
        "structure_correct": quality == 2,
        "confirmed_concept_count": len(confirmed),
        "confirmed_concept_ids": confirmed,
        "unconfirmed_concept_ids": [
            str(item) for item in expected_ids if item not in confirmed
        ],
        "all_required_parts_are_structural": all_structural,
        "reviewer_reason": submission["reviewer_reason"],
    }


def attach_manual_structure_review(
    score: Mapping[str, Any], submission: Mapping[str, Any]
) -> dict[str, Any]:
    """Return a copy of one automatic score with its bound human result."""

    packet = score.get("manual_structure_review_packet")
    result = validate_manual_structure_review_submission(packet, submission)
    copied = copy.deepcopy(dict(score))
    copied["manual_structure_review_result"] = result
    copied["manual_structure_review_status"] = "COMPLETE"
    return copied


def evaluate_case(record: Any, expected: Mapping[str, Any]) -> dict[str, Any]:
    """Evaluate one saved result; effect_type is diagnostic, never a 3C gate."""

    case_id = str(expected.get("case_id", ""))
    if not isinstance(record, Mapping):
        packet = build_manual_structure_review_packet(
            case_id, None, expected, reviewable=False, reason="result record missing"
        )
        return {
            "case_id": case_id,
            "api_success": False,
            "exactly_one_legal_tool_use": False,
            "schema_valid": False,
            "cross_field_valid": False,
            "envelope_valid": False,
            "base_identity_correct": False,
            "behavior_correct": False,
            "fixed_weapon_substitution": False,
            "fixed_weapon_substitution_terms": [],
            "fixed_weapon_substitution_attested": False,
            "automatic_retry_count": None,
            "retry_attested": False,
            "extra_root_wrapper": False,
            "repair_applied": None,
            "unwrap_applied": None,
            "coercion_applied": None,
            "defaults_applied": None,
            "local_transformation_free": False,
            "automatic_case_pass": False,
            "observed_effect_type": None,
            "manual_structure_review_status": packet["status"],
            "manual_structure_review_packet": packet,
            "manual_structure_review_result": None,
            "reviewer_reason": "result record missing",
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
        record.get("model_id") == "claude-sonnet-5"
        and record.get("response_model_id") == "claude-sonnet-5"
        and record.get("contract_version") == CONTRACT_VERSION
        and isinstance(record.get("request_id"), str)
        and bool(record.get("request_id"))
        and record.get("case_id") == case_id
    )
    correct_tool = tool_name == BLUEPRINT_TOOL_NAME
    eligible = bool(
        api_success
        and envelope_valid
        and one_tool
        and schema_valid
        and cross_valid
        and correct_tool
        and not extra_keys
        and not missing_keys
    )
    result = tool_input if eligible and isinstance(tool_input, Mapping) else None
    base_identity_correct, identity_reason = _base_identity_correct(result, expected)
    behavior_correct, behavior_reason = _behavior_correct(result, expected)
    # Substitution detection is diagnostic on the model's actual input even
    # when another envelope/schema gate failed. Identity and behavior credit
    # remain fail-closed behind ``eligible``.
    substitutions = _fixed_substitutions(
        tool_input if isinstance(tool_input, Mapping) else None
    )
    substitution_attested = isinstance(tool_input, Mapping)
    transform_values = {
        "repair_applied": record.get("repair_applied"),
        "unwrap_applied": record.get("unwrap_applied"),
        "coercion_applied": record.get("coercion_applied"),
        "defaults_applied": record.get("defaults_applied"),
    }
    transformation_free = all(value is False for value in transform_values.values())
    retry = record.get("retry_count")
    retry_attested = bool(
        isinstance(retry, int) and not isinstance(retry, bool) and retry >= 0
    )
    retry_count = retry if retry_attested else None
    observed_effect: Any = None
    if isinstance(result, Mapping) and isinstance(result.get("combat"), Mapping):
        observed_effect = result["combat"].get("effect_type")
    packet = build_manual_structure_review_packet(
        case_id,
        tool_input,
        expected,
        reviewable=eligible and transformation_free,
        reason="automatic contract, transport, or transformation gate failed",
    )
    automatic_pass = bool(
        eligible
        and base_identity_correct
        and behavior_correct
        and not substitutions
        and transformation_free
        and retry_attested
        and retry_count == 0
        and not extra_keys
    )
    reasons = [
        f"api_success={api_success}",
        f"envelope_valid={envelope_valid}",
        f"one_tool={one_tool}",
        f"validation={validation_stage}",
        f"root_keys={root_keys}",
        "base_identity=" + identity_reason,
        "behavior=" + behavior_reason,
        f"fixed_substitutions={substitutions}",
        f"local_transformation_free={transformation_free}",
        f"manual_review={packet['status']}",
    ]
    if issues:
        reasons.append("issues=" + " | ".join(issues))
    if extra_keys:
        reasons.append("extra_root_keys=" + ",".join(extra_keys))
    if missing_keys:
        reasons.append("missing_root_keys=" + ",".join(missing_keys))
    return {
        "case_id": case_id,
        "api_success": api_success,
        "exactly_one_legal_tool_use": one_tool,
        "schema_valid": schema_valid,
        "cross_field_valid": cross_valid,
        "envelope_valid": envelope_valid,
        "base_identity_correct": base_identity_correct,
        "behavior_correct": behavior_correct,
        "fixed_weapon_substitution": bool(substitutions),
        "fixed_weapon_substitution_terms": substitutions,
        "fixed_weapon_substitution_attested": substitution_attested,
        "automatic_retry_count": retry_count,
        "retry_attested": retry_attested,
        "extra_root_wrapper": bool(extra_keys),
        **transform_values,
        "local_transformation_free": transformation_free,
        "automatic_case_pass": automatic_pass,
        "observed_effect_type": observed_effect,
        "manual_structure_review_status": packet["status"],
        "manual_structure_review_packet": packet,
        "manual_structure_review_result": None,
        "reviewer_reason": "; ".join(reasons),
    }


def evaluate_run(
    output_run_directory: str | Path,
    expected_path: str | Path,
    review_rubric_path: str | Path | None = None,
) -> list[dict[str, Any]]:
    """Evaluate only saved 3C result files in fixed case order."""

    run_root = Path(output_run_directory).resolve()
    if ".tmp" in run_root.parts or not run_root.is_dir():
        raise BlindRetest3CEvaluationError("3C evaluator requires one final run directory")
    expected_by_id = load_expected(expected_path, review_rubric_path)
    scores: list[dict[str, Any]] = []
    for case_id in CASE_ORDER:
        expected = dict(expected_by_id[case_id])
        expected["case_id"] = case_id
        result_path = run_root / case_id / "result.json"
        record = _read_json_object(result_path) if result_path.is_file() else None
        scores.append(evaluate_case(record, expected))
    return scores


def aggregate(scores: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Aggregate automatic gates and, separately, completed human reviews."""

    if [str(score.get("case_id")) for score in scores] != list(CASE_ORDER):
        raise BlindRetest3CEvaluationError("3C scores are missing or out of order")
    automatic = {
        "api_success_count": sum(score.get("api_success") is True for score in scores),
        "exactly_one_legal_tool_use_count": sum(
            score.get("exactly_one_legal_tool_use") is True for score in scores
        ),
        "schema_and_cross_field_valid_count": sum(
            score.get("schema_valid") is True and score.get("cross_field_valid") is True
            for score in scores
        ),
        "envelope_valid_count": sum(
            score.get("envelope_valid") is True for score in scores
        ),
        "base_identity_correct_count": sum(
            score.get("base_identity_correct") is True for score in scores
        ),
        "behavior_correct_count": sum(
            score.get("behavior_correct") is True for score in scores
        ),
        "fixed_weapon_substitution_count": sum(
            score.get("fixed_weapon_substitution") is True for score in scores
        ),
        "fixed_weapon_substitution_attested_count": sum(
            score.get("fixed_weapon_substitution_attested") is True
            for score in scores
        ),
        "automatic_retry_count": sum(
            int(value)
            for score in scores
            for value in (score.get("automatic_retry_count"),)
            if isinstance(value, int) and not isinstance(value, bool) and value >= 0
        ),
        "retry_attested_count": sum(
            score.get("retry_attested") is True for score in scores
        ),
        "extra_root_wrapper_count": sum(
            score.get("extra_root_wrapper") is True for score in scores
        ),
        "repair_count": sum(score.get("repair_applied") is True for score in scores),
        "unwrap_count": sum(score.get("unwrap_applied") is True for score in scores),
        "coercion_count": sum(score.get("coercion_applied") is True for score in scores),
        "default_count": sum(score.get("defaults_applied") is True for score in scores),
        "local_transformation_free_count": sum(
            score.get("local_transformation_free") is True for score in scores
        ),
        "manual_structure_review_ready_count": sum(
            score.get("manual_structure_review_status") in {"PENDING", "COMPLETE"}
            for score in scores
        ),
    }
    automatic_thresholds = {
        "api_success_count": 4,
        "exactly_one_legal_tool_use_count": 4,
        "schema_and_cross_field_valid_count": 4,
        "envelope_valid_count": 4,
        "base_identity_correct_count": 4,
        "behavior_correct_count": 4,
        "fixed_weapon_substitution_count": 0,
        "fixed_weapon_substitution_attested_count": 4,
        "automatic_retry_count": 0,
        "retry_attested_count": 4,
        "extra_root_wrapper_count": 0,
        "repair_count": 0,
        "unwrap_count": 0,
        "coercion_count": 0,
        "default_count": 0,
        "local_transformation_free_count": 4,
        "manual_structure_review_ready_count": 4,
    }
    automatic_passed = all(
        automatic[name] == target for name, target in automatic_thresholds.items()
    )

    human_results = [score.get("manual_structure_review_result") for score in scores]
    complete_count = sum(
        isinstance(item, Mapping) and item.get("status") == "COMPLETE"
        for item in human_results
    )
    quality_2_count = sum(
        isinstance(item, Mapping) and item.get("structure_quality") == 2
        for item in human_results
    )
    correct_count = sum(
        isinstance(item, Mapping) and item.get("structure_correct") is True
        for item in human_results
    )
    manual_passed = complete_count == 4 and quality_2_count == 4 and correct_count == 4
    pending_count = sum(
        score.get("manual_structure_review_status") == "PENDING"
        and not isinstance(score.get("manual_structure_review_result"), Mapping)
        for score in scores
    )
    if automatic_passed and manual_passed:
        status = "PASS"
    elif automatic_passed and pending_count > 0 and complete_count + pending_count == 4:
        status = "MANUAL REVIEW PENDING"
    else:
        status = "NEEDS WORK"
    return {
        **automatic,
        "automatic_thresholds": automatic_thresholds,
        "automatic_thresholds_passed": automatic_passed,
        "manual_structure_review_complete_count": complete_count,
        "manual_structure_quality_2_count": quality_2_count,
        "manual_structure_correct_count": correct_count,
        "manual_structure_review_pending_count": pending_count,
        "manual_structure_thresholds_passed": manual_passed,
        "overall_thresholds_passed": automatic_passed and manual_passed,
        "status": status,
        "effect_type_is_scored": False,
    }


__all__ = [
    "CASES_VERSION",
    "CASE_ORDER",
    "EXPECTED_VERSION",
    "FREEZE_POLICY",
    "REVIEW_PACKET_VERSION",
    "REVIEW_RUBRIC_VERSION",
    "REVIEW_SUBMISSION_VERSION",
    "BlindRetest3CEvaluationError",
    "ManualStructureReviewError",
    "aggregate",
    "attach_manual_structure_review",
    "build_manual_structure_review_packet",
    "evaluate_case",
    "evaluate_run",
    "load_cases",
    "load_expected",
    "load_review_rubric",
    "validate_manual_structure_review_submission",
]
