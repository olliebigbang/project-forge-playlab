# Forge Motion Grammar Slice 1A — Per-Hit Combo Recipes

Status: **ORTHOGONAL GENERALIZATION TECHNICAL PASS / FEEL NEEDS WORK**

This report preserves the bounded Motion Grammar Slice 1A history and records the later orthogonal-composer generalization checks. The original three-asset Slice eventually passed its frozen comparison, but the newer unseen-identity comparison scored 3/5 and does not pass its feel gate. The current implementation therefore does not claim that the melee reskin problem is solved for new identities.

## Existing combat chain reused

No second compiler, controller, attack state machine, enemy system, or room was added. The implementation continues to use:

`WeaponVisualAsset + AnchorData + ObjectAffordanceProfile → MeleeMotionCompiler → CombatMotionProfile/ComboRecipe → MeleeCombatController → CombatFeelSlice0 + ImpactFeedbackProfile`

The existing input buffer, startup/active/recovery phases, hitstop, one-hit-per-target registration, enemy reactions, particles, sound, camera feedback, victory, defeat, and retry remain in place.

## Frozen real assets

| Asset | Frozen source | Runtime boundary |
|---|---|---|
| Frying pan | Open Playtest `R0001-17630115` | Real processed Sprite, Blueprint, confirmed anchors, Alpha bounds, and developer Affordance sidecar |
| Old mop | Open Playtest `R0020-03582d76` | Real processed Sprite, Blueprint, confirmed anchors, Alpha bounds, and developer Affordance sidecar |
| Shotgun | Approved one-time regeneration `shotgun_regeneration_01-seed_8072026` | Real processed Sprite and confirmed anchors; developer-only in-memory melee intent override |

The Shotgun Blueprint remains `sustained_ranged` on disk. Only the explicit Slice 1A developer entry derives an in-memory `heavy_melee` Blueprint. This override does not enter Open Playtest or any normal player flow.

## Structure rules and actual recipes

| Rule | Affordance trigger | Normal combo | Charge | Dodge |
|---|---|---|---|---|
| A | short handle/body, front mass, broad face/contact | `bash → bash → slam` | `slam` | advancing `bash` |
| B | long handle/body, broad or whole-body contact, no barrel | `sweep → thrust → spin` | wide `sweep` | sliding `sweep` |
| C | long rigid body, barrel, stock | `thrust → sweep → rear bash` | rear `bash` | advancing `thrust` |

Rules are selected only from `ObjectAffordanceProfile`, normalized anchors, Alpha bounds, and structural mass distribution. `MeleeMotionCompiler` does not receive or inspect display name, canonical name, source identity, player text, asset ID, file path, or run ID. Unmatched structures return exactly `UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A`; there is no generic sweep fallback.

The deterministic Recipe JSON remains under `data/combat_feel/live_assets/motion_grammar_slice_1a/recipes/`. Automated checks compare every exported signature with a fresh runtime compile.

## Runtime execution

`MeleeCombatController.current_primitive` is locked when an attack begins. Hit 1, Hit 2, Hit 3, Charge, and Dodge each select their own Recipe primitive. Buffered input and hitstop cannot switch it early; combo timeout returns the next normal attack to Hit 1.

`CombatFeelSlice0` reads the same locked Primitive for:

- weapon start/end angle, local offsets, extension, and trajectory;
- startup, active, and recovery timing;
- reach, root motion, and movement allowed during attack;
- hitbox width/length and collision family;
- contact anchor (`tip`, `muzzle`, `whole_body`, or `rear_contact`);
- debug hitbox rendering;
- knockback, stagger, hitstop, and camera-kick multipliers.

The global `CombatMotionProfile.motion_family` remains only for legacy compatibility metadata. It no longer drives normal, Charge, or Dodge attack pose/collision execution when a Recipe Primitive is present.

## Input response and body poses

Attack press now enters the selected Hit startup immediately, so the next rendered frame shows motion. A short release commits the normal hit; holding through the charge threshold promotes the same input into the Recipe Charge primitive. Input presses during later combo windows are buffered, and hitstop preserves that buffer.

Runtime logs now record `input_to_visual_ms` and `input_to_active_ms`. No human timing sample is claimed until the comparison is run.

