# 陌生枪械自动参考与成品管线 V1

## 一句话结果

玩家只输入枪械名称。目录里没有该型号时，AI 自动认出它、填写封闭机制轴与精确外形身份证；系统再从 Wikimedia Commons 自动寻找可复用的真实参考图，核对许可和型号，最后才交给 FAL 画像素成品。整个流程不问玩家“这把武器怎么打”。

## 为什么要增加这一层

只有“常规步枪、长枪管、前置弹匣”这类机制轴时，玩法可以成立，但 M16A2、AKM、MP5 等型号仍容易被画成同一根长条枪。V2 枪械身份解析现在额外强制输出：

- 5 个精确外形轴：枪托、上方标志、弹匣、护木/前端、机匣；
- 2–8 个在 96×96 像素仍必须看见的识别点；
- 1–8 个必须排除的近似型号或错误结构。

这些字段只约束画面，不拥有伤害、射速、后坐力、装填或玩家操作。机制仍只来自封闭 ranged axes。

## 自动流程

1. 先查四个内置型号和已验证的本地身份缓存。
2. 陌生名字由 Anthropic 返回严格的 `forge-firearm-identity-ai-response-v3`；Python 与 Godot 各验证一次。V3 同时包含枪械机制轴 V2。
3. 只有受当前轴系统支持的弹匣供弹步枪、卡宾枪、带枪托冲锋枪和半自动手枪会继续。坦克、左轮、管式霰弹枪、弹链武器和发射器继续在类别边界处拒绝。
4. 动态身份自动声明 `auto_wikimedia_v1`，玩家不能提供 URL。
5. Wikimedia Action API 只搜索 File 命名空间，并只接受 Commons 来源页、`upload.wikimedia.org` 图片、JPEG/PNG 和许可白名单：Public Domain、CC0、CC BY、CC BY-SA。
6. 下载后计算 SHA-256；作者、来源页、许可链接和源文件 SHA-1 一并留档。本地缓存再次读取时会复核身份卡指纹、文件格式和图片哈希。
7. 参考图要经过最多两次、最终必须两次一致通过的视觉核验：准确型号、目标清楚、可用侧视关系、全部大轮廓识别点存在、没有易混结构。
8. 通过的参考图以 data URI 送入 `fal-ai/gpt-image-1.5/edit`，再由 `fal-ai/image2pixel` 转成最多 24 色的像素图。
9. 成品再由 Anthropic 做两次参考图对候选图核验，并经过 Godot 的真实 Alpha、色板、角色区域和结构门槛。
10. 只有全部通过的成品才可写入 accepted-only 视觉缓存并标记 `finished_art=true`、`presentable_to_player=true`。

Wikimedia 客户端使用带项目联系地址的描述性 Bot User-Agent、串行下载、1 秒最小图片请求间隔，并遵守 `Retry-After`。429/503 最多自动重试一次；服务端要求等待超过 30 秒时，本次请求会失败关闭，不绕过限流。

## M16A2 真实端到端证据

输入 `M16A2`，它不在四枪内置目录中。

- 动态身份：`ai_b5e3514c97d43412`，置信度 0.95；
- 机制：常规步枪、固定枪托、握把前供弹、弯弹匣、长枪管、提把上轮廓；
- 自动参考：`File:M16A2 noBG.jpg`，Swedish Army Museum，CC BY-SA 4.0；
- 下载 SHA-256：`930d054265e381f5c5dccdf09ac403a24af832e403f074b29b31715097112aa3`；
- 参考图视觉核验：2/2 通过，最低置信度 0.95；
- 成品视觉核验：2/2 通过，最低置信度 0.93，使用了参考图比较；
- Godot 自动结构门槛：通过；
- 最终状态：`finished_art=true`、`presentable_to_player=true`；
- 再次输入同名型号：身份缓存与已验收视觉缓存均命中，`visual_cache_hit=true`。

工作区证据：

- `output/firearm-dynamic-auto-reference-v1-20260827/m16a2/generation/manifest.json`
- `output/firearm-dynamic-auto-reference-v1-20260827/m16a2/generation/processed_sprite.png`
- `output/firearm-dynamic-auto-reference-v1-20260827/m16a2/reference/record.json`
- `output/firearm-dynamic-auto-reference-v1-20260827/m16a2/reference/last_attempt.json`

`last_attempt.json` 也保留被拒或下载失败的候选与机器错误码，不会把失败过程伪装成成功。

## 主要实现文件

- V3 语义契约：`data/combat_feel/firearm_identity_ai_response_schema_v3.json`
- V3 系统提示：`data/combat_feel/firearm_identity_ai_prompt_v3.txt`
- Godot 身份验证与缓存：`scripts/combat_feel/firearm_identity_ai_resolver.gd`
- Commons 检索、许可、哈希与参考核验：`tools/visual/wikimedia_firearm_reference_resolver.py`
- FAL 接入与双图成品核验：`tools/visual/fal_firearm_pixel_bridge.py`
- 无界面端到端运行器：`tools/visual/run_dynamic_firearm_live.gd`

## 当前验证

- 语义桥：9/9；
- Python 视觉管线：26/26；
- Godot 动态枪名解析：11/11；
- Godot 枪械机制与视觉：16/16；
- Godot 主回归：38/38。

## 许可说明

参考图的作者、许可和来源页会进入最终 manifest。CC BY 与 CC BY-SA 需要署名；使用 CC BY-SA 参考进行高保真变换时，正式发行前还必须把相应署名和 ShareAlike 要求纳入游戏资产清单与发行许可流程。当前管线负责保存完整溯源证据，不把“Commons 可下载”误写成“无条件无署名”。
