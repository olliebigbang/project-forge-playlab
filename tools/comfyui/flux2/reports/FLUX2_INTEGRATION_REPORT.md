# Forge FLUX.2 Klein 4B Download & Visual Pipeline Integration Spike 5

Date: 2026-08-03 UTC  
Repository: `project-forge-playlab`  
Formal matrix: `flux2-matrix-20260803T130451548924Z`

## Final decision

| Boundary | Verdict | Evidence |
|---|---|---|
| DOWNLOAD | **PASS** | The three approved artifacts were downloaded from the official workflow/model sources, then size, safetensors header, and full SHA-256 were verified. |
| RUNTIME | **PASS** | Isolated ComfyUI v0.30.0 ran on `127.0.0.1:8190`; normal-mode smoke, edit wiring smoke, the eight-image matrix, exact-PID stop, and port closure all succeeded. |
| MODEL IDENTITY | **PASS** | 8/8 raw images have the correct canonical identity, 24/24 frozen identity structures are visible, 8/8 are complete single objects, and there are zero fixed-weapon substitutions. |
| ALPHA | **NEEDS WORK** | Active v1 delivered 6/8 sprites. Both B03 staplers were correctly rejected with `OBJECT_TOUCHES_RAW_EDGE`; all six delivered sprites retain some visible magenta, and four retain floor/shadow residue. |
| GODOT TRAINING INTEGRATION | **PASS (technical delivery only)** | An already-published successful result was loaded through the real `LOCAL_COMFYUI / flux2_klein_4b` provider boundary into `WeaponVisualAsset` and a training-only viewport. No ninth generation was performed. |
| OVERALL RECOMMENDATION | **HOLD — do not promote to the default player flow** | Keep `MOCK` as the default. FLUX.2 is the stronger identity model candidate, but Alpha and the live structured-semantic handoff remain release blockers. |

No combat room, enemy, behavior family, anchor feature, V2 content, Anthropic call, Gate A call, or old ComfyUI workflow was added or changed.

## 1. Isolated runtime and provenance

The runtime is isolated at `C:\AI\ComfyUI-ForgeFlux2`; the two historical installations were not updated or used for generation. All weights and caches are on C:. The recorded free space after download was 434,669,023,232 bytes.

| Item | Frozen value |
|---|---|
| ComfyUI remote | `https://github.com/Comfy-Org/ComfyUI.git` |
| Release | `v0.30.0` |
| Commit | `b1693ecba9f5b65f8c80ab36b195ab963ec92413` |
| Python | `3.11.9` in `C:\AI\ComfyUI-ForgeFlux2\.venv` |
| PyTorch | `2.13.0+cu130` |
| CUDA reported by Torch | `13.0` |
| GPU | NVIDIA GeForce RTX 4070 Ti |
| Runtime endpoint | `http://127.0.0.1:8190` |
| Custom nodes | disabled |
| API nodes | disabled |

The active v1 sprite processor imports OpenCV, so `opencv-python-headless==4.12.0.88` was installed only inside this isolated venv. The complete dependency freeze is in `runtime_install_manifest.json`.

### Downloaded model artifacts

| File | Bytes | SHA-256 | Provenance/license status |
|---|---:|---|---|
| `flux-2-klein-4b-fp8.safetensors` | 4,070,624,520 | `97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6` | Official BFL artifact; Apache-2.0 |
| `qwen_3_4b.safetensors` | 8,044,982,048 | `6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a` | Official Comfy template artifact; conversion-level license provenance remains **TO VALIDATE** |
| `flux2-vae.safetensors` | 336,213,556 | `d64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5` | Official Comfy template artifact; hosting repository exposes a FLUX.2 Dev license, so product-use scope remains **TO VALIDATE** |

The Apache-2.0 statement is limited to the primary FLUX.2 Klein 4B model and is not legal advice. Companion-artifact ambiguity must be resolved before product/commercial use. See `model_download_manifest.json` and `LICENSE_AUDIT.md`.

## 2. Official workflows and profile adapter

Official workflow snapshots came from `https://github.com/Comfy-Org/workflow_templates.git` at commit `cebdebc9fc2febcb97a5db0dd291f59f5300b176`:

