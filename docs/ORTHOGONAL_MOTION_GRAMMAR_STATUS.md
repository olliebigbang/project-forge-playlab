# Orthogonal Motion Grammar — implementation status

## Outcome

The existing `MeleeMotionCompiler -> MeleeCombatController -> CombatFeelSlice0`
runtime chain is retained. The three exact sample matchers have been replaced by
one identity-free, score-based composer over orthogonal affordance axes.

Current status:

- **OFFLINE TECHNICAL PASS**
- **REAL AI AFFORDANCE VALIDATION NEEDS WORK (8/12 strict-valid)**
- **HUMAN FEEL RETEST BLOCKED**

The earlier three-sample 5/5 result is preserved as historical evidence and is
marked `SUPERSEDED` by the adjacent supersession ledger. It is not evidence for
the new composer.

## Runtime boundary

The compiler accepts only `ObjectAffordanceProfile`, anchor data, and alpha
bounds. It does not accept identity text, display names, asset IDs, paths, or
run IDs. Invalid, contradictory, incomplete, or low-confidence profiles fail
closed with `UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A` / `AFFORDANCE_NOT_READY`.

The frozen semantic v1.1 contract remains the default Open Playtest contract.
`forge-semantic-v1.2-candidate` remains a non-default candidate. A bounded
12-call Anthropic retest was executed after explicit approval with the frozen
`claude-sonnet-5` model: eight results passed the strict candidate contract and
compiled through the existing `MeleeMotionCompiler`; four were rejected. FLUX,
BiRefNet, ComfyUI, and the new BlindComparison were not started.

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
| A03 | fire axe | rejected by canonical `fire` false-positive | — | — | CONTRACT/RUNNER NEEDS WORK |
| A04 | spear | strict-valid | long/front/point | thrust → thrust → slam | COMPILED |
| A05 | hammer | strict-valid | long/front/broad | bash → slam → sweep | COMPILED |
| A06 | baseball bat | strict-valid | medium/front/broad | bash → slam → bash | COMPILED |
| A07 | chair | unknown extra field | — | — | MODEL SCHEMA FAILURE |
| A08 | fire extinguisher | rejected by canonical `fire` false-positive | — | — | CONTRACT/RUNNER NEEDS WORK |
| A09 | shield | contradictory body-grip/short-handle pair | — | — | MODEL CROSS-FIELD FAILURE |
| A10 | giant chicken leg | strict-valid | short/front/broad | bash → slam → bash | COMPILED |
| A11 | folding stool | strict-valid | none/front/broad | bash → slam → bash | COMPILED |
| A12 | fishing rod | strict-valid | medium+long/rear/flexible whole-body | sweep → spin → slam | COMPILED |

## Acceptance implications

All five primitives are reachable through an orthogonal synthetic basis. The
three retained real assets produce distinct signatures, Pan has the shortest
reach, Mop has the widest contact coverage, and the barrel/stock structure has
the greatest root-motion total. No exact multiplier or legacy sequence is an
acceptance requirement.

The next step is an offline contract/runner correction for the four failed
paths. A maximum four-call targeted retest requires new approval after those
offline regressions pass. The new BlindComparison remains blocked; the
orthogonal composer must not be promoted to the default player flow.
