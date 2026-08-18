"""Rank every affordance axis by how many collisions it could still break. Follows P13.

P13 asked one axis -- rigidity -- whether it separates objects that compile to the same
primitive sequence, and found it splits two of three colliding groups and four of seven
colliding pairs. Those four are now built. This asks the same question of every other axis
the contract already carries, so the next one is chosen by measurement rather than by
which field sounds promising.

The point is not to find a new field. P12 established that several existing axes reach
nothing categorical at all -- they feed a scoring table that contact_surface already
decides. An axis that splits the remaining pairs is one that needs an outlet, which is
exactly what rigidity needed.

Usage:
    python tools/combat_feel/rank_axes_by_collision_split.py
"""

from __future__ import annotations

import csv
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MATRIX = next((REPO_ROOT / "tools" / "semantic" / "reports").rglob("coverage_matrix.csv"), None)

# Order of the slash-joined affordance_axes column.
AXES = [
    "handle_length", "body_length", "grip_topology", "rigidity",
    "mass_distribution", "contact_surface", "declared_features",
]


def axis_value(row: dict, index: int) -> str:
    parts = row["affordance_axes"].split("/")
    return parts[index] if len(parts) > index else "?"


def main() -> None:
    if MATRIX is None:
        print("coverage_matrix.csv not found.")
        return
    rows = list(csv.DictReader(MATRIX.open(encoding="utf-8")))

    groups: dict[str, list[dict]] = {}
    for row in rows:
        groups.setdefault(row["primitive_sequence"], []).append(row)
    colliding = {seq: members for seq, members in groups.items() if len(members) > 1}

    total_pairs = sum(len(m) * (len(m) - 1) // 2 for m in colliding.values())
    print("=" * 76)
    print("Which axes could still break a collision?")
    print("=" * 76)
    print(f"\n{len(rows)} objects, {len(groups)} sequences, "
          f"{len(colliding)} colliding groups, {total_pairs} colliding pairs\n")

    ranked = []
    for index, name in enumerate(AXES):
        groups_split = 0
        pairs_split = 0
        for members in colliding.values():
            values = [axis_value(m, index) for m in members]
            if len(set(values)) > 1:
                groups_split += 1
            for i in range(len(values)):
                for j in range(i + 1, len(values)):
                    if values[i] != values[j]:
                        pairs_split += 1
        ranked.append((pairs_split, groups_split, name, index))

    ranked.sort(reverse=True)
    print(f"  {'axis':<20} {'groups':>8} {'pairs':>8}   {'already has an outlet?':<24}")
    outlets = {
        "contact_surface": "yes -- selection (P12)",
        "rigidity": "yes -- impact (1B)",
    }
    for pairs_split, groups_split, name, _ in ranked:
        print(f"  {name:<20} {groups_split:>4}/{len(colliding):<3} {pairs_split:>4}/{total_pairs:<3}"
              f"   {outlets.get(name, 'no'):<24}")

    print("\n[the pairs nothing has broken yet]")
    for seq, members in sorted(colliding.items()):
        names = [m["identity"] for m in members]
        for i in range(len(members)):
            for j in range(i + 1, len(members)):
                if axis_value(members[i], 3) != axis_value(members[j], 3):
                    continue  # rigidity already splits this one
                splitters = [
                    AXES[k] for k in range(len(AXES))
                    if axis_value(members[i], k) != axis_value(members[j], k)
                ]
                print(f"  {names[i]} / {names[j]}   [{seq}]")
                print(f"    differ on: {', '.join(splitters) if splitters else 'NOTHING'}")


if __name__ == "__main__":
    main()
