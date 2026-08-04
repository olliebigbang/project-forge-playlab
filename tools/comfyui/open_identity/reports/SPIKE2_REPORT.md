# Forge Open Identity Interpretation Spike 2 report

Status: **STOPPED — identity/behavior architecture implemented; real visual identity gate failed.**

No V2 work was started. No enemy, room, combat family, balance, questionnaire, or anchor-calibration work was added. ComfyUI was stopped after the bounded evaluation, and port 8188 was verified closed.

## Outcome

The fixed **behavior-family → weapon identity** mapping is removed from the active code path:

```text
player text + optional sketch
→ player identity passthrough
→ independent local action-rule behavior compiler
→ generic identity-preserving generation_prompt
→ local ComfyUI visual provider
→ validated transparent 96×96 asset
→ training only
```

`project.godot` now starts `res://scenes/open_identity_spike.tscn`. That scene never calls the two combat-room stages. The legacy fixed renderer remains reachable only through a button labelled `LOCAL SAMPLE · 固定回归图 · 未解释输入`; Mock cannot render an arbitrary player identity and fails explicitly instead of pretending it understood one.

This does **not** clear the end-to-end product blocker: the bounded real-image evaluation preserved only 2/5 requested identities. The code boundary is corrected, while promotion remains blocked at the visual-semantic gate.

## Identity and behavior boundary

`WeaponBlueprint` now carries these separate fields:

- `source_identity`
- `player_identity_text`
- `identity_confidence`
- `preserved_visual_features`
- `visual_description`
- `behavior_family`
- `delivery`
- `impact_mode`
- `effect_type`
- `drawback`

No local semantic model was available. Consequently, `source_identity`, `player_identity_text`, and `visual_description` contain the complete player sentence rather than a falsely extracted noun. `identity_confidence = 1.0` means the passthrough is byte-for-byte player-authoritative after edge trimming; it does **not** mean a model understood the object.

The behavior compiler uses action phrases only. It never uses object nouns such as table, chair, teapot, food, or umbrella. Conflicting action clues trigger the single behavior clarification instead of silently winning by priority. The five required text cases compile to:

| Input | Behavior family | Visual identity field |
|---|---|---|
| 会飞出去撞敌人再返回的木桌 | `returning_thrown` | original text |
| 会连续发射螺丝的木椅 | `sustained_ranged` | original text |
| 喷射高温蒸汽的旧茶壶 | `sustained_ranged` | original text |
| 会吸血的巨大鸡腿 | `heavy_melee` | original text |
| 能放出电流的机械雨伞 | `sustained_ranged` | original text |

The abstract sketch case returns `你画的是什么？`, has no blueprint, and cannot default to a Gatling. The clarification UI collects the identity and a behavior selection in that single screen. Its structured answer is retained for the unchanged input across cancellation/retry; changing the text or raw strokes invalidates it. Text-only mode retains a drawing on the canvas for the player but sends no stale sketch evidence to ComfyUI.

## Training runtime boundary

The Spike 2 training scene uses `OpenIdentityTrainingArena`, a training-only subclass of the existing arena:

- `delivery=whole_object_return` hides the held object and flies the same generated `asset.texture` out and back around its existing `SpinPivot`;
- `delivery=whole_object_strike` swings the same generated texture as the contact region;
- `effect_type` gates thermal, electric, lifesteal, fastener, or generic presentation independently of identity;
- no table, chair, teapot, chicken-leg, or umbrella class/mapping exists in this runtime.

Prompt/manifest validation proves only that identity text reached generation. Because no approved VLM exists, a real result cannot enter training until the player explicitly presses `仍能认出原物件，进入训练区`. Rejecting it preserves the Forge input. A labelled fixed `LOCAL SAMPLE` remains separately usable.

## Was AI interpretation actually used?

**No.** The local-model audit found no installed, callable text LLM or VLM interface. See `LOCAL_MODEL_AUDIT.md`.

The following parts are only player-text passthrough:

- object identity;
- display identity;
- visual description;
- ComfyUI identity evidence.

The following parts are deterministic local rules, not AI:

- the three behavior families;
- delivery, impact, cadence and drawback profile;
- simple action-effect labels such as electric, thermal and lifesteal.

Every interpreter result says `ai_interpretation_used=false` and `identity_semantics_understood=false`.

## Real ComfyUI result

Selected install: `%USERPROFILE%\Documents\ai漫剧\tools\ComfyUI` with `RealVisXL_V5.0_fp16.safetensors`.

Reason: Spike 0 had already validated its Python environment, core-node workflow, loopback API and checkpoint. Only this installation was started, with `--listen 127.0.0.1 --disable-all-custom-nodes`; the other ComfyUI installation was not started or modified.

The official policy1 run used one common workflow, one common prompt builder, seed `52002`, no sketch, no retry, and the exact five Chinese player strings. The original player string is recorded in both `prompt` and `player_identity_text`, and its bounded model projection is recorded in `generation_prompt` with a SHA-256 hash.

