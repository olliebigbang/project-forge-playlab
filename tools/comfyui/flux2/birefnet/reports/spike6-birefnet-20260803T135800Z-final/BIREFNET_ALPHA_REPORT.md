# Forge FLUX Alpha Segmentation Spike 6 — BiRefNet

## 正式结论

**MODEL PASS / ALPHA PASS**

Spike 5 的冻结结论在本次验证完成前始终保持 `MODEL PASS / ALPHA NEEDS WORK`。Spike 6 使用官方原生 BiRefNet 对同一批 8 张冻结 FLUX 原图完成分割后，Alpha 门槛通过。结果仍 **不自动晋升默认玩家流程**，需等待 Live End-to-End 明确批准。

## 结果摘要

- 官方 BiRefNet RGBA + Mask：8/8。
- 96×96 技术交付：8/8。
- 人工可用 Sprite：7/8。
- 96×96 可识别：8/8。
- 严重结构丢失：0/8。
- 明显背景残留：0/8；明显投影残留：0/8。
- 洋红污染/歧义：1/8。
- 自动重试：0；案例专用修正：0。

人工评分基于实际 raw、RGBA、Mask 与 96×96 图片逐张目视检查，不以 Prompt、JSON 或启发式置信度代替视觉判断。

## 正式门槛

| 门槛 | 实际 | 要求 | 结果 |
|---|---:|---:|---|
| `rgba_and_mask` | 8 | >= 8 | PASS |
| `usable_sprite` | 7 | >= 7 | PASS |
| `identity_recognizable_96` | 8 | >= 7 | PASS |
| `serious_structure_loss` | 0 | <= 0 | PASS |
| `background_residual` | 0 | <= 0 | PASS |
| `shadow_residual` | 0 | <= 0 | PASS |
| `b01_both_hose_and_nozzle` | 2 | >= 2 | PASS |
| `b03_both_subjects_complete` | 2 | >= 2 | PASS |
| `b04_both_stem_and_base` | 2 | >= 2 | PASS |
| `automatic_retry` | 0 | <= 0 | PASS |
| `case_specific_correction` | 0 | <= 0 | PASS |

## 逐张人工结构审阅

| Case | Seed | 关键结构 | 背景/投影 | 洋红 | 96×96 | 严重丢失 | 可用 |
|---|---:|---:|---|---|---|---|---|
| B01 | 4041001 | 3/3 | PASS | FAIL | PASS | NO | FAIL |
| B01 | 4041002 | 3/3 | PASS | PASS | PASS | NO | PASS |
| B02 | 4041001 | 3/3 | PASS | PASS | PASS | NO | PASS |
| B02 | 4041002 | 3/3 | PASS | PASS | PASS | NO | PASS |
| B03 | 4041001 | 3/3 | PASS | PASS | PASS | NO | PASS |
| B03 | 4041002 | 3/3 | PASS | PASS | PASS | NO | PASS |
| B04 | 4041001 | 3/3 | PASS | PASS | PASS | NO | PASS |
| B04 | 4041002 | 3/3 | PASS | PASS | PASS | NO | PASS |

B01 / 4041001 的吸尘器主体、长软管和吸嘴全部保留，且无地面或投影残留；但 BiRefNet 同时保留了与测试底色高度相似的粉洋红喷射尾迹。由于无法安全区分这是有效灼热沙子效果还是色键污染，该张按预先定义的 `no_magenta_contamination` 规则保守判为不可用。问题归属为 **原图前景效果与背景融合**，不是主体结构被 BiRefNet 或 96×96 后处理切掉。

## 与旧色键结果的公平对照

| 指标 | 旧 process_sprite 色键 | 官方 BiRefNet + 新像素后处理 |
|---|---:|---:|
| 技术 Sprite 交付 | 6/8 | 8/8 |
| 96×96 可识别 | 6/8 | 8/8 |
| 明显背景残留 | 6/8 | 0/8 |
| 明显投影残留 | 4/8 | 0/8 |

BiRefNet 方法胜出。它直接使用官方 Mask，不再次运行洋红 Flood Fill 或 GrabCut，也不采用“只保留最大组件”。两张 B01 的软管与吸嘴、两张 B03 的主体、两张 B04 的细杯脚与底座均保留。

## 官方来源与运行边界

- 模型：`birefnet.safetensors`，444,473,596 bytes，SHA-256 `9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154`。
- 官方工作流原件及逐字节副本 SHA-256：`ab7bf67d91a17750222da4131790ca38f651d8078ff28213e15cf0ebd86b3354`。
- Forge API binding 工作流 SHA-256：`56d74936b840de2ce2d5e823b6ad1704b9e65dd7ddd8b7a0edbfb5d4d4cf19df`。
- API 图仅含原生背景移除、Mask/Alpha 拼接和保存节点；没有 FLUX 采样器。
- 8 张按 batch size 1 串行处理，0 次自动重试；未调用 Anthropic。
- ComfyUI 仅监听 `127.0.0.1:8190`；完成后 8190 与 8188 均确认关闭。
- 模型卡声明 MIT；本地仓库未附独立模型 LICENSE 文件，生产法律来源仍需单独复核。ComfyUI 本体许可记录与模型许可分开保存。

## 验证与冻结

- 自动测试：31 项，0 failures，0 errors。
- Spike 5 冻结清单：54 个文件记录全部复核一致。
- Verified review packet：64 个输入证据文件及 5 个对照产物全部重新哈希。
- 8 个 Spike 6 完整结果目录保留在 `tools/comfyui/flux2/birefnet/output/`；本报告不复制或覆盖 Spike 5 原证据。

## 下一步

本 Spike 在建议门槛下通过，可申请一个独立的 Live End-to-End 验证；当前不接入实时 Godot、战斗房间、锚点、训练区或默认玩家流程，也不启动草图编辑质量 Gate。
