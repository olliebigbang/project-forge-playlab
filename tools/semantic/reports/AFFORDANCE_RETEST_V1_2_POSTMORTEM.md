# Affordance Retest v1.2 — independent offline postmortem

## Verdict boundary

- Frozen official automatic verdict: **NEEDS WORK**.
- Independent forensic verdict: **8/12 strict candidate outputs usable; 4/12 rejected**.
- Promotion: **blocked**. Do not start a new BlindComparison from this run.
- Real calls: 12 reserved, 12 observed, zero retries.
- Image and gameplay services: FLUX, BiRefNet, ComfyUI, and BlindComparison were not started.

This postmortem is additive. It does not alter the frozen run directory,
automatic summary, CSV, raw-response evidence, or evidence hashes.

## Failure ownership

| Case | Frozen automatic path | Actual evidence | Primary owner | Classification |
|---|---|---|---|---|
| A03 fire axe | `$.identity.canonical_name_en` | The local error says canonical identity contained `fire`; the runner failed before preserving the parsed tool input or redacted raw response. | contract + runner | The v1.1 pollution rule treats the lexicalized identity `fire axe` as an effect modifier. The runner then misreported a completed API response as a local/API failure and lost the redacted response. |
| A07 wooden chair | `/affordance/has_broad_face_evidence` | Model emitted the extra field `has_broad_face_evidence: true`. | model | Closed Schema correctly rejected an unknown field. No repair, unwrap, coercion, or default is permitted. |
| A08 fire extinguisher | `$.identity.canonical_name_en` | The local error says canonical identity contained `fire`; the runner failed before preserving the parsed tool input or redacted raw response. | contract + runner | The v1.1 pollution rule treats the lexicalized identity `fire extinguisher` as an effect modifier. Evidence recording has the same defect as A03. |
| A09 round shield | `/affordance/grip_topology` | `handle_length=short` with `grip_topology=body_grip`. | model | The candidate addendum defines `body_grip` for a body-held object. A shield with a rear handle should use a handle topology or declare no handle when genuinely body-gripped. The closed cross-field rule correctly rejected the contradictory pair. |

The contract false-positive is implemented by the unqualified token intersection
in `tools/semantic/bridge/semantic_contract.py`: `fire` is globally forbidden in
canonical English names even when it is part of a conventional object name.
This rule needs an identity-aware lexical exception or a more precise modifier
test; removing `fire` from the ban entirely would be too broad.

## Independent semantic review of strict-valid outputs

The following review checks only whether the recorded model affordance is a
reasonable representation of the frozen object description. It is not a feel
test and does not modify the official automatic verdict.

| Case | Identity | Strict profile | Structural review | Notes |
|---|---|---:|---:|---|
| A01 | kitchen cleaver | yes | pass | Edge, point, broad blade face, short handle, and front mass are supported. |
| A02 | longsword | yes | pass | Long rigid blade, edge/point, hilt, and balanced mass are supported. |
| A04 | spear | yes | pass | Long two-hand shaft, point contact, rigid body, and front head are supported. |
| A05 | large iron hammer | yes | pass | Long handle, front-heavy broad hammer face, and rigid head are supported. |
| A06 | wooden baseball bat | yes | pass with note | `barrel` is a literal baseball-bat structural term, not a firearm inference; no stock was invented. |
| A10 | giant chicken drumstick | yes | pass | Bone grip, front meat mass, and broad semi-rigid contact are supported. |
| A11 | folding stool | yes | pass | Clamp/body handling, broad seat, rigid frame, and front mass are supported. |
| A12 | fishing rod | yes | pass | Long flexible rod, two-hand grip, rear reel mass, and whole-body sweep evidence are supported. |

All eight strict-valid outputs contain at least two useful structural evidence
parts. A07 and A09 are not silently salvaged, despite otherwise plausible
fields. A03 and A08 cannot receive a response-level semantic review because the
runner did not preserve their exact parsed tool input.

## Existing compiler handoff

The eight valid affordances were passed to the existing GDScript
`MeleeMotionCompiler` using one identical neutral anchor/bounds basis. Eight
recipes compiled; no object name, expected label, or review rubric entered the
compiler. The sequences are recorded in the frozen run report and
`compiled_recipes.json`.

## Required correction before another paid call

1. Preserve parsed tool input and redacted raw response even when local
   candidate validation raises.
2. Record HTTP/API success independently from local contract success.
3. Narrow the canonical modifier rule so lexicalized identities such as
   `fire axe` and `fire extinguisher` remain legal while fantasy/effect prefixes
   remain rejected.
4. Add offline regressions for A03, A07, A08, and A09 without changing their
   frozen evidence.
5. If those corrections pass offline, request separate approval for a maximum
   four-call targeted retest. Do not repeat the eight valid calls.

No automatic retry, second model scorer, output repair, image generation, or
combat BlindComparison is authorized by this postmortem.
