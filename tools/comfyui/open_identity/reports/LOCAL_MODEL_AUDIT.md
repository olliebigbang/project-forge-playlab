# Spike 2 local interpretation model audit

Audit date: 2026-08-02  
Status: **CONFIRMED — no installed, callable local text interpretation model or VLM was approved for Spike 2.**

This was a read-only audit. It did not start WSL or Docker, did not access the internet, did not download a model, and did not read another project's secret.

## Findings

| Candidate | Read-only evidence | Decision |
|---|---|---|
| Playlab interpreter | The former active scene instantiated `MockWeaponInterpreter`; `WeaponInterpreter` itself is only an interface. | Mock only; not AI. |
| Ollama, LM Studio, llama.cpp and common local endpoints | No executable on PATH, common installation, active process, uninstall record, or listener on the common local ports checked. | Not callable. |
| `C:\AI\ComfyUI` | ComfyUI runtime exists. Its locally present weights are diffusion, ControlNet, IP-Adapter, CLIP Vision, VAE and text-conditioning assets. | Visual generation only; not a structured text interpreter or VLM endpoint. |
| `%USERPROFILE%\Documents\ai漫剧\tools\ComfyUI` | ComfyUI runtime and RealVisXL exist. Present related weights are diffusion, CLIP Vision, InsightFace, IP-Adapter and LoRA assets. | Selected only for local sprite generation; not an interpretation model. |
| OpenMontage analysis scripts | Source contains optional CLIP/BLIP-2/LLaVA `from_pretrained` entry points, but the environment lacks the required `torch`/`transformers` installation and cached model weights; the code is not forced to `local_files_only`. | Unusable offline; not invoked. |
| Docker | Docker CLI exists, but no Docker service/container interface was active. | Not callable. |

Additional facts:

- The selected ComfyUI workflow is RealVisXL + CLIP text encoding + KSampler image generation. It is not a language understanding service.
- Example references to LLaVA/Qwen-style architectures in installed source code do not constitute installed weights or a runnable interface.
- **TO VALIDATE:** a dormant WSL or stopped Docker environment was not started, so it cannot be ruled out as storage. It is not an available interface for this Spike.

## Implemented boundary

Spike 2 therefore reports its interpretation mode exactly as:

```text
PLAYER TEXT PASSTHROUGH + LOCAL RULE BEHAVIOR COMPILER
```

The result contract always includes:

- `ai_interpretation_used = false`
- `identity_semantics_understood = false`
- `identity_passthrough = true`

The full player sentence is preserved in `source_identity`, `player_identity_text`, and `visual_description`. Only action words select one of the three existing behavior families. Object nouns never select a family. A sketch without text returns the exact single identity clarification `你画的是什么？`.

Approval of a future local interpreter would require a separately authorized fixed model/runtime, a fully offline structured-output smoke test, model/license evidence, resource limits, and explicit failure behavior. Nothing was downloaded or provisioned here.
