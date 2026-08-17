"""Measure the contact_resolution split and pick its threshold. Evidence for 1B M1.

The 1B spec derives a three-valued contact_resolution from rigidity and the mass axis:

    rigid       + mass_axis <  theta  -> rebound
    rigid       + mass_axis >= theta  -> arrest
    semi_rigid                        -> follow_through
    flexible                          -> follow_through

rigidity and mass enter the lookup separately, never as a product, per P11.

theta must be measured rather than chosen. The previous draft of the spec wrote a number
first and promised an audit afterwards, which is the wrong order. This script reports
what the shipped affordance profiles can actually support, and picks theta as the
midpoint of the widest gap between adjacent rigid objects on the mass axis, so the
threshold sits as far as possible from any object's own estimator noise.

Reuses P09's compression and P09's measured noise floor, the same two constants
compare_axis_separability.py uses for P11.

Usage:
    python tools/combat_feel/measure_contact_resolution.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AFFORDANCE_ROOT = REPO_ROOT / "artifacts" / "mass_axis_poc" / "affordance_v1_4"
MASS_PROBE = REPO_ROOT / "artifacts" / "mass_probe_v1" / "raw_estimates.json"

# Mirrors melee_motion_compiler.gd _mass_axis_from_kg.
AXIS_MIN, AXIS_MAX = 0.35, 1.00
MASS_FLOOR_KG, MASS_CEILING_KG = 0.15, 8.0

# P09's worst measured repeat-driven axis movement.
NOISE_FLOOR = 0.065


def mass_axis(mass_kg: float) -> float:
    span = math.log(MASS_CEILING_KG) - math.log(MASS_FLOOR_KG)
    position = (math.log(max(mass_kg, MASS_FLOOR_KG * 0.01)) - math.log(MASS_FLOOR_KG)) / span
    return AXIS_MIN + max(0.0, min(1.0, position)) * (AXIS_MAX - AXIS_MIN)


def resolution_for(rigidity: str, axis: float, theta: float) -> str:
    if rigidity != "rigid":
        return "follow_through"
    return "rebound" if axis < theta else "arrest"


def load_objects() -> list[dict]:
    objects = []
    for profile_path in sorted(AFFORDANCE_ROOT.glob("*/object_affordance_profile.json")):
        profile = json.loads(profile_path.read_text(encoding="utf-8"))
        mass_kg = profile.get("real_mass_kg")
        rigidity = profile.get("rigidity")
        if mass_kg is None or rigidity is None:
            continue
        objects.append(
            {
                "id": profile_path.parent.name,
                "rigidity": rigidity,
                "mass_kg": float(mass_kg),
                "axis": mass_axis(float(mass_kg)),
                "contact_surface": profile.get("contact_surface"),
            }
        )
    return objects


def probe_ids() -> list[str]:
    if not MASS_PROBE.exists():
        return []
    data = json.loads(MASS_PROBE.read_text(encoding="utf-8"))
    return [row["id"] for row in data.get("results", [])]


def widest_gap(axes: list[float]) -> tuple[float, float, float]:
    """Return (theta, gap_width, margin) for the widest gap between adjacent values."""
    ordered = sorted(axes)
    best_low, best_high, best_width = ordered[0], ordered[0], -1.0
    for low, high in zip(ordered, ordered[1:]):
        width = high - low
        if width > best_width:
            best_low, best_high, best_width = low, high, width
    theta = (best_low + best_high) / 2.0
    return theta, best_width, best_width / 2.0


def main() -> None:
    objects = load_objects()
    if not objects:
        print("No affordance profiles with both rigidity and real_mass_kg were found.")
        return

    print("=" * 78)
    print("M1 -- contact_resolution distribution and threshold")
    print("=" * 78)

    print("\n[data coverage]")
    known = {obj["id"] for obj in objects}
    probed = set(probe_ids())
    print(f"  objects carrying rigidity + real_mass_kg : {len(objects)}")
    print(f"  objects in the mass probe                : {len(probed)}")
    print(f"  probed objects with no affordance profile: {len(probed - known)}")
    if probed - known:
        print(f"    {', '.join(sorted(probed - known))}")

    counts: dict[str, int] = {}
    for obj in objects:
        counts[obj["rigidity"]] = counts.get(obj["rigidity"], 0) + 1
    print("\n[rigidity distribution]")
    for value in ("rigid", "semi_rigid", "flexible"):
        print(f"  {value:<12} {counts.get(value, 0)}")

    rigid_axes = [obj["axis"] for obj in objects if obj["rigidity"] == "rigid"]
    if len(rigid_axes) < 2:
        print("\nFewer than two rigid objects: theta cannot be measured.")
        return

    theta, gap, margin = widest_gap(rigid_axes)

    print("\n[mass axis, all objects]")
    print(f"  {'id':<20} {'rigidity':<12} {'kg':>7} {'axis':>7}")
    for obj in sorted(objects, key=lambda o: o["axis"]):
        print(
            f"  {obj['id']:<20} {obj['rigidity']:<12} "
            f"{obj['mass_kg']:>7.2f} {obj['axis']:>7.3f}"
        )

    print("\n[threshold]")
    print(f"  widest gap between adjacent rigid objects : {gap:.3f}")
    print(f"  theta (gap midpoint)                      : {theta:.3f}")
    print(f"  margin to nearest object                  : {margin:.3f}")
    print(f"  noise floor (P09)                         : {NOISE_FLOOR:.3f}")
    verdict = "robust" if margin > NOISE_FLOOR else "INSIDE NOISE"
    print(f"  margin vs noise floor                     : {verdict}")

    print("\n[resulting classes]")
    assigned: dict[str, list[str]] = {"rebound": [], "arrest": [], "follow_through": []}
    for obj in sorted(objects, key=lambda o: o["axis"]):
        assigned[resolution_for(obj["rigidity"], obj["axis"], theta)].append(obj["id"])
    for name in ("rebound", "arrest", "follow_through"):
        members = assigned[name]
        print(f"  {name:<16} {len(members)}  {', '.join(members) if members else '-'}")

    print("\n[spec acceptance: every class used, none with a single member]")
    empty = [n for n, m in assigned.items() if not m]
    singleton = [n for n, m in assigned.items() if len(m) == 1]
    if empty:
        print(f"  FAIL: unused classes      : {', '.join(empty)}")
    if singleton:
        print(f"  FAIL: single-member classes: {', '.join(singleton)}")
    if not empty and not singleton:
        print("  PASS")

    print("\n[the pair 1B exists to separate]")
    by_id = {obj["id"]: obj for obj in objects}
    if "frying_pan" in by_id and "chicken_leg" in by_id:
        pan, chicken = by_id["frying_pan"], by_id["chicken_leg"]
        pan_res = resolution_for(pan["rigidity"], pan["axis"], theta)
        chicken_res = resolution_for(chicken["rigidity"], chicken["axis"], theta)
        print(f"  frying_pan  rigidity={pan['rigidity']:<11} axis={pan['axis']:.3f} -> {pan_res}")
        print(f"  chicken_leg rigidity={chicken['rigidity']:<11} axis={chicken['axis']:.3f} -> {chicken_res}")
        print(f"  separated on the axis by {abs(pan['axis'] - chicken['axis']):.3f}")
        print(f"  distinct resolution: {'yes' if pan_res != chicken_res else 'NO'}")


if __name__ == "__main__":
    main()
