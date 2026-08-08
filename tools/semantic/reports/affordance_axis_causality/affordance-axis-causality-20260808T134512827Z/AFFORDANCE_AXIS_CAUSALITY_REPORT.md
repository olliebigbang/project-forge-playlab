# Anonymous Affordance Axis Causality Audit

Status: **PASS**

This offline audit changes one legal anonymous structural axis at a time against a neutral baseline. It evaluates the actual CombatMotionProfile and five MotionPrimitive specs after removing trace text, confidence, evidence wording, and reporting metadata. A primitive score change alone is not accepted as a runtime effect.

No identity, object name, asset ID, run ID, player prompt, Claude call, image generation, or human feel retest is involved.

## Summary

- Mechanism probes: 23
- Probes with an actual runtime effect: 23
- Score-only masked probes: 0
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
| grip_topology | ACTIVE | 2 | 2 | 0 | - |
| handle_length | ACTIVE | 2 | 2 | 0 | - |
| has_barrel | ACTIVE | 1 | 1 | 0 | - |
| has_broad_face | ACTIVE | 1 | 1 | 0 | - |
| has_edge | ACTIVE | 1 | 1 | 0 | - |
| has_point | ACTIVE | 1 | 1 | 0 | - |
| has_stock | ACTIVE | 1 | 1 | 0 | - |
| mass_distribution | ACTIVE | 2 | 2 | 0 | - |
| rigidity | ACTIVE | 2 | 2 | 0 | - |
| secondary_contact_surface | ACTIVE | 4 | 4 | 0 | - |

## Probe matrix

| Probe | Axis | Change | Classification | Sequence | Runtime paths changed |
|---|---|---|---|---|---:|
| handle_short | handle_length | `{"handle_length":"short"}` | SEQUENCE_EFFECT | `bash -> slam -> bash` | 30 |
| handle_long | handle_length | `{"handle_length":"long"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 25 |
| body_short | body_length | `{"body_length":"short"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 24 |
| body_long | body_length | `{"body_length":"long"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 26 |
| grip_two_hand | grip_topology | `{"grip_topology":"two_hand_handle"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| grip_clamp | grip_topology | `{"grip_topology":"clamp_grip"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 15 |
| grip_handleless_body | grip_mode | `{"grip_topology":"body_grip","handle_length":"none"}` | SEQUENCE_EFFECT | `bash -> slam -> bash` | 36 |
| rigidity_semi | rigidity | `{"rigidity":"semi_rigid"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| rigidity_flexible | rigidity | `{"rigidity":"flexible"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 7 |
| mass_rear | mass_distribution | `{"mass_distribution":"rear"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 35 |
| mass_front | mass_distribution | `{"mass_distribution":"front"}` | SEQUENCE_EFFECT | `bash -> slam -> bash` | 47 |
| primary_point | contact_surface | `{"contact_surface":"point"}` | SEQUENCE_EFFECT | `thrust -> sweep -> bash` | 33 |
| primary_edge | contact_surface | `{"contact_surface":"edge"}` | SEQUENCE_EFFECT | `sweep -> thrust -> slam` | 35 |
| primary_whole_body | contact_surface | `{"contact_surface":"whole_body"}` | SEQUENCE_EFFECT | `sweep -> spin -> slam` | 38 |
| secondary_point | secondary_contact_surface | `{"secondary_contact_surface":"point"}` | SEQUENCE_EFFECT | `bash -> thrust -> slam` | 6 |
| secondary_edge | secondary_contact_surface | `{"secondary_contact_surface":"edge"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| secondary_broad | secondary_contact_surface | `{"secondary_contact_surface":"broad"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| secondary_whole_body | secondary_contact_surface | `{"secondary_contact_surface":"whole_body"}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| feature_point | has_point | `{"has_point":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| feature_edge | has_edge | `{"has_edge":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| feature_broad_face | has_broad_face | `{"has_broad_face":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| feature_barrel | has_barrel | `{"has_barrel":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 5 |
| feature_stock | has_stock | `{"has_stock":true}` | PARAMETER_EFFECT | `bash -> sweep -> slam` | 1 |
| confidence_high | confidence | `{"confidence":0.95}` | INVARIANT_PASS | `bash -> sweep -> slam` | 0 |
| evidence_changed | evidence_parts | `{"evidence_parts":["different anonymous evidence wording"]}` | INVARIANT_PASS | `bash -> sweep -> slam` | 0 |

## Interpretation

All mechanism probes now alter an actual runtime profile or MotionPrimitive field, while confidence and evidence wording remain mechanically inert. The correction uses identity-free continuous coupling and does not change Primitive winner weights for a named sample.

This technical result does not replace the separate human feel verdict. A new human comparison is required before promoting the Composer.
