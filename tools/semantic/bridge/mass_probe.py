"""Probe whether the model estimates real object mass reliably enough to drive tempo.

The mass counterpart of `length_probe.py`, and deliberately the same three checks, none
of which need ground truth:

  1. REPEAT SPREAD   -- ask the same object k times. If the answer moves a lot, the field
                        cannot drive mechanics no matter how accurate the median is.
  2. ORDERING        -- does chicken leg < cleaver < axe < shield < chair come out right?
                        Robust to every reference value being somewhat off. Pairs that are
                        genuinely close are excluded rather than scored.
  3. CONTROL PAIRS   -- two of them, because mass has two ways to go wrong that length
                        did not. A 30cm `iron bar` beside a 30cm `wooden spoon` catches a
                        model sizing the silhouette instead of weighing the material; a
                        `giant wooden spoon` beside a plain one re-runs P06's check that
                        the size modifier in display_name is read at all.

The reference values in the case file are a rough human band, used only to flag
order-of-magnitude misses -- never as the pass/fail criterion.

Uses the same estimate call as production, so what this measures is what the pipeline
would get.

Usage:
    python mass_probe.py <cases.json> <output_dir> [--repeats 3]
    python mass_probe.py <cases.json> <output_dir> --dry-run   # no API key needed
    python mass_probe.py <cases.json> <output_dir> --length-report <raw_estimates.json>
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from estimate_real_mass import MODEL, estimate_real_mass_kg  # noqa: E402


SPREAD_MAX = 0.20        # a spread wider than this makes the field unusable for tempo

# Looser than length_probe's 1.3 for one reason, not to make the test easier: a human
# reference for mass is a worse guess than one for length. Most people know a mop is
# about 1.4m far better than they know whether it weighs 1.0kg or 1.3kg, so pairs that
# close are not evidence of a model error either way. The check itself is unchanged.
ORDER_PAIR_MIN_RATIO = 1.5

# Higher than length_probe's 1.4 because mass responds far more strongly than length to
# both things the control pairs vary. Swapping wood for steel at fixed size, or scaling a
# utensil up to weapon size, moves mass by a factor, not by a fraction.
CONTROL_MIN_RATIO = 3.0


def _collect(client, objects: list[dict], repeats: int, dry_run: bool) -> list[dict]:
    results = []
    for index, entry in enumerate(objects, start=1):
        blueprint = {"identity": entry["identity"]}
        estimates, bases = [], []
        for attempt in range(repeats):
            if dry_run:
                # Exercise the report without calling the API: echo the reference.
                estimates.append(float(entry["reference_kg"]))
                bases.append("dry-run: reference echoed")
                continue
            estimate = estimate_real_mass_kg(client, blueprint)
            estimates.append(float(estimate["real_mass_kg"]))
            bases.append(estimate["basis"])
        print(f"  [{index}/{len(objects)}] {entry['id']}: {estimates}", file=sys.stderr)
        results.append({
            "id": entry["id"],
            "reference_kg": entry["reference_kg"],
            "band_kg": entry["band_kg"],
            "reference_length_cm": entry.get("reference_length_cm"),
            "estimates_kg": estimates,
            "median_kg": statistics.median(estimates),
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
            reference_ratio = high["reference_kg"] / low["reference_kg"]
            if reference_ratio < ORDER_PAIR_MIN_RATIO:
                continue  # genuinely close; not a fair pair to score
            if high["median_kg"] <= low["median_kg"]:
                violations.append((low["id"], high["id"]))
    return violations


def _load_length_medians(path: Path | None) -> dict[str, float]:
    """Measured length medians from a previous length_probe run, if one was supplied."""
    if path is None:
        return {}
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    return {row["id"]: float(row["median_cm"]) for row in payload.get("results", [])}


def _report(cases: dict, results: list[dict], repeats: int, dry_run: bool,
            length_medians: dict[str, float]) -> str:
    by_id = {row["id"]: row for row in results}
    known = set(cases.get("known_objects", []))
    lines = []
    add = lines.append

    add(f"REAL MASS ESTIMATE PROBE — {len(results)} objects x {repeats} repeats — {MODEL}")
    if dry_run:
        add("*** DRY RUN: reference values echoed, no model was called. Numbers below are not evidence. ***")
    add("")

    add("1. REPEAT SPREAD  (same object asked repeatedly; 0.0% = every repeat agreed)")
    add(f"   {'object':<20}{'median':>10}{'min':>9}{'max':>9}{'spread':>9}   verdict")
    worst = 0.0
    for row in results:
        spread = _spread(row["estimates_kg"])
        worst = max(worst, spread)
        verdict = "stable" if spread <= SPREAD_MAX else "UNSTABLE — cannot drive tempo"
        add(f"   {row['id']:<20}{row['median_kg']:>9.2f}kg{min(row['estimates_kg']):>8.2f}"
            f"{max(row['estimates_kg']):>9.2f}{spread * 100:>8.1f}%   {verdict}")
    add("")
    add(f"   worst spread {worst * 100:.1f}%  ->  " + (
        "repeatable enough to drive decisions" if worst <= SPREAD_MAX
        else "NOT REPEATABLE: the same object measures differently run to run"))
    add("")

    add("2. ORDERING  (sorted by model median; reference in brackets)")
    for row in sorted(results, key=lambda r: r["median_kg"]):
        mark = " *" if row["id"] in known else "  "
        add(f"   {row['median_kg']:>8.2f} kg  [{row['reference_kg']:>5.2f} ref]{mark} {row['id']}")
    violations = _order_violations(results)
    add("")
    if violations:
        add(f"   {len(violations)} ordering violation(s) among clearly-separated pairs:")
        for low, high in violations:
            add(f"     {high} should exceed {low}, but measured "
                f"{by_id[high]['median_kg']:.2f} vs {by_id[low]['median_kg']:.2f}")
    else:
        add("   no ordering violations among clearly-separated pairs")
    add("")

    add("3. CONTROL PAIRS  (mass must not collapse into length, or into the bare noun)")
    for pair in cases.get("control_pairs", []):
        plain, modified = by_id.get(pair["plain"]), by_id.get(pair["modified"])
        if not plain or not modified:
            add(f"   {pair['plain']} / {pair['modified']}: absent from results")
            continue
        ratio = modified["median_kg"] / plain["median_kg"] if plain["median_kg"] else float("inf")
        verdict = "separated" if ratio >= CONTROL_MIN_RATIO else "COLLAPSED — the axis is not being read"
        add(f"   {pair['modified']} / {pair['plain']} = {ratio:.2f}x "
            f"({modified['median_kg']:.2f} vs {plain['median_kg']:.2f} kg)  ->  {verdict}")
        add(f"     asserts: {pair['asserts']}")
    add("")

    add("4. REFERENCE BAND  (rough human estimate — flags order-of-magnitude misses only)")
    outside = [r for r in results if not r["band_kg"][0] <= r["median_kg"] <= r["band_kg"][1]]
    if outside:
        for row in outside:
            add(f"   {row['id']:<20}{row['median_kg']:>8.2f} kg  outside band {row['band_kg']}")
    else:
        add("   every median inside its band")
    add("")

    # Informational, and the reason this axis was added at all: if mass simply tracked
    # length it would be a second reading of an axis the compiler already has, and the
    # combinations would not multiply (T51/T76). Disagreeing ranks are what make it a
    # genuinely orthogonal axis rather than a proxy.
    add("5. AXIS INDEPENDENCE  (informational: does mass say anything length did not?)")
    paired = [r for r in results if r["id"] in length_medians]
    if not paired:
        add("   no measured lengths supplied (--length-report); skipped")
    else:
        by_mass = sorted(paired, key=lambda r: r["median_kg"])
        by_length = sorted(paired, key=lambda r: length_medians[r["id"]])
        mass_rank = {row["id"]: i for i, row in enumerate(by_mass)}
        length_rank = {row["id"]: i for i, row in enumerate(by_length)}
        inversions = 0
        total = 0
        for i, low in enumerate(paired):
            for high in paired[i + 1:]:
                total += 1
                if (mass_rank[low["id"]] < mass_rank[high["id"]]) != \
                   (length_rank[low["id"]] < length_rank[high["id"]]):
                    inversions += 1
        add(f"   {len(paired)} objects measured on both axes; {inversions} of {total} pairs "
            f"rank differently ({inversions / total * 100:.0f}%)")
        add("   largest disagreements (long-but-light vs short-but-heavy):")
        spun = sorted(paired, key=lambda r: mass_rank[r["id"]] - length_rank[r["id"]])
        for row in spun[:3] + spun[-3:]:
            delta = mass_rank[row["id"]] - length_rank[row["id"]]
            add(f"     {row['id']:<20}{length_medians[row['id']]:>7.0f} cm "
                f"{row['median_kg']:>8.2f} kg   rank shift {delta:+d}")
        if inversions == 0:
            add("   MASS TRACKS LENGTH EXACTLY — it would add no new axis; check the estimator")
    add("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases_json", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--length-report", type=Path, default=None,
                        help="raw_estimates.json from a length_probe run, for the independence section")
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
    report = _report(cases, results, args.repeats, args.dry_run,
                     _load_length_medians(args.length_report))

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
