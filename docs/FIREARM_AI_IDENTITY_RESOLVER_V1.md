# Firearm AI Identity Resolver V1

> V2 已增加精确外形轴、96px 必见识别点、易混型号排除项，以及陌生型号的 Wikimedia 可信参考图自动检索。见 `docs/FIREARM_DYNAMIC_REFERENCE_PIPELINE_V1.md`。

## Plain-language contract

The player types an object name. The player never chooses how it attacks.

For a firearm name that is not already cached, one semantic AI call translates the exact name into a closed identity card. Godot validates every field and compiles the ranged mechanisms. The generic pixel scaffold is now a hidden structural guide only; the player-facing sprite must come from the gated AI pixel-art pipeline described in `FIREARM_AI_PIXEL_ART_PIPELINE_V2.md`.

## Runtime flow

1. Check the four curated firearm profiles and the locally validated AI cache.
2. If the identity is still unknown and firearm AI is enabled, submit the exact text as untrusted identity data.
3. Require one strict response containing classification, public identity evidence, visible silhouette parts, eight structural axes and eight mechanism axes.
4. Validate the response independently in the Python bridge and again in Godot.
5. Cache only a fully validated supported handheld-firearm profile.
6. Compile the profile through the ranged runtime, generate external finished pixel art, and accept it only after the automatic firearm identity gate passes.

There is no player mechanism clarification path and no automatic retry.

## Current representable firearm families

- magazine-fed bullpup rifles;
- magazine-fed conventional rifles, compact carbines and shoulder-stocked submachine guns;
- magazine-fed semi-automatic pistols.

Revolvers, tube-fed or break-action shotguns, belt-fed weapons and launchers are recognized as unsupported instead of being collapsed into a generic rifle. Tanks and other armed vehicles return `AI_VEHICLE_PLATFORM_COMPILER_REQUIRED`; they are never treated as handheld weapons.

## Developer launch

Run:

```powershell
.\scripts\run_open_identity_firearm_ai.ps1
```

The launcher supplies `--firearm-ai=anthropic`, keeps the API credential in the process environment only, and clears its local plaintext references on exit. No API key is stored in the repository, request files, cache or result files. A new uncached identity may make one semantic API call; known validated identities reuse the local cache.

The ordinary game launch remains offline and uses only the curated plus already validated cache. This prevents an accidental paid request.

## Frozen response artifacts

- Schema: `res://data/combat_feel/firearm_identity_ai_response_schema_v1.json`
- Prompt: `res://data/combat_feel/firearm_identity_ai_prompt_v1.txt`
- Godot validator/cache: `res://scripts/combat_feel/firearm_identity_ai_resolver.gd`
- Process provider: `res://scripts/services/firearm_identity_ai_provider.gd`
- Semantic bridge: `res://tools/semantic/bridge/firearm_identity_ai_bridge.py`
