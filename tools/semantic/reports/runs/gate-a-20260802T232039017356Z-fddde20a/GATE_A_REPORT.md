# Forge Multilingual Semantic Compiler Spike 3 — Gate A

Status: **NEEDS WORK**

- Provider: Anthropic official Messages API at https://api.anthropic.com/v1/messages
- Exact model ID: claude-sonnet-5
- Real AI calls performed: true
- Calls: 20 (automatic retries: 0)
- Attested Anthropic envelopes: 16/20
- Persistent call reservation attested: true
- Delivered result files attested: 20/20
- Unique provider response IDs: 16/20
- Processable results: 16/20
- Structured Schema valid: 16/20
- Identity correct: 15/20
- Behavior correct: 16/20
- Preserved-features quality 2: 6/20
- Clarification correct: 0/2
- Fixed weapon substitutions: 0
- Token usage: input 78615, output 11593, cache creation 0, cache read 0
- Cost: COST_NOT_CALCULATED — TOKEN_USAGE_ONLY
- Gate B recommended: false (separate user approval is still required)

## Per-case review

| Case | API | Result | Schema | Identity | Behavior | Features | Clarification | Fixed substitution | Reason |
|---|---:|---|---:|---:|---:|---:|---:|---:|---|
| 01 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 2/3；质量=1；缺失 桌腿 / table legs |
| 02 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 3/4；质量=1；缺失 椅腿 / chair legs |
| 03 | 200 | compiled | True | True | True | 2 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 3/3；质量=2 |
| 04 | 200 | compiled | True | False | True | 1 | False | False | 身份: 英文身份不匹配(Giant Lifesteal Chicken Leg)；行为: 匹配 heavy_melee；特征: 2/3；质量=1；缺失 鸡腿骨 / chicken leg bone |
| 05 | 200 | compiled | True | True | True | 2 | False | False | 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 3/3；质量=2 |
| 06 | 200 | compiled | True | True | True | 2 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 3/3；质量=2 |
| 07 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 heavy_melee；特征: 2/3；质量=1；缺失 面包轮廓 / bread silhouette |
| 08 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 2/3；质量=1；缺失 工具箱结构 / toolbox construction |
| 09 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 2/3；质量=1；缺失 机翼 / wings |
| 10 | 200 | failed | False | False | False | 0 | False | False | 结构或跨字段验证失败；结果工具错误('failed', 'submit_forge_semantic_blueprint') |
| 11 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 2/3；质量=1；缺失 两侧长杆 / side rails |
| 12 | 200 | compiled | True | True | True | 2 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 3/3；质量=2 |
| 13 | 200 | failed | False | False | False | 0 | False | False | 结构或跨字段验证失败；结果工具错误('failed', 'submit_forge_semantic_blueprint') |
| 14 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 1/3；质量=1；缺失 锅身 / pan body, 金属厨具身份 / metal cookware identity |
| 15 | 200 | compiled | True | True | True | 2 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 3/3；质量=2 |
| 16 | 200 | compiled | True | True | True | 2 | False | False | 身份: 中英身份均匹配；行为: 匹配 heavy_melee；特征: 3/3；质量=2 |
| 17 | 200 | failed | False | False | False | 0 | False | False | 结构或跨字段验证失败；澄清工具错误('failed', 'request_forge_clarification') |
| 18 | 200 | failed | False | False | False | 0 | False | False | 结构或跨字段验证失败；澄清工具错误('failed', 'request_forge_clarification') |
| 19 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 1/3；质量=1；缺失 木箱 / wooden box, 工具箱身份 / toolbox identity |
| 20 | 200 | compiled | True | True | True | 1 | False | False | 身份: 中英身份均匹配；行为: 匹配 heavy_melee；特征: 2/3；质量=1；缺失 抽象身份 / abstract identity |

## Failures

- 01: 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 2/3；质量=1；缺失 桌腿 / table legs
- 02: 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 3/4；质量=1；缺失 椅腿 / chair legs
- 04: 身份: 英文身份不匹配(Giant Lifesteal Chicken Leg)；行为: 匹配 heavy_melee；特征: 2/3；质量=1；缺失 鸡腿骨 / chicken leg bone
- 07: 身份: 中英身份均匹配；行为: 匹配 heavy_melee；特征: 2/3；质量=1；缺失 面包轮廓 / bread silhouette
- 08: 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 2/3；质量=1；缺失 工具箱结构 / toolbox construction
- 09: 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 2/3；质量=1；缺失 机翼 / wings
- 10: 结构或跨字段验证失败；结果工具错误('failed', 'submit_forge_semantic_blueprint')
- 11: 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 2/3；质量=1；缺失 两侧长杆 / side rails
- 13: 结构或跨字段验证失败；结果工具错误('failed', 'submit_forge_semantic_blueprint')
- 14: 身份: 中英身份均匹配；行为: 匹配 returning_thrown；特征: 1/3；质量=1；缺失 锅身 / pan body, 金属厨具身份 / metal cookware identity
- 17: 结构或跨字段验证失败；澄清工具错误('failed', 'request_forge_clarification')
- 18: 结构或跨字段验证失败；澄清工具错误('failed', 'request_forge_clarification')
- 19: 身份: 中英身份均匹配；行为: 匹配 sustained_ranged；特征: 1/3；质量=1；缺失 木箱 / wooden box, 工具箱身份 / toolbox identity
- 20: 身份: 中英身份均匹配；行为: 匹配 heavy_melee；特征: 2/3；质量=1；缺失 抽象身份 / abstract identity

## Boundary declaration

- ComfyUI was not started.
- Gate B was not executed.
- V2 was not started.
- Protected gameplay, Web, ComfyUI, art, and room files match the pre-execution scope hash.
- A passing Gate A still requires separate user approval before Gate B.
