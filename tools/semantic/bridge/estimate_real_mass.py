"""Ask Claude for an object's real-world mass and write a v1.4 affordance sidecar.

The mass counterpart of `estimate_real_length.py`, and deliberately the same shape. It
answers the question that actually matters: can the model say how heavy an object is,
given only what the blueprint says about it?

A rendered image cannot answer that. T60 retired measuring mass off the drawing because
ink area saturates -- `280x30` and `280x60` both measure 1.000, so the picture cannot
tell a hammer from a shield. Real kilograms are exactly what geometry cannot see, which
is the case T73/T74 reserve for asking the model. Deliberately no image input: passing
the sprite would invite the model to judge the picture instead of recalling the thing.

Deliberately no `real_length_cm` input either, even though the v1.3 sidecar already
carries one. Mass is meant to be an axis of its own -- a wooden spoon and an iron bar of
the same length differ tenfold -- and feeding the length in would make this estimate
partly a density calculation off the other axis, so a length error would propagate into
mass and the two fields would stop being independent evidence.

Requires ANTHROPIC_API_KEY (or an `ant auth login` profile) and the `anthropic` package.

Usage:
    python estimate_real_mass.py <semantic_blueprint.json> <v1_3_profile.json> <output.json>
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import anthropic

sys.path.insert(0, str(Path(__file__).resolve().parent))

from affordance_contract_v1_4 import (  # noqa: E402
    MAX_REAL_MASS_KG,
    MIN_REAL_MASS_KG,
    upgrade_profile_to_v1_4,
    validate_real_mass_kg,
)


MODEL = "claude-opus-5"

# Structured outputs reject numeric bounds (minimum/maximum) and string-length bounds,
# so the range lives in the description and is enforced client-side after the call.
ESTIMATE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["real_mass_kg", "basis"],
    "properties": {
        "real_mass_kg": {
            "type": "number",
            "description": (
                "Mass of the real object in kilograms, between "
                f"{MIN_REAL_MASS_KG:g} and {MAX_REAL_MASS_KG:g}."
            ),
        },
        "basis": {
            "type": "string",
            "description": "The everyday reference the estimate is anchored to, in one short phrase.",
        },
    },
}

SYSTEM = (
    "You estimate the physical mass of real objects. Estimate the object itself, not any "
    "picture of it: a rendered sprite fills its canvas whatever the subject, and the area "
    "a drawing covers says nothing about how heavy the thing is. Give the mass of a "
    "typical example in kilograms. Order of magnitude is what matters -- a chicken leg is "
    "a fraction of a kilogram, a sledgehammer is several. Anchor the estimate to an "
    "everyday reference.\n\n"
    "Material is usually the deciding factor. Two objects the same size can differ "
    "tenfold: a wooden spoon and an iron bar of the same length are not close. Read the "
    "material hints before answering, and weigh the whole object as it would be picked "
    "up, including handle and fittings.\n\n"
    "The canonical name is deliberately stripped of modifiers, so size words live in the "
    "display name and the silhouette hints. Size words there ('giant', 'oversized', "
    "'miniature') describe the real object and must change your estimate; combat flavour "
    "words ('battle', 'cursed', 'mighty') must not. Treat 'heavy' in a name as flavour "
    "unless the material or the stated size supports it -- a name is not a measurement."
)


def estimate_real_mass_kg(client: anthropic.Anthropic, blueprint: dict) -> dict:
    identity = blueprint.get("identity", {})
    # display_name carries the size modifier and must be sent. The canonical name is
    # deliberately stripped of modifiers upstream (contract v1.2.1 exists to keep
    # combat/effect words out of it), so "Giant Battle Wooden Spoon" has a
    # canonical_name_en of plain "wooden spoon". Omitting display_name asks the model
    # about the wrong object -- the same defect P06 found in the length estimator, where
    # it answered a correct and useless 30cm for a spoon that is meant to be huge.
    description = json.dumps(
        {
            "canonical_name_en": identity.get("canonical_name_en"),
            "canonical_name_zh": identity.get("canonical_name_zh"),
            "display_name_en": identity.get("display_name_en"),
            "display_name_zh": identity.get("display_name_zh"),
            "category": identity.get("category"),
            "required_identity_parts": identity.get("required_identity_parts"),
            "material_hints": identity.get("material_hints"),
            "silhouette_hints": identity.get("silhouette_hints"),
        },
        ensure_ascii=False,
        indent=2,
    )
    response = client.messages.create(
        model=MODEL,
        max_tokens=16000,
        system=SYSTEM,
        output_config={
            "effort": "low",
            "format": {"type": "json_schema", "schema": ESTIMATE_SCHEMA},
        },
        messages=[{"role": "user", "content": f"How heavy is this object?\n\n{description}"}],
    )
    # Safety classifiers can decline a request: HTTP 200 with an empty or partial body.
    if response.stop_reason == "refusal":
        raise RuntimeError(f"model declined the request: {response.stop_details}")
    text = next(block.text for block in response.content if block.type == "text")
    estimate = json.loads(text)
    # The schema cannot carry the bounds, so an out-of-range answer has to fail here
    # rather than travel on as if the contract had vetted it.
    validate_real_mass_kg(estimate["real_mass_kg"])
    return estimate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("semantic_blueprint", type=Path)
    parser.add_argument("affordance_profile", type=Path, help="the object's existing v1.3 profile")
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()

    blueprint = json.loads(args.semantic_blueprint.read_text(encoding="utf-8"))
    profile = json.loads(args.affordance_profile.read_text(encoding="utf-8"))

    estimate = estimate_real_mass_kg(anthropic.Anthropic(), blueprint)
    upgraded = upgrade_profile_to_v1_4(profile, estimate["real_mass_kg"])

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(upgraded, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": "success",
        "provenance": "model_estimate",
        "model": MODEL,
        "real_mass_kg": estimate["real_mass_kg"],
        "basis": estimate["basis"],
        "path": str(args.output_json),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
