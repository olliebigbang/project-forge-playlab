"""Ask whether rigidity separates objects that already collide. Corrects P13's test.

P13 counted how often `rigidity` returns each value across every profile and found 78%
`rigid`, then concluded the field cannot carry a categorical impact layer. That is the
marginal distribution, and it is the wrong question. An impact axis never has to tell
apart two objects that already swing differently -- P12 showed contact_surface reaches
selection from every baseline, so those objects are already distinguished upstream.

What the axis has to do is separate objects that compile to the SAME primitive sequence.
This groups the handoff cases by their compiled sequence and asks, inside each group,
whether rigidity splits it.

Reads the v1.2.1 combined handoff coverage matrix, which carries identity, affordance
axes and the compiled sequence in one row.

Usage:
    python tools/combat_feel/measure_within_collision_split.py
"""

from __future__ import annotations

import collections
import csv
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MATRIX = next(
    (REPO_ROOT / "tools" / "semantic" / "reports").rglob("coverage_matrix.csv"), None
)


def axis(row: dict, index: int) -> str:
    parts = row["affordance_axes"].split("/")
    return parts[index] if len(parts) > index else "?"


def main() -> None:
    if MATRIX is None:
        print("coverage_matrix.csv not found.")
        return
    rows = list(csv.DictReader(MATRIX.open(encoding="utf-8")))

    print("=" * 78)
    print("Does rigidity separate objects that share a compiled primitive sequence?")
    print("=" * 78)
    print(f"\nsource: {MATRIX.relative_to(REPO_ROOT)}   cases: {len(rows)}")

    groups: dict[str, list[dict]] = {}
    for row in rows:
        groups.setdefault(row["primitive_sequence"], []).append(row)

    colliding = {seq: members for seq, members in groups.items() if len(members) > 1}
    singles = len(groups) - len(colliding)

    print(f"\ndistinct sequences: {len(groups)}   "
          f"reached by one object: {singles}   colliding: {len(colliding)}")

    split_ok = 0
    total_pairs = 0
    unsplit_pairs = 0
    for seq, members in sorted(colliding.items(), key=lambda kv: -len(kv[1])):
        rigidities = [axis(m, 3) for m in members]
        distinct = len(set(rigidities))
        splits = distinct > 1
        split_ok += splits
        print(f"\n  [{seq}]  {len(members)} objects")
        for member, rig in zip(members, rigidities):
            print(f"    {member['case_id']:<5} {member['identity']:<10} "
                  f"rigidity={rig:<11} contact={axis(member, 5)}")
        print(f"    -> rigidity values: {sorted(set(rigidities))}  "
              f"{'SPLITS the group' if splits else 'does not split'}")
        n = len(members)
        pairs = n * (n - 1) // 2
        total_pairs += pairs
        same = sum(
            1
            for i in range(n)
            for j in range(i + 1, n)
            if rigidities[i] == rigidities[j]
        )
        unsplit_pairs += same

    print("\n" + "-" * 78)
    print(f"colliding groups rigidity splits : {split_ok} of {len(colliding)}")
    print(f"colliding pairs                  : {total_pairs}")
    print(f"still identical after rigidity   : {unsplit_pairs}")
    print(f"separated by rigidity            : {total_pairs - unsplit_pairs}")

    print("\n[for contrast: the marginal distribution P13 measured]")
    marginal = collections.Counter(axis(row, 3) for row in rows)
    total = sum(marginal.values())
    for value, n in marginal.most_common():
        print(f"  {value:<12} {n:>3}   {100.0 * n / total:5.1f}%")


if __name__ == "__main__":
    main()
