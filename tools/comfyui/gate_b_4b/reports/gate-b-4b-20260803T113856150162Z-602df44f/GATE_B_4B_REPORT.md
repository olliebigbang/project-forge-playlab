# Forge Gate B 4B — Offline Alpha Extraction Spike

Final status: **NEEDS WORK**

Gate B 4A remains **NEEDS WORK**. No Gate B 4A file, frozen raw image, prompt, seed, manifest, score, or conclusion was rewritten.

## Outcome

- v1 technical Alpha delivery: 1/8.
- v2 technical Alpha delivery: 8/8.
- v2 usable Alpha after human structure review: 4/8.
- Serious subject loss: 4/8.
- Frozen raw identity baseline: 6/8; retained at 96×96: 5/8.
- Fake-transparent deliveries: 0.
- Human review SHA-256: `194e6b4dc5c24bc6667d591ef6e420207a28ebb6b3b657e80cec00a8a807834a`.
- Frozen Gate B 4A bytes verified unchanged: 78/78.
- Post-freeze Godot `.import`/`.translation` sidecars recorded separately: 41.
- Pre-existing gameplay drift recorded at closeout: changed=2, added=0, missing=0.

The selected OpenCV Chroma + GrabCut method was the only locally executable candidate. It did not defeat an installed learned model in a head-to-head comparison: Candidate B was unavailable because its local node code had no installed weights.

## Eight frozen results

| Case | Seed | v1 | v2 technical | Confidence | 96px identity | Serious loss | Preserved parts |
|---|---:|---|---|---:|---|---|---:|
| B01 | 4041001 | failed (OBJECT_TOUCHES_RAW_EDGE) | success | 0.957 | yes | yes | 2/3 |
| B01 | 4041002 | failed (OBJECT_TOUCHES_RAW_EDGE) | success | 0.959 | yes | yes | 1/3 |
| B02 | 4041001 | failed (OBJECT_TOUCHES_RAW_EDGE) | success | 0.976 | yes | yes | 3/3 |
| B02 | 4041002 | failed (OBJECT_TOUCHES_RAW_EDGE) | success | 0.959 | no | no | 2/2 |
| B03 | 4041001 | success | success | 0.945 | yes | no | 3/3 |
| B03 | 4041002 | failed (OBJECT_TOUCHES_RAW_EDGE) | success | 0.970 | no | no | 1/1 |
| B04 | 4041001 | failed (OBJECT_TOUCHES_RAW_EDGE) | success | 0.952 | yes | no | 3/3 |
| B04 | 4041002 | failed (BACKGROUND_NOT_HIGH_CONTRAST_CHROMA) | success | 0.952 | no | yes | 1/3 |

## Thresholds

- FAIL — `usable_transparent_alpha_at_least_7_of_8`
- PASS — `fake_transparent_zero`
- FAIL — `serious_subject_missing_zero`
- PASS — `raw_identity_baseline_is_6_of_8`
- FAIL — `all_six_raw_identities_remain_recognizable_at_96`
- FAIL — `b01_hose_and_nozzle_preserved_both_seeds`
- PASS — `b03_seed_4041001_remains_usable`
- FAIL — `b04_stem_and_base_preserved_both_seeds`
- PASS — `background_ground_shadow_residual_zero`
- PASS — `human_review_complete_8_of_8`

## v1 failure postmortem

The exact v1 replay found six `OBJECT_TOUCHES_RAW_EDGE` failures, one `BACKGROUND_NOT_HIGH_CONTRAST_CHROMA` failure, and one success. Gradients, floor bands, shadows, and reflections joined the inverse-background candidate; largest-component-only selection could not distinguish those regions from the prop.

## v2 interpretation

v2 produced valid 96×96 RGBA/Alpha pairs for all eight inputs, but its confidence range of 0.945–0.976 failed to flag visible subject loss. The primary actual failure layer is the postprocess algorithm, especially the lower dense-row rejection. This is not evidence that all eight RealVisXL raw generations failed.

B02 clock-face numbers and hands were reviewed as intrinsic identity markings, not extraneous text or a watermark.

## Offline environment audit

- Learned Candidate B: `UNAVAILABLE_OFFLINE` and not executed.
- Native BiRefNet and SAM3 node source exists locally, but the required model weights are absent.
- Bria RMBG is an upload/API node and was not used.
- No package, node, or model was downloaded or installed.

## Known v2 limitations

- The border-coherence threshold is derived from the same border distribution and can accept a noisy magenta backdrop.
- The dense lower-row rejection is not constrained to a bottom-edge-connected run; it visibly removed valid lower structures in this run.
- Strong central color-difference pixels can be forced back after GrabCut, allowing some connected neutral shadows to survive.
- The secondary-component local-size rule lacks a mandatory bounding-box gap test and can retain an unrelated nearby component.
- A hard chroma edge can still produce a binary source matte; final resizing happened to provide soft pixels for these eight outputs.
- Semi-transparent RGB is quantized after a dark composite, which may produce dark fringes under Godot straight-alpha blending.
- A final delivery-validation failure is not currently published as a diagnostic rejection packet.

## Recommendation

RealVisXL may remain a temporary raw prop generator because the frozen raw identity baseline is still 6/8, but the current photographic studio backdrop plus classical chroma extraction is not reliable as a Sprite delivery chain. A future separately approved experiment should either use a genuinely flat no-floor generation workflow or an approved fully local learned segmentation model.

Do **not** enter anchor calibration or the training-zone integration from this result. The Alpha/structure gate is not met.

No Anthropic call, ComfyUI launch, image regeneration, network access, gameplay edit, anchor edit, or V2 work occurred in Gate B 4B.
The closeout preflight and postflight snapshots are byte-identical. Any gameplay drift listed in the evidence ledger predates this closeout and was neither reverted nor modified.
