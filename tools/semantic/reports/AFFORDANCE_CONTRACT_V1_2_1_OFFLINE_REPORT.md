# Affordance Contract v1.2.1 — offline correction report

## Outcome

Status: **OFFLINE PASS / REAL RETEST NOT AUTHORIZED**

The frozen v1.1 contract, v1.2 candidate implementation, 12-call run, automatic
report, postmortem, and evidence hashes remain unchanged. The correction is an
additive v1.2.1 candidate boundary.

## Corrections

1. Conventional lexicalized identities can retain an otherwise effect-shaped
   English word only when the complete canonical name is in the evaluator's
   conventional-compound vocabulary. This vocabulary is evaluator-only and is
   never passed to `MeleeMotionCompiler` or used for recipe selection.
2. `fire axe` and `fire extinguisher` pass the new candidate identity check.
3. Non-conventional effect pollution such as `fire sword` or
   `flaming fire axe` remains rejected.
4. The exact frozen A07 extra-field output remains rejected without repair.
5. The exact frozen A09 grip/handle contradiction remains rejected without
   repair.
6. A corrected targeted runner records `api_status=200`, request ID, exact tool
   input, redacted raw response, and usage before local validation. A local
   contract failure can no longer erase or misclassify successful API evidence.

## Four-case freeze

Only A03, A07, A08, and A09 are eligible for a future targeted retest. Their
input digests and available frozen result digests are pinned in
`tools/semantic/cases/affordance_targeted_4_v1_2_1.json`. A03 and A08 explicitly
record that the old runner failed to preserve their exact tool inputs; no
fixture invents or reconstructs those responses.

## Offline verification

- v1.2.1 concentrated tests: 8/8 pass.
- Targeted preflight: pass, four cases, maximum four calls, zero retries.
- Frozen v1.2 evidence: 58/58 hashes verified.
- Real calls performed by this correction: 0.
- FLUX, BiRefNet, ComfyUI, and BlindComparison: not started.

## Next gate

An explicit user approval is required before invoking
`--execute-approved-four-call-retest`. If approved, each of the four frozen
inputs may be called once with `claude-sonnet-5`, with no retry and no repair.
Even a 4/4 semantic pass must not automatically start BlindComparison.