The existing part-based player now has minimum procedural participation for all five generic primitives:

- `sweep`: torso twist and broad hand arc;
- `bash`: forward lean and short arm drive;
- `thrust`: forward step and straight extension;
- `slam`: lift followed by body drop;
- `spin`: body rotation and lowered center of mass.

These are procedural test poses, not production frame animation.

### Character Pose Visibility Revision

The first implementation changed pose values, but the visible body displacement at gameplay scale was too small and the arms were still rendered as single shoulder-to-hand lines. The player correctly rejected that as insufficient evidence for section 9.

The bounded revision keeps the same combat controller and procedural renderer, but now:

- renders main and support arms as articulated shoulder-elbow-hand chains;
- applies visible torso rotation, head follow, stance width, stepping, forward lean, and crouch;
- gives `slam` separate raised windup and dropped contact silhouettes;
- gives `sweep`, `bash`, `thrust`, and `spin` visibly different torso, arm, and foot placement;
- provides a deterministic `--pose-capture-dir` evidence mode with windup/contact frames for all five primitives;
- tests minimum visible pose amplitude instead of accepting five merely different dictionaries.

This revision does not alter Recipe selection, timing data, collision rules, damage, feedback tuning, enemies, rooms, or model pipelines. Automated pose evidence is available, but the status remains **CHARACTER POSE VISIBILITY PENDING HUMAN CHECK** until the revised live animation is viewed by the player.

## Direction normalization

Pan and Mop use the existing generic orientation normalization that transforms Sprite, anchors, and hitbox together. The regenerated Shotgun source is intrinsically forward-facing, with `muzzle.x > GripPrimary.x` and `rear_contact.x < GripPrimary.x`. Pan, Mop, and regenerated Shotgun direction/holding were each confirmed by the player on 2026-08-08.

Rule C Hit 3 uses the normalized `rear_contact`; it does not branch on the word Shotgun.

## Blind comparison

Run:

```powershell
cd "C:\Users\Eddie L\Documents\project-forge-playlab"
.\scripts\run_motion_grammar_slice_1a.ps1 -BlindComparison
```

The launcher randomizes the three real assets, displays only A/B/C plus the actual Sprite, hides identity/Recipe/Affordance labels, and requires all three combat runs to complete. It then records five A/B/C answers:

1. shortest reach;
2. widest coverage;
3. heaviest third hit;
4. best crowd control;
5. most forward movement.

It also records explicit qualitative confirmation for Pan, Mop, and Shotgun differences. Results are saved locally to `user://playlab/motion_grammar_slice_1a/blind_comparison_results.jsonl`. The script reports `TECHNICAL PASS / FEEL PASS` only when at least 4/5 answers are correct and all three qualitative confirmations pass; otherwise it reports `TECHNICAL PASS / FEEL NEEDS WORK`. It never claims the game is fun.

## Human blind result

Session: `blind-20260807T145145295Z-f859b287`

Randomized mapping:

- A: frying pan
- B: old mop
- C: Shotgun stock melee

| Question | Player answer | Expected | Result |
|---|---:|---:|---|
| Shortest reach | C | A | Incorrect |
| Widest coverage | B | B | Correct |
| Heaviest third hit | B | C | Incorrect |
| Best crowd control | B | B | Correct |
| Most forward movement | B | C | Incorrect |

Blind score: **2/5**. All three post-run qualitative confirmations were `yes`, but those confirmations do not override the frozen 4/5 blind threshold.

Recorded run evidence:

| Label | Completion time | Last recorded input-to-visual | Last recorded input-to-active |
|---|---:|---:|---:|
| A | 28.13 s | 297 ms | 582 ms |
| B | 25.58 s | 0 ms | 309 ms |
| C | 41.34 s | 0 ms | 279 ms |

The correct formal result is **TECHNICAL PASS / FEEL NEEDS WORK**. The widest/control distinction for the Mop was readable, but Pan shortness and the Shotgun's forward drive/heavy third hit were not reliably distinguishable in blind play.

## Bounded feel-tuning pass after the failed blind test

The failed dimensions received one structure-rule-only tuning pass. No controller, input system, enemy, room, asset, semantic field, or model pipeline was changed.

