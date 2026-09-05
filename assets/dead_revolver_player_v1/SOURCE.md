# Dead Revolver 人物原包来源

日期：2026-08-31。

## 当前上传核查（2026-09-05）

作者官方商品页的 More information 当前明确标注 Asset license 为 CC0 v1.0 Universal；本轮按此依据将项目已导入的 PNG、Aseprite 动作时序源及说明纳入开发分支快照。购买 ZIP 和账户/支付信息不上传。完整边界见仓库根目录 docs/ASSET_UPLOAD_SCOPE.md。
下文保留导入历史，其中“未上传/不公开再分发”描述各历史操作的当时范围，不应被误读为当前作者授权条款。此核查不把任意付费素材自动视为可再分发。

## 导入历史

- 作者与产品：[Dead Revolver — Pixel Prototype Player Sprites](https://deadrevolver.itch.io/pixel-prototype-player-sprites)。
- 输入：用户在本对话主动提供的 `<USERPROFILE>/Downloads/PixelPrototypePlayer.zip`，不是从网页预览截取的人物。
- ZIP SHA256：`74D939C1D10A642A1E35901B4CEE4BC7AD6C90C81E06FB21FD47D335E3515040`。
- 原包 `Readme.txt` 明确区分完整动画、身体部件拆分动画、Aseprite 源文件。本地保留该说明。
- 仅导入14组候选动画的完整与拆分 PNG、3个 Aseprite 文件及说明，共775个原文件。
- 逐文件与 ZIP 内对应条目核对 SHA256：775个相同，0个不一致。Godot 生成的 `.import` 不属于原文件。
- 使用 `tools/art/import_dead_revolver_player.ps1` 有界导入，拒绝路径越界与覆盖已有文件。没有运行原包自带脚本。

运行时实际使用 Idle、GunWalk、GunRun 的头、躯干、腿及空闲手臂，以及 GunAim 的右臂像素。持械双臂从这条完整右臂拆分并作关节变换；不是宣称原包已经附带所有物品的双手握持动画。

PNG 未被改画。场景运行时给不同身体部件着色、加一像素轮廓和朝向眼点，按同一像素网格绘制；最终衣服、头发、表情还未设计。未提交、推送或上传原包及其源文件。本记录是本地素材溯源，不将用户提供 ZIP 等同于可任意公开再分发授权。

## 后续补入：原包剑招还原（2026-08-31）

独立`original_sword_preview`入口直接使用完整人物PNG，不使用以上旧V1分臂/调色方式。为还原原作者动作，从同一用户ZIP只补入`Sprites/Combat/SwordRun`与`SwordCombo01`至`SwordCombo04`共32张PNG，工具为`tools/art/import_original_sword_clips.ps1`，拒绝覆盖不同内容的已有文件。原775个文件不改。

此入口使用的全部60张PNG（上述32张及原有SwordIdle/SwordWalk/SwordSlash01/StandingSlash）与ZIP对应原文件SHA256均相同。原画布96×84，原白人偶、剑与绿色斩光全部保留；逐帧时长从未改动的`Aseprite/PlayerCombat.aseprite`读取。没有执行作者脚本、生成或重画原图、购买、提交、推送或公开发布素材。详见`docs/ORIGINAL_SWORD_PREVIEW_V1.md`（仓库根目录）。

## 后续补入：原包全动作训练场（2026-08-31）

`tools/art/import_original_action_clips.ps1`从同一用户ZIP有界核对680个原文件，
新增528个文件；既存文件只核对SHA256，不覆盖不同内容。包括非攀爬全身PNG、
配套FX/Weapons、75张原枪Weapon层，以及PlayerFishing/Effects两个Aseprite源文件。
运行库不使用没有源tag的IdleTransition两张PNG；不执行包内脚本。

普通画布96×84，钓鱼画布143×104，使用各自固定脚点保留原始全身像素。原钓鱼
Prepare03/Cast01含大紫棕拖影，原CrouchDustBack末三帧为空，未改画或掩盖这些源特征。
Effects的重复RunDustFront标签在解析时保留最后同名标签，只作检查菜单播放。

107组动作/配套图的接入分层、实际用途与审核限制见仓库根目录
`docs/ORIGINAL_ACTION_PREVIEW_V1.md`。没有购买、上传、提交、推送或公开发布原包。

## 后续补入：实际战斗原包动作适配（2026-08-31）

用户确认替换后，`tools/art/import_original_action_clips.ps1`补全非攀爬
人物动作的Head/Torso/LeftArm/RightArm/LeftLeg/RightLeg及Weapon分层。
本轮有界导入共核对3811个ZIP条目，新增2540个原文件；拒绝覆盖不同哈希。
不执行ZIP内Export.sh，不公开再分发原素材，不重画原PNG。

主远征与Sunny持械场景现共用`authored_player`适配器：原身体/腿/头帧，
真实AI武器替代原Weapon。双臂是原手臂像素的关节重定位，源手臂层里属于
颈胸的原像素留在身体核心；离散1–4px动作碎屑仅在运行时过滤。
固定源画布和脚点保留，原动作对照场景不受该适配绘制影响。

它不意味着每一源动作已成为主游戏技能，也不意味着所有源分臂天生带有
完整不遮挡的肢体。本轮仍是白人偶动作适配，不是最终皮肤；证据见仓库根
`docs/AUTHORED_PLAYER_INTEGRATION_V1.md`。