- T2I official snapshot SHA-256: `f5b2e75448e1ef44ab3d08da00900000f0258f8f963934370c6a1c329d1328c2`
- Distilled single-image edit official snapshot SHA-256: `e0388a8870495802314d58fa61616ddcdb7064dac5f85a8787c9e08180b8a560`

The `*_official.json` files remain byte-for-byte snapshots. The `*_forge_api.json` files are independent API-format copies with `_forge` bindings for prompt, seed, dimensions, steps, guidance, output path, and the edit reference. Both graphs use only core nodes and exactly the three approved filenames. The distilled path remains Euler + `Flux2Scheduler`, 4 steps, CFG 1.0, batch 1, 512×512.

The official combined T2I template names a non-FP8 distilled UNet in its selected subgraph; the API copy makes the single task-approved substitution to `flux-2-klein-4b-fp8.safetensors`. The negative text is injected and encoded but then zeroed through `ConditioningZeroOut`, preserving the official distilled CFG=1 behavior. Therefore negative-prompt influence should not be overstated.

The reusable profile is `tools/comfyui/config/profiles/flux2_klein_4b.json`; the historical RealVisXL profile remains separate. The Playlab default remains `MOCK`, and there is no automatic Mock fallback. Image edit remains behind the explicit developer switch `--flux2-enable-sketch-edit` and has no quality-pass claim.

## 3. Smoke results

### Fixed T2I smoke

- Prompt: the exact approved old wooden table prompt
- Seed: `5050001`
- Parameters: 512×512, batch 1, 4 steps, CFG 1.0
- Mode: normal; no low-memory retry was needed
- Status: **PASS**
- Generation: 10.801 s
- Total bridge wall time: 10.838 s
- Orchestration wall time: 32.757 s
- Peak observed VRAM: 11,711 MB
- Peak observed RAM: 14,134.3 MB
- Retry count: 0

The smoke ledger contains exactly one attempt. Earlier lifecycle-script diagnostics occurred before any prompt submission and do not constitute generation attempts.

### Image-edit wiring smoke

The successful T2I table raw was used as the single reference with seed `5050002`. The edit graph returned one valid 512×512 PNG in 8.621 s and retained the table identity against a magenta background. This is a **technical wiring PASS only**; sketch/edit identity quality was not gated and is not claimed.

## 4. Frozen eight-image matrix

The runner verified the existing 4A handoff and four 3C result hashes, wrote the immutable visual-only projection to `frozen_semantic_blueprints.json`, and sent English-only structured fields to FLUX.2. It did not call Claude or reinterpret the Chinese source. Frozen blueprint SHA-256: `4e97731a8b600ec2e6733c2a6ad5a0eabf5fd9f5b6c439046a2e905c9797b4bb`.

One common T2I workflow and fixed settings were used for B01–B04 at seeds 4041001 and 4041002. There were eight submissions, zero retries, no third seed, and no per-case code or workflow branch.

| Case | Seeds | Raw identity | Frozen parts visible | Raw complete | v1 Sprite | Alpha failure |
|---|---|---:|---:|---:|---:|---|
| B01 old vacuum cleaner | 4041001/4041002 | 2/2 | 6/6 | 2/2 | 2/2 | — |
| B02 twin-bell alarm clock | 4041001/4041002 | 2/2 | 6/6 | 2/2 | 2/2 | — |
| B03 giant stapler | 4041001/4041002 | 2/2 | 6/6 | 2/2 | 0/2 | `OBJECT_TOUCHES_RAW_EDGE` ×2 |
| B04 green goblet | 4041001/4041002 | 2/2 | 6/6 | 2/2 | 2/2 | — |

Human review was performed on the actual raw, sprite, and mask PNGs, not on prompts or manifests:

- correct raw identity: **8/8** (threshold 7)
- required identity parts: **24/24** (threshold 21)
- single complete object: **8/8**
- person/hand absent: **8/8**
- complete and not cropped: **8/8**
- fixed gun/sword/umbrella substitution: **0/8**
- clock-face numbers/ticks: intrinsic identity markings, not extraneous text

The model identity result is therefore **PASS**. The strongest visible improvement is that the second clock remains a twin-bell alarm clock and the second stapler remains a desktop stapler; their frozen RealVisXL counterparts became a mantel clock and a staple-gun-like object.

