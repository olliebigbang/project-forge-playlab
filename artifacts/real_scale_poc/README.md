# Real-scale normalization — proof of concept

Four sprites on one ruler, so that measured length carries information about the object
instead of about the frame. See `docs/DECISIONS.md` P01–P04.

**These are evidence, not production assets.** The frozen sprites under `data/` are
SHA-256 pinned in their `index.json` and are deliberately untouched.

## Provenance

Only `shotgun_melee` still has its raw render, so only it goes through the real
postprocessor. The other three raws were never committed, and `process_sprite.py`
consumes a raw flat-chroma image — so they are rebuilt from their finished 96px sprites
by `rescale_to_real_length.py`, which applies the same scale formula to a lossy source.

| sprite | source | path |
|---|---|---|
| shotgun_melee | raw 512x512 render | `process_sprite.py` |
| frying_pan | finished 96px sprite | `rescale_to_real_length.py` |
| giant_wooden_spoon | finished 96px sprite | `rescale_to_real_length.py` |
| old_mop | finished 96px sprite | `rescale_to_real_length.py` |

## Reproduce

```bash
A=data/combat_feel/live_assets
PP=tools/comfyui/postprocess
OUT=artifacts/real_scale_poc

python $PP/process_sprite.py \
  $A/motion_grammar_slice_1a/shotgun_melee_regenerated_20260807/raw.png \
  $OUT/shotgun_melee.png artifacts/real_scale_poc_masks/shotgun_melee_alpha.png \
  --object-id shotgun_melee

python $PP/rescale_to_real_length.py $A/recipe_slice_1b/frying_pan/processed_sprite.png    $OUT/frying_pan.png         --object-id frying_pan
python $PP/rescale_to_real_length.py $A/revision_a/giant_wooden_spoon/processed_sprite.png $OUT/giant_wooden_spoon.png --object-id giant_wooden_spoon
python $PP/rescale_to_real_length.py $A/recipe_slice_1b/old_mop/processed_sprite.png       $OUT/old_mop.png            --object-id old_mop
```

Requires `numpy`, `pillow`, `opencv-python`.

## Result

Measured by `project-forge-claude/tools/shape_metrics/run_report.py`:

| sprite | real cm | length before | length after | soft% before → after | swing before → after |
|---|---|---|---|---|---|
| frying_pan | 40 | 82.6 | 21.6 | 29.5% → 0.0% | 5.3% → 0.0% |
| giant_wooden_spoon | 60 | 91.9 | 33.6 | 37.9% → 0.0% | 9.8% → 0.0% |
| shotgun_melee | 100 | 81.2 | 56.7 | 57.1% → 0.0% | 21.8% → 0.0% |
| old_mop | 150 | 99.7 | 84.6 | 55.3% → 0.0% | 15.5% → 0.0% |

Longest / shortest: **1.21x before, 3.92x after** (real ratio 3.75x).

Note that slenderness is scale invariant by design (decision T60), so it barely moves —
this change puts information into `length`, which the compiler can now interpolate reach
from instead of clamping to two hard-coded bands.