| Metric | Result |
|---|---:|
| Blueprint identity passthrough | 5/5 (100%) |
| Correct behavior family | 5/5 (100%) |
| Technical ComfyUI + Alpha delivery | 5/5 (100%) |
| Raw visual identity preserved | **2/5 (40%)** |
| Identity recognizable at 96×96 | **2/5 (40%)** |
| No person or hands | 4/5 (80%) |
| Requested effect visibly expressed | 0/5 (0%) |
| AI semantic interpretation | 0/5; not used |

Per case:

- Wood table → a human figure: identity failure and person-constraint failure. Chroma cleanup retained a body fragment but technically accepted Alpha.
- Wood chair → an ornate mace/staff: identity failure.
- Old teapot → a recognizable teapot: identity success; no steam effect.
- Giant chicken leg → an ornate staff: identity failure.
- Mechanical umbrella → a recognizable umbrella: identity success; no electrical/mechanical effect.

The three `sustained_ranged` inputs remain three distinct blueprint identities and produced three distinct silhouettes (mace, teapot, umbrella), so the behavior family no longer dictates one visual. Only two of those three outputs preserve the requested source identity.

Warm policy1 generation took 10.946 seconds wall time for five images. Individual generation was 2.014–2.531 seconds; mean was 2.130 seconds. Postprocess was 0.037–0.053 seconds; mean was 0.041 seconds. Failure/retry count at the technical layer was 0/0.

## Prompt-policy defect found and bounded correction

The first diagnostic run attempted to say “do not replace with a generic gun or sword” inside positive CLIP text. CLIP does not reliably model negation; all five same-seed images became handguns. That run scored 0/5 identity and is retained as failure evidence.

The generic policy was corrected once by removing all forbidden object names from positive text. The same seed then produced the official 2/5 result above. No case-specific English translation, object keyword branch, special workflow, model branch, retry, or further tuning was added.

After that bounded run—and without restarting ComfyUI—the active prompt contract was versioned to `forge-open-identity-v2` so `delivery`, `impact_mode`, and `effect_type` can enter as explicitly action-only evidence. The bridge records this version separately. Policy v2 passed injection/boundary tests but has **no new visual score**; all images and 2/5 metrics in this report remain immutable policy-v1 evidence. This distinction prevents the latest code from borrowing an unevaluated visual claim.

## Is RealVisXL suitable?

**Not for raw-Chinese open-identity promotion.** It can sometimes recover familiar nouns such as teapot and umbrella, but the 40% identity rate, human violation, and 0% described-effect rate show that raw Chinese passthrough is not a reliable semantic bridge. The prior English-authored Spike 0 prompts performed materially better, but manually translating these five cases in code would be the prohibited test-specific path.

RealVisXL may remain an isolated visual-chain fixture. It must not be described as having understood arbitrary player identity and should not become the normal visual promise until an approved multilingual interpreter/translation or suitable multilingual object model exists.

## Evidence

- `identity_raw_processed_comparison.png` — all five official raw/96×96 pairs.
- `prompt_policy_ab_comparison.png` — same-seed diagnostic policy0 versus corrected generic policy1.
- `evaluation.json` — conservative per-case manual scoring.
- `generation_summary.json` — timing and atomic output paths.
- `evidence_hashes.json` — SHA-256 for all five official manifests, raw images, and processed sprites.
- `compiled_cases.json` — complete Blueprint contracts and clarification result.
- `output/<case>/<run>/manifest.json` — actual prompt, policy, workflow/checkpoint, timing and Alpha evidence.

## Verification

- Main Godot suite: 32/32 passed.
- Dedicated open-identity interpreter suite: 10/10 passed.
- Local-provider security/atomic-read suite: 2/2 passed.
- Python bridge hardening suite: 6/6 passed.
- Spike 0 bridge/postprocess suite: 13/13 passed.
- Spike 2 evidence/integration suite: 9/9 passed.
- Official policy-v1 evidence hashes: 15/15 matched; runner refuses an existing summary before generation unless overwrite is explicit.
- Atomic teapot result → `WeaponVisualAsset` → `OpenIdentityTrainingArena` handoff: passed at 96×96; delivered `anchors.json` remained byte-for-byte unchanged.
- Headless import and active-scene startup: passed on Godot 4.7.1.
- Local ComfyUI health check confirmed loopback-only before generation; service was stopped afterward.

## Unresolved risks and recommendation

1. There is no approved real semantic interpreter or VLM. Behavior rules are intentionally narrow and openly labelled.
2. RealVisXL does not reliably understand the raw Chinese identity sentence.
3. A technically valid Alpha image can still be semantically invalid or contain a person; the player-confirmation gate prevents silent promotion but is not automatic semantic validation.
4. Requested functional effects were absent in all five official samples.
5. The active desktop path is implemented, but promotion should remain blocked at the visual-semantic gate.

Recommendation: stop here. A next Spike should begin only after a separately approved, already-owned offline multilingual text/VLM interface or object-generation model is supplied. Do not hide this gap with keyword object translations, fixed visual mappings, extra behavior families, or automatic Mock fallback.
