"""Ask whether evidence_parts already separates a striking end from a grip. Evidence for P13's
follow-up.

P13 found `rigidity` near-constant, and found the reason is not the estimator: asked about a
chicken leg the model answered `semi_rigid` and wrote "bulbous meat mass at striking end".
The reasoning reaches the contact end; the three-value enum is where it is lost.

This measures whether that is true in general or true once. For every affordance profile
carrying `evidence_parts`, it splits the listed parts into the ones naming a striking end and
the ones naming a grip, reads a material out of each, and reports how often the two differ.

An axis is worth asking the model for only if the answer is already latent in what it
volunteers. This does not build the axis and does not score separability -- there is no
compliance scale yet to score against. It answers the prior question: is there anything here.

The material lexicon and the part-role keywords below are HAND-AUTHORED, not model output.
They are a reading of the model's text, and a different reading would move the counts.

Usage:
    python tools/combat_feel/measure_contact_end_material.py
"""

from __future__ import annotations

import collections
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Hand-authored. Tier is how much the material yields where it lands, not how strong it is.
MATERIAL_TIER = {
    "steel": "hard", "iron": "hard", "metal": "hard", "bronze": "hard", "blade": "hard",
    "stone": "hard", "glass": "hard", "ceramic": "hard",
    "wood": "firm", "wooden": "firm", "bone": "firm", "plastic": "firm", "cork": "firm",
    "bamboo": "firm",
    "meat": "yielding", "flesh": "yielding", "meaty": "yielding", "rubber": "yielding",
    "leather": "yielding", "padded": "yielding", "foam": "yielding",
    "cloth": "soft", "fabric": "soft", "cotton": "soft", "rope": "soft", "straw": "soft",
    "bristle": "soft",
}

CONTACT_WORDS = ("striking", "strike", "impact", "head", "tip", "edge", "face", "blade",
                 "end", "mass", "point", "spearhead", "barrel", "nozzle", "seat", "rim")
GRIP_WORDS = ("handle", "grip", "shaft", "haft", "stock", "hold", "held", "grasp")


def material_of(text: str) -> str | None:
    for word, tier in MATERIAL_TIER.items():
        if re.search(r"\b" + word, text.lower()):
            return tier
    return None


def role_of(text: str) -> str | None:
    low = text.lower()
    grip = any(w in low for w in GRIP_WORDS)
    contact = any(w in low for w in CONTACT_WORDS)
    if grip and not contact:
        return "grip"
    if contact and not grip:
        return "contact"
    return None


def profiles() -> list[tuple[str, dict]]:
    found = []
    for path in sorted(REPO_ROOT.rglob("*.json")):
        if ".git" in path.parts:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError, OSError):
            continue
        if not isinstance(data, dict) or "evidence_parts" not in data:
            continue
        if "rigidity" not in data:
            continue
        label = path.parent.name
        if label in ("affordance_v1_3", "affordance_v1_4", "affordance_profiles"):
            label = path.stem
        found.append((label, data))
    # one row per object, preferring the entry with the most parts
    best: dict[str, dict] = {}
    for label, data in found:
        if label not in best or len(data["evidence_parts"]) > len(best[label]["evidence_parts"]):
            best[label] = data
    return sorted(best.items())


def main() -> None:
    rows = profiles()
    print("=" * 78)
    print("Does evidence_parts already name a striking end and a grip separately?")
    print("=" * 78)

    split_count = 0
    contact_tiers: list[str] = []
    print(f"\n  {'object':<22} {'rigidity':<11} {'grip':<9} {'contact':<9} differ")
    for label, data in rows:
        grip_tier = contact_tier = None
        for part in data["evidence_parts"]:
            role, tier = role_of(part), material_of(part)
            if tier is None or role is None:
                continue
            if role == "grip" and grip_tier is None:
                grip_tier = tier
            if role == "contact" and contact_tier is None:
                contact_tier = tier
        differ = bool(grip_tier and contact_tier and grip_tier != contact_tier)
        split_count += differ
        if contact_tier:
            contact_tiers.append(contact_tier)
        print(
            f"  {label:<22} {str(data.get('rigidity')):<11} "
            f"{str(grip_tier or '-'):<9} {str(contact_tier or '-'):<9} {'YES' if differ else ''}"
        )

    print(f"\n  objects examined                       : {len(rows)}")
    print(f"  naming a different material at each end : {split_count}")
    print(f"  contact-end material readable at all    : {len(contact_tiers)}")

    print("\n[distribution: contact-end material tier vs the rigidity enum]")
    tiers = collections.Counter(contact_tiers)
    rigid = collections.Counter(str(d.get("rigidity")) for _, d in rows)
    total_t = sum(tiers.values()) or 1
    total_r = sum(rigid.values()) or 1
    print("  contact-end tier")
    for value in ("hard", "firm", "yielding", "soft"):
        n = tiers.get(value, 0)
        print(f"    {value:<10} {n:>3}   {100.0 * n / total_t:5.1f}%")
    print("  rigidity")
    for value in ("rigid", "semi_rigid", "flexible"):
        n = rigid.get(value, 0)
        print(f"    {value:<10} {n:>3}   {100.0 * n / total_r:5.1f}%")

    if tiers:
        worst_t = max(tiers.values()) / total_t
        worst_r = max(rigid.values()) / total_r
        print(f"\n  largest single class: contact-end {100.0 * worst_t:.1f}%  "
              f"vs rigidity {100.0 * worst_r:.1f}%")


if __name__ == "__main__":
    main()
