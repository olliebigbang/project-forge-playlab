# Forge Combat Feel Slice 0 使用说明

这是 `project-forge-playlab` 内部的独立桌面试玩切片，不是 V2，也不会成为默认主场景。

## 启动固定开发夹具

```powershell
cd "C:\Users\Eddie L\Documents\project-forge-playlab"
.\scripts\run_combat_feel_slice.ps1 -Fixture M01
.\scripts\run_combat_feel_slice.ps1 -Fixture M02
.\scripts\run_combat_feel_slice.ps1 -Fixture M03
```

`THRUST` 仅用于开发者验证通用刺击动作。所有 fixture 都会在界面中明确显示 `DEVELOPER FIXTURE`，不会冒充真实生成结果。

## 使用现有 Live 结果

不调用任何模型；只把已经存在且已确认的本地结果交给战斗切片：

```powershell
.\scripts\run_combat_feel_slice.ps1 `
  -SpritePath "<processed_sprite.png>" `
  -BlueprintPath "<blueprint.json>" `
  -AnchorsPath "<anchors.json>"
```

入口会拒绝非 `heavy_melee` Blueprint，不会强制改成固定武器。若从打包版启动，显式传入 `-- --mode=combat-feel-slice-0`；无此参数时默认 Playlab 流程不变。

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
