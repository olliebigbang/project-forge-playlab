# Forge Multilingual Semantic Compiler Spike 3 — Gate A

Status: **NEEDS WORK**

- Provider: Anthropic official Messages API at https://api.anthropic.com/v1/messages
- Exact model ID: claude-sonnet-5
- Real AI calls performed: true
- Calls: 20 (automatic retries: 0)
- Attested Anthropic envelopes: 0/20
- Persistent call reservation attested: true
- Delivered result files attested: 20/20
- Unique provider response IDs: 0/20
- Processable results: 0/20
- Structured Schema valid: 0/20
- Identity correct: 0/20
- Behavior correct: 0/20
- Preserved-features quality 2: 0/20
- Clarification correct: 0/2
- Fixed weapon substitutions: 0
- Token usage: input 0, output 0, cache creation 0, cache read 0
- Cost: COST_NOT_CALCULATED — TOKEN_USAGE_ONLY
- Gate B recommended: false (separate user approval is still required)

## Per-case review

| Case | API | Result | Schema | Identity | Behavior | Features | Clarification | Fixed substitution | Reason |
|---|---:|---|---:|---:|---:|---:|---:|---:|---|
| 01 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 02 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 03 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 04 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 05 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 06 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 07 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 08 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 09 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 10 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 11 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 12 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 13 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 14 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 15 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 16 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 17 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；澄清工具错误('failed', None) |
| 18 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；澄清工具错误('failed', None) |
| 19 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |
| 20 | 400 | failed | False | False | False | 0 | False | False | API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None) |

## Failures

- 01: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 02: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 03: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 04: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 05: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 06: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 07: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 08: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 09: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 10: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 11: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 12: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 13: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 14: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 15: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 16: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 17: API 未成功(400)；结构或跨字段验证失败；澄清工具错误('failed', None)
- 18: API 未成功(400)；结构或跨字段验证失败；澄清工具错误('failed', None)
- 19: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)
- 20: API 未成功(400)；结构或跨字段验证失败；结果工具错误('failed', None)

## Boundary declaration

- ComfyUI was not started.
- Gate B was not executed.
- V2 was not started.
- Protected gameplay, Web, ComfyUI, art, and room files match the pre-execution scope hash.
- A passing Gate A still requires separate user approval before Gate B.
