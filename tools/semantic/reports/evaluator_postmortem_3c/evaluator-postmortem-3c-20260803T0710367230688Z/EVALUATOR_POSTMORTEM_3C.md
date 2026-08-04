# Forge Semantic Evaluator Postmortem 3C

## 结论

本任务是对 Blind Retest 3C 的纯离线评估器复盘，不是重新执行或覆盖 3C。

- **Official automatic verdict（冻结不变）**：身份 `3/4`、行为 `4/4`、自动门槛未通过，状态 `NEEDS WORK`；官方人工结构审阅仍为 `PENDING`。
- **Independent semantic review（独立记录）**：身份 `4/4`、行为 `4/4`、四例均至少有两个有效身份结构，结构质量 2 为 `4/4`。
- B03 的官方身份失败是冻结评估策略造成的 false negative，不是模型、Schema、解析器或运行合同执行错误。
- B04 的 `stem` 应当确认高脚杯杯脚结构；此前要求它在 `required_identity_parts` 中重复 `narrow`，属于人工解释过严，不是模型错误，也不是官方自动评估失败。
- 独立语义审阅满足用户指定的 Gate B 建议条件，因此**建议语义层进入 Gate B**；本任务没有启动 Gate B，仍需用户另行批准。

Source run：`blind-retest-3c-20260803T060715018997Z-4ddf8f31`  
Frozen pending evidence SHA-256：`650c0de04ebe417c822a19d542528908170897047daacefd5e79e589efe74f29`

## 1. 双轨结果不可混写

| 维度 | Official automatic verdict | Independent semantic review |
|---|---:|---:|
| API 成功 | 4/4 | 不重新调用 |
| exactly one legal tool_use | 4/4 | 不重新解析 |
| Schema + cross-field 有效 | 4/4 | 不重新验证 |
| 基础身份正确 | 3/4 | 4/4 |
| 行为正确 | 4/4 | 4/4 |
| 至少两个有效结构 | 官方仍为 0/4 complete、4/4 pending | 4/4 |
| 固定武器替换 | 0 | 0 |
| 自动重试 | 0 | 0 次新调用 |
| 结果状态 | `NEEDS WORK` | 合同语义条件满足 |

独立审阅没有修改 `automatic_scores.json`、`pending_summary.json`、冻结 expected、评估器、Schema、Prompt、原始结果或 pending evidence。它不取代、不重算、不“修复” official automatic verdict。

## 2. 四例独立结构审阅

人工判断只比较冻结结构概念与模型实际 `required_identity_parts` 是否表达同一结构；不要求形容词逐字完全一致。材料、颜色、效果、动作和装饰不能获得结构分。

| Case | 冻结结构 | 模型实际原句 | 独立判断 |
|---|---|---|---|
| B01 | vacuum body / 吸尘器主体 | `main canister body` | 是 |
| B01 | long hose / 长软管 | `long flexible hose` | 是 |
| B01 | nozzle or suction head / 吸嘴或吸头 | `nozzle end` | 是 |
| B02 | clock face / 钟面 | `clock face with hands` | 是 |
| B02 | twin bells / 双铃 | `twin bells on top` | 是 |
| B02 | hands or clock body / 指针或钟体 | `round clock body` | 是，匹配“钟体”分支 |
| B03 | upper pressing arm / 上压臂 | `hinged top arm` | 是 |
| B03 | base / 底座 | `base plate` | 是 |
| B03 | rear hinge / 后部铰链 | 无独立明确原句 | 否 |
| B04 | cup bowl / 杯身 | `cup bowl` | 是 |
| B04 | narrow stem / 细长杯脚 | `stem` | 是；“细长”是轮廓修饰 |
| B04 | base / 底座 | `base foot` | 是 |

确认结构数为 B01 `3`、B02 `3`、B03 `2`、B04 `3`，共 `11/12`。四例实际 `required_identity_parts` 中的其余项目也都是结构部件，不是材质或装饰，因此四例结构质量均为 2。

B04 的模型还在独立轮廓字段中输出：

> `wide bowl narrowing to slender stem widening to round base`

并在视觉提示中输出 `slender stem`。这证明 `stem` 是结构名，而 `slender` 已由轮廓/视觉描述承载；要求在结构名内再次写出 `narrow` 会把轮廓修饰错误提升为结构词面门槛。

## 3. B03 身份争议

模型实际输出：

- `canonical_name_zh`: `订书机`
- `canonical_name_en`: `stapler`
- `display_name_zh`: `巨型夹击订书机`
- `display_name_en`: `Giant Clamping Stapler`
- `visual.prompt_en`: 以 `A giant oversized stapler` 开头

v1.1 的字段边界规定 canonical name 表达原物件身份，display name 可承载表现修饰，silhouette 单独描述轮廓。`巨大 / giant` 是尺寸或轮廓修饰，不会把“订书机”变成另一种基础物件。模型既保留了 canonical 的订书机身份，也在 display 与视觉提示中保留了巨大尺度，所以独立合同语义判断为身份正确。

## 4. 准确根因

冻结 3C expected 对 B03 只允许以下 canonical 类别：

- 中文必须包含 `巨大`、`巨型` 或 `大号`；
- 英文必须包含 `giant`、`oversized` 或 `large`。

评估器 `_canonical_equal` 对规范化后的完整字符串做严格相等。因此 `订书机 / stapler` 按冻结机械规则必然失败。与此同时，相同冻结 expected 对 B01 允许裸 `吸尘器 / vacuum cleaner`，对 B04 允许裸 `高脚杯 / goblet`，没有要求年龄或颜色必须进入 canonical。

责任分类：

| 争议 | 准确责任 | 模型错误 | 评估器错误 |
|---|---|---:|---:|
| B03 canonical 遗漏“巨大” | 冻结 evaluator expected/policy 对尺寸修饰处理不一致 | 否 | 是，false negative |
| B04 `stem` 未重复“细长” | 先前拟议的人工审阅解释过严 | 否 | 否；官方结构审阅尚未完成 |

Schema 只要求 `required_identity_parts` 为 2–5 个具体结构字符串，并将 silhouette 分离；本地解析器没有修改模型输出。因此这两项争议均不归 Schema 或解析器。

## 5. 不采用物件专用运行时映射

本 Postmortem 没有修改评估器，也没有增加 stapler、goblet、vacuum 或 alarm-clock 的运行时关键词/物件映射。案例文字只存在于冻结证据与独立审阅记录中。

若未来修订评估合同，应采用通用字段政策：

1. canonical 先判断基础物件身份；
2. 尺寸、颜色、年代、材料和轮廓修饰单独检查是否在适当 typed field 或视觉描述中得到保留；
3. 战斗/效果词继续禁止污染 canonical；
4. 结构同义判断保留身份范围约束，但不要求轮廓形容词在结构名中重复。

这是一项面向所有物件的合同规则，不是为 B03/B04 添加特例。本任务只记录建议，没有修改当前 v1.1 Schema、Prompt、evaluator 或运行合同。

## 6. Gate B 建议与停止条件

独立审计确认：

- 身份正确 `4/4`；
- 行为正确 `4/4`；
- 每例至少两个有效结构 `4/4`；
- 固定武器替换 `0`。

因此建议语义层进入 Gate B。该建议不改变 frozen official automatic `NEEDS WORK`，也不等于批准或启动 Gate B。

本任务执行的外部 API 调用为 `0`；没有启动 ComfyUI、Gate B 或 V2，也没有修改战斗、房间、锚点或美术系统。完成本离线 Postmortem 后停止。
