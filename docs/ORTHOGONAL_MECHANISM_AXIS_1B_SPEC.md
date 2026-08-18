# Contact Resolution Axis — 1B 规格

状态：DESIGN ONLY。**§4.2 的派生规则经 P13 复核后成立，但输入不完整**——
rigidity 只解决碰撞组里 7 对中的 4 对，其余 3 对靠 θ 的质量分叉或尚无解。
§3 的通道移交不受影响。

承接：`DECISIONS.md` 的 P11 与 P12。两者都以"下一步该建一个材质/接触解算轴，
并把通道从 tempo 手里拿过来"收尾；本文件是那句话的落地规格。

> 本文件的上一版是对着 `codex/feat/orthogonal-affordance-grammar` 写的，
> 依赖该分支独有的 `RIGIDITY_RUNTIME`，并建议加 `rotational_inertia_proxy`。
> 两条都不适用于本线：前者在本分支不存在，后者已被 P11 实测否决。整篇已重写。

---

## 1. 诊断

不是"机制轴不足"。P12 已经把数量问题排除了：契约里的轴不缺，缺的是**下游的类别性结果**。

**选择层**（P12 实测，`measure_selection_sensitivity.gd`）：42 组 (baseline, axis) 中只有
9 组能改变挥击组合。`contact_surface` 是唯一从每个基线都能改变它的轴，且每次都能触达
全部四种组合。`has_point` / `has_edge` / `has_broad_face` / `has_barrel` 从任何基线都
**动不了**选择，尽管评分表给了它们 0.75–0.90。`real_mass_kg` 与 `real_length_cm` 同样
动不了——它们只到参数层。

**参数层**（本文件复核，`melee_motion_compiler.gd:361-364`）：质量进入冲击通道的全部途径是

```
knockback_multiplier   = (0.88 + 0.18 * mass_axis) * finisher
stagger_multiplier     = (0.90 + 0.20 * mass_axis) * finisher
hitstop_multiplier     = (0.82 + 0.22 * mass_axis) * finisher
camera_kick_multiplier = (0.84 + 0.20 * mass_axis) * finisher
```

`mass_axis` 值域 `[0.35, 1.0]`（P09 刻意未加宽），因此四项的实际跨度分别是
**12.4% / 13.4% / 16.0% / 14.3%，且四项同向**。这就是 P12 所说的"12–16% band，
全都朝同一个方向推"。

**冲击层**（`impact_feedback_profile.gd:18-31`）：真正的类别级差异全部由 `tempo` 一个
三值枚举给出——

```
rapid:      hitstop 0.035  knockback  82  camera 1.8  sound forge_impact_light
balanced:   hitstop 0.048  knockback 116  camera 3.5  sound forge_impact_medium
committed:  hitstop 0.064  knockback 152  camera 4.8  sound forge_impact_heavy
```

跨度 1.83×、1.85×，是参数层的十倍量级。

**结论**：可感知空间 ≈ 选择 4 种 × tempo 3 种，其余一切是 12–16% 的同向微调。
平底锅与金色鸡腿之所以难分，不是因为没有轴描述它们的差别，而是因为它们的差别
（材质、怎么落上去）在下游**没有任何类别性出口**——它只能被折算成一个 16% 的乘数。

---

## 2. 必须遵守的既有决策

| 决策 | 约束 | 本规格如何满足 |
|---|---|---|
| **P08** | 真实量可以决定你是**哪种**武器，永远不能决定你**值不值得用** | §4.3 三种解算各有明确上风，不是单调排名 |
| **P09** | 质量买 tempo，永不买伤害；`MASS_AXIS_MIN/MAX` 刻意不加宽 | 本规格不碰伤害、不碰 mass band |
| **P11** | 质量与长度保持两个轴，**不得相乘** | §4.2 派生只用 `rigidity` 与 `mass_axis`，两者独立进入，无乘积 |
| **P12** | 不得重新平衡 `contact_surface` 权重；新通道要**从 tempo 手里拿**，不是并排加 | §3 是移交表，不是新增表 |
| **T60** | 生成 sprite 上的几何度量不一定有区分度（细长比在四个真实 sprite 上只跨 4.43–9.96） | §5 把 `contact_flatness` 降级为**测量门**，不是实现项 |
| **T73/T74** | 几何能测的自己测，只问模型几何看不见的 | `rigidity` 是材质属性，几何看不见，继续由模型给；不新增 AI 字段 |

---

## 3. 核心改动：四个冲击通道从 tempo 移交给 contact_resolution

这是 1B 的**全部实质内容**。不是加字段，是改所有权。

| 通道 | 现在的拥有者 | 之后的拥有者 |
|---|---|---|
| `hitstop_seconds` | tempo | **contact_resolution** |
| `knockback_strength` | tempo | **contact_resolution** |
| `camera_shake_strength` | tempo | **contact_resolution** |
| `sound_profile` | tempo | **contact_resolution** |
| `recoil_degrees` | 仅连段阶段 | **contact_resolution** |
| 时序（startup/active/recovery） | tempo | tempo（不动） |
| 伤害 22/27/34 | tempo | tempo（不动） |
| 移动保留 | tempo | tempo（不动） |