Rule A (`short handle + front mass + broad face`) now has:

- compiled reach clamped to 72–80 px;
- normal combo root motion reduced from `8/8/10` to `4/4/7` px;
- shorter per-hit reach and hitbox-length multipliers;
- slightly smaller rendering scale.

Rule C (`long rigid body + barrel + stock`) now has:

- normal combo root motion increased from `32/22/28` to `52/34/50` px;
- a longer Hit 1 thrust extension;
- Hit 3 recovery increased to `1.40×`;
- Hit 3 knockback, stagger, and hitstop increased to `1.55×`;
- Hit 3 camera kick increased to `1.50×`;
- Charge and Dodge forward motion increased consistently with the same structural rule.

The Mop/Rule B Recipe was not changed. Updated deterministic signatures are stored only for the Pan and Shotgun Recipe JSON. The original 2/5 blind record remains preserved in local JSONL history. This tuning does not change the formal status until a new blind run is completed.

## Human blind retest after bounded tuning

Session: `blind-20260807T152040784Z-e67fd4bc`

Randomized mapping:

- A: old mop
- B: frying pan
- C: Shotgun stock melee

| Question | Player answer | Expected | Result |
|---|---:|---:|---|
| Shortest reach | C | B | Incorrect |
| Widest coverage | A | A | Correct |
| Heaviest third hit | B | C | Incorrect |
| Best crowd control | A | A | Correct |
| Most forward movement | C | C | Correct |

Retest score: **3/5**. Shotgun forward movement improved from incorrect to correct. Mop width and control remained readable. Pan shortest reach and Shotgun heaviest third hit remained incorrect.

Post-run qualitative confirmation was `yes` for Pan and Mop, but `no` for Shotgun linear advancement/heaviest-third as a combined statement. The frozen threshold remains unmet, so the result stays **TECHNICAL PASS / FEEL NEEDS WORK**. No second automatic tuning pass is performed.

## Rule C contact-reliability pass after human diagnosis

The player then identified a more precise failure: the Shotgun Hit 1 thrust and Hit 3 rear-stock bash were difficult to land. The third hit being the heaviest remained conceptually correct, but its feedback was often not perceived because the contact missed. This evidence justified one narrow contact-reliability pass; it did not justify another increase to damage, hitstop, stagger, knockback, or camera strength.

The generic runtime changes are:

- thrust collision now retains a bounded rear tolerance after root movement, so a close target is not skipped when the attacker advances through the original hand plane;
- the F3 debug thrust rectangle is generated by the same helper as collision, preventing visual/collision drift;
- Rule C Hit 1 active time is `1.15x`, width is `0.95x`, and immediate root movement is reduced from `52` to `42` px;
- Rule C Hit 3 active time is `1.25x`, its bounded rear-contact radius is enlarged through `1.30x` hitbox and `1.25x` width multipliers, and immediate root movement is reduced from `50` to `44` px;
- Rule C Hit 3 impact multipliers remain unchanged at the already frozen tuned values (`1.55x` knockback/stagger/hitstop and `1.50x` camera kick);
- each normal combo index now records attempts, successful attacks, and whiffs in F3 debug output, local questionnaire records, and BlindComparison run evidence.

The change is still structure-driven by Rule C (`long rigid body + barrel + stock`). It does not inspect the Shotgun name or asset ID.

### Focused Shotgun verification

On 2026-08-08, the player completed the focused `ShotgunMelee` run after the contact-reliability pass and accepted the revised Hit 1 / Hit 3 contact as **PASS**. This is a qualitative single-asset verification only. It confirms that the bounded contact correction is usable; it does not replace the frozen three-asset BlindComparison threshold and does not change the overall Slice verdict by itself.

## Final human blind verification

Session: `blind-20260807T234515908Z-514d3e4f`

Randomized mapping:

- A: frying pan
- B: Shotgun stock melee
- C: old mop

| Question | Player answer | Expected | Result |
|---|---:|---:|---|
| Shortest reach | A | A | Correct |
| Widest coverage | C | C | Correct |
| Heaviest third hit | B | B | Correct |
| Best crowd control | C | C | Correct |
| Most forward movement | B | B | Correct |

