# 素材与上传范围

核查日期：2026-09-05。用途是保存当前游戏开发分支，不是打包转售第三方素材。
仅检查项目文件和可核对的作者授权信息；购买记录、付款信息和下载账户不上传。

## 允许进入本轮代码快照的范围

| 素材目录 | 来源 / 核查证据 | 本轮范围 |
|---|---|---|
| assets/dead_revolver_player_v1 | [Dead Revolver 官方页面](https://deadrevolver.itch.io/pixel-prototype-player-sprites) 当前 More information 将 Asset license 标为 CC0 v1.0 Universal；原包 Readme 和 SOURCE.md 保留 | 已导入的原包 PNG 分层、完整动作、Aseprite 时序源、说明与适配清单；不上传购买 ZIP/账户信息 |
| assets/art_vertical_slice_v1 | [Ansimuz Church](https://ansimuz.itch.io/gothicvania-church-pack)，目录 public-license.pdf 明确允许 CC0 使用、修改和再分发 | 已选取的 PNG 和该授权说明；不据此授权其它音乐包 |
| assets/sunny_arena_preview_v1、sunny_enemies_v1 | [Ansimuz SunnyLand](https://ansimuz.itch.io/sunny-land-pixel-game-art)，保留的 public-license.pdf / SOURCE.md | 项目使用的原包图、来源说明；旧动物图仅兼容/练习依赖，不作为新增战斗怪物方向 |
| assets/sunny_fantasy_enemies_v1 | [SunnyLand Extended](https://ansimuz.itch.io/sunnyland-enemies-extended-pack) 的包内 CC0 PDF；[Sideview Fantasy 作者发布页](https://opengameart.org/content/sideview-fantasy-patreon-collection) 标注 CC0 | 已导入精灵与授权/来源记录 |
| assets/fonts | 随字体的 OFL.txt | Noto 字体与 OFL 一起保留 |
| sunny_expedition_v1、sunny_player_v2、背景改绘、武器固定样本 | 各 SOURCE.md、项目生成提示、固定结果 | 用户已要求保留的项目生成资源与必需的回归输入；不是第三方原包，不能冒称原作者绘制或一律标成 CC0 |

Dead Revolver 文件原先文档中的“未上传”是历史操作状态。本轮以核实到的官方 CC0 标注确定已导入文件的上传范围，
不是把“用户买了 ZIP”当作默认再分发权。将来新增其他付费素材要重新检查，不能套用本结论。

## 必须排除

- .env / .env.*（仅无真实值的 example/template 可跟踪）、*.local.json、真实密钥/令牌、账户和私人下载 URL。
- 根目录 sessions/、weapons/、sunny-expedition-v1/、church-expedition-v1/：玩家个人记录，不是随游戏提供的固定样本。
- .godot/、.tools/、build/、*.import、日志、临时文件、Python 缓存、引擎二进制、模型权重。
- 原始购买 ZIP、收据，以及与项目无关的个人/商业文件。
- 本轮识别出的旧本机路径清单与运行日志：从索引移除，文件留在本机，不删除原证据。

不能把 tools/comfyui/output 等目录整体删除：其中有运行和回归需要的冻结图片/契约样本。
忽略文件不等于已经从 Git 索引退出，须对实际暂存区再扫一遍。

## 门禁与边界

执行：`python -B tools/release/audit_upload.py --staged`，报告只给文件名/规则，不打印密钥值。
同时检查大文件、差异、文件来源、干净导出可运行性。自动扫描是启发式，不能证明所有未知格式或二进制元数据绝无敏感内容。

远端可见性属于单独的发布决定。2026-09-05 用户明确确认“保持公开”，授权按以上排除范围推送现有 PUBLIC 仓库的开发分支；不变更可见性、不合并 main。
不能把私有仓库视为绕过素材授权和敏感信息审批的理由。旧提交里已存在的本机路径未作历史重写。
