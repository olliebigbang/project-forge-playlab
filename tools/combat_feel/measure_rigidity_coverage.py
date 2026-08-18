"""Census every value of a categorical axis the estimator has ever produced. Evidence for P13.

The 1B spec derives contact_resolution's soft branch from `rigidity != rigid`. That is
only worth building if rigidity actually varies across real objects. This walks every
affordance profile in the repository -- shipped sidecars, proof-of-concept artifacts and
the anonymised handoff sets alike -- and counts what the estimator returned.

It also prints the material_hints recorded in each shipped semantic blueprint, because
those are the same objects and the free text is where the compliance signal turns out to
have survived.

Takes the axis name as an optional argument so the same question can be put to any
categorical field; it defaults to rigidity, which is what P13 cites.

Usage:
    python tools/combat_feel/measure_rigidity_coverage.py [axis]
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AXIS = sys.argv[1] if len(sys.argv) > 1 else "rigidity"
VALUES = {
    "rigidity": ("rigid", "semi_rigid", "flexible"),
    "grip_topology": ("one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"),
    "mass_distribution": ("rear", "balanced", "front"),
    "contact_surface": ("point", "edge", "broad", "whole_body"),
}.get(AXIS)


def profiles() -> list[tuple[str, str, str, str]]:
    """Return (group, label, rigidity, contact_surface) for every affordance profile."""
    found = []
    for path in sorted(REPO_ROOT.rglob("*.json")):
        if ".git" in path.parts:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError, OSError):
            continue
        if not isinstance(data, dict) or AXIS not in data:
            continue
        label = path.parent.name
        if label in ("affordance_v1_3", "affordance_v1_4", "affordance_profiles"):
            label = path.stem
        group = str(path.relative_to(REPO_ROOT).parts[0])
        if "affordance_profiles" in path.parts:
            group = "anonymised handoff"
        elif group == "artifacts":
            group = "proof of concept"
        elif group == "data":
            group = "shipped sidecar"
        found.append((group, label, str(data.get(AXIS)), str(data.get("contact_surface"))))
    return found


def main() -> None:
    rows = profiles()
    if not rows:
        print("No affordance profiles found.")
        return

    print("=" * 74)
    print("P13 evidence -- what %s actually returns" % AXIS)
    print("=" * 74)

    by_group: dict[str, list[tuple[str, str, str, str]]] = {}
    for row in rows:
        by_group.setdefault(row[0], []).append(row)

    for group in sorted(by_group):
        entries = by_group[group]
        print(f"\n[{group}]  {len(entries)} profiles")
        counts = collections.Counter(entry[2] for entry in entries)
        for value in (VALUES or sorted(counts)):
            print(f"  {value:<18} {counts.get(value, 0)}")

    print("\n[all profiles combined]")
    counts = collections.Counter(row[2] for row in rows)
    total = sum(counts.values())
    for value in (VALUES or sorted(counts)):
        n = counts.get(value, 0)
        print(f"  {value:<18} {n:>3}   {100.0 * n / total:5.1f}%")
    print(f"  {'total':<12} {total:>3}")

    print("\n[contact_surface, for comparison -- the axis P12 found decisive]")
    surfaces = collections.Counter(row[3] for row in rows)
    for value, n in surfaces.most_common():
        print(f"  {value:<12} {n:>3}   {100.0 * n / total:5.1f}%")

    print("\n[material_hints in shipped semantic blueprints]")
    for path in sorted((REPO_ROOT / "data").rglob("semantic_blueprint.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        hints = data.get("identity", {}).get("material_hints", [])
        print(f"  {path.parent.name:<36} {hints}")


if __name__ == "__main__":
    main()
