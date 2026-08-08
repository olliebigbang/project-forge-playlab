# Anonymous Affordance Axis Causality Audit

Status: **NEEDS_WORK**

This offline audit changes one legal anonymous structural axis at a time against a neutral baseline. It evaluates the actual CombatMotionProfile and five MotionPrimitive specs after removing trace text, confidence, evidence wording, and reporting metadata. A primitive score change alone is not accepted as a runtime effect.

No identity, object name, asset ID, run ID, player prompt, Claude call, image generation, or human feel retest is involved.

## Summary

- Mechanism probes: 23
- Probes with an actual runtime effect: 15
- Score-only masked probes: 8
- Fully silent probes: 0
- Non-mechanical invariant controls passed: 2/2

## Axis states

| Axis | State | Probes | Runtime effects | Score-only | Failed probes |
|---|---|---:|---:|---:|---|
| body_length | ACTIVE | 2 | 2 | 0 | - |
| confidence | INVARIANT_PASS | 1 | 0 | 0 | - |
| contact_surface | ACTIVE | 3 | 3 | 0 | - |
| evidence_parts | INVARIANT_PASS | 1 | 0 | 0 | - |
| grip_mode | ACTIVE | 1 | 1 | 0 | - |
| grip_topology | PARTIAL_THRESHOLD_MASKING | 2 | 1 | 1 | grip_clamp |
| handle_length | ACTIVE | 2 | 2 | 0 | - |
| has_barrel | ACTIVE | 1 | 1 | 0 | - |
| has_broad_face | SCORE_ONLY_MASKED | 1 | 0 | 1 | feature_broad_face |
| has_edge | SCORE_ONLY_MASKED | 1 | 0 | 1 | feature_edge |
| has_point | SCORE_ONLY_MASKED | 1 | 0 | 1 | feature_point |
| has_stock | ACTIVE | 1 | 1 | 0 | - |
| mass_distribution | ACTIVE | 2 | 2 | 0 | - |
| rigidity | PARTIAL_THRESHOLD_MASKING | 2 | 1 | 1 | rigidity_semi |
| secondary_contact_surface | PARTIAL_THRESHOLD_MASKING | 4 | 1 | 3 | secondary_edge, secondary_broad, secondary_whole_body |

## Probe matrix

| Probe | Axis | Change | Classification | Sequence | Runtime paths changed |
|---|---|---|---|---|---:|
| handle_short | handle_length | `{"handle_length":"short"}` | SEQUENCE_EFFECT | `bash -> slam -> bash` | 30 |
| handle_long | handle_length | `{"handle_length":"long"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 25 |
| body_short | body_length | `{"body_length":"short"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 24 |
| body_long | body_length | `{"body_length":"long"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 26 |
| grip_two_hand | grip_topology | `{"grip_topology":"two_hand_handle"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| grip_clamp | grip_topology | `{"grip_topology":"clamp_grip"}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| grip_handleless_body | grip_mode | `{"grip_topology":"body_grip","handle_length":"none"}` | SEQUENCE_EFFECT | `bash -> slam -> bash` | 36 |
| rigidity_semi | rigidity | `{"rigidity":"semi_rigid"}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| rigidity_flexible | rigidity | `{"rigidity":"flexible"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 6 |
| mass_rear | mass_distribution | `{"mass_distribution":"rear"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 35 |
| mass_front | mass_distribution | `{"mass_distribution":"front"}` | SEQUENCE_EFFECT | `bash -> slam -> bash` | 47 |
| primary_point | contact_surface | `{"contact_surface":"point"}` | SEQUENCE_EFFECT | `thrust -> sweep -> bash` | 33 |
| primary_edge | contact_surface | `{"contact_surface":"edge"}` | SEQUENCE_EFFECT | `sweep -> thrust -> slam` | 35 |
| primary_whole_body | contact_surface | `{"contact_surface":"whole_body"}` | SEQUENCE_EFFECT | `sweep -> spin -> slam` | 38 |
| secondary_point | secondary_contact_surface | `{"secondary_contact_surface":"point"}` | SEQUENCE_EFFECT | `bash -> thrust -> slam` | 5 |
| secondary_edge | secondary_contact_surface | `{"secondary_contact_surface":"edge"}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| secondary_broad | secondary_contact_surface | `{"secondary_contact_surface":"broad"}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| secondary_whole_body | secondary_contact_surface | `{"secondary_contact_surface":"whole_body"}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| feature_point | has_point | `{"has_point":true}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| feature_edge | has_edge | `{"has_edge":true}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| feature_broad_face | has_broad_face | `{"has_broad_face":true}` | SCORE_ONLY_MASKED | `bash -> sweep -> slam` | 0 |
| feature_barrel | has_barrel | `{"has_barrel":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 5 |
| feature_stock | has_stock | `{"has_stock":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| confidence_high | confidence | `{"confidence":0.95}` | INVARIANT_PASS | `bash -> sweep -> slam` | 0 |
| evidence_changed | evidence_parts | `{"evidence_parts":["different anonymous evidence wording"]}` | INVARIANT_PASS | `bash -> sweep -> slam` | 0 |

## Interpretation

`SCORE_ONLY_MASKED` means the input axis changed internal primitive scores but produced no change in the runtime profile or MotionPrimitive specs for this neutral structure. This is threshold masking, not proof that the field is globally unused. It is nevertheless a failed local causal probe because a player would receive the same mechanics for that one-axis change.

This audit does not authorize sample-specific tuning. Any future correction must make generic axes influence continuous runtime parameters or selection in anonymous profiles, then rerun this same matrix before another human test.
