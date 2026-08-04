#!/usr/bin/env python3
"""Independent, deterministic Gate A semantic evaluator.

This module never imports an AI SDK, performs network I/O, or asks the tested
model to grade itself. It reads one explicitly selected, atomically delivered
Gate A run plus the private expected-label file and applies conservative,
bilingual alias matching.

The runner contract consumed here is::

    <run_dir>/<case_id>/result.json

Each result contains the local envelope at the top level and the validated
tool input in ``result``. No recursive discovery is performed; in particular,
``tools/semantic/.tmp`` can never be selected accidentally.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


CASE_FILE_VERSION = "forge-semantic-gate-a-cases-v1"
EXPECTED_FILE_VERSION = "forge-semantic-gate-a-expected-v1"
CONTRACT_VERSION = "forge-semantic-v1.1"
LEGACY_CONTRACT_VERSION = "forge-semantic-v1"
COMPILED_TOOL = "submit_forge_semantic_blueprint"
CLARIFICATION_TOOL = "request_forge_clarification"

CSV_FIELDS = (
    "case_id",
    "api_status",
    "result_type",
    "schema_valid",
    "identity_correct",
    "behavior_correct",
    "preserved_features_quality",
    "clarification_correct",
    "fixed_weapon_substitution",
    "reviewer_reason",
    "input_tokens",
    "output_tokens",
    "elapsed_ms",
)

_COMPILED_ROOT_KEYS = {"identity", "combat", "visual", "confidence"}
_IDENTITY_KEYS_V1 = {
    "name_zh",
    "name_en",
    "category",
    "preserved_features",
    "material_hints",
    "silhouette_hints",
}
_IDENTITY_KEYS_V1_1 = {
    "canonical_name_zh",
    "canonical_name_en",
    "display_name_zh",
    "display_name_en",
    "category",
    "required_identity_parts",
    "material_hints",
    "silhouette_hints",
    "optional_decorations",
}
_COMBAT_KEYS = {
    "behavior_family",
    "delivery",
    "impact_mode",
    "effect_type",
    "drawback",
    "cadence_hint",
}
_VISUAL_KEYS = {
    "prompt_en",
    "negative_prompt_en",
    "must_preserve",
    "must_not_replace_with",
}
_CLARIFICATION_KEYS = {
    "question_zh",
    "ambiguity_type",
    "known_identity_hint",
    "known_action_hints",
}

_CATEGORIES = {
    "furniture",
    "food",
    "tool",
    "toy",
    "traditional_weapon",
    "household_object",
    "instrument",
    "clothing",
    "abstract_fantasy",
    "other",
}
_BEHAVIORS = {"sustained_ranged", "returning_thrown", "heavy_melee"}
_DELIVERIES = {
    "continuous_emission",
    "projectile_stream",
    "whole_object_return",
    "whole_object_strike",
    "melee_swing",
}
_IMPACTS = {
    "emitter_projectiles",
    "continuous_stream",
    "whole_body_collision",
    "strike_edge",
    "strike_point",
}
_EFFECTS = {
    "normal",
    "fire",
    "electric",
    "ice",
    "steam",
    "lifesteal",
    "fastener",
    "poison",
    "sound",
    "light",
    "other",
}
_DRAWBACKS = {
    "overheat",
    "slow_startup",
    "slow_movement",
    "weapon_absent_while_flying",
    "long_recovery",
    "lower_damage",
    "unstable_recoil",
}
_CADENCES = {"continuous", "single_commit", "slow_heavy"}
_AMBIGUITIES = {
    "identity_unclear",
    "behavior_conflict",
    "insufficient_information",
}

# Deterministic structural concepts for feature scoring.  Identity aliases are
# deliberately handled by the stricter `_contains_alias`; these concepts apply
# only after canonical identity has independently matched the expected object.
_STRUCTURAL_CONCEPT_ALIASES: Mapping[str, tuple[str, ...]] = {
    "leg": ("leg", "legs", "table legs", "chair legs", "wooden legs", "桌腿", "桌脚", "椅腿", "椅脚", "支腿"),
    "tabletop": ("tabletop", "table top", "桌面", "台面"),
    "seat": ("seat", "chair seat", "座面", "椅座", "座板"),
    "backrest": ("backrest", "chair back", "椅背", "靠背"),
    "handle": ("handle", "grip", "carrying handle", "把手", "手柄", "提手"),
    "spout": ("spout", "nozzle", "壶嘴", "喷口"),
    "teapot_body": ("teapot body", "kettle body", "壶身", "壶体"),
    "bell_body": ("bell body", "bell-shaped body", "钟体", "钟身", "圆钟形主体"),
    "bell_opening": ("bell opening", "bell mouth", "flared rim", "钟口", "钟沿", "钟口边缘"),
    "shaft": ("shaft", "long shaft", "spear shaft", "杆身", "长杆", "枪杆", "矛杆"),
    "spearhead": ("spearhead", "spear head", "spear tip", "pointed head", "枪头", "枪尖", "矛尖"),
    "wing": ("wing", "wings", "paper wing", "机翼", "翼面"),
    "rung": ("rung", "rungs", "ladder rung", "梯级", "横档"),
    "side_rail": ("side rail", "side rails", "ladder rail", "梯杆", "两侧长杆", "两侧梯腿"),
    "pan_body": ("pan body", "pan head", "cooking surface", "锅身", "锅体", "锅面"),
    "canopy": ("canopy", "umbrella canopy", "伞面"),
    "umbrella_rib": ("umbrella rib", "umbrella ribs", "伞骨"),
    "door": ("door", "doors", "cabinet door", "wardrobe door", "柜门"),
    "beak": ("beak", "bill", "鸭嘴"),
    "lens": ("lens", "camera lens", "镜头"),
    "viewfinder": ("viewfinder", "取景器", "取景结构"),
    "violin_body": ("violin body", "琴身"),
    "neck": ("neck", "violin neck", "琴颈"),
    "string": ("string", "strings", "violin string", "琴弦"),
    "bow": ("bow", "violin bow", "琴弓"),
    "bone": ("bone", "bone handle", "bone grip", "drumstick bone", "鸡腿骨", "骨柄"),
    "bread_shape": ("bread silhouette", "baguette shape", "loaf shape", "面包轮廓", "法棍轮廓"),
    "cloud_shape": (
        "cloud silhouette", "cloud shape", "云状轮廓", "云形轮廓",
        "云朵外形", "云团轮廓",
    ),
}
_MATERIAL_WORDS = {
    "aged", "baked", "bronze", "cast", "cloth", "copper", "crust", "fabric",
    "glass", "iron", "leather", "material", "metal", "metallic", "old", "paper",
    "plastic", "rubber", "steel", "stone", "weathered", "wood", "wooden", "worn",
}
_MATERIAL_ONLY_CJK = re.compile(
    r"^(?:古旧|古老|老旧|破旧|风化|磨损|烘烤|氧化|木质|木制|木材|青铜|铜质|"
    r"金属|铁质|钢质|皮革|橡胶|纸张|塑料|石质|玻璃|布料|材质|表皮)+$"
)
_CANONICAL_EFFECT_WORDS = {
    "electric", "electricity", "fire", "flame", "flaming", "frost", "ice",
    "lifesteal", "lightning", "poison", "returning", "steam", "weaponised",
    "weaponized",
}
_CANONICAL_EFFECT_CJK = re.compile(
    r"吸血|电流|闪电|带电|火焰|喷火|冰雾|冰霜|蒸汽|毒液|回旋|返回|武器化|武装化"
)

# Only positive identity-bearing fields are scanned. Negative prompts and
# must_not_replace_with are intentionally excluded because those are the proper
# locations for replacement prohibitions.
_FIXED_REPLACEMENT_TERMS = (
    "gatling gun",
    "gatling",
    "minigun",
    "machine gun",
    "machinegun",
    "firearm",
    "rifle",
    "pistol",
    "cannon",
    "gun",
    "greatsword",
    "great sword",
    "sword",
    "umbrella",
    "parasol",
    "加特林",
    "机关枪",
    "机枪",
    "手枪",
    "步枪",
    "火炮",
    "大炮",
    "大剑",
    "巨剑",
    "雨伞",
)


class EvaluationInputError(ValueError):
    """Raised when local evaluation data violates the isolation contract."""


def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise EvaluationInputError(f"cannot read JSON object {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvaluationInputError(f"expected JSON object in {path}")
    return value


def load_gate_a_cases(path: str | Path) -> list[dict[str, str]]:
    """Load the model-facing corpus and reject any embedded expected labels."""

    source = Path(path)
    document = _read_json_object(source)
    if set(document) != {"contract_version", "cases"}:
        raise EvaluationInputError("case file may contain only contract_version and cases")
    if document["contract_version"] != CASE_FILE_VERSION:
        raise EvaluationInputError("unsupported Gate A case file version")
    raw_cases = document["cases"]
    if not isinstance(raw_cases, list) or len(raw_cases) != 20:
        raise EvaluationInputError("Gate A requires exactly 20 model-facing cases")

    cases: list[dict[str, str]] = []
    for index, item in enumerate(raw_cases, start=1):
        if not isinstance(item, dict) or set(item) != {"case_id", "input_text"}:
            raise EvaluationInputError(
                "each model-facing case must contain only case_id and input_text"
            )
        expected_id = f"{index:02d}"
        if item["case_id"] != expected_id:
            raise EvaluationInputError(
                f"Gate A cases must be ordered 01..20; found {item.get('case_id')!r}"
            )
        if not isinstance(item["input_text"], str) or not item["input_text"].strip():
            raise EvaluationInputError(f"case {expected_id} has empty input_text")
        cases.append({"case_id": item["case_id"], "input_text": item["input_text"]})
    return cases


def isolated_model_input(case: Mapping[str, Any]) -> str:
    """Return only player text for a request, rejecting enriched case records.

    Runners should use this boundary instead of merging case and expected data.
    It makes an accidental ``gate_a_expected`` payload leak fail closed.
    """

    if set(case) != {"case_id", "input_text"}:
        raise EvaluationInputError(
            "model input must originate from an isolated {case_id, input_text} record"
        )
    case_id = case.get("case_id")
    input_text = case.get("input_text")
    if not isinstance(case_id, str) or not re.fullmatch(r"\d{2}", case_id):
        raise EvaluationInputError("invalid model-facing case_id")
    if not isinstance(input_text, str) or not input_text.strip():
        raise EvaluationInputError("invalid model-facing input_text")
    return input_text


def load_gate_a_expected(path: str | Path) -> list[dict[str, Any]]:
    """Load evaluator-only labels. This function is never used by payload code."""

    source = Path(path)
    document = _read_json_object(source)
    required_top = {"contract_version", "evaluator_policy", "cases"}
    if set(document) != required_top:
        raise EvaluationInputError("unexpected keys in Gate A expected-label file")
    if document["contract_version"] != EXPECTED_FILE_VERSION:
        raise EvaluationInputError("unsupported Gate A expected-label version")
    expected = document["cases"]
    if not isinstance(expected, list) or len(expected) != 20:
        raise EvaluationInputError("Gate A requires exactly 20 expected records")
    for index, item in enumerate(expected, start=1):
        if not isinstance(item, dict) or item.get("case_id") != f"{index:02d}":
            raise EvaluationInputError("expected records must be ordered 01..20")
        if item.get("result_type") not in {"compiled", "needs_clarification"}:
            raise EvaluationInputError(f"case {index:02d} has invalid expected result_type")
    return expected


def _normalise(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = re.sub(r"[_\-]+", " ", value)
    value = re.sub(r"[^\w\u3400-\u9fff]+", " ", value, flags=re.UNICODE)
    return " ".join(value.split())


def _contains_alias(text: str, aliases: Iterable[str]) -> bool:
    normalised_text = _normalise(text)
    compact_text = normalised_text.replace(" ", "")
    for alias in aliases:
        normalised_alias = _normalise(alias)
        if not normalised_alias:
            continue
        if re.search(r"[\u3400-\u9fff]", normalised_alias):
            if normalised_alias.replace(" ", "") in compact_text:
                return True
        else:
            pattern = r"(?:^|\s)" + re.escape(normalised_alias) + r"(?:$|\s)"
            if re.search(pattern, normalised_text):
                return True
    return False


def _structural_concepts(value: str) -> set[str]:
    return {
        concept
        for concept, aliases in _STRUCTURAL_CONCEPT_ALIASES.items()
        if _contains_alias(value, aliases)
    }


def _feature_matches(candidate: str, aliases: Iterable[str]) -> bool:
    alias_values = [alias for alias in aliases if isinstance(alias, str) and alias.strip()]
    if _contains_alias(candidate, alias_values):
        return True
    candidate_concepts = _structural_concepts(candidate)
    if not candidate_concepts:
        return False
    expected_concepts: set[str] = set()
    for alias in alias_values:
        expected_concepts.update(_structural_concepts(alias))
    return bool(candidate_concepts.intersection(expected_concepts))


def _material_only(value: str) -> bool:
    if _structural_concepts(value):
        return False
    normalised = _normalise(value)
    latin = re.findall(r"[a-z0-9]+", normalised)
    if latin and all(token in _MATERIAL_WORDS for token in latin):
        return True
    compact_cjk = "".join(re.findall(r"[\u3400-\u9fff]+", normalised))
    return bool(compact_cjk and _MATERIAL_ONLY_CJK.fullmatch(compact_cjk))


def _canonical_name_clean(value: str) -> bool:
    normalised = _normalise(value)
    words = set(re.findall(r"[a-z0-9]+", normalised))
    return not words.intersection(_CANONICAL_EFFECT_WORDS) and not _CANONICAL_EFFECT_CJK.search(normalised)


def _is_string_list(value: Any, minimum: int, maximum: int) -> bool:
    return (
        isinstance(value, list)
        and minimum <= len(value) <= maximum
        and all(isinstance(item, str) and bool(item.strip()) for item in value)
    )


def _minimal_compiled_schema_valid(value: Any) -> bool:
    if not isinstance(value, dict) or set(value) != _COMPILED_ROOT_KEYS:
        return False
    identity = value.get("identity")
    combat = value.get("combat")
    visual = value.get("visual")
    confidence = value.get("confidence")
    if not isinstance(identity, dict):
        return False
    identity_keys = frozenset(identity)
    if identity_keys not in {
        frozenset(_IDENTITY_KEYS_V1),
        frozenset(_IDENTITY_KEYS_V1_1),
    }:
        return False
    if not isinstance(combat, dict) or set(combat) != _COMBAT_KEYS:
        return False
    if not isinstance(visual, dict) or set(visual) != _VISUAL_KEYS:
        return False
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        return False
    if not math.isfinite(float(confidence)) or not 0 <= float(confidence) <= 1:
        return False

    is_v1_1 = identity_keys == frozenset(_IDENTITY_KEYS_V1_1)
    if is_v1_1:
        string_bounds = {
            "canonical_name_zh": 80,
            "canonical_name_en": 120,
            "display_name_zh": 100,
            "display_name_en": 160,
        }
        if any(
            not isinstance(identity[field], str)
            or not 1 <= len(identity[field]) <= maximum
            for field, maximum in string_bounds.items()
        ):
            return False
        if not all(
            _canonical_name_clean(identity[field])
            for field in ("canonical_name_zh", "canonical_name_en")
        ):
            return False
        if not _is_string_list(identity["required_identity_parts"], 2, 5):
            return False
        if any(_material_only(part) for part in identity["required_identity_parts"]):
            return False
        if not _is_string_list(identity["optional_decorations"], 0, 4):
            return False
    else:
        if not (isinstance(identity["name_zh"], str) and 1 <= len(identity["name_zh"]) <= 80):
            return False
        if not (isinstance(identity["name_en"], str) and 1 <= len(identity["name_en"]) <= 120):
            return False
        if not _is_string_list(identity["preserved_features"], 2, 6):
            return False
    if identity["category"] not in _CATEGORIES:
        return False
    if not _is_string_list(identity["material_hints"], 0, 4):
        return False
    if not _is_string_list(identity["silhouette_hints"], 1, 4):
        return False
    if is_v1_1:
        names = {
            _normalise(identity[field])
            for field in (
                "canonical_name_zh", "canonical_name_en", "display_name_zh", "display_name_en"
            )
        }
        if any(_normalise(hint) in names for hint in identity["silhouette_hints"]):
            return False

    if combat["behavior_family"] not in _BEHAVIORS:
        return False
    if combat["delivery"] not in _DELIVERIES:
        return False
    if combat["impact_mode"] not in _IMPACTS:
        return False
    if combat["effect_type"] not in _EFFECTS:
        return False
    if combat["drawback"] not in _DRAWBACKS:
        return False
    if combat["cadence_hint"] not in _CADENCES:
        return False

    behavior = combat["behavior_family"]
    if behavior == "sustained_ranged":
        if combat["delivery"] not in {"continuous_emission", "projectile_stream"}:
            return False
        if combat["cadence_hint"] != "continuous":
            return False
    elif behavior == "returning_thrown":
        if (
            combat["delivery"] != "whole_object_return"
            or combat["impact_mode"] != "whole_body_collision"
            or combat["cadence_hint"] != "single_commit"
            or combat["drawback"] != "weapon_absent_while_flying"
        ):
            return False
    elif behavior == "heavy_melee":
        if combat["delivery"] not in {"whole_object_strike", "melee_swing"}:
            return False
        if combat["impact_mode"] not in {
            "strike_edge",
            "strike_point",
            "whole_body_collision",
        }:
            return False
        if combat["cadence_hint"] != "slow_heavy":
            return False

    prompt = visual["prompt_en"]
    negative = visual["negative_prompt_en"]
    if not isinstance(prompt, str) or not 40 <= len(prompt) <= 1000:
        return False
    if not isinstance(negative, str) or not 1 <= len(negative) <= 500:
        return False
    if not _is_string_list(visual["must_preserve"], 2, 6):
        return False
    if not _is_string_list(visual["must_not_replace_with"], 1, 5):
        return False
    identity_name_en = (
        identity["canonical_name_en"] if is_v1_1 else identity["name_en"]
    )
    if not _contains_alias(prompt, [identity_name_en]):
        return False
    prompt_normal = _normalise(prompt)
    if any(phrase in prompt_normal for phrase in ("do not", "not a gun", "not a sword")):
        return False

    identity_features = (
        identity["required_identity_parts"]
        if is_v1_1
        else identity["preserved_features"]
    )
    if is_v1_1:
        if any(
            not any(_feature_matches(candidate, [feature]) for candidate in visual["must_preserve"])
            for feature in identity_features
        ):
            return False
    elif not any(
        _feature_matches(candidate, [feature])
        for feature in identity_features
        for candidate in visual["must_preserve"]
    ):
        return False
    return True


def _minimal_clarification_schema_valid(value: Any) -> bool:
    if not isinstance(value, dict) or set(value) != _CLARIFICATION_KEYS:
        return False
    question = value.get("question_zh")
    known_identity = value.get("known_identity_hint")
    if not isinstance(question, str) or not 1 <= len(question) <= 120:
        return False
    if value.get("ambiguity_type") not in _AMBIGUITIES:
        return False
    if not isinstance(known_identity, str) or len(known_identity) > 100:
        return False
    action_hints = value.get("known_action_hints")
    if not _is_string_list(action_hints, 0, 4):
        return False
    question = question.strip()
    if not re.search(r"[\u3400-\u9fff]", question) or re.search(r"[A-Za-z]", question):
        return False
    question_mark_count = question.count("?") + question.count("？")
    has_valid_ending = bool(
        re.search(r"[?？](?:[（(][^?？\r\n]{1,80}[）)])?$", question)
    )
    exclusive_choice = bool(re.search(r"还是|或是|或者", question))
    if question_mark_count < 1 or not has_valid_ending or (
        question_mark_count > 1
        and not (
            value.get("ambiguity_type") == "behavior_conflict" and exclusive_choice
        )
    ):
        return False
    if len(
        re.findall(
            r"什么|哪(?:个|种|一)|如何|怎样|怎么|是否|能否|要不要|是不是|为何|为什么|多少",
            question,
        )
    ) > 1:
        return False
    identity_focus = bool(
        re.search(r"(?:什么|哪(?:个|种|一)).{0,8}(?:物件|东西|物体|主体)|(?:物件|东西|物体|主体).{0,8}(?:什么|哪(?:个|种|一)|身份)|是什么|身份", question)
    )
    behavior_focus = bool(
        re.search(r"攻击|战斗|玩法|行为|怎么打|怎样打|如何打|发射|投掷|挥击", question)
    )
    if identity_focus and behavior_focus:
        return False
    return True


def _schema_valid(record: Mapping[str, Any]) -> bool:
    reported = record.get("schema_valid")
    if isinstance(reported, bool) and not reported:
        return False
    validation = record.get("validation")
    if isinstance(validation, dict) and validation.get("schema_valid") is False:
        return False
    result_type = record.get("result_type")
    tool_name = record.get("tool_name")
    value = record.get("result")
    if result_type == "compiled" and tool_name == COMPILED_TOOL:
        return _minimal_compiled_schema_valid(value)
    if result_type == "needs_clarification" and tool_name == CLARIFICATION_TOOL:
        return _minimal_clarification_schema_valid(value)
    return False


def _api_success(status: Any) -> bool:
    if isinstance(status, bool):
        return False
    if isinstance(status, int):
        return 200 <= status < 300
    if isinstance(status, str):
        clean = status.strip().casefold()
        if clean.isdigit():
            return 200 <= int(clean) < 300
        return clean in {"ok", "success", "succeeded"}
    return False


def _extract_usage(record: Mapping[str, Any]) -> tuple[int | None, int | None]:
    usage = record.get("usage")
    if isinstance(usage, dict):
        input_tokens = usage.get("input_tokens")
        output_tokens = usage.get("output_tokens")
    else:
        input_tokens = record.get("input_tokens")
        output_tokens = record.get("output_tokens")

    def clean(value: Any) -> int | None:
        return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None

    return clean(input_tokens), clean(output_tokens)


def _envelope_proves_real_anthropic(record: Mapping[str, Any]) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    if record.get("provider") != "anthropic":
        reasons.append("provider 不是 anthropic")
    if record.get("ai_interpretation_used") is not True:
        reasons.append("ai_interpretation_used 不是 true")
    if record.get("contract_version") not in {CONTRACT_VERSION, LEGACY_CONTRACT_VERSION}:
        reasons.append("contract_version 不合法")
    if not isinstance(record.get("model_id"), str) or not record.get("model_id", "").strip():
        reasons.append("model_id 缺失")
    if not isinstance(record.get("request_id"), str) or not record.get("request_id", "").strip():
        reasons.append("request_id 缺失")
    input_tokens, output_tokens = _extract_usage(record)
    if input_tokens is None or output_tokens is None:
        reasons.append("usage 信封不完整")
    return not reasons, reasons


def _positive_identity_text(result: Mapping[str, Any]) -> str:
    identity = result.get("identity")
    visual = result.get("visual")
    values: list[str] = []
    if isinstance(identity, dict):
        for key in (
            "canonical_name_zh", "canonical_name_en", "display_name_zh",
            "display_name_en", "name_zh", "name_en",
        ):
            if isinstance(identity.get(key), str):
                values.append(identity[key])
    if isinstance(visual, dict) and isinstance(visual.get("prompt_en"), str):
        values.append(visual["prompt_en"])
    return " ".join(values)


def _fixed_substitution(result: Any, expected: Mapping[str, Any]) -> tuple[bool, list[str]]:
    if not isinstance(result, dict):
        return False, []
    positive = _positive_identity_text(result)
    allowed = tuple(str(item) for item in expected.get("allowed_fixed_weapon_terms", []))
    found: list[str] = []
    for term in _FIXED_REPLACEMENT_TERMS:
        if _contains_alias(positive, [term]) and not _contains_alias(" ".join(allowed), [term]):
            found.append(term)
    return bool(found), found


def _identity_matches(result: Mapping[str, Any], expected: Mapping[str, Any]) -> tuple[bool, str]:
    identity = result.get("identity")
    if not isinstance(identity, dict):
        return False, "identity 缺失"
    actual_zh = identity.get("canonical_name_zh", identity.get("name_zh"))
    actual_en = identity.get("canonical_name_en", identity.get("name_en"))
    if not isinstance(actual_zh, str) or not isinstance(actual_en, str):
        return False, "中英身份名称缺失"
    identity_expected = expected.get("identity")
    if not isinstance(identity_expected, dict):
        return False, "expected identity 配置错误"
    zh_ok = _contains_alias(actual_zh, identity_expected.get("name_zh_aliases", []))
    en_ok = _contains_alias(actual_en, identity_expected.get("name_en_aliases", []))
    if zh_ok and en_ok:
        return True, "中英身份均匹配"
    failures: list[str] = []
    if not zh_ok:
        failures.append(f"中文身份不匹配({actual_zh})")
    if not en_ok:
        failures.append(f"英文身份不匹配({actual_en})")
    return False, "、".join(failures)


def _feature_candidates(result: Mapping[str, Any]) -> tuple[list[str], list[str]]:
    structural: list[str] = []
    descriptive: list[str] = []
    identity = result.get("identity")
    if isinstance(identity, dict):
        structural_key = (
            "required_identity_parts"
            if "required_identity_parts" in identity
            else "preserved_features"
        )
        value = identity.get(structural_key)
        if isinstance(value, list):
            structural.extend(item for item in value if isinstance(item, str))
        for key in ("material_hints", "silhouette_hints"):
            value = identity.get(key)
            if isinstance(value, list):
                descriptive.extend(item for item in value if isinstance(item, str))
    return structural, descriptive


def _feature_quality(
    result: Mapping[str, Any], expected: Mapping[str, Any], substituted: bool
) -> tuple[int, list[str], list[str]]:
    core_features = expected.get("core_features")
    if not isinstance(core_features, list) or not core_features:
        return 0, [], ["expected core_features 配置错误"]
    structural_candidates, descriptive_candidates = _feature_candidates(result)
    matched: list[str] = []
    missing: list[str] = []
    for feature in core_features:
        if not isinstance(feature, dict):
            missing.append("invalid expected feature")
            continue
        label = str(feature.get("label", "unnamed feature"))
        aliases = feature.get("aliases", [])
        expected_is_structural = isinstance(aliases, list) and any(
            _structural_concepts(alias)
            for alias in aliases
            if isinstance(alias, str)
        )
        candidates = (
            structural_candidates
            if expected_is_structural
            else structural_candidates + descriptive_candidates
        )
        if isinstance(aliases, list) and any(
            _feature_matches(candidate, aliases) for candidate in candidates
        ):
            matched.append(label)
        else:
            missing.append(label)
    if substituted or not matched:
        quality = 0
    elif not missing:
        quality = 2
    else:
        quality = 1
    return quality, matched, missing


def _clarification_correct(result: Any, expected: Mapping[str, Any]) -> tuple[bool, str]:
    if not isinstance(result, dict):
        return False, "澄清结构缺失"
    actual = result.get("ambiguity_type")
    expected_type = expected.get("ambiguity_type")
    if actual != expected_type:
        return False, f"ambiguity_type={actual!r}，预期 {expected_type!r}"
    question = result.get("question_zh")
    if not isinstance(question, str) or not question.strip():
        return False, "澄清问题为空"
    question_mark_count = question.count("?") + question.count("？")
    exclusive_choice = bool(re.search(r"还是|或是|或者", question))
    if question_mark_count < 1:
        return False, "澄清缺少问号"
    if question_mark_count > 1 and not (
        actual == "behavior_conflict" and exclusive_choice
    ):
        return False, "澄清包含多个独立问题"
    if len(
        re.findall(
            r"什么|哪(?:个|种|一)|如何|怎样|怎么|是否|能否|要不要|是不是|为何|为什么|多少",
            question,
        )
    ) > 1:
        return False, "澄清合并了多个关键问题"
    if any(key in result for key in ("identity", "combat", "visual", "confidence")):
        return False, "澄清结果伪造了 Blueprint"
    return True, "工具、歧义类型和单问题结构正确"


def evaluate_case(record: Mapping[str, Any] | None, expected: Mapping[str, Any]) -> dict[str, Any]:
    """Score one already-delivered case without calling any model."""

    case_id = str(expected.get("case_id", ""))
    if record is None:
        return {
            "case_id": case_id,
            "api_status": "missing",
            "result_type": "failed",
            "schema_valid": False,
            "identity_correct": False,
            "behavior_correct": False,
            "preserved_features_quality": 0,
            "clarification_correct": False,
            "fixed_weapon_substitution": False,
            "reviewer_reason": "结果文件缺失",
            "input_tokens": None,
            "output_tokens": None,
            "elapsed_ms": None,
            "envelope_valid": False,
            "matched_features": [],
            "missing_features": ["result.json"],
        }

    api_status = record.get("api_status", "missing")
    result_type = record.get("result_type", "failed")
    result = record.get("result")
    schema_valid = _schema_valid(record)
    envelope_valid, envelope_reasons = _envelope_proves_real_anthropic(record)
    input_tokens, output_tokens = _extract_usage(record)
    elapsed = record.get("elapsed_ms")
    if isinstance(elapsed, bool) or not isinstance(elapsed, (int, float)) or elapsed < 0:
        elapsed = None

    reasons: list[str] = []
    if not _api_success(api_status):
        reasons.append(f"API 未成功({api_status!r})")
    if not schema_valid:
        reasons.append("结构或跨字段验证失败")
    reasons.extend(envelope_reasons)
    if record.get("case_id") != case_id:
        reasons.append(f"case_id 信封不匹配({record.get('case_id')!r})")
        envelope_valid = False

    substituted, substitution_terms = _fixed_substitution(result, expected)
    if substituted:
        reasons.append("positive identity fields 出现固定武器替换: " + ", ".join(substitution_terms))

    eligible = _api_success(api_status) and schema_valid and envelope_valid
    identity_correct = False
    behavior_correct = False
    feature_quality = 0
    clarification_correct = False
    matched_features: list[str] = []
    missing_features: list[str] = []

    if expected.get("result_type") == "compiled":
        if result_type != "compiled" or record.get("tool_name") != COMPILED_TOOL:
            reasons.append(
                f"结果工具错误({result_type!r}, {record.get('tool_name')!r})"
            )
            eligible = False
        if eligible and isinstance(result, dict):
            identity_correct, identity_reason = _identity_matches(result, expected)
            reasons.append("身份: " + identity_reason)
            actual_behavior = (
                result.get("combat", {}).get("behavior_family")
                if isinstance(result.get("combat"), dict)
                else None
            )
            behavior_correct = actual_behavior == expected.get("behavior_family")
            reasons.append(
                "行为: "
                + (
                    f"匹配 {actual_behavior}"
                    if behavior_correct
                    else f"{actual_behavior!r}，预期 {expected.get('behavior_family')!r}"
                )
            )
            feature_quality, matched_features, missing_features = _feature_quality(
                result, expected, substituted
            )
            feature_total = len(expected.get("core_features", []))
            reasons.append(
                f"特征: {len(matched_features)}/{feature_total}；质量={feature_quality}"
                + (f"；缺失 {', '.join(missing_features)}" if missing_features else "")
            )
            if substituted:
                identity_correct = False
        else:
            identity_correct = False
            behavior_correct = False
            feature_quality = 0
    else:
        if result_type != "needs_clarification" or record.get("tool_name") != CLARIFICATION_TOOL:
            reasons.append(
                f"澄清工具错误({result_type!r}, {record.get('tool_name')!r})"
            )
            clarification_correct = False
        elif eligible:
            clarification_correct, clarification_reason = _clarification_correct(result, expected)
            reasons.append("澄清: " + clarification_reason)
        else:
            clarification_correct = False

    return {
        "case_id": case_id,
        "api_status": api_status,
        "result_type": result_type,
        "schema_valid": schema_valid,
        "identity_correct": identity_correct,
        "behavior_correct": behavior_correct,
        "preserved_features_quality": feature_quality,
        "clarification_correct": clarification_correct,
        "fixed_weapon_substitution": substituted,
        "reviewer_reason": "；".join(reasons) if reasons else "通过保守独立评估",
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "elapsed_ms": elapsed,
        "envelope_valid": envelope_valid,
        "matched_features": matched_features,
        "missing_features": missing_features,
    }


def load_run_results(run_dir: str | Path, case_ids: Sequence[str]) -> dict[str, dict[str, Any] | None]:
    """Load only direct final artifacts from one explicitly selected run."""

    root = Path(run_dir).resolve()
    if ".tmp" in root.parts:
        raise EvaluationInputError("the evaluator refuses temporary directories")
    if not root.is_dir():
        raise EvaluationInputError(f"run directory does not exist: {root}")

    results: dict[str, dict[str, Any] | None] = {}
    for case_id in case_ids:
        if not re.fullmatch(r"\d{2}", case_id):
            raise EvaluationInputError(f"invalid case id: {case_id!r}")
        result_path = root / case_id / "result.json"
        if not result_path.is_file():
            results[case_id] = None
            continue
        results[case_id] = _read_json_object(result_path)
    return results


def evaluate_run(run_dir: str | Path, expected_path: str | Path) -> list[dict[str, Any]]:
    """Evaluate exactly one run directory against evaluator-only labels."""

    expected = load_gate_a_expected(expected_path)
    by_id = load_run_results(run_dir, [item["case_id"] for item in expected])
    return [evaluate_case(by_id[item["case_id"]], item) for item in expected]


def summarize_scores(scores: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Return transparent counts; the report layer owns the final run verdict."""

    return {
        "case_count": len(scores),
        "api_processable_count": sum(_api_success(item.get("api_status")) for item in scores),
        "schema_valid_count": sum(item.get("schema_valid") is True for item in scores),
        "real_anthropic_envelope_count": sum(item.get("envelope_valid") is True for item in scores),
        "identity_correct_count": sum(item.get("identity_correct") is True for item in scores),
        "behavior_correct_count": sum(item.get("behavior_correct") is True for item in scores),
        "features_quality_2_count": sum(
            item.get("preserved_features_quality") == 2 for item in scores
        ),
        "clarification_correct_count": sum(
            item.get("clarification_correct") is True for item in scores
        ),
        "fixed_weapon_substitution_count": sum(
            item.get("fixed_weapon_substitution") is True for item in scores
        ),
    }


def write_scores_json(path: str | Path, scores: Sequence[Mapping[str, Any]]) -> None:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = {"scores": list(scores), "summary": summarize_scores(scores)}
    with destination.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def write_scores_csv(path: str | Path, scores: Sequence[Mapping[str, Any]]) -> None:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(scores)


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, help="explicit final Gate A run directory")
    parser.add_argument("--expected", required=True, help="gate_a_expected.json path")
    parser.add_argument("--json-output", help="optional evaluator JSON output")
    parser.add_argument("--csv-output", help="optional evaluator CSV output")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    try:
        scores = evaluate_run(args.run_dir, args.expected)
        if args.json_output:
            write_scores_json(args.json_output, scores)
        if args.csv_output:
            write_scores_csv(args.csv_output, scores)
        print(json.dumps(summarize_scores(scores), ensure_ascii=False, sort_keys=True))
        return 0
    except EvaluationInputError as exc:
        print(f"Gate A evaluator input error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