Final blind score: **5/5**. Pan short/fast/heavy-slap, Mop long/wide/control-oriented, and Shotgun linear/advancing/heaviest-third confirmations were all `yes`.

The new per-hit evidence also shows the focused Rule C correction working during blind combat: Shotgun Hit 1 recorded `8/10` successful attempts and Hit 3 recorded `6/6`, with `0` Hit 3 whiffs. This evidence is descriptive rather than a new threshold.

The frozen acceptance threshold (at least 4/5 plus all three qualitative confirmations) is met. The formal Slice result is **TECHNICAL PASS / FEEL PASS**. As required, this does not claim the game is fun and does not authorize further systems or content.

The exact final comparison record and its three A/B/C run records are frozen under `data/combat_feel/live_assets/motion_grammar_slice_1a/evidence/final_blind_20260807T234515908Z/`. `evidence_hashes.json` records SHA-256 and byte length; the frozen records were byte-compared with the local Godot source evidence before commit.

## Verification

- Combat Feel concentrated tests: **42/42 passed**.
- Pan/Mop Recipe and orientation tests: **11/11 passed**.
- Motion Grammar Slice 1A tests: **19/19 passed**.
- Playlab deterministic baseline: **32/32 passed**.
- Character pose visibility captures: **10/10 windup/contact PNGs generated for five primitives**.
- Legacy, Pan, Mop, and ShotgunMelee scene smoke launches: **passed**.
- Human BlindComparison: **initial 2/5, bounded-tuning retest 3/5, final contact-reliability retest 5/5; FEEL PASS**.
- `git diff --check`: **passed**.
- Anthropic, FLUX, BiRefNet, and ComfyUI calls: **0**.
- New enemies, rooms, ranged/returning combat, or V2 work: **0**.

## Remaining risks

Remaining risks:

- the revised procedural body poses have automated amplitude and screenshot evidence but still require live human visibility confirmation;
- the three Recipes can be numerically different yet still feel similar;
- the five-question result can be affected by enemy spacing and player execution;
- the Slice uses developer-authored Affordance sidecars, not a production authoring path;
- the Shotgun melee intent remains a developer-only test override.

The final unchanged three-asset BlindComparison passed at 5/5 with all qualitative weapon confirmations. Combo Grammar remains **TECHNICAL PASS** and weapon differentiation remains **FEEL PASS**. Character pose visibility is a separately tracked **PENDING HUMAN CHECK** item after the bounded visibility revision; no broader development is authorized.

## Orthogonal-composer supersession retest

The 5/5 result above remains historical evidence for the previous three-rule
compiler. It was marked `SUPERSEDED_FOR_ORTHOGONAL_COMPOSER_ACCEPTANCE` before
the score-based orthogonal composer was evaluated and is not reused as evidence
for the new composer.

After the bounded semantic v1.2.1 targeted retest passed 4/4, the player
separately approved and completed a new three-asset BlindComparison using the
orthogonal compiler without further tuning.

Session: `blind-20260808T130540547Z-65f7d463`

Randomized mapping:

- A: frying pan
- B: old mop
- C: Shotgun stock melee

| Question | Player answer | Expected | Result |
|---|---:|---:|---|
| Shortest reach | A | A | Correct |
| Widest coverage | B | B | Correct |
| Heaviest third hit | A | C | Incorrect |
| Best crowd control | B | B | Correct |
| Most forward movement | B | C | Incorrect |

The orthogonal-composer retest scored **3/5**. Pan and Mop qualitative
confirmations were `yes`; the combined Shotgun linear/advancing/heaviest-third
confirmation was `no`. Shotgun run evidence recorded Hit 1 at 7/9, Hit 2 at
1/6, and Hit 3 at 2/4 successful contacts. This supports a bounded
contact/readability diagnosis, but it does not authorize automatic tuning or a
repeat run.

The current formal result is **TECHNICAL PASS / FEEL NEEDS WORK**. The exact
comparison record and A/B/C run records are frozen under
`data/combat_feel/live_assets/motion_grammar_slice_1a/evidence/orthogonal_blind_20260808T130540547Z/`.

## Twelve-profile orthogonal coverage audit

