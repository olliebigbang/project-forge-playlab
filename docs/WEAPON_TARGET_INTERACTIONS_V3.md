# 武器→目标反应 V3

## 这层解决什么

以前武器轴主要改变自己的动作、射速、伤害和后坐。命中目标后，大部分结果仍然只是“扣血并闪一下”，所以不同武器的机制差异不够明显。

V3 在武器与敌人之间增加一个身份无关的反应编译器。它不读取枪名、武器名或敌人名字，只读取：

- 武器已经声明的机械结构轴；
- 当前接触动作或枪械运行参数；
- 目标提供的质量、护甲完整度和当前行动状态。

玩家不需要回答“这件武器应该怎么打”。

## 七个独立反应轴

| 反应轴 | 唯一最终参数 | 玩家能看到的结果 |
|---|---|---|
| wound | damage_multiplier | 刃面造成更深伤害 |
| impulse | displacement_scale | 宽面或强冲击把目标推开 |
| control | stagger_seconds | 目标硬直并中断动作 |
| breach | armor_damage_ratio | 护甲逐步破损，最后碎裂 |
| pin | pin_seconds | 点刺把单个目标钉在原位 |
| bind | entangle_seconds | 软性结构缠住目标；鱼钩则拉回 |
| suppress | suppression_seconds | 快速火力让目标减速并推迟攻击 |

每个最终参数只有一个反应轴能写入。单变量有限差分会遍历每个轴的 `none / light / medium / strong`，报告零效应、重复方向、覆盖项、未覆盖参数和所有 Clamp 后矩阵。

## 武器结构怎样变成反应

- 点接触配合突刺：钉住，并有中等破甲能力。
- 刃接触：提高伤害，不伪装成强击退。
- 宽面接触：主要负责推移。
- 整体接触：主要负责大范围硬直。
- 柔性线缠绕：延长束缚并阻止移动。
- 鱼钩：把目标朝玩家方向拉，不当成鞭子式缠绕。
- 枪械冲击轴：负责位移和硬直。
- 枪械穿透轴：负责护甲损耗。
- 枪械射击节奏轴：负责压制时间。

## 与敌人攻击分支的边界

本分支只决定“玩家武器命中后，目标怎么反应”。敌人攻击分支仍然独立决定敌人怎样预警、瞄准、出招和恢复。

以后合并时，敌人只需提供机械上下文：

```text
mass_class: light | medium | heavy
armor_integrity: 0.0 .. 1.0
state: tell | attack | charge | recovery
```

反应编译器不会根据敌人名字选择结果。

## 验证

```powershell
Godot_console.exe --headless --path . --script res://tests/test_weapon_target_interactions.gd
Godot_console.exe --headless --path . --script res://tools/export_weapon_target_interaction_audit.gd
```

审计工具默认把本地证据写到：

```text
output/weapon-target-interaction-v3-audit/finite_difference_audit.json
```

该输出是本地审计证据，不是游戏运行依赖。
