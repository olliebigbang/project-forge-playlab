# Orthogonal Motion Grammar — implementation status

## Outcome

The existing `MeleeMotionCompiler -> MeleeCombatController -> CombatFeelSlice0`
runtime chain is retained. The three exact sample matchers have been replaced by
one identity-free, score-based composer over orthogonal affordance axes.

Current status:

- **OFFLINE TECHNICAL PASS**
- **REAL AI AFFORDANCE VALIDATION PENDING**
- **HUMAN FEEL RETEST PENDING**

The earlier three-sample 5/5 result is preserved as historical evidence and is
marked `SUPERSEDED` by the adjacent supersession ledger. It is not evidence for
the new composer.

## Runtime boundary

The compiler accepts only `ObjectAffordanceProfile`, anchor data, and alpha
bounds. It does not accept identity text, display names, asset IDs, paths, or
run IDs. Invalid, contradictory, incomplete, or low-confidence profiles fail
closed with `UNSUPPORTED_AFFORDANCE_FOR_SLICE_1A` / `AFFORDANCE_NOT_READY`.

The frozen semantic v1.1 contract remains the default Open Playtest contract.
`forge-semantic-v1.2-candidate` is an offline candidate only. Its sidecar can be
published atomically only after strict validation. No Anthropic, FLUX,
BiRefNet, or ComfyUI call was made for this implementation.

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
| A01 | kitchen knife | — | — | — | PENDING REAL CALL |
| A02 | longsword | — | — | — | PENDING REAL CALL |
| A03 | fire axe | — | — | — | PENDING REAL CALL |
| A04 | spear | — | — | — | PENDING REAL CALL |
| A05 | hammer | — | — | — | PENDING REAL CALL |
| A06 | baseball bat | — | — | — | PENDING REAL CALL |
| A07 | chair | — | — | — | PENDING REAL CALL |
| A08 | fire extinguisher | — | — | — | PENDING REAL CALL |
| A09 | shield | — | — | — | PENDING REAL CALL |
| A10 | giant chicken leg | — | — | — | PENDING REAL CALL |
| A11 | folding stool | — | — | — | PENDING REAL CALL |
| A12 | fishing rod | — | — | — | PENDING REAL CALL |

## Acceptance implications

All five primitives are reachable through an orthogonal synthetic basis. The
three retained real assets produce distinct signatures, Pan has the shortest
reach, Mop has the widest contact coverage, and the barrel/stock structure has
the greatest root-motion total. No exact multiplier or legacy sequence is an
acceptance requirement.

The next authorized step is a bounded v1.2 real-model affordance retest for the
12 frozen inputs, followed by one new BlindComparison. Until both are reviewed,
the orthogonal composer must not be promoted to the default player flow.
