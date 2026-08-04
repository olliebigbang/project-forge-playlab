# FLUX.2 Klein 4B license audit

Audit date: 2026-08-03 UTC

This is an evidence record, not legal advice. It does not broaden any upstream license.

## Primary model

- Artifact: `flux-2-klein-4b-fp8.safetensors`
- Model: FLUX.2 Klein 4B Distilled FP8
- Publisher/source: Black Forest Labs, official Hugging Face repository
- Official model family page: `https://huggingface.co/black-forest-labs/FLUX.2-klein-4B`
- Download source used: `https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8/resolve/main/flux-2-klein-4b-fp8.safetensors`
- License identified by the official model repository: Apache-2.0
- Downloaded SHA-256: `97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6`

The Apache-2.0 statement above applies to the official FLUX.2 Klein 4B model. It is not a conclusion about every dependency or every possible output use.

## Required companion artifacts

### Qwen text encoder conversion

- Artifact: `qwen_3_4b.safetensors`
- Official Comfy template source: `https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors`
- Downloaded SHA-256: `6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a`
- Local/remote metadata reviewed for this Spike did not expose a model card or an unambiguous artifact-level license declaration for this converted file.
- Status: **LICENSE PROVENANCE TO VALIDATE**. Do not infer that the conversion is Apache-2.0 solely because the primary Klein model is Apache-2.0.

### FLUX.2 VAE

- Artifact: `flux2-vae.safetensors`
- Official Comfy template source: `https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors`
- Downloaded SHA-256: `d64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5`
- The hosting repository metadata observed during the audit identifies the FLUX.2 Dev non-commercial license rather than Apache-2.0.
- Status: **LICENSE SCOPE TO VALIDATE BEFORE PRODUCT USE**. This Spike uses it only for a local disposable experiment and does not claim production or commercial clearance.

## Runtime code

- ComfyUI source: `https://github.com/Comfy-Org/ComfyUI.git`
- Frozen release: `v0.30.0`
- Commit: `b1693ecba9f5b65f8c80ab36b195ab963ec92413`
- ComfyUI carries its own repository license; Python packages retain their individual licenses.

## Decision

The primary FLUX.2 Klein 4B model meets the requested Apache-2.0 provenance check. The Qwen conversion and VAE companion-artifact license provenance are not sufficiently clear to approve a formal product release. They are acceptable here only within the explicitly local Spike scope; resolve both before any wider distribution or commercial deployment.
