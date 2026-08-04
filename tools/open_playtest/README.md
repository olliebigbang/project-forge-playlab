# Forge Open Playtest Mode

这是 `project-forge-playlab` 内部的开放输入试玩入口，不是正式产品模式，也不是 V2。默认 Godot 主场景和默认 Provider 仍为 `MOCK`；只有从专用脚本启动并在界面点击 **进入 OPEN PLAYTEST MODE** 后，才会使用真实链路。

## 启动

在新的 PowerShell 窗口执行：

```powershell
cd "C:\Users\Eddie L\Documents\project-forge-playlab"
.\scripts\run_open_playtest.ps1
```

脚本会先执行离线测试和安全预检，再启动只监听 `127.0.0.1:8190` 的 ComfyUI、只监听 `127.0.0.1:8771` 的本地桥接层，最后打开独立 Godot 场景。

Anthropic Key 每个试玩窗口最多输入一次，不是每个点子输入一次。Key 只存在于当前入口进程环境，不写入 `.env`、Git、JSON、CSV、截图或日志；关闭 Godot 后脚本会清除环境并停止本次拥有的服务。模型 ID 固定为 `claude-sonnet-5`，不能在界面更换。

## 一轮试玩

1. 输入任意中文描述并点击 `FORGE`。
2. 查看逐阶段状态：语义编译、图像生成、背景移除、Sprite 处理、身份确认、锚点确认、训练区就绪。
3. 对照 FLUX 原图和 96×96 透明 Sprite，回答“仍然能认出这是原物件吗？”
4. 选择“否”会记录备注并结束本轮；不会进入训练区。
5. 选择“是”后依次确认 `GripPrimary` 与当前行为所需的 `EffectOrigin`、`SpinPivot` 或 `StrikePoint`。
6. 训练区支持左右移动、攻击和闪避，只验证既有三类基础行为。
7. 结束训练后可评分、标记是否保留点子，并执行 `SAVE THIS RESULT`、`RETRY THIS IDEA` 或 `FORGE NEW IDEA`。

同一窗口最多进行 20 次真实语义调用。每轮只调用一次 Claude、一次 FLUX、一次 BiRefNet；没有自动重试，没有 Mock 回退，也没有固定武器替换。若 Claude 要求澄清，界面会把它作为语义阶段的单一澄清问题显示在失败原因中；编辑原输入后可显式重新 Forge。

## 模式边界

- 只接入已有训练区，不接入两个战斗房间。
- 不启用草图输入。
- 不增加敌人、关卡、成长、掉落、数值平衡或发布功能。
- 不修改 `project-forge` 或 `project-forge-claude`。
- 关闭窗口时不会自动保存为正式资产；`SAVE THIS RESULT` 只标记本地试玩记录。
- 当前提示文案明确说明：图像和基础攻击可验证，完整特效、数值、敌人平衡及正式玩法尚未完成。

## 本地文件

- 最近记录 JSON：`tools/open_playtest/local_history/playtest_history.json`
- 最近记录 CSV：`tools/open_playtest/local_history/playtest_history.csv`
- 每次会话：`tools/open_playtest/output/sessions/<session_id>/`
- 每轮证据：`tools/open_playtest/output/sessions/<session_id>/rounds/<round_id>/`
- 启动和进程日志：`tools/open_playtest/runtime/<session_id>/`

这些运行目录均被 `.gitignore` 排除，不做云同步。玩家中文输入属于本地试玩数据；需要分享前应自行审阅和脱敏。

完整字段说明见 [LOG_FORMAT.md](LOG_FORMAT.md)。

## 失败与清理

失败页显示准确阶段与本地错误代码，保留输入并提供 `REFORGE SAME IDEA` / `TRY NEW IDEA`。旧 `round_id + revision` 请求会被拒绝，未完成轮次不会被新请求覆盖。

正常关闭 Godot 后，入口脚本会：冻结本会话摘要与 SHA-256、停止桥接层、停止隔离 ComfyUI、清除 Key/模型环境变量、确认 8188/8190/8771 关闭，并验证历史 Spike 证据、两个正式仓库状态和默认 MOCK 边界没有改变。
