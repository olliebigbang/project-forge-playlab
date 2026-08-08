# Orthogonal Motion Grammar — implementation status

## Outcome

The existing `MeleeMotionCompiler -> MeleeCombatController -> CombatFeelSlice0`
runtime chain is retained. The three exact sample matchers have been replaced by
one identity-free, score-based composer over orthogonal affordance axes.

Current status:

- **OFFLINE TECHNICAL PASS**
- **REAL AI AFFORDANCE COVERAGE PASS WITH VERSIONED EVIDENCE**
- **12-PROFILE COMPOSER COVERAGE PASS (7 sequences, all 5 primitives)**
- **ANONYMOUS LOCAL AXIS CAUSALITY PASS AFTER GENERIC COUPLING (23/23)**
- **ANONYMOUS COMBAT-RUNTIME REALIZATION PASS AFTER GENERIC CORRECTION (23/23)**
- **OPEN PLAYTEST AFFORDANCE HANDOFF FAILS CLOSED**
- **HUMAN FEEL RETEST NEEDS WORK (3/5)**

The earlier three-sample 5/5 result is preserved as historical evidence and is
marked `SUPERSEDED` by the adjacent supersession ledger. It is not evidence for
the new composer.

## Runtime boundary

The compiler accepts only `ObjectAffordanceProfile`, anchor data, and alpha
bounds. It does not accept identity text, display names, asset IDs, paths, or
run IDs. Invalid, contradictory, incomplete, or low-confidence profiles fail
closed with `UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A` / `AFFORDANCE_NOT_READY`.

The frozen semantic v1.1 contract remains the default Open Playtest contract.
`forge-semantic-v1.2-candidate` and the additive v1.2.1 correction remain
non-default candidates. A bounded 12-call Anthropic retest produced eight
strict-valid results. A separately approved four-call v1.2.1 targeted retest
then produced strict-valid results for A03, A07, A08, and A09: 4/4 API success,
4/4 sole legal tool use, 4/4 Schema and cross-field valid, and zero retries.
Together these frozen runs cover all 12 inputs, but they are explicitly not
represented as one homogeneous 12/12 run under one contract version. FLUX,
BiRefNet, and ComfyUI were not started.

The manual runtime boundary is exposed as
`scripts/run_combat_feel_slice.ps1 -OpenPlaytestRound <path> -RequireAffordanceGrammar`.
That switch rejects a missing sidecar instead of entering the legacy compiler.

Open Playtest now preserves that same boundary. If a semantic result contains a
complete candidate `affordance`, the bridge validates the entire candidate
blueprint and atomically writes `object_affordance_profile.json` beside the
round asset. The UI exposes Combat Feel only for that validated handoff and
always launches it with `--require-affordance-grammar`. A default v1.1 result
has no affordance sidecar, remains usable in the basic preview, and cannot be
misrepresented as Motion Grammar combat. No identity-derived approximation is
inserted.

## Current real-asset compile table

| Asset | Affordance axes that dominate | Hit 1 → Hit 2 → Hit 3 | Status |
|---|---|---|---|
| frying_pan | short, rigid, front mass, broad face | bash → slam → bash | regenerated offline |
| old_mop | long, semi-rigid, whole-body contact | sweep → spin → slam | regenerated offline |
| shotgun_melee | long rigid body, point front, broad rear stock | thrust → bash → bash (rear contact on Hit 3) | developer-only override |

These sequences are outputs, not acceptance snapshots. Tests assert properties,
determinism, traceability, and ordinal gameplay relationships rather than these
exact strings.

## Frozen 12-case handoff table

The blind inputs are frozen in
`tools/semantic/cases/affordance_blind_12_candidate.json`. The following columns
must be filled only from a future approved real-model run; manual guesses must
not be presented as AI output.

| Case | Object | Model affordance | Dominant mechanism axes | Compiled combo | State |
|---|---|---|---|---|---|
| A01 | kitchen knife | strict-valid | short/front/edge | sweep → bash → slam | COMPILED |
| A02 | longsword | strict-valid | short+long/balanced/edge+point | sweep → thrust → slam | COMPILED |
| A03 | fire axe | v1.2.1 targeted strict-valid | long/front/edge+point | sweep → thrust → slam | COMPILED |
| A04 | spear | strict-valid | long/front/point | thrust → thrust → slam | COMPILED |
| A05 | hammer | strict-valid | long/front/broad | bash → slam → sweep | COMPILED |
| A06 | baseball bat | strict-valid | medium/front/broad | bash → slam → bash | COMPILED |
| A07 | chair | v1.2.1 targeted strict-valid | none/body-grip/front/whole-body | sweep → spin → slam | COMPILED |
| A08 | fire extinguisher | v1.2.1 targeted strict-valid | none/body-grip/balanced/whole-body | sweep → spin → slam | COMPILED |
| A09 | shield | v1.2.1 targeted strict-valid | short/clamp-grip/balanced/broad | bash → sweep → slam | COMPILED |
| A10 | giant chicken leg | strict-valid | short/front/broad | bash → slam → bash | COMPILED |
| A11 | folding stool | strict-valid | none/front/broad | bash → slam → bash | COMPILED |
| A12 | fishing rod | strict-valid | medium+long/rear/flexible whole-body | sweep → spin → slam | COMPILED |

## Acceptance implications

All five primitives are reachable through an orthogonal synthetic basis. The
three retained real assets produce distinct signatures, Pan has the shortest
reach, Mop has the widest contact coverage, and the barrel/stock structure has
the greatest root-motion total. No exact multiplier or legacy sequence is an
acceptance requirement.

