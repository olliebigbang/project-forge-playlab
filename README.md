# Forge Playlab V1

Forge Playlab is a standalone gameplay experiment. The active entry is **Sunny Expedition / 晴日远行**: describe an object (or choose a saved weapon), let the existing pipeline compile it, then choose either the three-leg first story chapter or an eight-enemy weapon trial. Story builds and loot persist across its route decisions; the short trial remains available so a newly generated object does not require an endurance clear.

This repository is not the Project Forge product line. It does not copy into or modify `project-forge` or `project-forge-claude`.

## Start here / 项目主文档

- [AGENTS.md — 工作规则](AGENTS.md)：接手先读，规定机制设计底线、验证和协作方式。
- [GAME_DESIGN.md — 游戏设计](GAME_DESIGN.md)：玩家做什么、AI 做什么、机制轴如何决定打法。
- [PROJECT_STATUS.md — 当前状态](PROJECT_STATUS.md)：活动分支、验证证据、缺口和启动命令。
- [NEXT_PHASE_HANDOFF.md — 下一阶段交接](docs/NEXT_PHASE_HANDOFF.md)：本轮审核、下一任务边界和验收标准。
- [ASSET_UPLOAD_SCOPE.md — 素材与上传范围](docs/ASSET_UPLOAD_SCOPE.md)：素材来源、授权依据、私人文件排除和发布门禁。

These are the current project entry points. Versioned reports retain their dated scope; early Mock-only, three-family and two-room documents do not define the current whole system. Check the current branch and HEAD against the handoff receipt; private saves and local test evidence are intentionally not included in Git.

## Play Sunny Expedition / 当前完整试玩

Double-click **`Play-Sunny.cmd`**. To play without loading `.env` or paid APIs,
run `./scripts/run_sunny_expedition.ps1 -Offline`. The main scene is
`scenes/sunny_expedition.tscn`; the normal launcher only calls AI after Generate.
The entire forge → shelf → story/trial route → result now uses Sunny art.
Existing AI weapons are labelled as existing, not fresh generations.

WASD/arrows move; J/Space attack or hold; K/Shift dodge; Q supplies; Esc pause.
Stop to shoot low targets: the original crouch pose lowers the actual muzzle,
automatically or with C. Sunny story/trial saves remain separate from the legacy Church game.
Player art deliberately retains the licensed original white prototype body.
Completed runs now earn capped workshop insight, shown in the hub header: future runs can reroll one or two
roadpost offers and unlock an advanced tradeoff pool, without permanent damage or
recoil bonuses. See [meta progression contract](docs/SUNNY_META_PROGRESSION_V1.md).
See [implementation, review and measured limits](docs/SUNNY_EXPEDITION_V1.md).

## Authored player in actual combat / 原包动作已替换到实际战斗

The Church Expedition and `Preview-Sunny-Player.cmd` now share the original
full-body animation adapter, holding the **actual AI weapon**, not the source
placeholder sword/gun. This iteration deliberately keeps the original white
prototype body; backgrounds and final character styling are not replaced.
Sword-family moves, moving attacks, roll, firearm poses/reload and conditional
cast/reel use the existing mechanism state. A stationary low-target gunner can
crouch (C; automatic crouch enabled), with bullets leaving the real lowered muzzle.
The 107-group source catalogue is not 107 new gameplay skills.
[Implementation, checks and limitations](docs/AUTHORED_PLAYER_INTEGRATION_V1.md).

## Original action training / 原包全动作训练场

Double-click `Preview-Original-Actions.cmd`: original full-body sword, gun,
bow, fishing and unarmed animation controls, including moving attacks and
real horizontal crouch shots against a low practice target. Keys 1–5 equip,
J attacks/holds charge, release casts, C crouches, G toggles automatic low-target
crouch; the bottom menu exposes all retained clips and supporting art.
107 loaded groups are NOT 107 finished game skills: 64 character clips are
context-driven, 6 support assets event-driven, the rest are explicitly inspect-only.
This offline original-art sample does not replace AI weapons or the campaign.
[Scope, full inventory and verification](docs/ORIGINAL_ACTION_PREVIEW_V1.md).

## Original sword animation sample / 原包剑招还原

Double-click `Preview-Original-Sword.cmd` for an isolated offline animation sample.
It uses the original full Dead Revolver character/sword frames and authored frame
durations: J/Space slash, K four-part combo, L quick slash; A/D move, Shift run.
Q auto-demo, T quarter-speed, P pause, then arrow keys to inspect frames.
This is the original white prototype character, not the new character skin or a
mechanism-driven combat implementation. [Scope and evidence](docs/ORIGINAL_SWORD_PREVIEW_V1.md).

