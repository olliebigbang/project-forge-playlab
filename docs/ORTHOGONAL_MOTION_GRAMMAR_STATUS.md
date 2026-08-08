# Orthogonal Motion Grammar — implementation status

## Outcome

The existing `MeleeMotionCompiler -> MeleeCombatController -> CombatFeelSlice0`
runtime chain is retained. The three exact sample matchers have been replaced by
one identity-free, score-based composer over orthogonal affordance axes.

Current status:

- **OFFLINE TECHNICAL PASS**
- **REAL AI AFFORDANCE COVERAGE PASS WITH VERSIONED EVIDENCE**
- **12-PROFILE COMPOSER COVERAGE PASS (7 sequences, all 5 primitives)**
- **ANONYMOUS LOCAL AXIS CAUSALITY NEEDS WORK (15/23 runtime effects)**
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

The approved orthogonal-composer BlindComparison was completed as session
`blind-20260808T130540547Z-65f7d463`. It scored **3/5**. Pan was correctly felt
as shortest and Mop as widest/best for control, but Shotgun stock was not felt
as the heaviest third hit or the greatest forward progression. The qualitative
Shotgun confirmation was also `no`. Runtime evidence recorded Shotgun Hit 2 at
1/6 successful contacts and Hit 3 at 2/4, which is consistent with the failed
feel read rather than a semantic or asset-identity failure.

The governing state is therefore **TECHNICAL PASS / FEEL NEEDS WORK**. The
orthogonal composer must not be promoted to the default player flow. The next
change, if separately approved, must audit or calibrate generic causal axis
effects with anonymous counterfactual profiles. The audit is now complete and
shows that score-only fields need a generic continuous parameter coupling or a
similarly identity-free composition rule so their effect survives even when
the winning Primitive does not change. It must not target Shotgun, Pan, Mop,
any case ID, or any identity label, and it must not silently tune until the
questionnaire passes.
