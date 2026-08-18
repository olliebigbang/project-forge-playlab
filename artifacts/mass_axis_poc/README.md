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

| object | group | real_length_cm | real_mass_kg | mass provenance |
|---|---|---|---|---|
| frying_pan | upgrade | 45 | 2.5 | model, from the frozen blueprint |
| giant_wooden_spoon | upgrade | 120 | 1.5 | model, from the frozen blueprint |
| shotgun_melee | upgrade | 100 | 3.4 | model, from the frozen blueprint |
| old_mop | upgrade | 140 | 1.2 | model, from the frozen blueprint |
| chicken_leg | model-backed demo | 13 | 0.12 | model, via the probe |
| sledgehammer | hand-authored demo | 90 | 5.0 | **hand-authored** — not in the probe set |

The four upgrades are `estimate_real_mass.py` run against the same frozen
`semantic_blueprint.json` files under `data/` that the game loads, which is the provenance
chain P06 established for length. The model's stated basis for each:

| object | kg | basis |
|---|---|---|
| frying_pan | 2.5 | cast iron skillet, about like a full 2L bottle |
| old_mop | 1.2 | a broom or dry cotton mop |
| giant_wooden_spoon | 1.5 | oversized carved wooden paddle spoon |
| shotgun_melee | 3.4 | typical pump-action 12-gauge, like a full jug of milk |

`chicken_leg` and `sledgehammer` are not shipped assets. The chicken leg's structural fields
come from the frozen A10 affordance estimator output; its 13cm length and 0.12kg mass are
the frozen model-probe medians. The sledgehammer's entire profile remains hand-authored and
must not be cited as evidence of affordance-model capability. Together they retain P08's
offline mass-axis control: both are `mass_distribution: "front"` with a `broad` contact
face, so before v1.4 the compiler gave them the same mass axis and the same `heavy` label.

## Reproduce

The four upgrades, from the frozen blueprints:

```bash
A=data/combat_feel/live_assets
V3=artifacts/real_scale_poc/affordance_v1_3
V4=artifacts/mass_axis_poc/affordance_v1_4

python tools/semantic/bridge/estimate_real_mass.py $A/recipe_slice_1b/frying_pan/semantic_blueprint.json          $V3/frying_pan/object_affordance_profile.json          $V4/frying_pan/object_affordance_profile.json
python tools/semantic/bridge/estimate_real_mass.py $A/recipe_slice_1b/old_mop/semantic_blueprint.json             $V3/old_mop/object_affordance_profile.json             $V4/old_mop/object_affordance_profile.json
python tools/semantic/bridge/estimate_real_mass.py $A/revision_a/giant_wooden_spoon/semantic_blueprint.json       $V3/giant_wooden_spoon/object_affordance_profile.json  $V4/giant_wooden_spoon/object_affordance_profile.json
python tools/semantic/bridge/estimate_real_mass.py $A/motion_grammar_slice_1a/shotgun_melee/semantic_blueprint.json $V3/shotgun_melee/object_affordance_profile.json     $V4/shotgun_melee/object_affordance_profile.json
```

The model-backed chicken demo, the hand-authored sledgehammer control, and the offline path:

```bash
python tools/semantic/bridge/author_v1_4_sidecars.py <some_scratch_dir>
```

That script writes the chicken structure from frozen A10 model output, but still writes
hand-authored placeholder masses for the four upgrades and a wholly hand-authored
sledgehammer. Point it somewhere else; do not let it overwrite the four model estimates.

## Result

`tools/combat_feel/verify_mass_ab.gd` compiles each object twice from the same sidecar,
with `real_mass_kg` zeroed on the OFF side, so the only variable is mass:

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/combat_feel/verify_mass_ab.gd
```

| object | kg | mass_axis OFF → ON | weight_class OFF → ON | tempo OFF → ON |
|---|---|---|---|---|
| chicken_leg | 0.12 | 1.000 → 0.350 | heavy → light | balanced → **rapid** |
| sledgehammer | 5.00 | 1.000 → 0.923 | heavy → heavy | committed → committed |
| frying_pan | 2.50 | 1.000 → 0.810 | heavy → medium | balanced → balanced |
| giant_wooden_spoon | 1.50 | 1.000 → 0.726 | heavy → medium | committed → committed |
| old_mop | 1.20 | 1.000 → 0.690 | heavy → medium | committed → committed |
| shotgun_melee | 3.40 | 0.350 → 0.860 | heavy → heavy | balanced → **committed** |

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

Mass spans 41.7x across these six objects. Base damage takes exactly three values —
22 / 27 / 34 — because mass reaches damage only by selecting one of three tempo classes,
never as a multiplier. That is decision P08's rule, and section 3 of `verify_mass_ab.gd`
prints the evidence for it on every run.

## Reliability

Measured with `tools/semantic/bridge/mass_probe.py`, 18 objects x 3 repeats on
`claude-opus-5`. Report: `artifacts/mass_probe_v1/REPORT.txt`.

```bash
python tools/semantic/bridge/mass_probe.py \
  tools/semantic/cases/real_mass_probe_v1.json artifacts/mass_probe_v1 \
  --repeats 3 --length-report artifacts/length_probe_v1/raw_estimates.json
```

Ordering, both control pairs and the reference band all pass. **The repeat-spread check
does not**, and the failure is real but narrower than the verdict line suggests — see P09.
Worst raw spread is 40% (fishing rod, 0.20–0.30kg), against a 20% threshold inherited from
the length probe. Both failures are at the light end, where the model answers round numbers
and a 30g difference is a large percentage.

Two of eighteen exceed the threshold. After the compiler's log compression the worst axis
movement is +0.066 on a band of 0.65, and **no object's `weight_class` changes across
repeats**. The chicken leg's 25% raw spread compresses to exactly 0.000, because 0.12 and
0.15 both sit at or below the axis floor.
