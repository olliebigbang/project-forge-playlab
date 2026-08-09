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

Lengths come from the affordance sidecars in `affordance_v1_3/`, which carry
`real_length_cm` under contract v1.3 (decision P05). Those four values are hand-authored
placeholders — see the note below.

```bash
A=data/combat_feel/live_assets
PP=tools/comfyui/postprocess
OUT=artifacts/real_scale_poc
AF=$OUT/affordance_v1_3

python tools/semantic/bridge/author_v1_3_sidecars.py $AF

python $PP/process_sprite.py \
  $A/motion_grammar_slice_1a/shotgun_melee_regenerated_20260807/raw.png \
  $OUT/shotgun_melee.png artifacts/real_scale_poc_masks/shotgun_melee_alpha.png \
  --affordance-profile $AF/shotgun_melee/object_affordance_profile.json

python $PP/rescale_to_real_length.py $A/recipe_slice_1b/frying_pan/processed_sprite.png    $OUT/frying_pan.png         --affordance-profile $AF/frying_pan/object_affordance_profile.json
python $PP/rescale_to_real_length.py $A/revision_a/giant_wooden_spoon/processed_sprite.png $OUT/giant_wooden_spoon.png --affordance-profile $AF/giant_wooden_spoon/object_affordance_profile.json
python $PP/rescale_to_real_length.py $A/recipe_slice_1b/old_mop/processed_sprite.png       $OUT/old_mop.png            --affordance-profile $AF/old_mop/object_affordance_profile.json
```

Requires `numpy`, `pillow`, `opencv-python`.

## Where the lengths come from

The sidecars in `affordance_v1_3/` are **model output** (`claude-opus-5`, via
`estimate_real_length.py` against the frozen blueprints under `data/`):

| object | real_length_cm | model's stated basis |
|---|---|---|
| frying_pan | 45 | cast iron skillet with handle, about a forearm length |
| shotgun_melee | 100 | pump-action shotgun, about as long as a baseball bat |
| giant_wooden_spoon | 120 | about the length of a broom handle, versus a normal 30cm kitchen spoon |
| old_mop | 140 | broom handle reaching chest height on an adult |

Reliability was measured separately over 17 objects x 3 repeats — see
`artifacts/length_probe_v1/REPORT.txt` and decision P06. Worst repeat spread 5.6%.

`author_v1_3_sidecars.py` still hand-authors the same four values for working offline
without an API key; anything it produces is labelled `hand_authored_placeholder` and is
not evidence.

Note that `real_length_cm` separates three objects that `body_length` cannot: mop, spoon
and shotgun are all `"long"` under the ordinal, and 140 / 120 / 100 under the number.

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