移交后 tempo 仍然完整承担 P09 赋予它的职责——质量买 tempo、tempo 买时序与伤害——
但它不再同时是材质的代言人。两个不同的问题从此有两个不同的出口。

⚠️ 连段阶段的叠乘（`combo_index >= 3`、`charge`、`combo_index == 2`）与 primitive
乘数**保持不变**，仍然乘在 contact_resolution 给出的基值上。本次不重构那部分。

---

## 4. `contact_resolution`

### 4.1 定义

| 项 | 值 |
|---|---|
| 字段名 | `contact_resolution` |
| 类型 / 值域 | `enum { "rebound", "arrest", "follow_through" }` |
| 来源 | **编译期派生**，不进契约，不问模型 |
| 输入 | `rigidity`（既有 AI 字段）+ `mass_axis`（既有，来自 `real_mass_kg`） |
| 载体 | `CombatMotionProfile` 上一个新导出字段，随 `to_dict()` 序列化 |

不新增契约字段，因此 v1.4 不变、估计器不变、冻结哈希链不受影响（P10）。

### 4.2 派生规则

> **P13 复核结论：成立，但不足。**第一版 P13 用 rigidity 的边缘分布（78% 恒定）
> 判它不可用——那是错的判据。冲击轴永远不需要分开本来就挥法不同的物件（P12 已证
> `contact_surface` 在选择层做了这件事），它只需要分开**共享同一连击序列**的物件。
>
> 按条件分布实测（12 个 handoff 案例 → 7 种序列，3 组碰撞，7 对配对）：
> **rigidity 分开 2/3 组、4/7 对**。分开的两组正是本轴的动机——鸡腿从棒球棒+折叠凳
> 分出，钓鱼竿从木椅+灭火器分出。
>
> 未解决的 3 对全是同值配对：长剑/消防斧、棒球棒/折叠凳、木椅/灭火器。它们要靠
> θ 的质量分叉，或者尚无解。所以 `follow_through` 类别小**不是缺陷**，但 rigidity
> 单独也不够。
>
> ⚠️ 实现前必须先修 `artifacts/mass_axis_poc/` 的 chicken_leg——它的 `rigidity: rigid`
> 是手写的（`author_v1_4_sidecars.py` 注释自承），模型给的是 `semi_rigid`。
> 按手写值，鸡腿会留在 rigid 分支跟棒球棒和折叠凳一起，正好是 1B 要破的那个碰撞。



```
θ = 待测定，不得拍脑袋（见 §6）

rigid       + mass_axis <  θ   ->  rebound
rigid       + mass_axis >= θ   ->  arrest
semi_rigid                     ->  follow_through
flexible                       ->  follow_through
```

物理直觉：软物件不会急停也不会弹回——它形变、吸收、带走能量。刚性物件按质量分叉：
轻则被弹开，重则把动能全部交出去。

**这里没有乘积。**`rigidity` 与 `mass_axis` 各自独立进入一张查表，符合 P11 的核心论点
（两个近独立的轴，其独立性本身就是资产，不要乘掉）。

**诚实标注的局限**：soft 半区完全由 `rigidity` 决定，只有 rigid 半区因质量而分叉。
所以本轴在 1B 中**不是** `rigidity` 的正交补，而是"`rigidity` 第一次获得一个类别性
出口"。这正是 P12 想要的东西——`rigidity` 目前只喂评分表，在冲击层没有任何存在感
（本分支 `impact_feedback_profile.gd` 只 `match profile.tempo`，不读 `rigidity`）。

### 4.3 运行时行为：每种解算都要有上风（P08 的硬约束）

上一版规格在这里犯了错：它给出的是一张单调表（rigid 在所有通道都最强，flexible 都最弱），
那正是 P08 禁止的"更差而不是不同"。改成互有取舍：

| | `arrest` | `rebound` | `follow_through` |
|---|---|---|---|
| 典型物件 | 铸铁锅、大锤 | 扳手、木勺 | 鸡腿、拖把 |
| `hitstop_seconds` | **最长** | **最短促**（硬切） | 中长（缓出） |
| `knockback_strength` | **最大** | 小 | 小 |
| `camera_shake_strength` | 最大幅度 | 高频短促 | 低频长 |
| `recoil_degrees` | 0（武器不回弹） | **大**（武器被弹回） | 负（继续走完弧线） |
| `sound_profile` | 闷、死 | 脆、响 | 软、噗 |
| **上风（必须有）** | 单发控场最强 | **恢复最快、连段窗口最宽** | **穿透继续，命中后不损失位移与后续判定** |

三者在时长上互相矛盾、在方向上互相矛盾——这是 §1 诊断要求的解耦，也是让它区别于
"同一把武器强一点/弱一点"的关键。

具体数值不在本文件锁定：它们必须落在 P08 第二层（设计给定的可用带）之内，
由 §6 的测量与真人验证共同定，而不是在设计阶段拍出来。

### 4.4 消费点

