#!/usr/bin/env python3
"""Project a validated semantic blueprint into a static-only FLUX prompt.

This module never changes the semantic blueprint.  It creates a separate visual
handoff containing only identity fields from the blueprint plus one generic,
effect-type-to-physical-fixture mapping.  Runtime trails remain a Godot concern.
"""

from __future__ import annotations

import copy
import re
from typing import Any, Mapping


PROJECTION_CONTRACT = "forge-live-static-visual-projection-v1"

PHYSICAL_FIXTURES: dict[str, tuple[str, ...]] = {
    "normal": ("a small neutral forge functional fixture",),
    "fire": ("a compact heated core", "an ember-colored physical fixture"),
    "electric": ("compact conductive coils", "an insulated electric core"),
    "ice": ("a compact insulated frost core", "a cold-metal vent fixture"),
    "steam": ("a pressure valve", "a reinforced physical spout"),
    "lifesteal": ("a sealed crimson reservoir", "a solid runic intake fixture"),
    "fastener": ("a mechanical feed port", "a compact fastener magazine"),
    "poison": ("a sealed toxic reservoir", "a green glass chamber"),
    "sound": ("a compact resonant chamber", "a reinforced acoustic aperture"),
    "light": ("a luminous lens", "a compact crystal emitter"),
    "other": ("a small neutral forge functional fixture",),
}

DYNAMIC_VISUAL_TERMS = (
    "trail", "stream", "beam", "projectile", "bullet", "missile", "return arc",
    "motion blur", "floating flame", "floating fire", "floating electricity",
    "lightning arc", "steam cloud", "mist cloud", "ice mist", "frost cloud",
    "acid flow", "blood energy", "large glow", "combat scene", "action scene",
)

GENERIC_STATIC_POSITIVE = (
    "one isolated handcrafted fantasy game prop; complete object visible; single subject; "
    "side view or slight three-quarter side view; facing right; readable silhouette; "
    "clear holdable region; clear solid functional fixture; flat high-contrast magenta "
    "studio background; object centered with generous empty margin; no crop"
)

GENERIC_STATIC_NEGATIVE = (
    "person, human, face, hand, character holding object, text, label, logo, watermark, UI, "
    "inventory grid, weapon sheet, multiple views, multiple objects, scenery, room, floor, "
    "ground shadow, cropped object, gun substitution, gatling substitution, sword substitution, "
    "greatsword substitution, umbrella substitution, boomerang substitution, dynamic trail, "
    "fire trail, electric trail, steam cloud, floating mist, acid stream, projectile, bullet, "
    "blood energy, return trail, motion blur, large glowing smoke"
)


class StaticProjectionError(ValueError):
    pass


def _string_list(value: Any, path: str, *, allow_empty: bool = True) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item.strip() for item in value):
        raise StaticProjectionError(f"{path}:NONEMPTY_STRING_ARRAY_REQUIRED")
    result = [item.strip() for item in value]
    if not allow_empty and not result:
        raise StaticProjectionError(f"{path}:MUST_NOT_BE_EMPTY")
    return result


def _ascii(value: str) -> str:
    if not value.isascii():
        raise StaticProjectionError("STATIC_FLUX_PROMPT_MUST_BE_ASCII")
    return value


def _contains_dynamic_term(value: str) -> str | None:
    lowered = re.sub(r"\s+", " ", value.lower())
    return next((term for term in DYNAMIC_VISUAL_TERMS if term in lowered), None)


def project_static_visual(blueprint: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    identity = blueprint.get("identity")
    combat = blueprint.get("combat")
    visual = blueprint.get("visual")
    if not isinstance(identity, Mapping) or not isinstance(combat, Mapping) or not isinstance(visual, Mapping):
        raise StaticProjectionError("BLUEPRINT_IDENTITY_COMBAT_VISUAL_REQUIRED")

    canonical = str(identity.get("canonical_name_en", "")).strip()
    if not canonical or not canonical.isascii():
        raise StaticProjectionError("CANONICAL_NAME_EN_INVALID")
    required = _string_list(identity.get("required_identity_parts"), "/identity/required_identity_parts", allow_empty=False)
    materials = _string_list(identity.get("material_hints"), "/identity/material_hints")
    silhouette = _string_list(identity.get("silhouette_hints"), "/identity/silhouette_hints")
    decorations = _string_list(identity.get("optional_decorations"), "/identity/optional_decorations")
    source_visual_prompt = str(visual.get("prompt_en", "")).strip()
    source_negative = str(visual.get("negative_prompt_en", "")).strip()
    must_preserve = _string_list(visual.get("must_preserve"), "/visual/must_preserve")
    must_not_replace = _string_list(visual.get("must_not_replace_with"), "/visual/must_not_replace_with")
    effect_type = str(combat.get("effect_type", "normal"))
    fixture = PHYSICAL_FIXTURES.get(effect_type, PHYSICAL_FIXTURES["other"])

    clauses = [
        f"canonical object identity: {canonical}",
        "identity-critical physical parts: " + ", ".join(required),
    ]
    if materials:
        clauses.append("physical material cues: " + ", ".join(materials))
    if silhouette:
        clauses.append("silhouette cues: " + ", ".join(silhouette))
    if decorations:
        clauses.append("optional small forge decorations only: " + ", ".join(decorations))
    clauses.append("solid effect fixture: " + ", ".join(fixture))
    clauses.append(GENERIC_STATIC_POSITIVE)
    static_prompt = _ascii("; ".join(clauses))
    dynamic_match = _contains_dynamic_term(static_prompt)
    if dynamic_match:
        raise StaticProjectionError(f"DYNAMIC_TERM_LEAKED_TO_STATIC_PROMPT:{dynamic_match}")

    negative_clauses = [GENERIC_STATIC_NEGATIVE]
    if source_negative and source_negative.isascii():
        negative_clauses.append(source_negative)
    if must_not_replace:
        negative_clauses.append("do not replace with: " + ", ".join(must_not_replace))
    static_negative = _ascii("; ".join(negative_clauses))

    projected = copy.deepcopy(dict(blueprint))
    projected["visual"] = {
        "prompt_en": static_prompt,
        "negative_prompt_en": static_negative,
        "must_preserve": required,
        "must_not_replace_with": must_not_replace,
    }
    evidence = {
        "contract": PROJECTION_CONTRACT,
        "semantic_blueprint_modified": False,
        "source_fields": [
            "identity.canonical_name_en",
            "identity.required_identity_parts",
            "identity.material_hints",
            "identity.silhouette_hints",
            "identity.optional_decorations",
            "visual.prompt_en",
            "visual.negative_prompt_en",
            "visual.must_preserve",
            "visual.must_not_replace_with",
            "combat.effect_type",
        ],
        "source_visual_prompt": source_visual_prompt,
        "effect_type": effect_type,
        "physical_fixture_terms": list(fixture),
        "static_prompt_en": static_prompt,
        "static_negative_prompt_en": static_negative,
        "dynamic_term_scan": "PASS",
    }
    return projected, evidence


__all__ = [
    "DYNAMIC_VISUAL_TERMS",
    "PHYSICAL_FIXTURES",
    "PROJECTION_CONTRACT",
    "StaticProjectionError",
    "project_static_visual",
]