The eight frozen strict-valid v1.2 affordance profiles and four separately
frozen strict-valid targeted v1.2.1 profiles were combined in a versioned
offline handoff. They were not represented as one homogeneous 12/12 model run.
Only anonymous affordance profiles, case IDs, neutral anchors, and neutral alpha
bounds entered the existing `MeleeMotionCompiler`; identity labels were joined
after compilation for the report table.

Results:

- 12/12 profiles compiled through the existing compiler;
- seven distinct Hit 1 -> Hit 2 -> Hit 3 sequences;
- 12 distinct mechanical parameter Recipes after excluding evidence text and
  reporting metadata from the mechanical signature;
- all five primitives appeared in ordinary combo hits;
- the most common sequence appeared in 3/12 cases (25%);
- no single-sequence or >=50% dominant-sequence warning;
- no object-name, asset-ID, run-ID, or case-specific Recipe branch was added.

The exact `affordance -> dominant mechanism scores -> primitive sequence`
matrix and frozen hashes are stored in
`tools/semantic/reports/affordance_combined_handoff_v1_2_1/affordance-combined-v1-2-1-20260808T132129343Z/`.

This audit resolves the structural coverage question: the orthogonal composer
does not reduce the twelve frozen inputs to one reskinned attack. It does not
override the separate 3/5 human result. The next investigation must concern
generic causal axis readability across anonymous profiles, not Shotgun-specific
or other identity-specific tuning.

## Anonymous local-axis causality audit

The follow-up audit used one anonymous neutral Affordance profile, fixed neutral
anchors and alpha bounds, and 25 legal counterfactuals. Twenty-three probes
changed mechanism inputs one axis at a time; two controls changed only
confidence or evidence wording and were required to remain mechanically
invariant. Object names, case IDs, assets, prompts, and model calls were absent.

The audit compares actual `CombatMotionProfile` fields and all five generated
`MotionPrimitive` specs after removing scores, trace text, confidence, evidence
wording, and report metadata. A changed primitive score by itself is not counted
as a runtime effect.

Result: **NEEDS WORK**.

- 15/23 mechanism probes changed runtime mechanics;
- 8/23 changed scores only and were masked by selection thresholds;
- 0/23 were completely unread by the scorer;
- 2/2 non-mechanical invariant controls passed;
- active axes included handle/body length, primary contact, mass distribution,
  handleless body grip, barrel, and stock;
- partially masked axes included grip topology, rigidity, and secondary contact;
- point, edge, and broad-face feature flags were score-only on the neutral
  baseline.

This explains how corpus-level diversity can coexist with weak perceptual
control: the Composer creates several Recipes globally, but some legitimate
one-axis changes disappear locally unless they cross an argmax boundary. The
evidence and complete probe matrix are frozen under
`tools/semantic/reports/affordance_axis_causality/affordance-axis-causality-20260808T133454359Z/`.

No weights or runtime behavior were changed by this audit. A future correction
must couple those generic axes to continuous runtime parameters or another
identity-free composition mechanism; it must not tune a named sample.

## Generic continuous-coupling correction

The correction kept Primitive scoring and winner weights unchanged. It added
identity-free parameter coupling only where the anonymous audit had found local
threshold masking:

- an available point contributes bounded reach;
- an available edge and semi-rigid/flexible structure contribute swing arc;
- a broad face contributes hitbox thickness;
- a clamp grip contributes bounded startup, recovery, and movement commitment;
- a secondary contact surface contributes bounded control strength.

These fields are consumed by the existing `CombatFeelSlice0` collision and
`ImpactFeedbackProfile` paths. No object name, asset ID, prompt, model result,
or sample-specific Recipe branch is involved. The three derived Recipe JSON
files were regenerated from the same Compiler; their ComboRecipe signatures did
not change because this correction affects profile-level continuous parameters,
not the selected Primitive sequence or its winner weights.

The non-overwriting follow-up audit at
`tools/semantic/reports/affordance_axis_causality/affordance-axis-causality-20260808T134512827Z/`
reports **PASS**: 23/23 mechanism probes changed actual runtime parameters,
0 were score-only masked, 0 were silent, and both non-mechanical controls
remained invariant. This is a technical causality result only; the governing
human verdict remains **FEEL NEEDS WORK** until a new approved comparison.

## Unseen-identity generalization blind comparison

