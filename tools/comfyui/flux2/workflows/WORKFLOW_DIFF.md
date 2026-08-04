# Official template to Forge API adaptation

Source repository: `https://github.com/Comfy-Org/workflow_templates.git`

Frozen source commit: `cebdebc9fc2febcb97a5db0dd291f59f5300b176`

| Artifact | SHA-256 |
| --- | --- |
| `flux2_klein_4b_t2i_official.json` | `f5b2e75448e1ef44ab3d08da00900000f0258f8f963934370c6a1c329d1328c2` |
| `flux2_klein_4b_edit_official.json` | `e0388a8870495802314d58fa61616ddcdb7064dac5f85a8787c9e08180b8a560` |

The `*_official.json` files are byte-for-byte snapshots and are never loaded by
the API bridge. The `*_forge_api.json` files flatten only the applicable core
subgraph into ComfyUI API prompt format and add `_forge` metadata.

T2I selects the official Distilled subgraph: Euler sampler, `Flux2Scheduler`,
four steps, CFG 1.0, `EmptyFlux2LatentImage`, `SamplerCustomAdvanced`, and the
FLUX.2 VAE. The only model-loader substitution is the task-approved official
FP8 diffusion file in place of the BF16 distilled filename present in the
combined template.

Edit selects the official single-reference Distilled path. The disabled
multi-reference example is intentionally omitted. `reference_strength` is not
invented because the official template exposes no such control. Edit remains a
developer-only wiring smoke and has no quality-pass claim.

Both API graphs add a separately injectable negative-text encoder whose output
is zeroed through `ConditioningZeroOut`, preserving the official distilled
CFG=1 behavior while keeping a uniform bridge contract. Width and height are
fixed to 512 for this Spike, batch remains 1, and no custom node is used.
