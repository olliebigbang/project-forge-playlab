# Forge Affordance v1.2 Limited Real Retest

Status: **NEEDS_WORK**

This bounded run used the official Anthropic Messages API with the exact frozen model `claude-sonnet-5`. Each of the 12 frozen inputs was called once with zero retries. FLUX, BiRefNet, ComfyUI, and BlindComparison were not started.

## Automatic envelope

- API success: 10/12
- Exactly one legal tool use: 10/12
- Candidate Schema and cross-field valid: 8/12
- Existing MeleeMotionCompiler offline compile: 8/12
- Human affordance correctness: pending independent review

## Frozen handoff table

| Case | Frozen identity | Model affordance | Dominant mechanism axes | Compiled combo | State |
|---|---|---|---|---|---|
| A01 | 菜刀 | `{"handle_length":"short","body_length":"short","grip_topology":"one_hand_handle","rigidity":"rigid","mass_distribution":"front","contact_surface":"edge","secondary_contact_surface":"point","has_point":true,"has_edge":true,"has_broad_face":true,"has_barrel":false,"has_stock":false,"confidence":0.88,"evidence_parts":["wide rectangular blade","straight cutting edge","short wooden handle","blade tip","flat blade face"]}` | handle_length=short, body_length=short, grip_topology=one_hand_handle, rigidity=rigid, mass_distribution=front, contact_surface=edge, secondary_contact_surface=point | sweep → bash → slam | VALID |
| A02 | 长剑 | `{"handle_length":"short","body_length":"long","grip_topology":"one_hand_handle","rigidity":"rigid","mass_distribution":"balanced","contact_surface":"edge","secondary_contact_surface":"point","has_point":true,"has_edge":true,"has_broad_face":false,"has_barrel":false,"has_stock":false,"confidence":0.9,"evidence_parts":["long slender blade","sharp tip","cutting edge","handle grip","crossguard"]}` | handle_length=short, body_length=long, grip_topology=one_hand_handle, rigidity=rigid, mass_distribution=balanced, contact_surface=edge, secondary_contact_surface=point | sweep → thrust → slam | VALID |
| A03 | 消防斧 | `{}` | handle_length=None, body_length=None, grip_topology=None, rigidity=None, mass_distribution=None, contact_surface=None, secondary_contact_surface=None | — | FAILED |
| A04 | 长矛 | `{"handle_length":"long","body_length":"long","grip_topology":"two_hand_handle","rigidity":"rigid","mass_distribution":"front","contact_surface":"point","secondary_contact_surface":"none","has_point":true,"has_edge":false,"has_broad_face":false,"has_barrel":false,"has_stock":false,"confidence":0.9,"evidence_parts":["long shaft held with two hands","pointed spearhead for thrusting","front-weighted head mass"]}` | handle_length=long, body_length=long, grip_topology=two_hand_handle, rigidity=rigid, mass_distribution=front, contact_surface=point, secondary_contact_surface=none | thrust → thrust → slam | VALID |
| A05 | 铁锤 | `{"handle_length":"long","body_length":"medium","grip_topology":"two_hand_handle","rigidity":"rigid","mass_distribution":"front","contact_surface":"broad","secondary_contact_surface":"none","has_point":false,"has_edge":false,"has_broad_face":true,"has_barrel":false,"has_stock":false,"confidence":0.9,"evidence_parts":["long wooden handle","heavy iron hammer head","flat striking face"]}` | handle_length=long, body_length=medium, grip_topology=two_hand_handle, rigidity=rigid, mass_distribution=front, contact_surface=broad, secondary_contact_surface=none | bash → slam → sweep | VALID |
| A06 | 棒球棒 | `{"handle_length":"medium","body_length":"medium","grip_topology":"two_hand_handle","rigidity":"rigid","mass_distribution":"front","contact_surface":"broad","secondary_contact_surface":"none","has_point":false,"has_edge":false,"has_broad_face":true,"has_barrel":true,"has_stock":false,"confidence":0.9,"evidence_parts":["tapered narrow handle for two-hand grip","knob end to prevent slipping","thick cylindrical barrel for impact","wood construction giving rigidity"]}` | handle_length=medium, body_length=medium, grip_topology=two_hand_handle, rigidity=rigid, mass_distribution=front, contact_surface=broad, secondary_contact_surface=none | bash → slam → bash | VALID |
| A07 | 木椅 | `{}` | handle_length=None, body_length=None, grip_topology=None, rigidity=None, mass_distribution=None, contact_surface=None, secondary_contact_surface=None | — | FAILED |
| A08 | 灭火器 | `{}` | handle_length=None, body_length=None, grip_topology=None, rigidity=None, mass_distribution=None, contact_surface=None, secondary_contact_surface=None | — | FAILED |
| A09 | 圆盾 | `{}` | handle_length=None, body_length=None, grip_topology=None, rigidity=None, mass_distribution=None, contact_surface=None, secondary_contact_surface=None | — | FAILED |
| A10 | 巨大鸡腿 | `{"handle_length":"short","body_length":"medium","grip_topology":"one_hand_handle","rigidity":"semi_rigid","mass_distribution":"front","contact_surface":"broad","secondary_contact_surface":"none","has_point":false,"has_edge":false,"has_broad_face":true,"has_barrel":false,"has_stock":false,"confidence":0.82,"evidence_parts":["narrow bone shaft as handle","bulbous meat mass at striking end","semi-rigid meat and bone structure","front-heavy weight distribution"]}` | handle_length=short, body_length=medium, grip_topology=one_hand_handle, rigidity=semi_rigid, mass_distribution=front, contact_surface=broad, secondary_contact_surface=none | bash → slam → bash | VALID |
| A11 | 折叠凳 | `{"handle_length":"none","body_length":"short","grip_topology":"clamp_grip","rigidity":"rigid","mass_distribution":"front","contact_surface":"broad","secondary_contact_surface":"none","has_point":false,"has_edge":false,"has_broad_face":true,"has_barrel":false,"has_stock":false,"confidence":0.8,"evidence_parts":["flat seat surface as striking face","folding legs as grip point","rigid leg frame","seat mass offset from hand grip"]}` | handle_length=none, body_length=short, grip_topology=clamp_grip, rigidity=rigid, mass_distribution=front, contact_surface=broad, secondary_contact_surface=none | bash → slam → bash | VALID |
| A12 | 钓鱼竿 | `{"handle_length":"medium","body_length":"long","grip_topology":"two_hand_handle","rigidity":"flexible","mass_distribution":"rear","contact_surface":"whole_body","secondary_contact_surface":"point","has_point":true,"has_edge":false,"has_broad_face":false,"has_barrel":false,"has_stock":false,"confidence":0.75,"evidence_parts":["long flexible rod shaft","cork handle grip","rod tip","reel mounted near handle"]}` | handle_length=medium, body_length=long, grip_topology=two_hand_handle, rigidity=flexible, mass_distribution=rear, contact_surface=whole_body, secondary_contact_surface=point | sweep → spin → slam | VALID |

## Interpretation boundary

The model produced semantic identity, combat, visual, and affordance data only. Recipe selection was performed afterward by the existing GDScript `MeleeMotionCompiler` with one neutral anchor/bounds basis for every case. No object name, expected answer, or review rubric was sent to the compiler.

The automatic result does not certify semantic correctness or combat feel. Complete `human_affordance_review.csv` before authorizing a new BlindComparison.
