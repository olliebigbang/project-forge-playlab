"""Ask whether the mass split resolves what rigidity left. Follows P13.

P13 measured rigidity inside collision groups: of seven colliding pairs it separates four
and leaves three, all same-rigidity. Those three are the remaining target. This asks
whether contact_resolution's other half -- the theta split on the mass axis -- takes any
of them, using the probe masses and the compiler's own compression.

Theta = 0.538 comes from measure_contact_resolution.py: the midpoint of the widest gap
between adjacent rigid objects, 2.9x P09's noise floor away from the nearest one.

Usage:
    python tools/combat_feel/measure_remaining_collisions.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MASS_PROBE = REPO_ROOT / "artifacts" / "mass_probe_v1" / "raw_estimates.json"

AXIS_MIN, AXIS_MAX = 0.35, 1.00
MASS_FLOOR_KG, MASS_CEILING_KG = 0.15, 8.0
NOISE_FLOOR = 0.065
THETA = 0.538

# The three pairs P13 left: same rigidity, same compiled primitive sequence.
PAIRS = [
    ("bash -> slam -> bash", "baseball_bat", "stool"),
    ("sweep -> spin -> slam", "wooden_chair", "fire_extinguisher"),
    ("sweep -> thrust -> slam", "sword", "axe"),
]


def mass_axis(mass_kg: float) -> float:
    span = math.log(MASS_CEILING_KG) - math.log(MASS_FLOOR_KG)
    position = (math.log(max(mass_kg, MASS_FLOOR_KG * 0.01)) - math.log(MASS_FLOOR_KG)) / span
    return AXIS_MIN + max(0.0, min(1.0, position)) * (AXIS_MAX - AXIS_MIN)


def main() -> None:
    probe = json.loads(MASS_PROBE.read_text(encoding="utf-8"))
    mass = {row["id"]: float(row["median_kg"]) for row in probe["results"]}

    print("=" * 74)
    print(f"Does the theta split resolve P13's three remaining pairs?  theta = {THETA}")
    print("=" * 74)

    resolved = 0
    for sequence, left, right in PAIRS:
        if left not in mass or right not in mass:
            print(f"\n  [{sequence}] {left} / {right}: not both in the mass probe")
            continue
        la, ra = mass_axis(mass[left]), mass_axis(mass[right])
        lc = "rebound" if la < THETA else "arrest"
        rc = "rebound" if ra < THETA else "arrest"
        gap = abs(la - ra)
        split = lc != rc
        resolved += split
        print(f"\n  [{sequence}]")
        print(f"    {left:<18} {mass[left]:>6.2f} kg   axis {la:.3f}   {lc}")
        print(f"    {right:<18} {mass[right]:>6.2f} kg   axis {ra:.3f}   {rc}")
        print(f"    axis gap {gap:.3f}  ({gap / NOISE_FLOOR:.1f}x noise floor)")
        print(f"    -> {'SPLIT' if split else 'same class, still colliding'}")
        if not split:
            lo, hi = sorted((la, ra))
            print(f"       a theta in ({lo:.3f}, {hi:.3f}] would split it")

    print("\n" + "-" * 74)
    print(f"pairs resolved by the theta split : {resolved} of {len(PAIRS)}")
    print(f"total collisions resolved by 1B   : {4 + resolved} of 7")

    print("\n[where every probed object lands on the axis]")
    for name, kg in sorted(mass.items(), key=lambda kv: kv[1]):
        a = mass_axis(kg)
        side = "rebound" if a < THETA else "arrest"
        print(f"  {name:<20} {kg:>6.2f} kg   axis {a:.3f}   {side}")


if __name__ == "__main__":
    main()