The frozen `visual.prompt_en` fields themselves contain sand-stream and acidic-glow wording. The bridge did not invent those effects, but B01 and B04 rendered them visibly. This is a remaining contract-boundary risk because future production prompts should leave dynamic combat effects to Godot without modifying this frozen Spike evidence.

## 5. Alpha and 96×96 result

The active processor remained byte-identical (`process_sprite.py` SHA-256 `f748c8e61dfd022d351d84c57c2d68b50b3dc39685403c7af20cc0402eebc0e9`). No threshold was relaxed.

- raw PNG delivered: 8/8
- valid 96×96 Sprite delivered: **6/8**
- recognizable at 96×96: **6/8** (suggested identity threshold met exactly)
- serious identity-structure loss among delivered sprites: 0
- visible chroma/background residue: **6/6 delivered sprites**
- visible floor/shadow residue: **4/6 delivered sprites**
- false transparent success: 0

Both B03 objects are complete in the raw images, but their generated studio-shadow bands reach the raw lower edge. v1 correctly fails closed rather than publishing fake transparency. B01 retains light magenta around the hose hole/edge; B02 retains obvious magenta around the handle/bells and feet; B04 retains base shadow/chroma residue.

This yields the required split conclusion: **MODEL PASS / ALPHA NEEDS WORK**. The failure is not an identity-model failure, but the current results are not clean enough for player-facing delivery.

## 6. RealVisXL frozen comparison

The 78 frozen Gate B 4A evidence files were rehashed and all matched. No RealVisXL image was regenerated or overwritten.

| Metric | RealVisXL 4A frozen | FLUX.2 Klein 4B | Change |
|---|---:|---:|---:|
| raw identity preserved | 6/8 (75%) | 8/8 (100%) | +25 percentage points |
| recognizable v1 96×96 delivery | 1/8 (12.5%) | 6/8 (75%) | +62.5 points |
| person/hand error | 0/8 | 0/8 | unchanged |
| v1 Alpha delivery | 1/8 (12.5%) | 6/8 (75%) | +62.5 points |

The comparison supports continuing with FLUX.2 as the temporary identity-generation candidate, not continuing RealVisXL as the primary object model. It does not remove the Alpha blocker.

## 7. Performance and resource behavior

Formal matrix generation times were 1.007–2.527 s, mean 1.609 s and median 1.536 s. Total recorded matrix wall time was 13.401 s. Maximum observed matrix VRAM was 11,641 MB and maximum observed process-tree RAM was 14,189.6 MB.

All 8/8 generations completed with zero retry, no ComfyUI crash, and no observed persistent runtime process. Normal mode was sufficient despite the narrow 12 GB VRAM margin. The largest measured smoke peak was 11,711 MB, so concurrent GPU workloads remain an OOM risk; concurrency must stay at 1.

## 8. Godot training-only delivery

`tools/comfyui/flux2/godot/flux2_training_delivery.tscn` is an explicit developer verification entry. It requires all three arguments:

```text
--visual-provider=LOCAL_COMFYUI
--comfy-profile=flux2_klein_4b
--comfy-result=<successful formal matrix directory>
```

It configures the existing `LocalComfyForgeVisualProvider`, calls `load_atomic_result`, validates a successful final manifest and 96×96 Alpha image, resolves the existing `WeaponVisualAsset`, and renders it in a training-only viewport. Missing provider/profile arguments, temporary directories, and B03 raw-only results fail closed. It never starts ComfyUI, makes a network request, enters a combat room, or falls back to Mock.

Actual checked state:

- provider/profile: `LOCAL_COMFYUI / flux2_klein_4b`
- source: B01 seed 4041001 formal result
- delivered image: 96×96 with valid Alpha
- training screenshot: 1280×720, no debug text or anchor overlay
- Godot: `4.7.1.stable.official.a13da4feb`

This proves the post-generation provider-to-training delivery boundary. It does **not** claim that the current normal Chinese input UI has a live v1.1 semantic compiler wired into Godot, and it deliberately performs no ninth image generation. Formal frozen Blueprint→FLUX generation and FLUX result→Godot delivery are evidenced as two bounded stages.

Because Alpha is still `NEEDS WORK`, the developer-only check may remain, but enabling `LOCAL_COMFYUI` as the normal player training flow is **not recommended** yet. `MOCK` remains the default and must remain explicitly labelled.