The versioned twelve-profile handoff was compiled through the same existing
`MeleeMotionCompiler` with one neutral anchor/bounds basis. It produced 12/12
valid compilations, seven distinct normal-combo sequences, 12 mechanically
distinct parameter Recipes, and normal-combo use of all five primitives. The
most frequent sequence appears in 3/12 cases (25%), so the corpus has not
collapsed to one default combo. The complete reproducible matrix is frozen in
`tools/semantic/reports/affordance_combined_handoff_v1_2_1/affordance-combined-v1-2-1-20260808T132129343Z/`.

A stricter anonymous local-causality audit then changed one legal structural
axis at a time against a neutral profile. Only 15/23 mechanism probes changed
the actual runtime profile or MotionPrimitive specs. Eight probes changed
internal scores but were swallowed by winner-selection thresholds: clamp grip,
semi-rigid, secondary edge/broad/whole-body contact, and the point/edge/broad-
face feature flags. No probe was fully unread by the scorer, and the confidence
and evidence-text controls correctly remained mechanically invariant (2/2).
The frozen audit is in
`tools/semantic/reports/affordance_axis_causality/affordance-axis-causality-20260808T133454359Z/`.

That failure evidence remains frozen. A generic correction then coupled the
masked structural facts to already-consumed continuous mechanics without
changing Primitive winner weights: point to reach, edge and rigidity to swing
arc, broad face to hitbox thickness, clamp grip to timing and movement, and
secondary contact to control strength. The follow-up anonymous matrix passed 23/23 mechanism probes,
with zero score-only or silent probes and both non-mechanical controls still
invariant. Its evidence is frozen in
`tools/semantic/reports/affordance_axis_causality/affordance-axis-causality-20260808T134512827Z/`.

The approved orthogonal-composer BlindComparison was completed as session
`blind-20260808T130540547Z-65f7d463`. It scored **3/5**. Pan was correctly felt
as shortest and Mop as widest/best for control, but Shotgun stock was not felt
as the heaviest third hit or the greatest forward progression. The qualitative
Shotgun confirmation was also `no`. Runtime evidence recorded Shotgun Hit 2 at
1/6 successful contacts and Hit 3 at 2/4, which is consistent with the failed
feel read rather than a semantic or asset-identity failure.

The governing state remains **TECHNICAL PASS / FEEL NEEDS WORK**. The anonymous
causality defect is corrected, but that technical result cannot replace the
existing 3/5 human comparison. The orthogonal composer must not be promoted to
the default player flow until a separately approved human retest verifies that
the parameter differences are perceptible. Any such retest must use the generic
Composer unchanged and must not tune Shotgun, Pan, Mop, a case ID, or an
identity label to make the questionnaire pass.

## Anonymous combat-runtime realization audit

The earlier 23/23 causality result proves that every mechanical field changes a
compiled `CombatMotionProfile` or `MotionPrimitive`. It does not prove that the
changed value survives the selected Primitive and reaches collision, timing,
movement, feedback, or the rendered character pose. A second anonymous audit
therefore instantiated the existing `CombatFeelSlice0` directly and measured:

- the real `_attack_contains()` collision result across each active trajectory;
- `CombatMotionProfile.timing_for()`;
- root motion and movement allowance;
- `ImpactFeedbackProfile.for_attack()`;
- the current Primitive-driven character pose.

The diagnostic high-resolution run passed **21/23** mechanical property probes
and **2/2** non-mechanical invariants. It found two generic defects:

- `mass_distribution = rear` produces slower startup and stronger knockback
  than the neutral balanced profile, the opposite of the declared rear-loaded
  monotonic property;
- `has_stock = true` changes the compiled profile but produces no measured
  combat-runtime difference when varied alone.

The `has_point` probe initially appeared to fail under an 8-pixel extent grid.
A non-overwriting successor run refined the affected hit's forward boundary to
one-pixel precision and measured the expected increase from 170 to 174 pixels.
The preliminary run is retained with an explicit supersession marker.

All twelve frozen affordance profiles were also executed through the same
neutral runtime harness as coverage witnesses. They were not used as tuning
targets. No Grammar weights, named-asset branches, model contracts, assets, or
combat runtime behavior were changed by this audit.

Formal result: **RUNTIME REALIZATION NEEDS WORK (21/23)**. The next correction
must address only the two failed generic axes, then rerun this same matrix before
any new real-asset human blind test. The corrected evidence is frozen under
`tools/semantic/reports/affordance_runtime_realization/affordance-runtime-realization-20260808T153433399Z/`.

### Generic runtime-consumer correction

The two remaining defects were corrected without reading an identity or tuning
a retained sample:

- the continuous mass axis is now ordered `rear < balanced < front`, so mass
  closer to the grip reduces startup commitment and delivered contact feedback;
- `has_stock` now independently makes a rear `bash` available for a finisher,
  with an explicitly declared secondary surface refining its width rather than
  being required for the stock to exist mechanically;
- when a generated asset has no explicit rear-contact anchor, the existing
  combat runtime derives it generically by searching the Alpha body opposite
  the Grip-to-function axis, then falls back to the opaque-bounds intersection.

The non-overwriting rerun passed **23/23** mechanical monotonic contracts and
**2/2** invariant controls. The rear-mass probe changed total startup from
0.5554 to 0.5371 and total knockback from 454.65 to 437.93. The stock-only probe
changed the normal combo from `bash -> sweep -> slam` to
`bash -> sweep -> bash`, with Hit 3 using `rear_contact`.

Only the affected derived Shotgun Recipe JSON changed after regeneration; Pan
and Mop Recipe bytes remained unchanged. The 21/23 evidence is preserved and
marked superseded. Current formal result: **RUNTIME REALIZATION PASS (23/23)**.
This remains a technical property result, not a human claim that the game feels
good. Evidence:
`tools/semantic/reports/affordance_runtime_realization/affordance-runtime-realization-20260808T154441435Z/`.
