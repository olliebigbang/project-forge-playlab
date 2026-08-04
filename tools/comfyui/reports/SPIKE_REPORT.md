# Forge Object Sprite Generation Spike 0 report

Status: **STOPPED — Spike implemented and evaluated; recommended gate not met.**

No V2 work was started. No gameplay content was added. The only Godot integration is the independent desktop training scene `res://scenes/comfy_training_spike.tscn`.

## Outcome

The real local chain works end to end:

```text
Godot desktop request
→ local Python bridge
→ ComfyUI 127.0.0.1 API
→ RealVisXL SDXL core workflow
→ strict Alpha postprocess
→ atomic run directory
→ Godot Alpha + grip-profile anchor search
→ existing training area
```

The visual quality and anchor reliability do not meet the suggested Spike gate.

| Suggested gate | Result | Assessment |
|---|---:|---|
| Single complete subject | 14/15 | Pass (target 12) |
| No person, hand, or text | 15/15 | Pass (target 12) |
| Identity recognizable at 96×96 | 9/15 | **Fail** (target 10) |
| Background and Alpha usable in Godot | 11/15 | Pass (target 10) |
| At least one reasonable grip/effect result in four input classes | 2/5 classes | **Fail** (target 4) |

Additional conservative scores:

- Original object identity recognizable in raw output: 14/15.
- Facing-right constraint satisfied: 3/15.
- Description-specific functional features visible: 6/15.
- GripPrimary reasonable: 4/15 overall, 4/11 among delivered sprites.
- Muzzle/Tip/EffectOrigin reasonable: 6/15 overall, 6/11 among delivered sprites.

## Matrix result

- Attempts: 15.
- Successful transparent sprites: 11.
- Explicit failures: 4 (`OBJECT_TOUCHES_RAW_EDGE`).
- Failure rate: 26.7%.
- Retries: 0.
- Warm generation mean: 2.049 seconds.
- Warm generation maximum: 2.091 seconds.
- Successful postprocess mean: 0.037 seconds.
- Matrix wall time: 31.299 seconds.
- First cold smoke generation: 12.149 seconds before the model was resident.
- Configured request timeout: 120 seconds.

The four Alpha failures are conservative background-segmentation rejections. Their raw object was often visually complete, but generated shadows or tonal bands connected the candidate foreground to an image edge. The tool correctly refused to publish pseudo-transparent sprites.

## Per-case findings

- **Case A — heavy multi-barrel object:** 3/3 Alpha deliveries, but only one result reads clearly at 96×96. One seed produced a repeated multi-object strip; largest-component cleanup cannot make the raw generation compliant. Strength 0.70 produced the clearest functional barrel/handle layout.
- **Case B — returning mechanical lightning umbrella:** umbrella identity survived 3/3 raw generations; 2/3 Alpha deliveries. Handles were readable, but lightning and return semantics were mostly absent.
- **Case C — blood-draining chainsaw greatsword:** 3/3 identity and Alpha deliveries. All three blades pointed left despite the facing-right prompt, so the existing rear-grip assumption placed GripPrimary on the blade side and Tip on the handle side.
- **Case D — screw-firing wooden chair:** chair identity survived all three seeds, satisfying the important non-weapon identity check. 2/3 Alpha deliveries. One 0.70 result retained the rough chair outline strongly; believable handholds remained weak.
- **Case E — steam weapon teapot:** teapot identity survived all three seeds, satisfying the second non-weapon identity check. Only 1/3 Alpha deliveries. The successful teapot pointed its spout left, so both grip and effect anchors were wrong.

The 0.45 versus 0.70 comparison is observational rather than causal because strength and seed both vary. The 0.70 results more literally retained rough proportions in Cases A, C, and D, sometimes becoming line-art-like; text features still failed to supply several missing functional effects.

## API reuse and isolation

No historical API script was copied, imported, modified, or overwritten. The new bridge implements a narrow local client while reusing the established endpoint pattern observed read-only in:

- `C:\AI\ComfyUI\script_examples\basic_api_example.py`: workflow injection and `POST /prompt`.
- `%USERPROFILE%\Documents\ai漫剧\production\wan22-t2v-shaw-test\render_shaw_cat_t2v.py`: prompt-id polling via `/history/{prompt_id}` and explicit timeout cancellation.

The new bridge adds request IDs, output validation, fixed timeout, targeted cancellation, failure isolation, revision checks, and atomic directory publication. It never calls an external network service.

## Nodes and assets intentionally not used

- FaceID and `ComfyUI_IPAdapter_plus`.
- `ip-adapter-faceid-plusv2_sdxl_lora.safetensors`.
- DWPose, OpenPose, and `control_v11p_sd15_openpose.pth`.
- Person/face LoRAs and first-frame continuity workflows.
- All custom nodes; the selected ComfyUI process used `--disable-all-custom-nodes`.
- Canny, Scribble, and Lineart preprocessors, because no compatible static-object ControlNet model existed locally.

## Is RealVisXL suitable as a temporary model?

**Suitable only for continued isolated exploration, not for Playlab promotion.** It is fast after warm-up and preserved chair/teapot/umbrella/chainsaw identity surprisingly well. It did not reliably obey facing direction, single-object composition, flat-background requirements, small-scale functional readability, or effect semantics. It also has no native transparent output.

## Integration behavior

- Provider switch: startup argument `--visual-provider=MOCK|LOCAL_COMFYUI`.
- Default: Mock.
- Local provider: desktop only.
- Web: no direct ComfyUI call.
- Failure: clear error, player prompt/sketch retained.
- Mock fallback: only after the player explicitly presses `M`.
- Timeout: 120 seconds.
- Cancellation/stale result: current revision changes; old runs cannot mount over a newer request.
- Atomic delivery: all files are assembled under `output/.tmp/` and moved to the final case/run directory only after validation.
- Rooms, enemies, combat, balance, modification, and survey systems are not connected to this provider.

One integration-only handoff race was found while taking the end-to-end screenshot: the bridge process could exit just before the atomic directory became visible. A two-second post-exit grace window was added. The final console-backed run reported `running → success`, wrote Godot anchors, mounted the sprite, and captured the training area.

## Evidence

- `raw_processed_comparison.png`: all 15 raw outputs beside accepted 96×96 sprites or explicit rejection reasons.
- `alpha_anchor_debug.png`: checkerboard Alpha view plus Godot-resolved anchors for all 11 accepted sprites.
- `training_zone_local_comfyui.png`: deterministic load of a matrix result in the existing training area.
- `training_zone_end_to_end.png`: a fresh Godot → bridge → ComfyUI → postprocess → Godot run in the existing training area.
- `spike_scores.csv`: all 15 runs across the requested evaluation dimensions.

## Tests

`tools/comfyui/scripts/test_spike.ps1` passes:

- 11 Spike Python tests: parameter injection, bounded timeout/cancel, corrupt PNG rejection, no-subject rejection, 96×96 and Alpha checks, temporary-directory invisibility, manifest completeness, anchor parsing, failed-delivery isolation, explicit unavailable error, and prompt exclusions.
- 17 Godot tests: the original V1 suite plus stale-revision rejection and Mock provider continuity.

## Recommendation

Stop here as requested. Do not start V2 and do not integrate this provider into rooms.

If a later, separately authorized Spike is opened, the highest-value work is not more prompt tuning. It is one of:

1. Provide an already-owned, compatible object Scribble/Lineart/Canny ControlNet model and test it without changing the gameplay scope.
2. Add a deterministic orientation classifier/flip decision before anchor resolution.
3. Replace chroma-key inference with a reliable, already-installed segmentation/background-removal capability.
4. Add semantic handle/effect-region validation before accepting anchors.

Until at least the 96×96 and four-of-five anchor gates pass, keep `LOCAL_COMFYUI` behind the standalone training Spike and retain Mock as the normal Playlab provider.