## Play Church Expedition / 保留的旧教堂版

Double-click **`Play-Church.cmd`**, or run `./scripts/run_church_ai_forge.ps1`.
Use `-Offline` to play without reading `.env` or enabling paid AI. Five clearly
labelled existing AI weapons are supplied; these are not fresh generations.
This legacy scene is `scenes/church_expedition.tscn`, no longer the default.

Choose a weapon or describe a new object (up to 160 characters). Starting saves
the complete selected weapon and chapter checkpoint. Defend two candle seals
per chapter, defeat the guardian, rest/change weapons at camp, then finish all
three chapters. Death retries the current chapter; completed chapters survive.
WASD/arrows move, J/Space attack, K/Shift dodge, Q uses a 35-health supply,
Esc pauses. Long-press abilities still come from the weapon's compiled structure.

The normal launcher can read the developer's `.env`, but calls paid AI only
after **Generate** is pressed. Generation failures never substitute a sample.
`-Smoke` retains the old empty-forge offline diagnostic; `-LiveReview` remains an
explicit paid developer test, not an ordinary launch or offline test.
See [Expedition scope, verification and limitations](docs/CHURCH_EXPEDITION_V1.md).

### Previous independent art sample

The previous independent GothicVania Church sample remains available with its
original two-enemy scope; it is not the current expedition and does not write
the weapon library.

From this repository: `./scripts/run_art_vertical_slice_v1.ps1`.
Use WASD to move, Space/J to attack (hold for supported object abilities),
Shift/K to dodge, 1–5/N to change weapon and restart, R to retry, Esc to exit.
`-Probe` checks cached entries; `-Replay` records explicitly labelled bot inputs
and real Godot frames. `-Smoke` captures the normal scene without bot inputs.
None of these modes calls online AI or loads `.env`.

See [Church sample scope and evidence](docs/CHURCH_ART_VERTICAL_SLICE_V1.md).

## Current active scope

The active flow is:

```text
player text (rough sketch remains in the legacy workshop)
→ strict AI identity router
→ firearm parser or general-object affordance parser
→ local Godot mechanism validation and compilation
→ FAL visual request + church_v1 local pixel-style validation
→ validated transparent 96px sprite
→ complete weapon library (image + anchors + rig + mechanism card)
→ one continuous side-scrolling route with three in-run build choices
→ capped workshop insight, rerolls and advanced module-pool unlocks
→ results and recent run history
→ reuse or change weapons
```

The active compilers cover handheld firearms and general physical objects, including rigid, flexible, tethered, deployable and functional-output structures. Names identify objects; mechanism declarations decide actions. Powered vehicles and living actors are explicitly outside the current handheld-object runtime. Earlier Spike 2 and room experiments remain historical evidence, not the current gameplay boundary.

See [Complete Weapon System V1](docs/COMPLETE_WEAPON_SYSTEM_V1.md) for the current flow, persistence contract and verification limits. This is a local prototype, not a released online service.

General melee now executes its compiled three-stage recipe and held structural ability in the main arena, sharing rendered pixel contact geometry with hit tests. See [Main Arena Mechanism Execution V1](docs/MAIN_ARENA_MECHANISM_EXECUTION_V1.md) for per-axis execution evidence, independent screenshot review and the still-pending desktop manual playtest.

The active desktop AI launcher supports strict Anthropic identity cards for firearm and general-object nouns. AI decides the complete mechanism declaration; Godot validates and compiles it locally, and never asks the player how the object should attack. Local ComfyUI, rough sketches, training and capability-gap rewards remain in the legacy workshop; they are not silently advertised as expedition features.

## Historical Spike 2 visual result

The architecture and safety boundary are implemented, but the real visual semantic gate failed.

- Blueprint identity passthrough: 5/5.
- Behavior classification: 5/5.
- Real ComfyUI/Alpha delivery: 5/5.
- Visual identity preservation from raw Chinese text: **2/5**.
- AI semantic interpretation: **not used**.

RealVisXL preserved the teapot and umbrella, but changed the table into a person and the chair/chicken leg into ornate staffs. Do not describe this as arbitrary identity understanding or promote it beyond the isolated desktop Spike.

Those images are immutable prompt-policy-v1 evidence. The active policy-v2 prompt additionally carries the generic action contract, but was not visually rerun because ComfyUI was deliberately left stopped; it has no claimed image score.

See [the full Spike 2 report](tools/comfyui/open_identity/reports/SPIKE2_REPORT.md) and [visual comparison](tools/comfyui/open_identity/reports/identity_raw_processed_comparison.png).

## Requirements

