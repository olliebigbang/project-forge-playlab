# Forge Semantic Contract v1.1 Limited Retest 3B

**结论：NEEDS WORK**

本次运行是独立、不可覆盖的六案例有限真实复测。未执行 Gate B，未启动 ComfyUI 或 V2，也未修改战斗、房间、锚点或美术系统。

## 调用与合同

- Run ID：`limited-retest-3b-20260803T040934865715Z-79738d1b`
- 官方端点：`https://api.anthropic.com/v1/messages`
- 精确模型：`claude-sonnet-5`
- 合同：`forge-semantic-v1.1`
- 调用：6/6；自动重试：0
- v1.1 实时 clarification 的 `known_action_hints` 仅允许数组；历史字符串只保留在 forensic replay。
- 模型 tool input 原样验证；没有修复、拆包、强制转换或默认值。

## 通过门槛

| 门槛 | 实际 | 要求 | 结果 |
|---|---:|---:|---|
| API 成功 | 6 | 6 | PASS |
| exactly one 合法 tool_use | 6 | 6 | PASS |
| Schema + 跨字段有效 | 6 | 6 | PASS |
| 澄清正确 | 2 | 2 | PASS |
| compiled 身份正确 | 3 | 4 | FAIL |
| compiled 行为正确 | 4 | 4 | PASS |
| required_identity_parts 质量 2 | 0 | 4 | FAIL |
| 固定武器替换 | 0 | 0 | PASS |
| 自动重试 | 0 | 0 | PASS |
| 额外根包装 | 0 | 0 | PASS |
| Key 泄漏 | 0 | 0 | PASS |

## 逐案例结果

| Case | API | Tool | Schema/Cross | 澄清 | 身份 | 行为 | Parts | 固定替换 | 根包装 |
|---|---|---|---|---|---|---|---:|---|---|
| 10 | PASS | PASS | PASS | — | PASS | PASS | 1 | PASS | PASS |
| 13 | PASS | PASS | PASS | — | FAIL | PASS | 0 | PASS | PASS |
| 17 | PASS | PASS | PASS | PASS | — | — | — | PASS | PASS |
| 18 | PASS | PASS | PASS | PASS | — | — | — | PASS | PASS |
| 04 | PASS | PASS | PASS | — | PASS | PASS | 1 | PASS | PASS |
| 01 | PASS | PASS | PASS | — | PASS | PASS | 1 | PASS | PASS |

## 输出摘录

- Case 10：`旧铜钟` / `Old Bronze Bell`；`sustained_ranged` + `sound`；parts=["bell body", "flared rim", "hanging loop or crown"]
- Case 13：`长枪` / `spear`；`sustained_ranged` + `ice`；parts=["long wooden shaft", "spear tip/blade", "spearhead socket"]
- Case 17：`identity_unclear`；问题：这个红色的东西具体是什么物品？；known_action_hints 类型：list
- Case 18：`behavior_conflict`；问题：物品是持续握在手里喷火,还是要整个飞出去撞击后返回?这两种主要攻击方式冲突,请问以哪一种为主?；known_action_hints 类型：list
- Case 04：`巨大鸡腿` / `giant chicken drumstick`；`heavy_melee` + `lifesteal`；parts=["thick meat body", "bone handle protruding at end", "rounded knuckle end"]
- Case 01：`老木桌` / `old wooden table`；`returning_thrown` + `normal`；parts=["flat tabletop", "four legs", "wooden frame"]

## 证据与边界

- 冻结 Gate A source run：`gate-a-20260802T232039017356Z-fddde20a`
- source evidence SHA-256：`94a602bdf2d0571cf294287f3d188e830fe7fa968b148e8ca67af3387cd0b347`
- Approved 3B config SHA-256：`ba32d21e0705cf3853376cfab99b1ad83c4b26102f72796f7726f335f332d10d`（24 个固定输入/执行文件）
- 原 Gate A 报告、Postmortem 3A 报告及四个冻结 fixture 在调用前后均按 SHA-256 验证，未改写。
- 每例完整脱敏响应位于本 run 的 `raw_response_redacted/`；逐例原始 tool input 同时保存在不可覆盖的 `result.json`。
- `evidence_hashes.json` 覆盖逐例结果、脱敏响应、请求清单、报告、额度锁和合同输入。
- Secret scan：PASS；Key 泄漏：0。

## 停止条件

Gate B 未执行。即使本次通过，也必须停止并等待用户批准 4 个全新盲测案例。
