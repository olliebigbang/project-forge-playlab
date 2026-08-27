# General Object AI Parser V1

## 白话结果

玩家现在可以只输入一个物件名称，例如 `冰箱`、`彩电`、`自行车`、`鞭子` 或 `鱼竿`。玩家不需要说明怎么攻击。

系统会自动完成三件事：

1. 名称 AI 判断它是什么真实物件，并列出在 96 像素图里必须看得见的大结构。
2. 名称 AI 按真实结构填写完整机制轴，例如从哪里握、硬还是软、重量靠哪边、用尖端/边缘/宽面/整个物体接触，以及有没有独立软线、钩住或甩出收回。
3. Godot 在本地拒绝缺项和矛盾，再把通过的轴编译成攻击动作、碰撞和反应。玩家不会收到“你想怎么打”的问题。

使用 FAL 视觉模式时，普通物件会先被画成透明身份图，再转成有限色 96 像素图。Godot 仍会检查 Alpha、GripPrimary、StrikePoint、机制轴和软体视觉结构。玩家最后只确认“画出来的东西还是不是原物件”，不确认攻击机制。

## 对象边界

- 普通非生命物件：进入统一的 whole-object 机制编译器。编译器内部同时支持硬物、半硬物、连续软体、链节和独立牵引线；`heavy_melee` 是历史编译器名字，不表示所有东西都很重。
- 枪械名称：转交现有枪械解析器，不会被做成普通棍子。
- 汽车、坦克、飞机等动力载具：停止并要求未来的载具/Actor 编译器，不会缩成手持玩具。
- 人、动物和角色：停止并转向活体/Actor 边界。
- 自行车：当前允许作为完整刚性物件挥砸，但不提供骑乘或独立车轮模拟。

AI 不能填写伤害数值、敌人状态或平衡参数。它只声明可以从真实结构得到的身份和 Affordance 轴。

## 运行

开发者密钥可以放在 `.env`，玩家不会接触密钥：

```powershell
.\scripts\run_open_identity_ai.ps1 -EnvFile "C:\path\to\.env"
```

历史参数名 `FAL_FIREARM` 现在代表同一个 FAL 视觉入口：枪械走带枪型验收的画图管线，普通物件走通用身份画图管线。两者共享启动方式，但不共享机制解析器。

如果只想使用本地 ComfyUI：

```powershell
.\scripts\run_open_identity_ai.ps1 -VisualProvider LOCAL_COMFYUI -EnvFile "C:\path\to\.env"
```

## 缓存与等待时间

- 名称解析结果按规范化后的输入名称缓存在 `user://playlab/general_object_ai/cache_v1.json`。
- FAL 普通物件像素结果按身份、可见部件、完整机制轴和管线版本缓存；重复输入不会重复付费画同一张结构卡。
- 第一次陌生名称仍需要一次语义调用和一次视觉生成。缓存只复用已经通过本地校验的结果。

## 证据

- 严格响应 Schema：`data/combat_feel/general_object_ai_response_schema_v1.json`
- 不信任玩家文本的系统提示：`data/combat_feel/general_object_ai_prompt_v1.txt`
- Python 单次 AI 桥接与本地校验：`tools/semantic/bridge/general_object_ai_bridge.py`
- Godot 接收、缓存和组合校验：`scripts/combat_feel/general_object_ai_resolver.gd`
- FAL 普通物件视觉桥接：`tools/visual/fal_general_object_pixel_bridge.py`
- Godot FAL 普通物件 Provider：`scripts/services/fal_general_object_visual_provider.gd`
- 端到端离线机制测试：`tests/test_general_object_ai_parser.gd`

真实语义验证对 `冰箱`、`彩电`、`自行车` 做了未预置名称调用，三者都得到过 `improvised_object_supported` 和完整机制声明。补充“开放车架不是宽面”的规则后，自行车重新得到 `whole_body`、`has_broad_face=false`；其中一次格式不合法的模型响应被本地校验直接拒绝，下一次合法响应才获准进入流程。离线回归另外覆盖鞭子与鱼竿的不同软体结构、枪械/载具/活体分流、缓存、身份回显防护和 FAL 96 像素 Alpha 交接。
