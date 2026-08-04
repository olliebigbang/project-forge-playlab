# Forge Semantic Anchor Calibration Spike 1

> 独立训练区验证；仅使用 Spike 0 已有的 11 张透明 Sprite。未启动 ComfyUI，未生成新图，未接入房间或正式战斗。

## 结论

- 自动可调锚点准确率：**11/22（50.0%）**。
- 完全自动可用率：**4/11（36.4%）**。
- 固定人工复核点经两步校准接口后最终可用率：**10/11（90.9%）**。
- 左向素材被派生资产水平归一化：**4** 张；原始 Sprite 未改写。

准确率按 96×96 图上 `GripPrimary` 与 `EffectOrigin/StrikePoint` 距人工视觉复核点不超过 9.0 px 计算；派生的 `GripSecondary` 与 `SpinPivot` 单独做 Alpha 几何检查。11 张的校准后比例来自固定复核坐标通过同一校准/保存接口的批量验证，不冒充 11 次录制的 GUI 会话；点击、拖动、分步确认与画布外起拖拒绝由独立自动 UI 事件测试覆盖。

## 逐张结果

| Sprite | 行为所需锚点 | 自动点 | 自动可用 | 校准后可用 | 训练派生翻转 |
|---|---|---:|:---:|:---:|:---:|
| case_a/seed_41001_s45 | GripPrimary, GripSecondary, EffectOrigin | 2/2 | ✓ | ✓ | — |
| case_a/seed_41002_s70 | GripPrimary, GripSecondary, EffectOrigin | 2/2 | ✓ | ✓ | — |
| case_a/seed_41003_s45 | GripPrimary, GripSecondary, EffectOrigin | 2/2 | ✓ | ✓ | — |
| case_b/seed_41001_s00 | GripPrimary, SpinPivot, StrikePoint | 1/2 | — | ✓ | — |
| case_b/seed_41003_s00 | GripPrimary, SpinPivot, StrikePoint | 2/2 | ✓ | ✓ | — |
| case_c/seed_41001_s45 | GripPrimary, GripSecondary, StrikePoint | 0/2 | — | ✓ | ✓ |
| case_c/seed_41002_s70 | GripPrimary, GripSecondary, StrikePoint | 0/2 | — | ✓ | ✓ |
| case_c/seed_41003_s45 | GripPrimary, GripSecondary, StrikePoint | 0/2 | — | ✓ | ✓ |
| case_d/seed_41002_s70 | GripPrimary, EffectOrigin | 1/2 | — | ✓ | — |
| case_d/seed_41003_s45 | GripPrimary, EffectOrigin | 1/2 | — | — | — |
| case_e/seed_41001_s00 | GripPrimary, EffectOrigin | 0/2 | — | ✓ | ✓ |

## 失败层与边界

- `case_d/seed_41003_s45` 即使完成两点校准，仍没有可信的可见发射/力量出口，因此按视觉语义复核判为不可用；不以继续调参或伪造枪口掩盖。
- `GripSecondary` 仅在双手行为声明下，按主握点朝 Alpha 质心方向搜索实体区域；玩家不需要逐件设置。
- `SpinPivot` 仅在回旋行为声明下使用二值 Alpha 质心；不要求玩家点击。
- `StrikePoint` 与 `SpinPivot` 在此 Spike 中由 Forge 覆盖层验证；现有战斗规则未被修改，因此本报告不声称它们已成为新的玩法机制。
- 运行时只向既有 `GameplayArena.start_stage("training", ...)` 交付复制出的校准资产；默认 Mock、房间一/二和 V2 均保持原状。

## 视觉证据

- `calibration_ui.png`：步骤 1、旧自动建议灰圈、Forge 握持夹具与作用符文。
- `calibration_step2.png`：家具 Sprite 的步骤 2 `EffectOrigin` 人工校准。
- `two_hand_strike.png`：双手行为的主/副握持夹具与 `StrikePoint`；副握点为 Alpha 派生。
- `returning_spin.png`：回旋行为的 `GripPrimary`、Alpha 质心 `SpinPivot` 与 `StrikePoint`。
- `training_zone.png`：校准资产、夹具和作用符文仅在既有训练区挂载。
- `test_run.txt`：Godot 解析、25 项回归/UI 事件测试及 11-Sprite 评估的可追溯输出。

## 产物

每张 Sprite 的独立 sidecar 位于 `tools/comfyui/anchor_calibration/output/<case_id>/<run_id>/semantic_anchors.json`，包含 `auto_anchors`、完整 `corrected_anchors`、`anchor_source`、`confidence` 与 `required_anchor_types`。
