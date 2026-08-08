# Anonymous Affordance Runtime Realization Audit

Status: **NEEDS_WORK**

This offline diagnostic keeps the current orthogonal Grammar weights frozen. It changes anonymous structural axes and measures the existing combat consumers directly: `CombatFeelSlice0._attack_contains`, `CombatMotionProfile.timing_for`, `ImpactFeedbackProfile.for_attack`, root motion, and the current character pose.

The twelve frozen affordance profiles are coverage witnesses only. They are not pass samples and were not used to tune any rule or weight. The prior three-asset blind comparison also remains historical evidence rather than a tuning target.

## Result

- Monotonic mechanism contracts passed: 21/23
- Non-mechanical invariants passed: 2/2
- Frozen profiles executed through the neutral harness: 12/12
- Profile changes that did not reach measured combat behavior: feature_stock
- Runtime changes with a wrong or incomplete monotonic direction: mass_rear

## Anonymous one-axis matrix

| Probe | Axis | Result | Classification | Sequence | Failed runtime properties |
|---|---|---|---|---|---|
| handle_short | handle_length | PASS | RUNTIME_PROPERTY_PASS | `bash -> slam -> bash` | - |
| handle_long | handle_length | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| body_short | body_length | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| body_long | body_length | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| grip_two_hand | grip_topology | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| grip_clamp | grip_topology | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| grip_handleless_body | grip_mode | PASS | RUNTIME_PROPERTY_PASS | `bash -> slam -> bash` | - |
| rigidity_semi | rigidity | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| rigidity_flexible | rigidity | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| mass_rear | mass_distribution | FAIL | RUNTIME_WRONG_DIRECTION_OR_INCOMPLETE | `bash -> sweep -> slam` | combo/startup_total, combo/knockback_total |
| mass_front | mass_distribution | PASS | RUNTIME_PROPERTY_PASS | `bash -> slam -> bash` | - |
| primary_point | contact_surface | PASS | RUNTIME_PROPERTY_PASS | `thrust -> sweep -> bash` | - |
| primary_edge | contact_surface | PASS | RUNTIME_PROPERTY_PASS | `sweep -> thrust -> slam` | - |
| primary_whole_body | contact_surface | PASS | RUNTIME_PROPERTY_PASS | `sweep -> spin -> slam` | - |
| secondary_point | secondary_contact_surface | PASS | RUNTIME_PROPERTY_PASS | `bash -> thrust -> slam` | - |
| secondary_edge | secondary_contact_surface | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| secondary_broad | secondary_contact_surface | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| secondary_whole_body | secondary_contact_surface | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| feature_point | has_point | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| feature_edge | has_edge | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| feature_broad_face | has_broad_face | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| feature_barrel | has_barrel | PASS | RUNTIME_PROPERTY_PASS | `bash -> sweep -> slam` | - |
| feature_stock | has_stock | FAIL | PROFILE_ONLY_NOT_REALIZED | `bash -> sweep -> slam` | complete_runtime |
| confidence_high | confidence | PASS | INVARIANT_PASS | `bash -> sweep -> slam` | - |
| evidence_changed | evidence_parts | PASS | INVARIANT_PASS | `bash -> sweep -> slam` | - |

## Frozen coverage profiles

These rows show diversity under the same neutral runtime geometry. They do not certify feel and do not authorize per-case fixes.

| Case | Primitive sequence | Collision area | Formation hits | Forward extent | Root motion | Knockback total |
|---|---|---:|---:|---:|---:|---:|
| A01 | `sweep -> bash -> slam` | 24896 | 14 | 144 | 25.90 | 502.97 |
| A02 | `sweep -> thrust -> slam` | 36096 | 18 | 192 | 44.87 | 543.60 |
| A03 | `sweep -> thrust -> slam` | 52096 | 20 | 224 | 53.63 | 659.06 |
| A04 | `thrust -> thrust -> slam` | 14464 | 9 | 264 | 63.84 | 757.22 |
| A05 | `bash -> slam -> sweep` | 50752 | 20 | 200 | 53.63 | 645.04 |
| A06 | `bash -> slam -> bash` | 47168 | 20 | 192 | 64.69 | 645.04 |
| A07 | `sweep -> spin -> slam` | 59072 | 17 | 168 | 29.31 | 674.19 |
| A08 | `sweep -> spin -> slam` | 53888 | 15 | 160 | 29.31 | 426.19 |
| A09 | `bash -> sweep -> slam` | 47296 | 19 | 184 | 34.66 | 474.42 |
| A10 | `bash -> slam -> bash` | 47232 | 19 | 184 | 34.66 | 492.27 |
| A11 | `bash -> slam -> bash` | 46784 | 19 | 176 | 20.55 | 492.27 |
| A12 | `sweep -> spin -> slam` | 91456 | 20 | 200 | 53.63 | 631.94 |

## Diagnosis

The orthogonal compiler is not yet fully realized by combat. A Compiler/Profile difference is not accepted when collision, timing, root movement, feedback, support-hand participation, or pose remains unchanged.

The next correction should be limited to the failed generic consumer paths. Do not tune named assets, restore exact legacy recipes, or conduct another three-sample feel pass until this same anonymous matrix passes.