| 行为 | 位置 | 改动性质 |
|---|---|---|
| 四通道基值 | `impact_feedback_profile.gd:18-31`，现为 `match profile.tempo` | 改为 `match profile.contact_resolution`；tempo 分支移除 |
| 回弹角 | `impact_feedback_profile.gd:12` `recoil_degrees`（字段已存在，默认 7.0） | 由解算给基值；连段叠乘不变 |
| 音效变体 | `sound_profile` 字符串 | 需要 3 个新变体资产；见 §7 风险 |
| 挥击进度 | `combat_feel_slice_0.gd` 的角度插值 | `follow_through` 需要命中后继续推进；`rebound` 需要反向。这是唯一的新运行时逻辑 |

---

## 5. `contact_flatness` —— 降级为测量门

上一版把它列为实现项，并给了"平底锅趋近 1.0、鸡腿 0.25–0.40"的**人工推演**。
T60 的记录正是针对这类推演：在生成 sprite 上，细长比只跨 4.43–9.96，四个物件里三个
落进同一档，`old_mop` 与 `shotgun_melee` 只差 1.02×。**几何度量在描边上有效不代表在
生成图上有效。**

因此 1B 不实现它，而是先测：

1. 按 §4.2 的判据（沿打击方向的共面像素占比）对 17 个已探测物件算出 `contact_flatness`
2. 复用 P11 的方法与阈值：数出距离小于 **0.065**（P09 实测的噪声底）的配对数
3. 与既有方案对比：`contact_surface` 四值单独 vs 加上 flatness

**通过条件**：flatness 让无法区分的配对数**低于** `contact_surface` 单独时的数量，
且平底锅与鸡腿的距离超过噪声底。

**未通过则不建**，并把结果作为一条新决策记入 `DECISIONS.md`——按 P11 的先例，
一次被测量否决的提案和一次被采纳的提案同等有价值。

---

## 6. 验证

### 6.1 测量（实现前）

| # | 测量 | 工具 | 用途 |
|---|---|---|---|
| M1 | `contact_resolution` 在 17 个物件上的分布 | 新增，仿 `compare_axis_separability.py` | 定 θ：选使三类都被用到、且不出现某类只有一个成员的阈值 |
| M2 | `contact_flatness` 可分性 | 同上 | §5 的门 |
| M3 | 移交后 tempo 是否仍保持 P09 的三值伤害性质 | `verify_mass_ab.gd`（已存在，可重跑） | 确认没有把伤害牵连进来 |

θ 由 M1 决定，不在本文件给值。上一版给了 `θ = 0.58` 并自称"待审计锁定"——那是先写
数字再补测量，顺序反了。

### 6.2 自动测试

| # | 断言 |
|---|---|
| A1 | 固定其余字段只改 `rigidity`：**只有** §3 表中移交的五个通道变化，时序与伤害逐位相等 |
| A2 | 固定其余字段只改 `real_mass_kg` 跨越 θ：只有 rigid 物件的 `contact_resolution` 翻转 |
| A3 | 相同 affordance → 相同 recipe（保持既有性质） |
| A4 | 三种解算在同一 tempo 下产生**互相矛盾**的通道排序（不是单调排名）——把 P08 变成可执行断言 |
| A5 | 伤害仍只取 22/27/34 三值（P09 的算术开关） |

A4 是本规格最重要的测试：它防止实现过程中把三种解算悄悄退化成一条强度轴。

### 6.3 真人验证

2AFC 同异判断，20 轮，通过线 **≥ 15/20**（对 50% 基线二项检验 p ≈ 0.021）。
必测配对：平底锅 vs 金色鸡腿（主判据）；平底锅 vs 平底锅（假阳性对照）；
以及 P11 列出的三对同尺寸同重量残余碰撞——菜刀 vs 锤、巨勺 vs 剑、盾 vs 椅。
最后三对是本轴存在的理由，它们过不了则本轴没有解决它被提出来要解决的问题。

---

## 7. 风险

| 风险 | 缓解 |
|---|---|
| `contact_resolution` 在 1B 未与 `rigidity` 正交（§4.2） | 明确标注；它的价值是给 `rigidity` 一个类别出口，不是新增一个独立维度 |
| 从 tempo 移交通道会改变所有现有物件的手感 | 移交前后各跑一次 2AFC 对照；P09 的 band 不动，改的是谁来选 |
| 音效资产是外部依赖（3 个新变体） | 先用占位音效验证机制；真人验证排在资产就位之后 |
| `follow_through` 的"穿透继续"是唯一的新运行时逻辑，可能影响命中判定 | 单独测：同一敌人不得被同一次挥击重复计入（`register_hit` 已有 `hit_targets` 去重） |
| θ 落在使某一类只有 1 个成员的位置 | M1 的选取条件已写明；若 17 个物件无法支撑三类，就先降为两类 |

---

## 8. 结论

**GO**，范围如上：不新增契约字段、不新增 AI 字段、不碰 mass band、不碰伤害、
不重新平衡选择层权重。1B 的全部实质是**把四个冲击通道从 tempo 移交给一个由材质与
质量派生的三值类别轴**，并让三种解算互有取舍而非互为强弱。

`contact_flatness` 先测后建。`rotational_inertia_proxy` 不建（P11）。
