"""Ask Claude for an object's real-world length and write a v1.3 affordance sidecar.

This is the real version of `author_v1_3_sidecars.py`, which hand-authors the same
number offline. It answers the question that actually matters: can the model estimate
how big an object is in the world, given only what the blueprint says about it?

A rendered image cannot answer that -- generators fill the canvas whatever the subject
-- so the estimate has to come from the model's knowledge of the object, not from
pixels. Deliberately no image input: passing the sprite would invite the model to
measure the picture instead of recalling the thing.

Requires ANTHROPIC_API_KEY (or an `ant auth login` profile) and the `anthropic` package.

Usage:
    python estimate_real_length.py <semantic_blueprint.json> <v1_2_profile.json> <output.json>
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import anthropic

sys.path.insert(0, str(Path(__file__).resolve().parent))

from affordance_contract_v1_3 import (  # noqa: E402
    MAX_REAL_LENGTH_CM,
    MIN_REAL_LENGTH_CM,
    upgrade_profile_to_v1_3,
    validate_real_length_cm,
)


MODEL = "claude-opus-5"

# Structured outputs reject numeric bounds (minimum/maximum) and string-length bounds,
# so the range lives in the description and is enforced client-side after the call.
ESTIMATE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["real_length_cm", "basis"],
    "properties": {
        "real_length_cm": {
            "type": "number",
            "description": (
                "Longest dimension of the real object in centimetres, between "
                f"{MIN_REAL_LENGTH_CM:g} and {MAX_REAL_LENGTH_CM:g}."
            ),
        },
        "basis": {
            "type": "string",
            "description": "The everyday reference the estimate is anchored to, in one short phrase.",
        },
    },
}

SYSTEM = (
    "You estimate the physical size of real objects. Estimate the object itself, not any "
    "picture of it: a rendered sprite fills its canvas whatever the subject, so image size "
    "carries no information about real size. Give the longest dimension of a typical example "
    "in centimetres. Order of magnitude is what matters -- a frying pan is tens of "
    "centimetres, a mop is over a metre. Anchor the estimate to an everyday reference.\n\n"
    "The canonical name is deliberately stripped of modifiers, so size words live in the "
    "display name and the silhouette hints. Size words there ('giant', 'oversized', "
    "'miniature') describe the real object and must change your estimate; combat flavour "
    "words ('battle', 'heavy', 'cursed') must not."
)


def estimate_real_length_cm(client: anthropic.Anthropic, blueprint: dict) -> dict:
    identity = blueprint.get("identity", {})
    # display_name carries the size modifier and must be sent. The canonical name is
    # deliberately stripped of modifiers upstream (contract v1.2.1 exists to keep
    # combat/effect words out of it), so "Giant Battle Wooden Spoon" has a
    # canonical_name_en of plain "wooden spoon". Omitting display_name asks the model
    # about the wrong object -- it answered 30cm for a spoon that is meant to be huge.
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
        messages=[{"role": "user", "content": f"How long is this object?\n\n{description}"}],
    )
    # Safety classifiers can decline a request: HTTP 200 with an empty or partial body.
    if response.stop_reason == "refusal":
        raise RuntimeError(f"model declined the request: {response.stop_details}")
    text = next(block.text for block in response.content if block.type == "text")
    estimate = json.loads(text)
    # The schema cannot carry the bounds, so an out-of-range answer has to fail here
    # rather than travel on as if the contract had vetted it.
    validate_real_length_cm(estimate["real_length_cm"])
    return estimate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("semantic_blueprint", type=Path)
    parser.add_argument("affordance_profile", type=Path, help="the object's existing v1.2 profile")
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()

    blueprint = json.loads(args.semantic_blueprint.read_text(encoding="utf-8"))
    profile = json.loads(args.affordance_profile.read_text(encoding="utf-8"))

    estimate = estimate_real_length_cm(anthropic.Anthropic(), blueprint)
    upgraded = upgrade_profile_to_v1_3(profile, estimate["real_length_cm"])

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(upgraded, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": "success",
        "provenance": "model_estimate",
        "model": MODEL,
        "real_length_cm": estimate["real_length_cm"],
        "basis": estimate["basis"],
        "path": str(args.output_json),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
