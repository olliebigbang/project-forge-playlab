"""Probe whether the model estimates real object length reliably enough to drive reach.

Comparing model output against hand-authored numbers is a weak test, because those
numbers are somebody's guess too. The three checks that carry weight here need no ground
truth at all:

  1. REPEAT SPREAD   -- ask the same object k times. If the answer moves a lot, the field
                        cannot drive mechanics no matter how accurate the median is.
  2. ORDERING        -- does chicken leg < cleaver < sword < mop < fishing rod come out
                        right? Robust to every reference value being somewhat off. Pairs
                        that are genuinely close are excluded rather than scored.
  3. CONTROL PAIR    -- plain `wooden spoon` beside `giant wooden spoon`. Identical
                        answers mean the model is pattern-matching the noun and ignoring
                        the description it was given.

The reference values in the case file are a rough human band, used only to flag
order-of-magnitude misses -- never as the pass/fail criterion.

Uses the same estimate call as production, so what this measures is what the pipeline
would get.

Usage:
    python length_probe.py <cases.json> <output_dir> [--repeats 3]
    python length_probe.py <cases.json> <output_dir> --dry-run   # no API key needed
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from estimate_real_length import MODEL, estimate_real_length_cm  # noqa: E402


# Mirrors process_sprite.PX_PER_CM. Duplicated rather than imported so the probe does not
# drag in the postprocessor's OpenCV dependency; override with --px-per-cm if it changes.
DEFAULT_PX_PER_CM = 0.56
SPRITE_SIZE = 96
MARGIN_RATIO = 0.10

SPREAD_MAX = 0.20        # a spread wider than this makes the field unusable for reach
ORDER_PAIR_MIN_RATIO = 1.3   # closer than this and the pair is too close to score
CONTROL_MIN_RATIO = 1.4      # the modified object must read meaningfully larger


def _collect(client, objects: list[dict], repeats: int, dry_run: bool) -> list[dict]:
    results = []
    for index, entry in enumerate(objects, start=1):
        blueprint = {"identity": entry["identity"]}
        estimates, bases = [], []
        for attempt in range(repeats):
            if dry_run:
                # Exercise the report without calling the API: echo the reference.
                estimates.append(float(entry["reference_cm"]))
                bases.append("dry-run: reference echoed")
                continue
            estimate = estimate_real_length_cm(client, blueprint)
            estimates.append(float(estimate["real_length_cm"]))
            bases.append(estimate["basis"])
        print(f"  [{index}/{len(objects)}] {entry['id']}: {estimates}", file=sys.stderr)
        results.append({
            "id": entry["id"],
            "reference_cm": entry["reference_cm"],
            "band_cm": entry["band_cm"],
            "estimates_cm": estimates,
            "median_cm": statistics.median(estimates),
            "bases": bases,
        })
    return results


def _spread(values: list[float]) -> float:
    """Max-min over the median. Zero means every repeat agreed."""
    if not values:
        return float("nan")
    center = statistics.median(values)
    return (max(values) - min(values)) / center if center else float("inf")


def _order_violations(results: list[dict]) -> list[tuple[str, str]]:
    """Pairs the reference separates clearly but the model ranks the wrong way round."""
    violations = []
    for i, low in enumerate(results):
        for high in results[i + 1:]:
            reference_ratio = high["reference_cm"] / low["reference_cm"]
            if reference_ratio < ORDER_PAIR_MIN_RATIO:
                continue  # genuinely close; not a fair pair to score
            if high["median_cm"] <= low["median_cm"]:
                violations.append((low["id"], high["id"]))
    return violations


def _report(cases: dict, results: list[dict], repeats: int, px_per_cm: float, dry_run: bool) -> str:
    by_id = {row["id"]: row for row in results}
    known = set(cases.get("known_objects", []))
    lines = []
    add = lines.append

    add(f"REAL LENGTH ESTIMATE PROBE — {len(results)} objects x {repeats} repeats — {MODEL}")
    if dry_run:
        add("*** DRY RUN: reference values echoed, no model was called. Numbers below are not evidence. ***")
    add("")

    add("1. REPEAT SPREAD  (same object asked repeatedly; 0.0% = every repeat agreed)")
    add(f"   {'object':<20}{'median':>9}{'min':>8}{'max':>8}{'spread':>9}   verdict")
    worst = 0.0
    for row in results:
        spread = _spread(row["estimates_cm"])
        worst = max(worst, spread)
        verdict = "stable" if spread <= SPREAD_MAX else "UNSTABLE — cannot drive reach"
        add(f"   {row['id']:<20}{row['median_cm']:>9.0f}{min(row['estimates_cm']):>8.0f}"
            f"{max(row['estimates_cm']):>8.0f}{spread * 100:>8.1f}%   {verdict}")
    add("")
    add(f"   worst spread {worst * 100:.1f}%  ->  " + (
        "repeatable enough to drive decisions" if worst <= SPREAD_MAX
        else "NOT REPEATABLE: the same object measures differently run to run"))
    add("")

    add("2. ORDERING  (sorted by model median; reference in brackets)")
    for row in sorted(results, key=lambda r: r["median_cm"]):
        mark = " *" if row["id"] in known else "  "
        add(f"   {row['median_cm']:>6.0f} cm  [{row['reference_cm']:>4} ref]{mark} {row['id']}")
    violations = _order_violations(results)
    add("")
    if violations:
        add(f"   {len(violations)} ordering violation(s) among clearly-separated pairs:")
        for low, high in violations:
            add(f"     {high} should exceed {low}, but measured "
                f"{by_id[high]['median_cm']:.0f} vs {by_id[low]['median_cm']:.0f}")
    else:
        add("   no ordering violations among clearly-separated pairs")
    add("")

    add("3. CONTROL PAIRS  (does the model read the size modifier, or just the noun?)")
    for pair in cases.get("control_pairs", []):
        plain, modified = by_id.get(pair["plain"]), by_id.get(pair["modified"])
        if not plain or not modified:
            add(f"   {pair['plain']} / {pair['modified']}: absent from results")
            continue
        ratio = modified["median_cm"] / plain["median_cm"] if plain["median_cm"] else float("inf")
        verdict = "modifier read" if ratio >= CONTROL_MIN_RATIO else "MODIFIER IGNORED — matching the noun, not the description"
        add(f"   {pair['modified']} / {pair['plain']} = {ratio:.2f}x "
            f"({modified['median_cm']:.0f} vs {plain['median_cm']:.0f})  ->  {verdict}")
    add("")

    add("4. REFERENCE BAND  (rough human estimate — flags order-of-magnitude misses only)")
    outside = [r for r in results if not r["band_cm"][0] <= r["median_cm"] <= r["band_cm"][1]]
    if outside:
        for row in outside:
            add(f"   {row['id']:<20}{row['median_cm']:>7.0f} cm  outside band {row['band_cm']}")
    else:
        add("   every median inside its band")
    add("")

    # A diagonal object fits more length in the same box than an upright one, so the
    # ceiling is a range, not a number. old_mop is the worked example: 150cm exceeds the
    # upright ceiling and still processes, because it sits corner to corner.
    axis_ceiling = SPRITE_SIZE / px_per_cm
    upright_ceiling = SPRITE_SIZE / ((1.0 + 2.0 * MARGIN_RATIO) * px_per_cm)
    add(f"5. FRAME CAPACITY  (96px at {px_per_cm} px/cm: ~{upright_ceiling:.0f}cm always fits, "
        f"~{axis_ceiling:.0f}cm is the diagonal best case)")
    impossible = [r for r in results if r["median_cm"] > axis_ceiling]
    orientation_dependent = [r for r in results if upright_ceiling < r["median_cm"] <= axis_ceiling]
    if impossible:
        add("   cannot fit at any orientation — postprocess fails closed on")
        add("   REAL_LENGTH_EXCEEDS_SPRITE_FRAME (decision P05: the contract allows these,")
        add("   the frame is what needs changing):")
        for row in impossible:
            add(f"     {row['id']:<20}{row['median_cm']:>7.0f} cm")
    if orientation_dependent:
        add("   fits only if the object sits diagonally in frame:")
        for row in orientation_dependent:
            add(f"     {row['id']:<20}{row['median_cm']:>7.0f} cm")
    if not impossible and not orientation_dependent:
        add("   every object fits the current frame at any orientation")
    add("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases_json", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--px-per-cm", type=float, default=DEFAULT_PX_PER_CM)
    parser.add_argument("--dry-run", action="store_true", help="echo reference values instead of calling the model")
    args = parser.parse_args()

    cases = json.loads(args.cases_json.read_text(encoding="utf-8"))
    client = None
    if not args.dry_run:
        import anthropic

        client = anthropic.Anthropic()

    print(f"estimating {len(cases['objects'])} objects x {args.repeats} repeats...", file=sys.stderr)
    try:
        results = _collect(client, cases["objects"], args.repeats, args.dry_run)
    except TypeError as exc:
        # The SDK resolves credentials lazily, so a missing key surfaces on the first
        # request rather than at construction.
        if "authentication" not in str(exc).lower():
            raise
        raise SystemExit(
            "no API credentials found.\n"
            "Set ANTHROPIC_API_KEY, or run `ant auth login`, or pass --dry-run to\n"
            "exercise the report without calling the model."
        ) from exc
    report = _report(cases, results, args.repeats, args.px_per_cm, args.dry_run)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "raw_estimates.json").write_text(
        json.dumps({
            "model": MODEL,
            "repeats": args.repeats,
            "provenance": "dry_run_reference_echo" if args.dry_run else "model_estimate",
            "results": results,
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.output_dir / "REPORT.txt").write_text(report + "\n", encoding="utf-8")
    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
