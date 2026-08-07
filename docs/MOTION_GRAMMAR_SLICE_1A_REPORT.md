# Forge Motion Grammar Slice 1A — staged technical report

Status: **TECHNICAL PASS / FEEL NOT YET TESTED**

This report covers the completed 1A.1 structure-grammar closure only. It does not claim that the full Slice 1A human-feel gate has passed.

## Existing runtime chain

The implementation reuses the existing chain and does not add a second combat controller or state machine:

`WeaponVisualAsset + AnchorData + ObjectAffordanceProfile → MeleeMotionCompiler → CombatMotionProfile/ComboRecipe → MeleeCombatController → CombatFeelSlice0 + ImpactFeedbackProfile`

The existing input buffer, startup/active/recovery phases, hitstop, per-target hit registration, enemy reaction, particles, sound, victory, defeat and retry remain in place.

## Frozen real assets

| Asset | Frozen source | Runtime boundary |
|---|---|---|
| Frying pan | Open Playtest `R0001-17630115` | Player-confirmed real sprite and anchors |
| Old mop | Open Playtest `R0020-03582d76` | Player-confirmed real sprite and anchors |
| Shotgun | Open Playtest `R0006-6a492611` | Player-confirmed real sprite; developer-only in-memory melee intent and corrected direction sidecar |

The Shotgun semantic Blueprint remains `sustained_ranged` on disk. The motion-grammar loader verifies its source hashes and applies `heavy_melee` only to a derived in-memory Blueprint inside the explicit developer entry. It does not enter normal Open Playtest flow.

## Rule results

| Rule | Affordance trigger | Compiled normal combo | Compile reason |
|---|---|---|---|
| A | short handle, short body, front mass, broad face/contact | `bash → bash → slam` | short handle + front mass + broad face |
| B | long handle, long body, broad/whole-body contact, no barrel | `sweep → thrust → spin` | long handle + long body + broad whole-body contact without barrel |
| C | long rigid body, barrel, stock | `thrust → sweep → bash` | long rigid body + barrel + stock |

Unmatched structures return exactly `UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A`; there is no uniform-sweep fallback.

The structure compiler accepts only `ObjectAffordanceProfile`, anchors and Alpha bounds. It does not accept or inspect display name, canonical identity, player text, asset ID or run ID. Pan, Broom and Shotgun labels exist only in the developer asset index and launcher.

## Actual Recipe JSON

The deterministic compiler outputs are exported to:

- `data/combat_feel/live_assets/motion_grammar_slice_1a/recipes/frying_pan.json`
- `data/combat_feel/live_assets/motion_grammar_slice_1a/recipes/old_mop.json`
- `data/combat_feel/live_assets/motion_grammar_slice_1a/recipes/shotgun_melee.json`

The Recipe signature covers Hit 1–3, Charge and Dodge primitive data. An automated test verifies each exported signature against a fresh runtime compile.

## Runtime differences now consumed

Normal hits now consume their locked `current_primitive` for:

- start/end angle and extension;
- local offsets;
- startup, active and recovery multipliers;
- reach and hitbox width/length;
- root-motion distance;
- movement allowed during committed phases;
- contact anchor (`tip`, `muzzle`, `whole_body`, `rear_contact`);
- knockback, stagger, hitstop and camera-kick multipliers;
- collision and debug hitbox geometry.

The existing controller still locks a Primitive only when an attack truly starts. Buffered input and hitstop do not switch it early.

## Direction normalization

Pan and Broom direction were human-confirmed after the shared sprite/anchor/hitbox normalization fix. During the 2026-08-07 runtime review, the player clarified that the generated Shotgun source image itself has its barrel facing left, behind the right-facing player. Its developer-only sidecar therefore requires a horizontal runtime mirror. Generic runtime normalization transforms Sprite, GripPrimary, muzzle, rear contact and Hitbox together. Rule C Hit 3 uses the transformed `rear_contact` rather than a Shotgun-name combat branch. The corrected Shotgun orientation awaits a second human confirmation.

## Verification

- Existing Combat Feel tests: 41/41 passed.
- Pan/Broom recipe and direction tests: 11/11 passed.
- Motion Grammar 1A concentrated tests: 11/11 passed.
- Pan, Broom and ShotgunMelee scene smoke launches: passed.
- Automatic model calls: none.

## Deliberately not completed in 1A.1

- Immediate press-to-visual input response remains unchanged; ordinary attacks still begin on release in the existing controller.
- Charge and Dodge retain the legacy global runtime path even though their proposed Primitive data is present in the exported Recipe.
- Minimum body-part pose work for the five Primitive families is not implemented.
- BlindComparison UI, randomized order and answer capture are not implemented.
- Shotgun direction and feel have not yet been human-tested.
- No human 4/5 comparison verdict has been collected.

Therefore the honest verdict is **TECHNICAL PASS / FEEL NOT YET TESTED**, not a claim that the melee reskin problem is solved. The next bounded step is a three-asset human comparison using `scripts/run_motion_grammar_slice_1a.ps1`, followed separately by input-response/body-pose work only if the current differences are still visually unclear.
