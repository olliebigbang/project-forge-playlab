# Known Limitations

> 历史限制清单：下文关于“全是离线 Mock”“只有三类动作”等结论属于早期实验，不是当前状态。当前限制及尚未完成的验收统一见 [PROJECT_STATUS.md](../PROJECT_STATUS.md)；本页保留原始记录。

当前新增边界：通用物品AI已要求把握持部、启动部和作用起点绑定到同一身份卡的可见部件，
并在画图与Alpha锚点阶段沿用；这能拒绝内部矛盾，不能证明AI对现实物品功能的判断为真。
有限额全新喷口样本已正确返回侧把/泵杆/喷口与持续定向输出，并完成三章；但远程像素转换
返回HTTP 403，最终像素图来自同一张新透明身份图的本地降级。旧喷水壶磁盘卡仍保留漏喷流的
旧声明。一个成功样本不能代表任意物品，更多结构仍需要独立限额验收。

- `CONFIRMED`: All interpretation and imagery are offline Mock implementations. No real semantic or image model is configured.
- `CONFIRMED`: Free descriptions map through a small multilingual keyword heuristic into exactly three supported families. Nuanced fantasy composition is not understood.
- `CONFIRMED`: Procedural sprites vary with family, palette, aspect ratio, and a small subset of sketch geometry; they do not trace the player drawing literally.
- `CONFIRMED`: Anchor resolution is profile-guided and local. Highly unusual silhouettes may need the included manual JSON override.
- `CONFIRMED`: The two-hand pose is a readable approximation, not full IK.
- `CONFIRMED`: Enemy behavior and room layouts are intentionally small and deterministic enough for a gameplay hypothesis, not production combat content.
- `CONFIRMED`: Touch is a basic Web-capable control layer, not a completed mobile release acceptance pass.
- `CONFIRMED`: Logs remain local and omit raw free text and sketch data, so qualitative analysis requires the moderator's separate notes.
- `ASSUMPTION`: System fallback fonts include Chinese glyphs on the playtest machine.
- `TO VALIDATE`: Players perceive the weapon visual and behavior as the same fantasy rather than two loosely related outputs.
- `TO VALIDATE`: Automatic anchors are believable across genuinely poor sketches.
- `TO VALIDATE`: A single modification is both understandable and materially noticeable in room two.

Manual anchor override is most likely for vertical sketches, extremely thin handles, or silhouettes whose visible mass is intentionally disconnected. The three fixed fixtures are designed to resolve without overrides.

