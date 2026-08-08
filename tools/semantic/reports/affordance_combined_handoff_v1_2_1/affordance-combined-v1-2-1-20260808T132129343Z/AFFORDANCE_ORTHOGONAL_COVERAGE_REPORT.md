# Orthogonal Affordance Coverage Matrix — 12 frozen inputs

Status: **PASS**

This is an offline compiler-coverage audit. It does not call Claude, FLUX, BiRefNet, ComfyUI, or a second model scorer. The compiler bundle contains only affordance profiles, case IDs, neutral anchors, and neutral alpha bounds. Identity labels are joined after compilation for this human-readable table.

## Version boundary

- A01, A02, A04, A05, A06, A10, A11, and A12 come from the frozen strict-valid v1.2 run.
- A03, A07, A08, and A09 come from the frozen strict-valid targeted v1.2.1 run.
- This is not represented as one homogeneous 12/12 model run.

## Coverage result

- Compiled profiles: 12/12
- Unique normal-combo sequences: 7
- Unique mechanical Recipes: 12
- All five primitives used in normal combo hits: true
- Most common sequence: `bash -> slam -> bash` (3/12)
- Single-sequence degradation: false
- Dominant-sequence warning (>= 50%): false

## Affordance to mechanism to combo matrix

| Case | Identity label (report only) | Contract source | Affordance axes | Dominant mechanism scores | Hit 1 -> Hit 2 -> Hit 3 |
|---|---|---|---|---|---|
| A01 | 菜刀 | forge-semantic-v1.2-candidate | `short/short/one_hand_handle/rigid/front/edge+point/point+edge+broad_face` | `sweep=4.100; slam=3.450; bash=3.344` | `sweep -> bash -> slam` |
| A02 | 长剑 | forge-semantic-v1.2-candidate | `short/long/one_hand_handle/rigid/balanced/edge+point/point+edge` | `sweep=5.100; thrust=3.788; slam=1.750` | `sweep -> thrust -> slam` |
| A03 | 消防斧 | forge-semantic-v1.2.1-candidate | `long/medium/two_hand_handle/rigid/front/edge+point/point+edge` | `sweep=5.650; thrust=3.788; slam=2.350` | `sweep -> thrust -> slam` |
| A04 | 长矛 | forge-semantic-v1.2-candidate | `long/long/two_hand_handle/rigid/front/point+none/point` | `thrust=6.850; sweep=1.850; bash=1.550` | `thrust -> thrust -> slam` |
| A05 | 铁锤 | forge-semantic-v1.2-candidate | `long/medium/two_hand_handle/rigid/front/broad+none/broad_face` | `bash=4.700; slam=4.100; sweep=2.650` | `bash -> slam -> sweep` |
| A06 | 棒球棒 | forge-semantic-v1.2-candidate | `medium/medium/two_hand_handle/rigid/front/broad+none/broad_face+barrel` | `bash=5.050; slam=4.100; sweep=2.150` | `bash -> slam -> bash` |
| A07 | 木椅 | forge-semantic-v1.2.1-candidate | `none/medium/body_grip/rigid/front/whole_body+edge/edge+broad_face` | `sweep=4.540; slam=4.206; bash=3.600` | `sweep -> spin -> slam` |
| A08 | 灭火器 | forge-semantic-v1.2.1-candidate | `none/medium/body_grip/rigid/balanced/whole_body+none/no-shape-flag` | `spin=3.650; sweep=3.100; slam=2.550` | `sweep -> spin -> slam` |
| A09 | 圆盾 | forge-semantic-v1.2.1-candidate | `short/medium/clamp_grip/rigid/balanced/broad+edge/edge+broad_face` | `bash=5.600; slam=4.056; sweep=3.690` | `bash -> sweep -> slam` |
| A10 | 巨大鸡腿 | forge-semantic-v1.2-candidate | `short/medium/one_hand_handle/semi_rigid/front/broad+none/broad_face` | `bash=5.000; slam=4.150; sweep=1.900` | `bash -> slam -> bash` |
| A11 | 折叠凳 | forge-semantic-v1.2-candidate | `none/short/clamp_grip/rigid/front/broad+none/broad_face` | `bash=6.100; slam=4.850; sweep=1.100` | `bash -> slam -> bash` |
| A12 | 钓鱼竿 | forge-semantic-v1.2-candidate | `medium/long/two_hand_handle/flexible/rear/whole_body+point/point` | `sweep=4.600; spin=4.050; thrust=3.138` | `sweep -> spin -> slam` |

## Interpretation boundary

A PASS means the frozen profiles compile without identity input, use the full five-primitive vocabulary across the corpus, and do not collapse to one normal-combo sequence. It does not mean the resulting differences are already perceptually strong or fun. The separately frozen orthogonal BlindComparison remains **TECHNICAL PASS / FEEL NEEDS WORK (3/5)**.

No object-name matcher, asset-ID matcher, runtime keyword map, or case-specific Recipe was added by this audit.
