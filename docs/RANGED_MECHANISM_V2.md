# 枪械机制轴 V2

> 本文最初记录V2因果合同。当前运行时已演进为
> `forge-ranged-runtime-profile-v5`；V2原则继续保留，当前新增项见下文
> “V5补充”。

## 目标

枪械型号只提供身份事实，AI 负责声明机制轴，Godot 负责验证并编译。玩家不会被要求决定武器怎么攻击。像素图只负责身份和结构可读性，不拥有战斗参数。

V2 把结构轴和机制轴明确分开：

- 结构轴：`layout`、`stock_structure`、`feed_position`、`magazine_shape`、`barrel_length`、`upper_profile`、`support_mode`。它们服务结构约束、锚点和画图验收。
- 机制轴：`fire_control`、`cadence`、`recoil`、`recoil_recovery`、`muzzle_climb`、`accuracy`、`impact_force`、`penetration`、`reload`、`effective_range`、`handling`、`magazine_capacity`。

## 因果合同

每个最终运行时参数只有一个声明的机制轴所有者：

- `fire_control` → 半自动或按住连射。
- `cadence` → 射击间隔。
- `recoil` → 单发后坐位移。
- `recoil_recovery` → 位移回正速度和枪口角度回正速度。
- `muzzle_climb` → 单发枪口上跳角度。
- `accuracy` → 基础弹道散布。
- `impact_force` → 单发伤害和命中停顿。
- `penetration` → 正面护甲伤害保留和继续穿过目标的数量。
- `reload` → 换弹时间。
- `effective_range` → 弹速、寿命、伤害衰减起点和终点。
- `handling` → 普通移动和射击期间移动倍率。
- `magazine_capacity` → 弹匣发数。

编译结果使用 `forge-ranged-runtime-profile-v2`，同时保留：

- `raw_parameters`：Clamp 前参数矩阵；
- `final_parameters`：所有最终 Clamp 后参数；
- `clamp_events`：发生实际覆盖时的原值、终值和上下界；
- `parameter_owners`：每个最终参数的唯一机制轴所有者。

## 运行时消费

V2 参数已经进入实际战斗状态：

- 后坐位移和枪口角度分别积累、分别恢复；
- 子弹方向读取当前枪口角度；
- 子弹携带伤害、命中停顿、护甲保留、穿透预算和距离衰减范围；
- 护甲命中和普通目标命中读取同一份弹丸机制参数；
- 移动、连射、换弹和容量不包含任何枪械型号名称分支。

## V5补充：分级上跳和斜线弹道

V5在原12项机制轴上增加机械循环、供弹方式、弹丸形态和持续上跳。当前与后坐
直接相关的职责如下：

- `recoil`只拥有每发枪身向后的位移；
- `recoil_recovery`拥有枪身位移和枪口角度的回正速度；
- `muzzle_climb`同时拥有每发即时上跳和即时上跳上限，低/中/高的最终上限为
  4/9/16度；
- `sustained_climb`拥有长按连射后的额外累积、额外上限、累积窗口和恢复倍率。

因此轻型低上跳枪不会因为长按而最终撞上与重机枪相同的隐藏上限。冻结M249
样本的高上跳上限为16度，递增持续上跳还可再增加9度；冻结M4样本的低上跳
上限为4度。运行时只读取这些Clamp后参数，不读取M4或M249名称。

Sunny横向战场继续从真实枪口按当前角度发射：

- 斜线经过哪个前后排，就用同一斜率检查那个位置的敌人真实Alpha；
- 水平线仍不能命中另一排；
- 斜射按斜线路径延长寿命及衰减距离，使其水平覆盖仍等于`effective_range`
  声明，而不是角度越大越早消失；
- 这不是自动瞄准，子弹方向没有朝敌人弯曲。

缺少`muzzle_climb_cap_degrees`的历史枪械包只在内存中由原机制轴重编译，
不会重写哈希包或个人存档。

## 自动有限差分

`RangedMechanismAxisResolver.finite_difference_audit()` 会对给定枪械的 12 个机制轴逐一替换为每个合法值，其余输入保持不变，并记录每个案例的完整最终 Clamp 后参数矩阵。

审计显式报告：

- `zero_effect_axes`：单变量变化后没有任何最终参数变化；
- `duplicate_direction_groups`：两个轴产生完全相同的最终参数方向向量；
- `covered_effects`：Clamp 前发生变化、Clamp 后变化消失；
- `uncovered_parameters`：没有任何单变量变化能够覆盖的最终参数；
- `owner_mismatches`：实际影响轴和声明所有者不一致。

导出完整四枪审计：

```powershell
Godot --headless --path . --script res://tools/export_ranged_mechanism_v2_audit.gd
```

默认结果写入：

`output/ranged-mechanism-v2-audit-20260827/firearm_mechanism_v2_audit.json`

## AI 协议

动态枪名使用 `forge-firearm-identity-ai-response-v3`。它保留 V2 的精确视觉身份卡，同时强制 AI 补齐新的 V2 机制轴。旧的动态语义缓存不会被静默补默认值；V3 使用独立缓存，缺少新轴的身份必须重新由 AI 判定。
