# Forge Playlab V1

Forge Playlab is a disposable, standalone gameplay experiment. It validates whether a player can express a weapon fantasy with one Chinese sentence, a rough sketch, or both, then receive a coherent pixel weapon that can be held, tested, fought with, and modified once between two combat rooms.

This repository is not the Project Forge product line. Do not merge it directly into `olliebigbang/project-forge` or `olliebigbang/project-forge-claude`. Those repositories were not copied or modified to create this experiment.

## What runs offline

V1 defaults to `MockWeaponInterpreter`, `MockWeaponImageGenerator`, and a deterministic procedural 96×96 pixel-weapon renderer. It requires no network, API key, paid call, account, or cloud service. Player-facing Chinese copy never exposes internal behavior enums.

The three supported behavior families are represented by:

- 幽蓝炉心加特林: hold to spin up and fire, burn, overheat, heavy movement;
- 雷鸣回旋伞: throw, outbound and return hits, electric chain, no rethrow before return;
- 血齿链锯大剑: slow heavy melee, lifesteal, reduced mobility during startup.

## Requirements

- Godot 4.7.1 exactly;
- Windows PowerShell is the primary script environment;
- Python 3 only for the local Web server.

The scripts look for Godot in this order: repository `.tools`, `godot4`/`godot` on PATH, then known local Godot 4.7.1 candidates. They do not change system configuration.

The Chinese UI bundles `NotoSansCJKsc-Regular.otf` from the official Noto CJK distribution. It is covered by the included SIL Open Font License in `assets/fonts/OFL.txt`.

## Run

```powershell
./scripts/run_game.ps1
```

Desktop controls:

- WASD or arrow keys: move;
- Space or J: attack;
- Shift or K: dodge;
- F3: show combat anchor markers.

Touch provides a left virtual stick, one attack button, and one dodge button.

## Test

```powershell
./scripts/test.ps1
```

Equivalent Godot command:

```powershell
godot --headless --path . --script tests/run_tests.gd
```

The focused suite covers schema repair, fixed blueprints, alpha-mask anchors, no-alpha failure, muzzle/tip placement, tradeoff-preserving deltas, the weapon/enemy damage matrix, forge locks, one intermission change, JSONL logging, and Web startup resources.

## Build and serve Web

```powershell
./scripts/build_web.ps1
./scripts/serve_web.ps1
```

Then open `http://localhost:8060`. Web export requires the Godot 4.7.1 Web templates; the build script fails explicitly if they are absent.

Bash equivalents are provided in `scripts/*.sh`.

## Mock and future approved models

Mock mode is the only implemented V1 mode and is enabled by construction in `scripts/main.gd`. The replaceable boundaries are `WeaponInterpreter` and `WeaponImageGenerator`. A future approved model implementation must be injected behind those interfaces and return the same structured data. It must not emit executable game code or determine damage, cooldowns, collision, enemy rules, victory, or final anchors.

No provider, model, endpoint, budget, or secret location is guessed here. Do not add a real adapter without explicit approval, a separate security review, and a failure-preserving local fallback. Never copy keys from another repository.

## Local data

Events are appended to `user://playlab/events.jsonl`. The logger stores event categories, timings, aggregate geometry, combat metrics, and response lengths. It removes raw descriptions, raw strokes, sketch PNG bytes, and free-form survey text from log payloads. Generated procedural assets and optional manual anchor overrides remain local under `user://playlab/`.

## Not V1

Accounts, cloud saves, stores, payments, narrative, bosses, inventories, multi-weapon switching, progression trees, infinite chat, long-term memory, production deployment, a fourth behavior family, AI-generated code, and a universal rig/anchor solver are deliberately excluded.

See [V1 scope](docs/V1_SCOPE.md), [architecture](docs/ARCHITECTURE.md), [playtest script](docs/PLAYTEST_SCRIPT.md), [results template](docs/PLAYTEST_RESULTS_TEMPLATE.md), and [known limitations](docs/KNOWN_LIMITATIONS.md).
