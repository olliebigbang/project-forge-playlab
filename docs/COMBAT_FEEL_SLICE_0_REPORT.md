# Forge Combat Feel Slice 0 Report

Status: **READY FOR HUMAN PLAYTEST — SUBJECTIVE FEEL NOT YET PASSED**

## 实现

- 独立场景 `combat_feel_slice_0.tscn`，默认 Playlab 主场景未改变；仅显式 `--mode=combat-feel-slice-0` 或运行脚本进入。
- 通用链路：`WeaponVisualAsset + AnchorData + CombatMotionProfile + MeleeMotionCompiler + MeleeCombatController`。
- `sweep / slam / thrust` 三种动作家族；三段普通连击、蓄力重击、Dodge Attack、单格输入缓冲和有限取消窗口。
- 同一武器 Sprite 围绕 `GripPrimary` 运动，命中区使用同一姿态和 StrikePoint/Alpha 尺寸；一次攻击对同一敌人只命中一次。
- 统一 `ImpactFeedbackProfile`：命中停顿、闪白、击退、硬直、镜头震动、粒子和程序化原创占位音。
- 两类固定原创敌人：Slag Puppet（接近/预警/挥击/恢复）与 Forge Ram（保持距离/压低锁定/直线冲锋/撞空恢复）。
- 三波共 8 只敌人，Victory、Defeat、Retry、Return to Forge；无掉落、升级、Boss 或第二房间。
- 原创锻造学徒占位轮廓、F3 Combat Debug Overlay、十项通用微调和本地 preset。
- M01–M03 与 THRUST 均为明确标注的本地开发 fixture；另支持将现有 Live `processed_sprite + blueprint + anchors` 作为只读 handoff，非 heavy_melee 会被拒绝。
- 胜利后七项 1–5 分和三项自由回答写入本地 JSONL。

## 暂定参数

- rapid：0.13 / 0.08 / 0.18 秒；balanced：0.19 / 0.10 / 0.25 秒；committed：0.29 / 0.13 / 0.36 秒（startup / active / recovery）。
- combo window 0.46 秒；input buffer 0.16 秒；charge threshold 0.30 秒；Dodge Attack window 0.26 秒。
- 普通 hitstop 起点约 40 / 60 / 80 ms；第三击或蓄力提高到最多约 115 ms，并增强击退、粒子和镜头反馈。
- Slag Puppet 预警/恢复 0.48/0.62 秒；Forge Ram 0.72/1.05 秒。

这些值仅是 Slice 0 的手感起点，不是正式平衡。

## 实际命令与结果

```powershell
.\scripts\test_combat_feel_slice.ps1
.\scripts\run_combat_feel_slice.ps1 -Fixture M01
.\scripts\run_combat_feel_slice.ps1 -Fixture M02
.\scripts\run_combat_feel_slice.ps1 -Fixture M03
.\scripts\build_combat_feel_windows.ps1
.\scripts\build_web.ps1
```

- Combat Feel 集中测试：23/23 PASS。
- 既有 Playlab 基线：32/32 PASS。
- M01、M02、M03、THRUST 独立场景 smoke：4/4 PASS。
- Windows runtime bundle 启动到显式 Combat Feel 场景并自动退出：PASS。
- Web 非阻塞导出：PASS。
- 本机缺少 Windows export template，因此 Windows 交付为已有 Godot 4.7.1 运行时加 PCK 的本地 Playlab bundle，不是正式 release export；没有下载任何模板。

## 截图

- [Slag Puppet 攻击预警](screenshots/combat_feel_slice_0/slag_puppet_telegraph.png)
- [Forge Ram 冲锋预警](screenshots/combat_feel_slice_0/forge_ram_telegraph.png)
- [普通命中反馈](screenshots/combat_feel_slice_0/normal_hit_feedback.png)
- [第三击命中反馈](screenshots/combat_feel_slice_0/third_hit_feedback.png)
- [三件 fixture 持有与攻击对照](screenshots/combat_feel_slice_0/three_weapon_comparison.png)

## 已知问题与真人试玩判断

- 自动测试只能证明状态机、输入窗口、敌人顺序和构建边界，不能声称“好玩”。
- 为区分点击和按住，普通攻击在按键释放时提交；真实玩家需要判断这点是否仍足够及时。
- 固定程序化角色/敌人/声音是可读占位资产，不是正式美术。
- 本轮没有重新调用 Claude、FLUX 或 BiRefNet，也没有重新生成 M01–M03；Live handoff 入口存在，但真实三件生成物的最终手感仍需人工跑。

当前版本适合开始 1280×720 Windows 键盘真人试玩，但在收集评分前不判定“手感通过”。下一步只需验证三个问题：

1. 普通攻击释放触发是否显得迟缓，输入缓冲 160 ms 是否自然；
2. M01–M03 的速度、距离、接触模式是否至少有两项被玩家明显区分；
3. Forge Ram 的非文字预警和恢复窗口是否支持稳定闪避反击。
