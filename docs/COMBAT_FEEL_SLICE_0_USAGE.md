# Forge Combat Feel Slice 0 使用说明

这是 `project-forge-playlab` 内部的独立桌面试玩切片，不是 V2，也不会成为默认主场景。

## 启动 Revision A（真实生成武器）

```powershell
cd "C:\Users\Eddie L\Documents\project-forge-playlab"
.\scripts\run_combat_feel_slice.ps1
```

默认加载冻结的真实 Live E2E L03 巨大木勺成品，并在载入前检查
Sprite/Blueprint/Anchors/Manifest 的 SHA-256、96×96 尺寸和透明 Alpha。
界面显示 `REAL LIVE FORGE RESULT — FROZEN`，不会再默认进入 fixture。

在 Open Playtest 中完成一个真实 `heavy_melee` 轮次并确认身份、锚点和训练后，
点击 `TEST HEAVY MELEE FEEL` 可直接以该轮最终目录打开本切片。该按钮不会对
`sustained_ranged` 或 `returning_thrown` 显示。

## 手工传入现有 Open Playtest / Live 结果

不调用任何模型；只把已经存在且已确认的本地结果交给战斗切片：

```powershell
.\scripts\run_combat_feel_slice.ps1 `
  -OpenPlaytestRound "<rounds\<round_id>>"

.\scripts\run_combat_feel_slice.ps1 `
  -SpritePath "<processed_sprite.png>" `
  -BlueprintPath "<blueprint.json>" `
  -AnchorsPath "<anchors.json>"
```

入口会拒绝非 `heavy_melee` Blueprint、非 96×96 Sprite、无有效 Alpha 或缺失
Blueprint/Anchors 的结果，不会强制改成固定武器，也不会回退 fixture。

## 仅供开发诊断的 fixture

fixture 必须显式请求：

```powershell
.\scripts\run_combat_feel_slice.ps1 -DeveloperFixture M01
.\scripts\run_combat_feel_slice.ps1 -DeveloperFixture M02
.\scripts\run_combat_feel_slice.ps1 -DeveloperFixture M03
```

它们仍会显示 `DEVELOPER FIXTURE`，只用于通用动作编译器回归，不作为真人试玩视觉证据。

## 操作与调试

- WASD / 方向键：移动
- Space / J：攻击；按住约 0.30 秒后释放为蓄力重击
- Shift / K：闪避；短窗口内攻击为 Dodge Attack
- F3：显示/隐藏战斗调试和通用参数面板

胜利后必须完成七项 1–5 分问卷，记录只写入 `user://playlab/combat_feel_slice_0_events.jsonl`。

## 验证

```powershell
.\scripts\test_combat_feel_slice.ps1
.\scripts\build_combat_feel_windows.ps1
.\scripts\build_web.ps1
```

若本机没有 Godot Windows export template，构建脚本不会联网下载；它会生成一个仅供本 Playlab 使用的离线 runtime bundle：同版本本地 Godot 可执行文件加 `ForgeCombatFeelSlice0.pck`。这不是正式发布包。
