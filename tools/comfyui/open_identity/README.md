# Forge Open Identity Interpretation Spike 2

This is the isolated Spike 2 implementation inside Forge Playlab. It separates player object identity from the three existing combat behavior families and connects only the Forge and training area.

Read `reports/SPIKE2_REPORT.md` before running it. The architecture is implemented, but the real visual identity gate failed: RealVisXL preserved only 2/5 required identities when the original Chinese text was sent directly.

The delivered images score prompt policy v1. Active policy v2 adds the generic action-only contract and is deliberately unscored because ComfyUI was not restarted after the runtime boundary fixes.

## Desktop run

Prepare the ignored local configuration from the example and set only local paths:

```powershell
Copy-Item .\tools\comfyui\open_identity\config\forge_open_identity_config.example.json `
  .\tools\comfyui\open_identity\config\forge_open_identity_config.local.json
```

Start the selected local ComfyUI and then the active Playlab scene:

```powershell
.\tools\comfyui\scripts\start_comfyui.ps1 `
  -ConfigPath .\tools\comfyui\open_identity\config\forge_open_identity_config.local.json
.\scripts\run_game.ps1 -- --visual-provider=LOCAL_COMFYUI
```

Stop ComfyUI when finished:

```powershell
.\tools\comfyui\scripts\stop_comfyui.ps1
```

Mock is allowed only as the explicitly labelled fixed sample:

```powershell
.\scripts\run_game.ps1 -- --visual-provider=MOCK
```

Submitting an arbitrary identity in Mock mode fails explicitly. The player must press the fixed `LOCAL SAMPLE` button to see the procedural fixture.

## Tests

```powershell
.\scripts\test.ps1
$godot = & .\scripts\find_godot.ps1
& $godot --headless --path . --script .\tests\test_open_identity_interpreter.gd
& $godot --headless --path . --script .\tools\comfyui\open_identity\verify_training_handoff.gd
$config = Get-Content .\tools\comfyui\open_identity\config\forge_open_identity_config.local.json | ConvertFrom-Json
& $config.python_executable -m unittest discover -s .\tools\comfyui\tests -p 'test_*.py' -v
& $config.python_executable -m unittest discover -s .\tools\comfyui\bridge\tests -p 'test_*.py' -v
& $config.python_executable -m unittest discover -s .\tools\comfyui\open_identity\tests -p 'test_*.py' -v
```

No command downloads a model or contacts an external service.
