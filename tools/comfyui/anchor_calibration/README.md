# Forge Semantic Anchor Calibration Spike 1

This is an independent, disposable training-area Spike. It consumes the 11 existing successful transparent outputs from Forge Object Sprite Generation Spike 0. It does not run image generation, start ComfyUI, add gameplay, or start V2.

## Player flow

1. `GripPrimary`: click or drag the Forge grip fixture.
2. `EffectOrigin` or `StrikePoint`: click or drag the Forge action rune selected by the behavior declaration.
3. Save the sidecar and load a copied, orientation-normalized visual asset into the existing training area.

`GripSecondary` is derived only for two-hand declarations by searching from the corrected primary grip toward the Alpha centroid. `SpinPivot` is derived only for returning declarations from the binary Alpha centroid. The original `AnchorResolver` suggestions remain visible in gray and remain selectable.

## Run and verify

```powershell
cd "$env:USERPROFILE\Documents\project-forge-playlab"

.\tools\comfyui\anchor_calibration\run_spike1.ps1
.\tools\comfyui\anchor_calibration\test_spike1.ps1
```

Without parameters, the runner selects the first entry from the declarative 11-Sprite corpus. Pass `-SpriteDirectory` to select another corpus entry. `-LoadReviewTargets` preloads the fixed visual-review coordinates for evidence capture; normal player calibration leaves this switch off.

The evaluation writes one independent sidecar per Sprite under `output/<case_id>/<run_id>/semantic_anchors.json` and regenerates `reports/evaluation.json` plus `reports/SPIKE1_REPORT.md`. It verifies that the legacy Spike 0 `anchors.json` hashes do not change.

Measured result on the fixed 11-Sprite corpus:

- automatic adjustable-anchor accuracy: 11/22 (50.0%);
- fully automatic usable Sprite rate: 4/11 (36.4%);
- usable after fixed human-review points pass through the two-step calibration interface: 10/11 (90.9%).

The 11-run percentage is a repeatable corpus result, not a claim that 11 separate GUI sessions were recorded. The test suite independently drives the actual pointer-event path for outside-press rejection, grip click/drag, step confirmation, action-point click, completion, and automatic-suggestion restoration.

`case_d/seed_41003_s45` remains a declared failure because it has no credible visible power outlet. A geometrically placeable rune is not treated as semantic success.
