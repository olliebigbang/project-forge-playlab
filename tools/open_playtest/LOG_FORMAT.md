# Open Playtest 本地日志格式

`playtest_history.json` 是权威本地索引，合同为 `forge-open-playtest-local-history-v1`。`playtest_history.csv` 是相同记录的便于筛选版本；`stage_timings` 在 CSV 中编码为 `stage_timings_json`。写入均先落临时文件，再原子替换；UI 只显示最近 10 条，磁盘最多保留 200 条索引记录。

| 字段 | 类型 | 含义 |
|---|---|---|
| `timestamp` | UTC string | 本轮开始时间 |
| `session_id` | string | 显式试玩会话 ID |
| `round_id` | string | 每轮唯一 ID |
| `revision` | integer | 单调递增版本，用于拒绝旧请求 |
| `user_input` | string | 玩家提交的中文原文 |
| `semantic_summary` | string | display name、行为家族、效果类型的本地组合摘要 |
| `behavior_family` | enum | `sustained_ranged` / `returning_thrown` / `heavy_melee` |
| `canonical_identity` | string | Claude v1.1 的基础中文物件身份 |
| `display_name` | string | 可带幻想修饰的中文显示名 |
| `raw_image_path` | string | 会话目录内冻结 FLUX 原图路径；失败前为空 |
| `processed_sprite_path` | string | 96×96 RGBA Sprite 路径；失败前为空 |
| `identity_confirmed` | boolean/null | 玩家身份确认；尚未评价为 `null` |
| `anchor_confirmed` | boolean | 两个行为所需锚点是否已确认 |
| `entered_training` | boolean | 是否实际进入并结束训练区 |
| `user_notes` | string | 可选本地备注 |
| `subjective_rating` | integer/null | 玩家 1–5 主观评分 |
| `keep_idea` | boolean/null | 是否想保留此点子 |
| `saved_locally` | boolean | 是否点击 `SAVE THIS RESULT` |
| `total_forge_seconds` | number/null | 语义到 96×96 完成总耗时 |
| `stage_timings` | object | 各生成阶段秒数 |
| `status` | string | 当前/最终状态 |
| `failure_stage` | string | 失败阶段；成功为空 |
| `failure_reason` | string | 本地错误代码；成功为空 |
| `semantic_mode` | enum | `v1_1` 或显式的 `affordance_v1_2_1` 会话模式 |
| `semantic_contract` | string | 本轮锁定的语义合同版本 |

每轮目录还保存 `semantic_blueprint.json`、脱敏语义响应、`flux_raw.png`、FLUX manifest、BiRefNet RGBA/Mask、`processed_sprite.png`、后处理指标、身份审阅、`anchors.json`、训练审阅和 `open_playtest_round.json`。显式 Affordance Grammar 会话还保存经过严格校验的 `object_affordance_profile.json`。运行失败只交付已完成的脱敏文件和 `failure_manifest.json`，不会伪造透明 Sprite。

Key、请求头和未脱敏 API 响应不属于日志合同，禁止写入上述文件。
