"""Compare how well candidate axes separate the probed objects. Evidence for P11.

An axis is only worth having if two different objects land far enough apart on it to be
told apart. This counts the pairs that do not, under four schemes: real mass alone, real
length alone, their product as a rotational inertia proxy, and the two kept separate.

The threshold is not arbitrary. P09 measured the worst repeat-driven movement of the mass
axis at 0.065 of the band, so any two objects closer than that sit inside the estimator's
own noise and cannot be a distinction the game may rely on.

Reads the two probe artifacts and applies the same logarithmic compression
`melee_motion_compiler.gd` uses, so the numbers describe the axis the compiler actually
sees rather than the raw quantity.

Usage:
    python tools/combat_feel/compare_axis_separability.py
"""

from __future__ import annotations

import json
import math
import statistics
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MASS_PROBE = REPO_ROOT / "artifacts" / "mass_probe_v1" / "raw_estimates.json"
LENGTH_PROBE = REPO_ROOT / "artifacts" / "length_probe_v1" / "raw_estimates.json"

# Mirrors melee_motion_compiler.gd. The mass constants are the shipped ones; length and
# inertia get the observed extremes so every scheme is judged on a full band and none
# wins or loses through clamping alone.
AXIS_MIN, AXIS_MAX = 0.35, 1.00
MASS_FLOOR_KG, MASS_CEILING_KG = 0.15, 8.0

# P09's worst measured repeat-driven axis movement.
NOISE_FLOOR = 0.065


def compress(value: float, low: float, high: float) -> float:
    span = math.log(high) - math.log(low)
    position = (math.log(max(value, low * 0.01)) - math.log(low)) / span
    return AXIS_MIN + max(0.0, min(1.0, position)) * (AXIS_MAX - AXIS_MIN)


def spearman(xs: list[float], ys: list[float]) -> float:
    def ranks(values: list[float]) -> list[float]:
        order = sorted(range(len(values)), key=lambda i: values[i])
        out = [0.0] * len(values)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
                j += 1
            shared = (i + j) / 2.0 + 1
            for k in range(i, j + 1):
                out[order[k]] = shared
            i = j + 1
        return out

    rx, ry = ranks(xs), ranks(ys)
    mx, my = statistics.mean(rx), statistics.mean(ry)
    numerator = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    denominator = math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
    return numerator / denominator if denominator else float("nan")


def load() -> list[dict]:
    masses = json.loads(MASS_PROBE.read_text(encoding="utf-8"))["results"]
    lengths = {r["id"]: r for r in json.loads(LENGTH_PROBE.read_text(encoding="utf-8"))["results"]}
    rows = []
    for entry in masses:
        measured_length = lengths.get(entry["id"])
        if measured_length is None:
            continue  # probed for mass only; cannot be placed on both axes
        rows.append({
            "id": entry["id"],
            "kg": entry["median_kg"],
            "metres": measured_length["median_cm"] / 100.0,
        })
    for row in rows:
        row["inertia"] = row["kg"] * row["metres"] ** 2
    return rows


def main() -> int:
    rows = load()
    lengths = [r["metres"] for r in rows]
    inertias = [r["inertia"] for r in rows]
    for row in rows:
        row["axis_mass"] = compress(row["kg"], MASS_FLOOR_KG, MASS_CEILING_KG)
        row["axis_length"] = compress(row["metres"], min(lengths), max(lengths))
        row["axis_inertia"] = compress(row["inertia"], min(inertias), max(inertias))

    print(f"{len(rows)} objects measured on both axes\n")

    print("RANK CORRELATION  (1.00 = identical ordering = no new information)")
    masses = [r["kg"] for r in rows]
    print(f"   inertia vs mass  : {spearman(inertias, masses):.3f}")
    print(f"   inertia vs length: {spearman(inertias, lengths):.3f}")
    print(f"   mass vs length   : {spearman(masses, lengths):.3f}"
          "   <- already near-independent; this is the asset the product spends")
    print()

    schemes = {
        "inertia m*L^2 alone": lambda a, b: abs(a["axis_inertia"] - b["axis_inertia"]),
        "length alone": lambda a, b: abs(a["axis_length"] - b["axis_length"]),
        "mass alone": lambda a, b: abs(a["axis_mass"] - b["axis_mass"]),
        "mass and length kept separate": lambda a, b: max(
            abs(a["axis_mass"] - b["axis_mass"]), abs(a["axis_length"] - b["axis_length"])
        ),
    }

    print(f"INDISTINGUISHABLE PAIRS  (axis distance < {NOISE_FLOOR}, P09's measured noise floor)")
    residual: list[tuple[float, str, str]] = []
    for label, distance in schemes.items():
        collisions: list[tuple[float, str, str]] = []
        total = 0
        for i, low in enumerate(rows):
            for high in rows[i + 1:]:
                total += 1
                gap = distance(low, high)
                if gap < NOISE_FLOOR:
                    collisions.append((gap, low["id"], high["id"]))
        print(f"   {label:<34}{len(collisions):>4}/{total}  ({len(collisions) / total * 100:>4.0f}%)")
        if label.startswith("mass and length"):
            residual = sorted(collisions)

    print("\nRESIDUAL COLLISIONS under the two-axis scheme")
    print("   These differ in neither kilograms nor centimetres, so no arrangement of the")
    print("   two will split them. They need a contact or material axis instead (P11).")
    for gap, low, high in residual:
        print(f"   {gap:.3f}  {low} / {high}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
