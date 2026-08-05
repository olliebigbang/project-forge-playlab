# Forge Combat Feel Slice 0 Revision A

Status: **NEEDS WORK — REAL ASSET VALIDATION 1/3; IMPLEMENTATION READY FOR THE REMAINING LIVE INPUTS**

## 本次修正结果

- 默认入口已从 `DEVELOPER FIXTURE` 切换到冻结的真实 Live E2E L03 巨大木勺。
- 冻结成品包含真实 FLUX/BiRefNet `processed_sprite.png`、v1.1 语义蓝图、玩家确认锚点和结果 manifest；复制文件均由 SHA-256 固定，原 Live 证据未覆盖。
- Open Playtest 的 `heavy_melee` 完成页新增 `TEST HEAVY MELEE FEEL`，将同一轮最终目录直接交给 Combat Feel 子进程。非近战行为不会显示入口。
- 本地入口拒绝非 heavy_melee、缺文件、非 96×96、无有效 Alpha 和哈希不一致；没有 Mock/fixture 自动回退。
- developer fixture 仍保留为显式离线诊断数据，但不再是正常试玩默认值或截图来源。

## 通用动作差异

没有增加木勺、平底锅或拖把专用攻击类/名称分支。`MeleeMotionCompiler` 只读取：

- `impact_mode`；
- `GripPrimary / GripSecondary / StrikePoint`；
- Alpha opaque bounds、填充率与攻击端局部实体宽度；
- 语义重量/节奏提示。

这些证据编译为 reach、tempo、motion family、弧度、命中区厚度、控制强度、拍击锐度和显示缩放。通用回归数据得到：

| 结构特征 | 编译结果 | 预期手感 |
|---|---|---|
| 长、前端有实体质量 | long / committed / broad sweep | 更长、更慢、更重、更大范围 |
| 短、紧凑、whole-body contact | short / rapid / slam | 更短、更快、更脆的拍击 |
| 长、稀疏、edge contact | long / balanced / wide sweep / higher control | 横扫和控场 |

冻结真实木勺实际编译为 `sweep / committed / long`。平底锅与拖把仍须用真实最终资产验证同一通用规则，不能用 fixture 代替结论。

## 打击感 Pass

- 第一击、第二击、第三击、蓄力使用四个可测的 hitstop 层级；committed 起点约为 64 / 82 / 118 / 135 ms。
- 第二击增加击退、震动、粒子和硬直；第三击有约 1.78 倍终结击退、42 px/s 向上分量、14° 后仰、双冲击环；蓄力为更大的硬直、小击飞和摄像机 kick。
- 普通敌人受击会闪白、后仰并移动；第三击与蓄力对 Slag Puppet 分别触发 0.68 s / 0.82 s 大硬直。
- 摄像机同时使用随机 shake 和反向 kick；第三击、蓄力强于前两击。
- 轻击、中击、终结/蓄力的火花数量、速度、颜色和冲击环不同。
- `swing_light`、`swing_heavy`、`whiff`、`hit`、`heavy_hit` 使用分开的程序化占位音路径；挥空不再播放命中声。
- 武器动画改为 startup → active → recovery 的单次连续姿态，不再在每个阶段重复完整挥动；第三击/蓄力弧线更大。

这些是近战切片参数，不是正式平衡或新战斗系统。

## 真实资产核对

| 物件 | 真实 Sprite | 真实锚点 | 真实蓝图 | Combat smoke | 状态 |
|---|---:|---:|---:|---:|---|
| 巨大木勺 | 是 | 是，玩家确认 | 是，v1.1 | PASS | VERIFIED |
| 平底锅 | 仓库中未找到 | 未找到 | 未找到 heavy_melee 最终轮次 | 未执行 | BLOCKED ON REAL OPEN PLAYTEST ROUND |
| 旧拖把 | 仓库中未找到 | 未找到 | 未找到 | 未执行 | BLOCKED ON REAL OPEN PLAYTEST ROUND |

缺失项明确记录在 `data/combat_feel/live_assets/revision_a/index.json`。没有把 developer fixture、Gate A 的 returning-thrown 平底锅文本，或任何手绘占位图冒充真实成品。

## 自动与构建验证

- Combat Feel tests: 33/33 PASS。
- Open Playtest offline tests: 21/21 PASS。
- 默认真实木勺场景 parse + smoke: PASS。
- Windows 本地 runtime + PCK：构建并以 PCK 内冻结真实资产启动 PASS。
- Web build: PASS；默认主场景/Mock 边界未改变。
- 没有调用 Claude、FLUX、BiRefNet，没有新增敌人、房间、行为家族或 V2 内容。

## 视觉证据

- [真实 Live 木勺 handoff](screenshots/combat_feel_slice_0_revision_a/real_weapon_comparison.png)
- [第一击命中层级](screenshots/combat_feel_slice_0_revision_a/normal_hit_feedback.png)
- [第三击终结层级](screenshots/combat_feel_slice_0_revision_a/third_hit_feedback.png)
- [Slag Puppet 预警](screenshots/combat_feel_slice_0_revision_a/slag_puppet_telegraph.png)
- [Forge Ram 预警](screenshots/combat_feel_slice_0_revision_a/forge_ram_telegraph.png)

## 完成 3/3 所需的唯一下一步

在显式 Open Playtest Mode 中各完成一次真实平底锅和旧拖把 heavy_melee 轮次，确认身份和锚点，然后点击 `TEST HEAVY MELEE FEEL`。这需要玩家在本机为每轮作身份/锚点判断；在获得这两个真实目录前，本报告不会声称三武器差异或 Revision A 真人手感已经通过。
