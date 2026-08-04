"""Strict local contracts for Forge Semantic Compiler Gate A.

Only the JSON Schema features used by the checked-in schemas are implemented.
The validator has no network or third-party dependencies and never repairs,
coerces, defaults, or otherwise mutates model output.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import math
from pathlib import Path
import re
from typing import Any, Mapping, Sequence
import unicodedata


SUBMIT_BLUEPRINT_TOOL = "submit_forge_semantic_blueprint"
REQUEST_CLARIFICATION_TOOL = "request_forge_clarification"
CONTRACT_VERSION = "forge-semantic-v1.1"
ALLOWED_TOOL_NAMES = frozenset({SUBMIT_BLUEPRINT_TOOL, REQUEST_CLARIFICATION_TOOL})

_SCHEMA_DIR = Path(__file__).resolve().parents[1] / "schema"


@dataclass(frozen=True)
class ValidationIssue:
    path: str
    message: str

    @property
    def json_pointer(self) -> str:
        """Return the issue path as RFC 6901 JSON Pointer."""

        if self.path == "$":
            return ""
        tokens: list[str] = []
        for match in re.finditer(
            r"\.([A-Za-z_][A-Za-z0-9_]*)|\[(\d+)\]|\[((?:\"(?:\\.|[^\"])*\"))\]",
            self.path[1:],
        ):
            plain, index, quoted = match.groups()
            if plain is not None:
                token = plain
            elif index is not None:
                token = index
            else:
                token = json.loads(quoted)
            tokens.append(str(token).replace("~", "~0").replace("/", "~1"))
        return "/" + "/".join(tokens)

    def __str__(self) -> str:
        return f"{self.path}: {self.message}"


class ContractValidationError(ValueError):
    """An explicit, non-repairing rejection of untrusted tool input."""

    def __init__(
        self,
        issues: Sequence[ValidationIssue] | ValidationIssue | str,
        *,
        stage: str = "contract",
    ):
        if isinstance(issues, str):
            normalized = (ValidationIssue("$", issues),)
        elif isinstance(issues, ValidationIssue):
            normalized = (issues,)
        else:
            normalized = tuple(issues)
        if not normalized:
            normalized = (ValidationIssue("$", "contract validation failed"),)
        self.issues = normalized
        self.stage = stage
        super().__init__("; ".join(str(issue) for issue in normalized))


SchemaValidationError = ContractValidationError


def _load_schema(filename: str) -> dict[str, Any]:
    path = _SCHEMA_DIR / filename
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"unable to load contract schema {filename}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"contract schema {filename} is not a JSON object")
    return value


FORGE_SEMANTIC_BLUEPRINT_SCHEMA = _load_schema(
    "forge_semantic_blueprint.schema.json"
)
LEGACY_FORGE_SEMANTIC_BLUEPRINT_SCHEMA_V1 = _load_schema(
    "forge_semantic_blueprint.v1.schema.json"
)
FORGE_SEMANTIC_BLUEPRINT_SCHEMA_V1_1 = FORGE_SEMANTIC_BLUEPRINT_SCHEMA
CLARIFICATION_REQUEST_SCHEMA = _load_schema("clarification_request.schema.json")
FORENSIC_CLARIFICATION_REQUEST_SCHEMA = _load_schema(
    "clarification_request.forensic_replay.schema.json"
)
TOOL_SCHEMAS: Mapping[str, Mapping[str, Any]] = {
    SUBMIT_BLUEPRINT_TOOL: FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    REQUEST_CLARIFICATION_TOOL: CLARIFICATION_REQUEST_SCHEMA,
}


def schema_for_tool(tool_name: str) -> Mapping[str, Any]:
    try:
        return TOOL_SCHEMAS[tool_name]
    except KeyError as exc:
        raise ContractValidationError(
            ValidationIssue("$.tool_name", f"unknown tool {tool_name!r}")
        ) from exc


def _type_name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    if isinstance(value, str):
        return "string"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    return type(value).__name__


def _matches_type(value: Any, expected: str) -> bool:
    checks = {
        "object": lambda: isinstance(value, dict),
        "array": lambda: isinstance(value, list),
        "string": lambda: isinstance(value, str),
        "number": lambda: isinstance(value, (int, float)) and not isinstance(value, bool),
        "integer": lambda: isinstance(value, int) and not isinstance(value, bool),
        "boolean": lambda: isinstance(value, bool),
        "null": lambda: value is None,
    }
    if expected not in checks:
        raise RuntimeError(f"unsupported schema type {expected!r}")
    return checks[expected]()


def _path(path: str, key: str) -> str:
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        return f"{path}.{key}"
    return f"{path}[{json.dumps(key, ensure_ascii=False)}]"


def _validate_node(
    value: Any,
    schema: Mapping[str, Any],
    path: str,
    issues: list[ValidationIssue],
) -> None:
    expected = schema.get("type")
    if expected is not None:
        expected_types = expected if isinstance(expected, list) else [expected]
        if not all(isinstance(item, str) for item in expected_types):
            raise RuntimeError(f"invalid type declaration in schema at {path}")
        if not any(_matches_type(value, item) for item in expected_types):
            issues.append(
                ValidationIssue(
                    path,
                    f"expected {' or '.join(expected_types)}, got {_type_name(value)}",
                )
            )
            return

    if "enum" in schema and value not in schema["enum"]:
        allowed = ", ".join(repr(item) for item in schema["enum"])
        issues.append(ValidationIssue(path, f"value {value!r} is not in enum [{allowed}]"))

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        if not isinstance(properties, dict) or not isinstance(required, list):
            raise RuntimeError(f"invalid object declaration in schema at {path}")
        for key in required:
            if key not in value:
                issues.append(
                    ValidationIssue(_path(path, str(key)), "required property is missing")
                )
        additional = schema.get("additionalProperties", True)
        for key, child in value.items():
            child_path = _path(path, str(key))
            if key in properties:
                child_schema = properties[key]
                if not isinstance(child_schema, dict):
                    raise RuntimeError(f"invalid property schema at {child_path}")
                _validate_node(child, child_schema, child_path, issues)
            elif additional is False:
                issues.append(ValidationIssue(child_path, "additional property is not allowed"))
            elif isinstance(additional, dict):
                _validate_node(child, additional, child_path, issues)
    elif isinstance(value, list):
        minimum, maximum = schema.get("minItems"), schema.get("maxItems")
        if minimum is not None and len(value) < minimum:
            issues.append(
                ValidationIssue(path, f"array has {len(value)} items; minimum is {minimum}")
            )
        if maximum is not None and len(value) > maximum:
            issues.append(
                ValidationIssue(path, f"array has {len(value)} items; maximum is {maximum}")
            )
        item_schema = schema.get("items")
        if item_schema is not None:
            if not isinstance(item_schema, dict):
                raise RuntimeError(f"invalid items declaration in schema at {path}")
            for index, child in enumerate(value):
                _validate_node(child, item_schema, f"{path}[{index}]", issues)
    elif isinstance(value, str):
        minimum, maximum = schema.get("minLength"), schema.get("maxLength")
        if minimum is not None and len(value) < minimum:
            issues.append(
                ValidationIssue(path, f"string length {len(value)} is below minimum {minimum}")
            )
        if maximum is not None and len(value) > maximum:
            issues.append(
                ValidationIssue(path, f"string length {len(value)} exceeds maximum {maximum}")
            )
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and not math.isfinite(value):
            issues.append(ValidationIssue(path, "number must be finite JSON data"))
            return
        minimum, maximum = schema.get("minimum"), schema.get("maximum")
        if minimum is not None and value < minimum:
            issues.append(ValidationIssue(path, f"number {value} is below minimum {minimum}"))
        if maximum is not None and value > maximum:
            issues.append(ValidationIssue(path, f"number {value} exceeds maximum {maximum}"))


def validate_schema_instance(value: Any, schema: Mapping[str, Any]) -> Any:
    """Validate the recursive schema subset and return the same value unchanged."""

    issues: list[ValidationIssue] = []
    _validate_node(value, schema, "$", issues)
    if issues:
        raise ContractValidationError(issues, stage="schema")
    return value


_FORBIDDEN_EXACT = frozenset(
    {
        "damage", "damagevalue", "dmg", "dps", "attackdamage", "attackpower",
        "attackspeed", "firerate", "rateoffire", "rof", "range", "attackrange",
        "weaponrange", "reach", "cooldown", "cooldowntime", "cooldownseconds",
        "cd", "code", "sourcecode", "runtimecode", "script", "javascript",
        "python", "gdscript", "executable", "executioncontent",
    }
)
_FORBIDDEN_CJK = (
    "伤害", "攻击力", "攻速", "攻击速度", "射速", "射程", "冷却", "代码", "脚本",
)


def _canonical_key(key: str) -> str:
    return re.sub(
        r"[^a-z0-9\u3400-\u9fff]+",
        "",
        unicodedata.normalize("NFKC", key).casefold(),
    )


def _forbidden_key(key: str) -> bool:
    canonical = _canonical_key(key)
    camel = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", key)
    tokens = set(
        re.findall(r"[a-z0-9]+", unicodedata.normalize("NFKC", camel).casefold())
    )
    if canonical in _FORBIDDEN_EXACT or any(part in canonical for part in _FORBIDDEN_CJK):
        return True
    if tokens.intersection(
        {"damage", "dmg", "dps", "range", "cooldown", "code", "script",
         "gdscript", "javascript", "python"}
    ):
        return True
    return any(
        part in canonical
        for part in (
            "damage", "attackspeed", "firerate", "rateoffire", "attackrange",
            "weaponrange", "cooldown", "sourcecode", "runtimecode", "gdscript",
            "javascriptcode", "pythoncode",
        )
    )


def _forbidden_field_issues(value: Any, path: str = "$") -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = _path(path, str(key))
            if _forbidden_key(str(key)):
                issues.append(
                    ValidationIssue(
                        child_path,
                        "model output may not define damage, attack-speed, range, cooldown, or code fields",
                    )
                )
            issues.extend(_forbidden_field_issues(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            issues.extend(_forbidden_field_issues(child, f"{path}[{index}]"))
    return issues


def _normalized_phrase(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(re.findall(r"[a-z0-9]+|[\u3400-\u9fff]+", value))


def _phrase_occurs(needle: str, haystack: str) -> bool:
    needle = _normalized_phrase(needle)
    haystack = _normalized_phrase(haystack)
    if not needle:
        return False
    if re.fullmatch(r"[a-z0-9 ]+", needle):
        return re.search(r"(?<![a-z0-9])" + re.escape(needle) + r"(?![a-z0-9])", haystack) is not None
    return needle in haystack


_NEGATION_PATTERNS = (
    re.compile(r"\bdo\s+not\b", re.I),
    re.compile(r"\bdon['’]?t\b", re.I),
    re.compile(r"\bmust\s+not\b", re.I),
    re.compile(r"\bnot\s+(?:a|an|the)\b", re.I),
    re.compile(r"\bno\s+(?:gun|sword|umbrella|gatling|weapon)\b", re.I),
    re.compile(r"\bnever\s+(?:replace|turn|transform|convert)\b", re.I),
    re.compile(r"\b(?:rather\s+than|instead\s+of)\b", re.I),
    re.compile(r"\b(?:avoid|exclude|forbid)\b", re.I),
    re.compile(r"(?:不要|不得|禁止|不能|不是|并非).{0,24}(?:替换|变成|枪|剑|伞)"),
)
_GENERIC_TOKENS = frozenset(
    {
        "and", "the", "with", "from", "object", "item", "thing", "identity",
        "feature", "features", "structure", "shape", "form", "complete",
        "visible", "view", "side", "old", "new", "large", "small",
    }
)

# These concepts are deliberately structural and conservative.  They are not
# an open-ended similarity model: an alias must name a recognisable part.  In
# particular, material/category phrases such as "wooden furniture" map to no
# concept and cannot stand in for a leg, handle, wing, or other part.
_STRUCTURAL_CONCEPT_ALIASES: Mapping[str, tuple[str, ...]] = {
    "leg": ("leg", "legs", "桌腿", "桌脚", "椅腿", "椅脚", "支腿"),
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

_MATERIAL_WORDS = frozenset(
    {
        "aged", "baked", "bronze", "cast", "cloth", "copper", "crust",
        "fabric", "glass", "iron", "leather", "material", "metal", "metallic",
        "old", "paper", "plastic", "rubber", "steel", "stone", "weathered",
        "wood", "wooden", "worn",
    }
)
_MATERIAL_ONLY_CJK = re.compile(
    r"^(?:古旧|古老|老旧|破旧|风化|磨损|烘烤|氧化|木质|木制|木材|青铜|铜质|"
    r"金属|铁质|钢质|皮革|橡胶|纸张|塑料|石质|玻璃|布料|材质|表皮)+$"
)
_CANONICAL_EFFECT_WORDS = frozenset(
    {
        "electric", "electricity", "fire", "flame", "flaming", "frost", "ice",
        "lifesteal", "lightning", "poison", "returning", "steam", "weaponised",
        "weaponized",
    }
)
_CANONICAL_EFFECT_CJK = re.compile(
    r"吸血|电流|闪电|带电|火焰|喷火|冰雾|冰霜|蒸汽|毒液|回旋|返回|武器化|武装化"
)


def _tokens(value: str) -> set[str]:
    result: set[str] = set()
    for token in re.findall(r"[a-z0-9]+", unicodedata.normalize("NFKC", value).casefold()):
        if len(token) < 3 or token in _GENERIC_TOKENS:
            continue
        result.add(token)
        if len(token) > 4 and token.endswith("s") and not token.endswith("ss"):
            result.add(token[:-1])
    return result


def _structural_concepts(value: str) -> set[str]:
    return {
        concept
        for concept, aliases in _STRUCTURAL_CONCEPT_ALIASES.items()
        if any(_phrase_occurs(alias, value) for alias in aliases)
    }


def _feature_equivalent(left: str, right: str) -> bool:
    left_norm, right_norm = _normalized_phrase(left), _normalized_phrase(right)
    if left_norm and left_norm == right_norm:
        return True
    left_concepts = _structural_concepts(left)
    return bool(left_concepts and left_concepts.intersection(_structural_concepts(right)))


def _feature_overlap(left_values: Sequence[str], right_values: Sequence[str]) -> bool:
    return any(
        _feature_equivalent(left, right)
        for left in left_values
        for right in right_values
    )


def _material_only(value: str) -> bool:
    if _structural_concepts(value):
        return False
    normalized = _normalized_phrase(value)
    latin = re.findall(r"[a-z0-9]+", normalized)
    if latin and all(token in _MATERIAL_WORDS for token in latin):
        return True
    compact_cjk = "".join(re.findall(r"[\u3400-\u9fff]+", normalized))
    return bool(compact_cjk and _MATERIAL_ONLY_CJK.fullmatch(compact_cjk))


def _canonical_name_pollution(value: str) -> list[str]:
    normalized = _normalized_phrase(value)
    latin_tokens = set(re.findall(r"[a-z0-9]+", normalized))
    found = sorted(latin_tokens.intersection(_CANONICAL_EFFECT_WORDS))
    found.extend(sorted(set(_CANONICAL_EFFECT_CJK.findall(normalized))))
    return found


def _identity_v1_1_issues(identity: Mapping[str, Any]) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    for field in ("canonical_name_zh", "canonical_name_en"):
        polluted = _canonical_name_pollution(identity[field])
        if polluted:
            issues.append(
                ValidationIssue(
                    f"$.identity.{field}",
                    "canonical identity contains combat/effect modifiers: "
                    + ", ".join(polluted),
                )
            )
    for index, part in enumerate(identity["required_identity_parts"]):
        if _material_only(part):
            issues.append(
                ValidationIssue(
                    f"$.identity.required_identity_parts[{index}]",
                    "required identity part is material-only; move it to material_hints",
                )
            )
    identity_names = {
        _normalized_phrase(identity[field])
        for field in (
            "canonical_name_zh", "canonical_name_en", "display_name_zh", "display_name_en"
        )
    }
    for index, hint in enumerate(identity["silhouette_hints"]):
        if _normalized_phrase(hint) in identity_names:
            issues.append(
                ValidationIssue(
                    f"$.identity.silhouette_hints[{index}]",
                    "silhouette hint merely repeats an identity name",
                )
            )
    return issues


def _blueprint_issues(
    payload: Mapping[str, Any], *, legacy_v1: bool = False
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    combat, identity, visual = payload["combat"], payload["identity"], payload["visual"]
    family = combat["behavior_family"]
    if family == "sustained_ranged":
        if combat["delivery"] not in {"continuous_emission", "projectile_stream"}:
            issues.append(ValidationIssue("$.combat.delivery", "sustained_ranged requires continuous_emission or projectile_stream"))
        if combat["cadence_hint"] != "continuous":
            issues.append(ValidationIssue("$.combat.cadence_hint", "sustained_ranged requires continuous cadence_hint"))
    elif family == "returning_thrown":
        required = {
            "delivery": "whole_object_return",
            "impact_mode": "whole_body_collision",
            "cadence_hint": "single_commit",
            "drawback": "weapon_absent_while_flying",
        }
        for field, expected in required.items():
            if combat[field] != expected:
                issues.append(ValidationIssue(f"$.combat.{field}", f"returning_thrown requires {expected!r}"))
    elif family == "heavy_melee":
        if combat["delivery"] not in {"whole_object_strike", "melee_swing"}:
            issues.append(ValidationIssue("$.combat.delivery", "heavy_melee requires whole_object_strike or melee_swing"))
        if combat["impact_mode"] not in {"strike_edge", "strike_point", "whole_body_collision"}:
            issues.append(ValidationIssue("$.combat.impact_mode", "heavy_melee requires strike_edge, strike_point, or whole_body_collision"))
        if combat["cadence_hint"] != "slow_heavy":
            issues.append(ValidationIssue("$.combat.cadence_hint", "heavy_melee requires slow_heavy cadence_hint"))

    if not legacy_v1:
        issues.extend(_identity_v1_1_issues(identity))
    prompt = visual["prompt_en"]
    identity_name_en = identity["name_en"] if legacy_v1 else identity["canonical_name_en"]
    if not _phrase_occurs(identity_name_en, prompt):
        field = "name_en" if legacy_v1 else "canonical_name_en"
        issues.append(ValidationIssue("$.visual.prompt_en", f"positive prompt must contain identity.{field}"))
    if any(pattern.search(prompt) for pattern in _NEGATION_PATTERNS):
        issues.append(ValidationIssue("$.visual.prompt_en", "positive prompt contains a forbidden negative replacement phrase"))
    for replacement in visual["must_not_replace_with"]:
        if _phrase_occurs(replacement, prompt):
            issues.append(ValidationIssue("$.visual.prompt_en", f"positive prompt contains forbidden replacement item {replacement!r}"))
    identity_parts = (
        identity["preserved_features"]
        if legacy_v1
        else identity["required_identity_parts"]
    )
    if legacy_v1:
        if not _feature_overlap(identity_parts, visual["must_preserve"]):
            issues.append(
                ValidationIssue(
                    "$.visual.must_preserve",
                    "must_preserve has no approved structural equivalent in identity.preserved_features",
                )
            )
    else:
        missing = [
            part
            for part in identity_parts
            if not any(_feature_equivalent(part, candidate) for candidate in visual["must_preserve"])
        ]
        if missing:
            issues.append(
                ValidationIssue(
                    "$.visual.must_preserve",
                    "must_preserve lacks required identity parts: " + ", ".join(missing),
                )
            )
    return issues


def validate_semantic_blueprint(payload: Any) -> dict[str, Any]:
    forbidden = _forbidden_field_issues(payload)
    if forbidden:
        raise ContractValidationError(forbidden, stage="policy")
    validate_schema_instance(payload, FORGE_SEMANTIC_BLUEPRINT_SCHEMA)
    issues = _blueprint_issues(payload)
    if issues:
        raise ContractValidationError(issues, stage="cross_field")
    return payload


def validate_legacy_semantic_blueprint_v1(payload: Any) -> dict[str, Any]:
    """Replay frozen v1 evidence without mutating or migrating it.

    This function is forensic-only.  Production tool dispatch always uses the
    v1.1 schema and never unwraps, coerces, or repairs legacy model output.
    """

    forbidden = _forbidden_field_issues(payload)
    if forbidden:
        raise ContractValidationError(forbidden, stage="policy")
    validate_schema_instance(payload, LEGACY_FORGE_SEMANTIC_BLUEPRINT_SCHEMA_V1)
    issues = _blueprint_issues(payload, legacy_v1=True)
    if issues:
        raise ContractValidationError(issues, stage="cross_field")
    return payload


def _validate_clarification_cross_fields(payload: Mapping[str, Any]) -> None:
    question = payload["question_zh"].strip()
    if not re.search(r"[\u3400-\u9fff]", question) or re.search(r"[A-Za-z]", question):
        raise ContractValidationError(
            ValidationIssue("$.question_zh", "clarification must be written in Chinese"),
            stage="cross_field",
        )
    question_mark_count = question.count("?") + question.count("？")
    has_valid_ending = bool(
        re.search(r"[?？](?:[（(][^?？\r\n]{1,80}[）)])?$", question)
    )
    exclusive_choice = bool(re.search(r"还是|或是|或者", question))
    if question_mark_count < 1 or not has_valid_ending or (
        question_mark_count > 1
        and not (
            payload["ambiguity_type"] == "behavior_conflict" and exclusive_choice
        )
    ):
        raise ContractValidationError(
            ValidationIssue(
                "$.question_zh",
                "clarification must express one answer focus; repeated question marks are allowed only for one explicit behavior choice",
            ),
            stage="cross_field",
        )
    focus_markers = re.findall(
        r"什么|哪(?:个|种|一|类)|如何|怎样|怎么|是否|能否|要不要|是不是|为何|为什么|多少|多快|多大|多高",
        question,
    )
    if len(focus_markers) > 1:
        raise ContractValidationError(
            ValidationIssue(
                "$.question_zh",
                "clarification combines more than one interrogative focus",
            ),
            stage="cross_field",
        )
    identity_focus = bool(
        re.search(
            r"(?:什么|哪(?:个|种|一|类)|哪一类).{0,8}(?:物件|物品|东西|物体|主体|类别|名称)"
            r"|(?:物件|物品|东西|物体|主体|类别|名称).{0,8}(?:什么|哪(?:个|种|一|类)|哪一类|身份)"
            r"|是什么|叫什么|具体名称|身份",
            question,
        )
    )
    behavior_focus = bool(
        re.search(
            r"攻击|战斗|玩法|行为|怎么打|怎样打|如何打|发射|投掷|抛出|飞出|飞回|返回|挥击|近战|远程|喷火|喷射|释放火|哪种为主|哪个为主|何种为主",
            question,
        )
    )
    secondary_attribute_focus = bool(
        re.search(
            r"多快|速度.{0,10}(?:吗|呢|多少|多快|如何|怎样|怎么|应该)"
            r"|快(?:速)?(?:近战|远程)?吗"
            r"|什么颜色|哪种颜色|颜色.{0,10}(?:吗|呢|要|应该|什么|哪)"
            r"|伤害.{0,10}(?:高|大|多少|吗|呢|哪个|哪种)"
            r"|哪个.{0,8}伤害|什么效果|哪种效果|效果.{0,8}(?:吗|呢|什么|哪)",
            question,
        )
    )
    ambiguity_type = payload["ambiguity_type"]
    invalid_focus = bool(identity_focus and behavior_focus) or secondary_attribute_focus
    if ambiguity_type == "identity_unclear":
        invalid_focus = invalid_focus or not identity_focus
    elif ambiguity_type == "behavior_conflict":
        invalid_focus = (
            invalid_focus
            or not behavior_focus
            or not exclusive_choice
            or identity_focus
        )
    if invalid_focus:
        raise ContractValidationError(
            ValidationIssue(
                "$.question_zh",
                "clarification must ask only the single focus declared by ambiguity_type",
            ),
            stage="cross_field",
        )


def _validate_clarification_against_schema(
    payload: Any, schema: Mapping[str, Any]
) -> dict[str, Any]:
    forbidden = _forbidden_field_issues(payload)
    if forbidden:
        raise ContractValidationError(forbidden, stage="policy")
    validate_schema_instance(payload, schema)
    _validate_clarification_cross_fields(payload)
    return payload


def validate_clarification_request(payload: Any) -> dict[str, Any]:
    """Validate production v1.1 clarification input without coercion.

    ``known_action_hints`` is array-only on this live path.  The sole tool
    dispatch function below calls only this validator.
    """

    return _validate_clarification_against_schema(
        payload, CLARIFICATION_REQUEST_SCHEMA
    )


def validate_forensic_clarification_request(payload: Any) -> dict[str, Any]:
    """Replay frozen clarification evidence without enabling it in production.

    The historical Case 17 response used one scalar ``known_action_hints``
    value.  This offline-only validator preserves that evidence byte-for-byte;
    it never coerces the scalar and is deliberately absent from
    :func:`validate_tool_input` and ``TOOL_SCHEMAS``.
    """

    return _validate_clarification_against_schema(
        payload, FORENSIC_CLARIFICATION_REQUEST_SCHEMA
    )


def validate_tool_input(tool_name: str, payload: Any) -> dict[str, Any]:
    if tool_name == SUBMIT_BLUEPRINT_TOOL:
        return validate_semantic_blueprint(payload)
    if tool_name == REQUEST_CLARIFICATION_TOOL:
        return validate_clarification_request(payload)
    raise ContractValidationError(ValidationIssue("$.tool_name", f"unknown tool {tool_name!r}"))


validate_forge_semantic_blueprint = validate_semantic_blueprint
validate_clarification = validate_clarification_request

__all__ = [
    "ALLOWED_TOOL_NAMES", "CLARIFICATION_REQUEST_SCHEMA", "CONTRACT_VERSION",
    "ContractValidationError", "FORENSIC_CLARIFICATION_REQUEST_SCHEMA",
    "FORGE_SEMANTIC_BLUEPRINT_SCHEMA", "FORGE_SEMANTIC_BLUEPRINT_SCHEMA_V1_1",
    "LEGACY_FORGE_SEMANTIC_BLUEPRINT_SCHEMA_V1", "REQUEST_CLARIFICATION_TOOL",
    "SUBMIT_BLUEPRINT_TOOL", "SchemaValidationError", "TOOL_SCHEMAS",
    "ValidationIssue", "schema_for_tool", "validate_clarification",
    "validate_clarification_request", "validate_forge_semantic_blueprint",
    "validate_forensic_clarification_request",
    "validate_legacy_semantic_blueprint_v1", "validate_schema_instance",
    "validate_semantic_blueprint", "validate_tool_input",
]
