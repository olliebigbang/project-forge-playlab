# Forge Playlab V1

Forge Playlab is a disposable, standalone gameplay experiment. The current active entry is **Forge Open Identity Interpretation Spike 2**. It tests whether a player's arbitrary object identity can remain independent from three limited combat behavior families.

This repository is not the Project Forge product line. It does not copy into or modify `project-forge` or `project-forge-claude`.

## Current active scope

The active flow is:

```text
player text + optional rough sketch
→ identity passthrough
→ deterministic action-only behavior compiler
→ local ComfyUI visual request
→ validated transparent sprite
→ existing training area
```

Only these behavior families remain:

- `sustained_ranged`
- `returning_thrown`
- `heavy_melee`

They decide how an object attacks, never its name or appearance. The active scene does not enter either combat room. No V2, enemy, room, behavior-family, balance, survey, or anchor-calibration expansion is part of Spike 2.

The machine audit found no installed, callable local text LLM or VLM. Spike 2 therefore labels itself accurately as **player text passthrough + local rule behavior compiler**. It does not claim AI semantic understanding. A sketch without text asks exactly `你画的是什么？` once and cannot default to a fixed weapon.

## Important result

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
- The already configured local ComfyUI install for real visual generation.

No script downloads models, installs custom nodes, invokes a paid API, exposes a provider key, or listens beyond `127.0.0.1`.

## Run Spike 2

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

Desktop controls in training:

- WASD or arrow keys: move.
- Space or J: attack.
- Shift or K: dodge.
- F3: show the existing anchor debug markers.

## Test

```powershell
.\scripts\test.ps1
$godot = & .\scripts\find_godot.ps1
& $godot --headless --path . --script .\tests\test_open_identity_interpreter.gd
& $godot --headless --path . --script .\tools\comfyui\open_identity\verify_training_handoff.gd
```

The suites cover schema parity, identity/behavior separation, five verbatim identities, three identities in one behavior family, exact sketch clarification, no object-noun behavior selection, Mock isolation, local prompt evidence, timeout/Alpha/atomic delivery, and training-only scope.

## Previous isolated Spikes

- `tools/comfyui/` contains Forge Object Sprite Generation Spike 0 and its 15-run report.
- `tools/comfyui/anchor_calibration/` contains Forge Semantic Anchor Calibration Spike 1 over the 11 existing successful sprites. Spike 2 does not continue or modify anchor calibration.
- The former `scenes/main.tscn` fixed-weapon flow remains only as legacy regression/capture code. `project.godot` now starts `scenes/open_identity_spike.tscn`.

## Out of scope

V2, new gameplay content, accounts, cloud saves, stores, payments, narrative, bosses, inventories, extra behavior families, production deployment, automatic paid/model fallback, and AI-generated gameplay code remain excluded.