- Godot 4.7.1 exactly.
- Windows PowerShell for the primary scripts.
- Configured Anthropic/FAL credentials for cloud generation, or the existing local ComfyUI setup for its visual path. Playing already saved weapons does not require a new online generation request.

The local ComfyUI path downloads nothing and listens only on `127.0.0.1`. The explicit AI launcher can call paid Anthropic and FAL APIs; credentials stay in the launcher process and are not written to manifests or caches.

For the **legacy** workshop with sketch support and FAL object pixels, run:

```powershell
.\scripts\run_open_identity_ai.ps1 -EnvFile "C:\path\to\.env"
```

See [General Object AI Parser V1](docs/GENERAL_OBJECT_AI_PARSER_V1.md).

## Legacy automatic armory level

The automatic level detects missing control, defense, area, reach, breach or mobility capabilities. AI proposes a physical object; the existing object/firearm parser must independently compile the requested capability before an image is requested. A fully validated and saved weapon becomes an optional completion reward. The player never has to describe an enemy or choose how an object attacks.

With the developer keys saved in the user-profile `.env`, run:

```powershell
.\scripts\run_open_identity_firearm_ai.ps1 -StartMode AutomaticLevel
```

See [Complete Weapon System V1](docs/COMPLETE_WEAPON_SYSTEM_V1.md). The [earlier firearm-only armory](docs/AUTOMATIC_ARMORY_V1.md) is historical.

## Local visual workflow and fixed regression sample

Start local-loopback ComfyUI, then launch the active scene:

```powershell
.\tools\comfyui\scripts\start_comfyui.ps1 `
  -ConfigPath .\tools\comfyui\open_identity\config\forge_open_identity_config.local.json
.\scripts\run_game.ps1 -- --visual-provider=LOCAL_COMFYUI
```

Stop ComfyUI afterward:

```powershell
.\tools\comfyui\scripts\stop_comfyui.ps1
```

If the ignored local Spike 2 config does not exist, copy [the example config](tools/comfyui/open_identity/config/forge_open_identity_config.example.json) to `forge_open_identity_config.local.json` and set the two local runtime paths. Paths and the loopback endpoint remain configuration, not business-code constants.

Mock can be selected only as an explicit fixed regression sample:

```powershell
.\scripts\run_game.ps1 -- --visual-provider=MOCK
```

Mock submission of arbitrary player identity fails with `MOCK_CANNOT_RENDER_ARBITRARY_PLAYER_IDENTITY`. It never silently equips a fixed weapon.

Desktop controls:

- WASD or arrow keys: move.
- Space or J: attack.
- General objects: tap for the compiled three-stage sequence; hold for the available structural ability, with release/toggle behavior determined by its declaration.
- Shift or K: dodge.
- F3: show the existing anchor debug markers.

## Test

Run from this repository directory:

```powershell
.\scripts\test_complete_weapon_system.ps1
```

This is the current isolated offline regression entry: weapon persistence, generation-service contracts, main-arena mechanism execution, training compatibility, soft-structure readability, firearm runtime, enemies, interactions and the three-battle loop. It does not load `.env`, clears online credentials for its child runs, and writes evidence under `.tools/system-tests/<run-id>`.

The latest recorded run passed 112 tests; see [PROJECT_STATUS.md](PROJECT_STATUS.md) for exact evidence and limitations. Those offline tests do not prove live AI success, complete axis independence, balanced gameplay or completion of the pending desktop manual playtest. The documentation cleanup did not rerun them.

Older `scripts/test.ps1` and isolated Spike test scripts are historical/focused checks, not the current whole-system acceptance command. Inspect their storage and environment effects before running them against a player's existing data.

## Previous isolated Spikes

- `tools/comfyui/` contains Forge Object Sprite Generation Spike 0 and its 15-run report.
- `tools/comfyui/anchor_calibration/` contains Forge Semantic Anchor Calibration Spike 1 over the 11 existing successful sprites. Spike 2 does not continue or modify anchor calibration.
- The former `scenes/main.tscn` fixed-weapon flow remains only as legacy regression/capture code. `project.godot` now starts `scenes/open_identity_spike.tscn`.

## Out of scope

The current prototype is not an online release. Accounts, cloud saves, production queues/billing, stores/payments and deployment are not completed. Powered vehicles and independent living actors are outside the handheld-object runtime. Do not execute AI-generated gameplay code or silently replace a rejected identity with a fixed weapon or unapproved paid provider.

The unified weapon library, three encounters and additional object structures are already part of the active scope; old exclusions of all inventories or all new behavior families no longer describe it. The remaining design gaps, including modification of an existing weapon in the current main flow, are tracked in [PROJECT_STATUS.md](PROJECT_STATUS.md).