## 9. Security, isolation, and automated verification

- 75/75 Spike 5 Python contract tests passed.
- 32/32 Godot project regression tests passed.
- Real lifecycle test: start, loopback health, verified child listener ownership, exact-PID stop, and closed ports passed.
- Secret scan: PASS, zero high-confidence findings.
- Generation bridge endpoints are restricted to exact `http://127.0.0.1:8190`.
- Formal generation used only loopback after downloads completed.
- Port 8188 was never started by this Spike.
- `*.safetensors`, `*.partial`, local runtime configuration, logs, and `tools/comfyui/flux2/output/` are Git-ignored; no model is tracked.
- Web export exclusions and no-Anthropic/no-Gate-A/no-V2 boundaries are covered by tests.

Final process/port audit after all work:

- isolated FLUX.2 Python runtime processes: 0
- listeners on 8190: 0
- listeners on 8188: 0

## 10. Actual commands

Run from `<USERPROFILE>\Documents\project-forge-playlab`:

```powershell
# Download/verify the exact three approved artifacts (already completed)
.\tools\comfyui\flux2\download\download_flux2_klein_4b.ps1 `
  -RuntimeRoot 'C:\AI\ComfyUI-ForgeFlux2'

# Fixed single T2I smoke; script starts and stops the isolated runtime
.\tools\comfyui\flux2\scripts\smoke_flux2_comfyui.ps1

# Technical edit smoke and the one formal eight-image matrix
.\tools\comfyui\flux2\scripts\start_flux2_comfyui.ps1
& 'C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe' `
  .\tools\comfyui\flux2\bridge\run_flux2_spike.py `
  --profile flux2_klein_4b edit-smoke
& 'C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe' `
  .\tools\comfyui\flux2\bridge\run_flux2_spike.py `
  --profile flux2_klein_4b matrix
.\tools\comfyui\flux2\scripts\stop_flux2_comfyui.ps1

# Offline evidence and tests
python .\tools\comfyui\flux2\bridge\finalize_flux2_evidence.py
python -m unittest discover -s .\tools\comfyui\flux2\tests -p 'test_*.py' -v
.\scripts\test.ps1

# Offline Godot delivery/capture of an existing successful result
$godot = & .\scripts\find_godot.ps1
$result = (Resolve-Path '.\tools\comfyui\flux2\output\flux2_matrix_20260803t130451548924z\b01\seed_4041001').Path
& $godot --path . --scene res://tools/comfyui/flux2/godot/flux2_training_delivery.tscn -- `
  --visual-provider=LOCAL_COMFYUI `
  --comfy-profile=flux2_klein_4b `
  "--comfy-result=$result" `
  --capture-path=res://tools/comfyui/flux2/reports/godot_training_holding.png
```

## 11. Delivered evidence index

- Download: `download/download_flux2_klein_4b.ps1`, `reports/model_download_manifest.json`
- Runtime/license: `reports/runtime_install_manifest.json`, `reports/LICENSE_AUDIT.md`
- Workflows: four JSON files under `workflows/`, `workflows/WORKFLOW_DIFF.md`, `reports/workflow_sources.json`
- Profile/bridge: `tools/comfyui/config/profiles/flux2_klein_4b.json`, `bridge/flux2_profile_bridge.py`
- Lifecycle: four PowerShell scripts under `scripts/`
- Smoke outputs: `output/smoke/` and `logs/smoke_attempts.json` (local, ignored)
- Formal results: `output/flux2_matrix_20260803t130451548924z/` (local, ignored)
- Scoring: `reports/flux2_matrix_results.csv`, `reports/human_visual_review.csv`, `reports/flux2_matrix_summary.json`
- Performance: `reports/performance_metrics.csv`
- Visual evidence: `reports/flux2_raw_contact_sheet.png`, `reports/flux2_raw_sprite_comparison.png`, `reports/realvisxl_flux2_raw_comparison.png`
- Godot: `godot/flux2_training_delivery.tscn`, `reports/godot_training_holding.png`, `reports/godot_training_integration_status.json`
- Integrity: `reports/evidence_hashes.json`

## Stop

Spike 5 stops here. Do not start a sketch quality gate, subsequent Gate B work, V2, or any combat-room integration without a separate approval.
