# FLUX.2 training-only delivery check

This scene is an explicit developer verification entry. It does not replace the
project's default `MOCK` launch mode and it has no route to either combat room.
It reads one already-published successful formal-matrix result through
`LocalComfyForgeVisualProvider.load_atomic_result()`. It never performs a health
check, starts ComfyUI, submits a workflow, or falls back to Mock.

Example (PowerShell):

```powershell
$godot = & .\scripts\find_godot.ps1
$result = Resolve-Path .\tools\comfyui\flux2\output\flux2_matrix_20260803t130451548924z\b01\seed_4041001
& $godot --path . --editor --quit
& $godot --headless --path . --scene res://tools/comfyui/flux2/godot/flux2_training_delivery.tscn -- `
  --visual-provider=LOCAL_COMFYUI `
  --comfy-profile=flux2_klein_4b `
  "--comfy-result=$result" `
  --verify-only
```

For a visible training-area review, remove `--headless` and `--verify-only`.
The scene intentionally contains no debug labels or anchor overlay. Provider,
profile, case, seed, and result directory are emitted to stdout as the auditable
status channel.

The frozen Spike 5 projection is visual-only. This harness therefore does not
claim to validate or reconstruct a combat behavior, and it never starts an
attack simulation. `WeaponBlueprint` is used only as the existing provider's
typed identity carrier while `WeaponVisualAsset` is resolved and displayed.
