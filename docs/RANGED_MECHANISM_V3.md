# 枪械机制轴 V3

V3 给击发方式增加了第三种真正可运行的状态：`three_round_burst`。现在枪械不是只有“点一下打一发”和“按住一直打”两种选择。

- `semi_auto`：每次按下只发射一发。
- `three_round_burst`：每次按下自动完成三发短点射；玩家松开按键后，本轮点射仍会按枪械自己的节奏完成。
- `select_fire_auto`：按住时持续射击。

机制编译结果使用 `forge-ranged-runtime-profile-v3`。`fire_control` 独占两个最终参数：

- `automatic_fire`：是否按住连射。
- `burst_size`：固定点射包含几发；当前三连发为 3，其余模式为 0。

M16A2 的本地身份卡声明 `three_round_burst`。运行层只读取编译参数，不检查 `M16A2` 或其他型号名称，因此陌生枪械也能由 AI 声明同一机制。

有限差分审计会逐一切换全部合法击发方式，并把 Clamp 后的 `automatic_fire` 与 `burst_size` 一并纳入覆盖、零效应、重复方向和所有权检查。
