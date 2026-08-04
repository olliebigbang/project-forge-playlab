# ComfyUI installation selection

Audit date: 2026-08-01. All inspection was read-only. Only the selected installation was started, and its input, temp, and output directories were redirected into `project-forge-playlab/tools/comfyui/runtime/`.

## Candidate 1: `C:\AI\ComfyUI`

- ComfyUI Python: `.venv/Scripts/python.exe`, Python 3.11, CUDA available.
- Checkpoint: `Realistic_Vision_V6.0_NV_B1.safetensors` (SD1.5 family).
- ControlNet model: `control_v11p_sd15_openpose.pth` only.
- Preprocessor custom node package: `comfyui_controlnet_aux` with Canny, Scribble, and Lineart wrappers.
- Downloaded auxiliary weights were DWPose-related. No compatible Canny, Scribble, or Lineart ControlNet model was present.
- Conclusion: preprocessing names exist, but the only usable ControlNet is human pose and is prohibited for this Spike. The older SD1.5 checkpoint is also less suitable for object identity and prompt composition than the available SDXL checkpoint.

## Candidate 2: `%USERPROFILE%\Documents\ai漫剧\tools\ComfyUI`

- Working Python: `tools/envs/comfy-faceid/python.exe`, Python 3.11.15, PyTorch 2.6.0+cu124, CUDA available.
- GPU observed: NVIDIA GeForce RTX 4070 Ti, 12 GB VRAM.
- Checkpoint: `RealVisXL_V5.0_fp16.safetensors` (SDXL family).
- No ControlNet model was present.
- Installed matching custom node: `ComfyUI_IPAdapter_plus`; it was not used.
- ComfyUI 0.25.0 successfully started with core nodes only.
- Selected core nodes: `CheckpointLoaderSimple`, `CLIPTextEncode`, `LoadImage`, `VAEEncode`, `KSampler`, `VAEDecode`, and `SaveImage`.

## Selection

Candidate 2 was selected because its existing CUDA environment starts cleanly, it has the stronger object-capable RealVisXL SDXL checkpoint, and all required core img2img nodes are present. It was launched with:

```text
--listen 127.0.0.1 --port 8188 --disable-auto-launch
--disable-all-custom-nodes --disable-metadata --preview-method none
```

All runtime directories were redirected to Playlab. This means FaceID, IPAdapter, DWPose, OpenPose, person LoRAs, and historical first-frame workflows were neither loaded into the workflow nor invoked.

## Sketch-control conclusion

Neither installation has a compatible static-object Scribble, Lineart, or Canny ControlNet model. A preprocessor node alone is not a control model and was not represented as one. Spike 0 therefore uses a labelled core-node img2img fallback:

- `control_type = img2img_sketch_fallback`
- `control_strength = 0.45` maps to `denoise = 0.721`
- `control_strength = 0.70` maps to `denoise = 0.566`

This can test rough silhouette influence, but it is not equivalent to ControlNet and should not be used to claim Scribble/Lineart/Canny validation.