The new comparison did not reuse the original Frying Pan, Old Mop, or Shotgun
assets. It used three frozen real Sprites through the same
`MeleeMotionCompiler -> MeleeCombatController -> CombatFeelSlice0` chain:

- a player-confirmed Open Playtest Longsword;
- a player-confirmed Open Playtest Spear;
- a frozen generated Wooden Chair, bound only for this developer test to an
  existing heavy-melee semantic result and existing manual anchor calibration.

The Chair binding is explicitly developer-only, performs no model call, does
not enter normal player flow, and stores no Recipe. All three Recipes are
compiled at runtime from their frozen Affordance profiles. The blind launcher
derives expected answers from the actual compiled runtime metrics rather than
from object-name mappings.

Session: `generalization-blind-20260808T140834789Z-61b35914`

Randomized mapping and compiled combo:

| Label | Frozen identity | Primitive sequence |
|---|---|---|
| A | Longsword | `sweep -> thrust -> slam` |
| B | Spear | `thrust -> thrust -> slam` |
| C | Wooden Chair | `sweep -> spin -> slam` |

| Question | Player answer | Runtime-metric answer | Result |
|---|---:|---:|---|
| Shortest reach | C | C | Correct |
| Widest coverage | B | C | Incorrect |
| Heaviest third hit | B | B | Correct |
| Best crowd control | B | C | Incorrect |
| Most forward movement | B | B | Correct |

Blind score: **3/5**.

The player confirmed that the three objects felt materially different and that
the motions were plausible for the visible structures. The player also answered
`yes` when asked whether they still felt like the same moves with swapped
Sprites. That last answer is retained as an explicit residual-reskin concern;
it is not overwritten by the two positive confirmations.

The runtime evidence shows three distinct Recipe signatures and three distinct
normal-combo sequences. It also shows that the two failed dimensions were not
perceived in the same order as their compiled values: the Chair had the highest
computed coverage and control scores, while the player selected the Spear for
both. This is a metric-to-perception failure, not evidence that all three
Recipes serialized identically. No automatic tuning is authorized from this
single result.

Formal result: **TECHNICAL PASS / FEEL NEEDS WORK**.

The exact comparison record, all three A/B/C run records, and their hashes are
frozen under
`data/combat_feel/live_assets/motion_grammar_generalization_v1/evidence/generalization_blind_20260808T140834789Z/`.

## Runtime-realization follow-up

An anonymous one-axis runtime audit now exercises the existing collision,
timing, root-motion, feedback, and character-pose consumers rather than treating
a changed compiled field as sufficient proof. The high-resolution frozen run
passed 21/23 mechanical monotonic contracts and both invariant controls.

The remaining generic failures are `mass_distribution = rear` (runtime changes
in the wrong direction relative to balanced) and `has_stock = true` (compiled
profile change with no measured combat-runtime result when varied alone). The
point-feature reach increase was confirmed at one-pixel resolution and is not a
remaining failure.

No named asset, identity, Recipe fixture, Compiler weight, model, or combat
behavior was changed. The three generalization assets and the twelve frozen
profiles remain evidence only, not tuning samples. Until the two anonymous
consumer defects are corrected, the runtime-realization status is
**NEEDS WORK**, independently of earlier per-profile causality and feel results.

Evidence:
`tools/semantic/reports/affordance_runtime_realization/affordance-runtime-realization-20260808T153433399Z/`.

### Generic correction result

The two failed anonymous consumers were corrected generically. Rear-distributed
mass is now ordered below balanced mass for startup and contact force. A stock
now provides a rear finisher contact without requiring an additional secondary
surface declaration, and a missing rear anchor is resolved from Alpha/bounds
opposite the Grip-to-function axis.

The non-overwriting follow-up passed **23/23** mechanical properties and both
invariants. It used the same anonymous scenarios, neutral asset harness, frozen
12-profile coverage set, and real combat consumers. No identity branch, model
call, new Primitive, enemy, room, or parallel controller was introduced.

Current runtime-realization result: **PASS**. This does not overwrite the
separate generalization human verdict of **FEEL NEEDS WORK**. Evidence:
`tools/semantic/reports/affordance_runtime_realization/affordance-runtime-realization-20260808T154441435Z/`.
