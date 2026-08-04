# Forge Object Sprite Generation Spike 0

This directory is an isolated, local-only ComfyUI experiment for Forge Playlab. It does not extend V1 gameplay and does not start V2.

## Scope boundary

- Desktop Godot only; Web never calls ComfyUI.
- The normal Playlab flow remains Mock by default.
- The Spike scene can mount a generated sprite only in the existing training area.
- No enemy, room, combat, balance, modification, or survey code is changed.
- Existing ComfyUI workflows, models, custom nodes, outputs, and API scripts are read-only.
- ComfyUI is bound only to `127.0.0.1`; all custom nodes are disabled for Spike runs.

## Directory map

- `workflows/forge_object_sprite_v0.json`: independent API workflow using only core nodes.
- `bridge/forge_comfy_bridge.py`: health check, workflow injection, submit/poll/cancel, validation, and atomic delivery.
- `postprocess/process_sprite.py`: strict background removal, Alpha cleanup, 96×96 conversion, palette limiting, and validation.
- `test_cases/`: five prompts, three rough sketches, seeds, strengths, and manual evaluations.
- `output/<case_id>/<run_id>/`: immutable run deliveries.
- `reports/`: selection audit, score table, comparison sheets, screenshots, and final assessment.
- `scripts/`: start, stop, run, and test commands.

`runtime/` and `config/forge_comfy_config.local.json` are intentionally ignored by Git. Copy the example config and set the audited local paths before running on another machine.

## Commands

```powershell
cd "$env:USERPROFILE\Documents\project-forge-playlab"

# Start only the selected ComfyUI installation on loopback.
.\tools\comfyui\scripts\start_comfyui.ps1

# Health check.
& "C:\path\to\configured\python.exe" `
  .\tools\comfyui\bridge\forge_comfy_bridge.py `
  --config .\tools\comfyui\config\forge_comfy_config.local.json health

# Run the fixed 5 x 3 matrix. Existing final run directories are never overwritten.
.\tools\comfyui\scripts\run_spike.ps1

# Run Spike and Playlab regression tests.
.\tools\comfyui\scripts\test_spike.ps1

# Launch the isolated training scene in Mock mode.
.\scripts\run_game.ps1 res://scenes/comfy_training_spike.tscn -- --visual-provider=MOCK

# Launch the local generation path. The bridge keeps the player prompt/sketch on failure.
.\scripts\run_game.ps1 res://scenes/comfy_training_spike.tscn -- `
  --visual-provider=LOCAL_COMFYUI `
  --comfy-config=res://tools/comfyui/config/forge_comfy_config.local.json `
  --sketch="C:\path\to\rough_sketch.png"

# Stop only the Spike-owned ComfyUI process.
.\tools\comfyui\scripts\stop_comfyui.ps1
```

The provider never falls back automatically. When local generation fails, the training scene displays the concrete error; the player must press `M` to explicitly choose Mock.

## Independent Semantic Anchor Spike 1

`anchor_calibration/` is a downstream, no-generation calibration experiment. It uses only the 11 already-successful transparent Sprite files and does not contact or start ComfyUI.

```powershell
# Player calibration UI, defaulting to the first declared corpus Sprite.
.\tools\comfyui\anchor_calibration\run_spike1.ps1

# Choose any one of the 11 corpus directories.
.\tools\comfyui\anchor_calibration\run_spike1.ps1 `
  -SpriteDirectory res://tools/comfyui/output/case_d/seed_41002_s70

# Parse, regression-test, evaluate all 11, and regenerate the report/sidecars.
.\tools\comfyui\anchor_calibration\test_spike1.ps1
```

The Spike 1 scene is not the project main scene, is excluded from Web export, and starts only `GameplayArena`'s training stage after explicit calibration. It does not modify rooms, enemies, combat rules, Mock defaults, or V2 scope.
