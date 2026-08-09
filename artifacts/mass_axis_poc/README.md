# Real-mass axis — proof of concept

Affordance sidecars carrying `real_mass_kg` under contract v1.4, so the compiler knows how
heavy an object is and not merely where its weight sits. See `docs/DECISIONS.md` P08–P09.

**These are evidence, not production assets.** The frozen sidecars under `data/` are
SHA-256 pinned in their `index.json` and are deliberately untouched, exactly as in P04/P05.

> This directory holds **JSON only**. It does not conflict with
> `USE_REAL_LENGTH_RENDER_SCALE` the way `artifacts/real_scale_poc/` does — that warning is
> about the rescaled *sprites* there, which solve the drawn-size problem a second time.
> Nothing here touches drawn size.

## What is in here

`affordance_v1_4/` has two groups, and they differ in how much you may trust them.

| object | group | real_length_cm | real_mass_kg | provenance |
|---|---|---|---|---|
| frying_pan | upgrade | 45 | 1.6 | length: model. mass: **hand-authored** |
| giant_wooden_spoon | upgrade | 120 | 1.5 | length: model. mass: **hand-authored** |
| shotgun_melee | upgrade | 100 | 3.2 | length: model. mass: **hand-authored** |
| old_mop | upgrade | 140 | 1.0 | length: model. mass: **hand-authored** |
| chicken_leg | demo | 13 | 0.15 | both **hand-authored** |
| sledgehammer | demo | 90 | 5.0 | both **hand-authored** |

The lengths on the four upgrades are model output carried over from P06. **Every mass in
this table is a hand-authored placeholder and is not evidence about what the model can
estimate.** `estimate_real_mass.py` and `mass_probe.py` are written and dry-run verified,
but have not been run against the model — see "Not yet measured" below.

`chicken_leg` and `sledgehammer` are not shipped assets. They exist to make P08's defect
reproducible by hand: both are `mass_distribution: "front"` with a `broad` contact face, so
before v1.4 the compiler gave them the *same* mass axis (1.0) and the *same* label
(`heavy`) across a 33x difference in real mass.

## Reproduce

```bash
python tools/semantic/bridge/author_v1_4_sidecars.py artifacts/mass_axis_poc/affordance_v1_4
```

## Result

`tools/combat_feel/verify_mass_ab.gd` compiles each object twice from the same sidecar,
with `real_mass_kg` zeroed on the OFF side, so the only variable is mass:

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/combat_feel/verify_mass_ab.gd
```

| object | kg | mass_axis OFF → ON | weight_class OFF → ON | tempo OFF → ON |
|---|---|---|---|---|
| chicken_leg | 0.15 | 1.000 → 0.350 | heavy → light | balanced → **rapid** |
| sledgehammer | 5.00 | 1.000 → 0.923 | heavy → heavy | committed → committed |
| frying_pan | 1.60 | 1.000 → 0.737 | heavy → medium | balanced → balanced |
| giant_wooden_spoon | 1.50 | 1.000 → 0.726 | heavy → medium | committed → committed |
| old_mop | 1.00 | 1.000 → 0.660 | heavy → medium | committed → committed |
| shotgun_melee | 3.20 | 0.350 → 0.850 | heavy → heavy | balanced → **committed** |

Before: **all six** objects classify `heavy`, and five of six share a mass axis of exactly
1.000 — the axis carried no information at all. After: the axis spans 0.350–0.923 and the
three labels are all in use.

What the chicken leg gets for being light is a trade, not a penalty (P08):

| | swing | movement kept | base damage | DPS |
|---|---|---|---|---|
| chicken_leg before | 0.54s | 0.62 | 27 | 50.0 |
| chicken_leg after | **0.39s** | **0.82** | 22 | **56.4** |

Faster, nearly a third more mobile, and *higher* sustained DPS for less damage per hit.

## The red line holds

Mass spans 33.3x across these six objects. Base damage takes exactly three values —
22 / 27 / 34 — because mass reaches damage only by selecting one of three tempo classes,
never as a multiplier. That is decision P08's rule, and section 3 of `verify_mass_ab.gd`
prints the evidence for it on every run.

## Not yet measured

`mass_probe.py` is the reliability check that has to pass before any of these masses count
as evidence, exactly as P06 was for length. It is written and dry-run verified against
18 objects (17 shared with the length probe, plus an `iron_bar` control), but the live run
needs `ANTHROPIC_API_KEY`, which was not available in the session that wrote it:

```bash
python tools/semantic/bridge/mass_probe.py \
  tools/semantic/cases/real_mass_probe_v1.json artifacts/mass_probe_v1 \
  --repeats 3 --length-report artifacts/length_probe_v1/raw_estimates.json
```

Until that runs, treat every mass here as a placeholder. P06 is the reason to insist:
the hand-authored guess for the giant spoon was 60cm and the model said 120.
