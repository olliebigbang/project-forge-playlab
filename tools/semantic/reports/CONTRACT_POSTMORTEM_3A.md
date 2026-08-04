# Forge Semantic Contract Postmortem 3A

Status: **OFFLINE COMPLETE — GATE A REMAINS NEEDS WORK**

- Evidence run: `gate-a-20260802T232039017356Z-fddde20a`
- Historical contract: `forge-semantic-v1`
- Revised contract: `forge-semantic-v1.1`
- Anthropic API calls during 3A: **0**
- External network during 3A: **not used**
- ComfyUI started: **false**
- Gate B executed: **false**
- V2 started: **false**
- Combat, rooms, anchors, and art systems modified: **false**

This postmortem does not replace or reinterpret the immutable Gate A verdict. It separates the exact saved failure stages, fixes local contracts and evaluator policy offline, and recommends a later limited retest only after separate approval.

## 中文结论摘要

- Case 10：模型把完整蓝图错误包在 `$FUNCTION_NAME2` 下；根级缺少四个必填字段并多出一个未知字段。继续严格拒绝，不自动解包。
- Case 13：JSON Schema 实际通过；失败来自中文身份结构与英文视觉结构之间的纯词面比较。已改为受控的双语结构概念归一化。
- Case 17：实际失败字段是 `/known_action_hints`，不是 `known_identity_hint`。v1.1 明确允许单个字符串或字符串数组，但绝不自动互相转换。
- Case 18：JSON Schema 实际通过；同一个行为二选一被“必须恰好一个问号”误判。v1.1 改为检查是否只有一个回答焦点。
- `known_identity_hint` 没有任何 `null` 失败证据，因此继续只允许字符串；无身份线索统一使用空字符串 `""`。
- 铜钟与长枪的真实输出都已选择 `sustained_ranged`；失败和物件类别无关，也没有添加任何物件专用行为映射。
- 合同已升级为 v1.1，将 canonical identity、display name、必要结构、材质、轮廓和可选装饰分开。
- 121/121 项离线测试通过，秘密扫描 0 项；原 20 次结果和历史报告哈希全部保持不变。
- 建议以后在单独批准下进行 6 例有限真实复测；本任务没有进行复测，也没有启动 Gate B、ComfyUI 或 V2。

## 1. Evidence inventory and limitations

The investigation used the saved provider response and delivered local result for each case, not the abbreviated top-level report.

| Case | Redacted provider response | Delivered result / failure record | Raw SHA-256 | Result SHA-256 |
|---|---|---|---|---|
| 10 | `reports/raw_response_redacted/gate-a-20260802T232039017356Z-fddde20a/10.json` | `output/gate_a/gate-a-20260802T232039017356Z-fddde20a/10/result.json` | `f90b7e78c0c8c89d88a47db70f9c380a0452eff28e3ff8e48a2228f658662a1d` | `ad3a57ae501d3bc201bde2e22f7c8656d710bbae67cef4d742d7386a48936417` |
| 13 | `reports/raw_response_redacted/gate-a-20260802T232039017356Z-fddde20a/13.json` | `output/gate_a/gate-a-20260802T232039017356Z-fddde20a/13/result.json` | `df3e1710e110063a675408a7eaf4acbc9430d88bc37074d5d7b03a9c13c843db` | `752ac5f31b670d8946db2c587f192a3aad0f9342235fa4a38e7215b0fbcd5d3b` |
| 17 | `reports/raw_response_redacted/gate-a-20260802T232039017356Z-fddde20a/17.json` | `output/gate_a/gate-a-20260802T232039017356Z-fddde20a/17/result.json` | `83e2d4888097d186dd2d5057069fc0ed3539b62c6832680a656b890f54bcf0c1` | `598d896087fbb6b62d461bbba93019b0122251cb61ccbd9792b5cf12e590a46a` |
| 18 | `reports/raw_response_redacted/gate-a-20260802T232039017356Z-fddde20a/18.json` | `output/gate_a/gate-a-20260802T232039017356Z-fddde20a/18/result.json` | `9ca355eeb1b3f4ba5d26fe451e8b6a94a7342c84cc67a1ddf049063d90e6f124` | `ce5dc8692e81cae4ac578eb53ecab0da7a5c8a9504a16a3961736512782966b8` |

Evidence limitations are material:

1. Each failed case directory contains only `result.json`. There is no saved `request.json`, independent `validator.log`, or separate failure-manifest file.
2. The full outbound request envelope was deliberately not persisted. The current request builder can show its shape, but that is reconstruction, not saved evidence, so this report does not present it as the actual historical envelope.
3. The four cases have no files under `reports/compiled_blueprints/<run_id>/`; their delivered `result` value is `null`.
4. `result.json` stored `schema_valid=false` and `cross_field_valid=false` for every `ContractValidationError`. That is inaccurate for Cases 13 and 18: their JSON Schema stage passed and only their cross-field stage failed.
5. `api_status=200` is the local normalized success status for a parsed response. The raw response contains an attested Anthropic message, response ID, tool use, stop reason, and usage, but the original HTTP response line was not separately persisted.

Contract v1.1 now records `validation.stage`, separate nullable `schema_valid` / `cross_field_valid` values, and issue objects containing both the legacy JSONPath and RFC 6901 JSON Pointer. Existing v1 evidence was not rewritten.

## 2. Exact failure paths

### Case 10 — structural wrapper emitted by the model

```yaml
case_id: "10"
tool_name: submit_forge_semantic_blueprint
provider_response_id: msg_011CdenEjey9u54eaftoUZZD
tool_use_id: toolu_011po9VbYWi6PpzdEnmhPPcX
schema_stage: FAIL
cross_field_stage: NOT_RUN
failure_category: "6. unknown other cause — model/provider output-shape anomaly"
root_cause_owner: model/provider response structure
local_parser_owner: false
```

Actual `tool_use.input`:

```json
{
  "$FUNCTION_NAME2": {
    "identity": {
      "name_zh": "旧铜钟",
      "name_en": "Old Bronze Bell",
      "category": "instrument",
      "preserved_features": ["圆钟形主体", "钟顶悬挂钮", "钟口边缘外扩", "古旧氧化铜绿色表面", "厚重钟壁"],
      "material_hints": ["oxidized bronze", "aged copper-green patina", "heavy cast metal"],
      "silhouette_hints": ["classic temple bell silhouette", "wide flared rim", "domed top with hanging loop"]
    },
    "combat": {
      "behavior_family": "sustained_ranged",
      "delivery": "continuous_emission",
      "impact_mode": "continuous_stream",
      "effect_type": "sound",
      "drawback": "overheat",
      "cadence_hint": "continuous"
    },
    "visual": {
      "prompt_en": "Old Bronze Bell, a heavy aged bronze temple bell with oxidized green patina, domed top with a hanging loop, wide flared rim, thick cast bell walls, side view, small functional sound-emission fixture subtly integrated near the rim, isolated single object, complete object fully visible, detailed metal texture",
      "negative_prompt_en": "do not depict as a gun, cannon, speaker, sword, umbrella, or any generic weapon; do not add barrels, triggers, or firearm parts; avoid multiple objects, avoid background scenery",
      "must_preserve": ["圆钟形主体", "钟顶悬挂钮", "钟口边缘外扩", "古旧氧化铜绿色表面", "厚重钟壁"],
      "must_not_replace_with": ["gun", "cannon", "speaker system", "sword", "umbrella"]
    },
    "confidence": 0.85
  }
}
```

Exact failures:

| JSON Pointer | Rule | Actual | Allowed |
|---|---|---|---|
| `/identity` | required property | missing | object required |
| `/combat` | required property | missing | object required |
| `/visual` | required property | missing | object required |
| `/confidence` | required property | missing | number required |
| `/$FUNCTION_NAME2` | `additionalProperties=false` | unexpected object wrapper | only `identity`, `combat`, `visual`, `confidence` |

The parser deep-copied the saved input and did not add this wrapper. No other implementation occurrence of `$FUNCTION_NAME2` exists. The nested behavior is correctly `sustained_ranged`, but validation must not unwrap unknown model output. Contract v1.1 therefore continues to reject this fixture with exactly the five pointers above. This is correct fail-closed processing, not an unresolved parser defect.

### Case 13 — bilingual structural equivalence rejected by lexical overlap

```yaml
case_id: "13"
tool_name: submit_forge_semantic_blueprint
provider_response_id: msg_011CdenGXVY8jPjaYd2NKKrw
tool_use_id: toolu_01WJZfhhegXEYq4xevaWeAT6
schema_stage: PASS
cross_field_stage: FAIL
failure_path: /visual/must_preserve
failure_type: bilingual_structural_false_negative
failure_category: "4. cross-field rule error"
root_cause_owner: contract/local validator
```

Actual `tool_use.input`:

```json
{
  "identity": {
    "name_zh": "古老冰雾长枪",
    "name_en": "ancient spear with frost mist emitter",
    "category": "traditional_weapon",
    "preserved_features": ["长枪杆身", "尖锐枪头", "古老磨损质感", "枪尖喷雾开口"],
    "material_hints": ["aged wood shaft", "weathered metal spearhead", "worn leather wrappings"],
    "silhouette_hints": ["long straight shaft with pointed tip", "spearhead silhouette at one end"]
  },
  "combat": {
    "behavior_family": "sustained_ranged",
    "delivery": "continuous_emission",
    "impact_mode": "continuous_stream",
    "effect_type": "ice",
    "drawback": "overheat",
    "cadence_hint": "continuous"
  },
  "visual": {
    "prompt_en": "Ancient spear with frost mist emitter, long weathered wooden shaft with worn leather wrappings, aged metal spearhead at the tip, small functional mist-emitting fixture built into the spearhead, icy frost vapor curling from the tip, isolated single object, side view, complete object visible from butt end to tip",
    "negative_prompt_en": "not a gun, not a rifle, not a wand, not a staff, no futuristic sci-fi weapon, no unrelated firearm parts, instead of spear do not show generic blaster",
    "must_preserve": ["long straight shaft", "pointed spearhead", "ancient weathered material", "mist emission point at tip"],
    "must_not_replace_with": ["gun", "rifle", "wand", "staff", "generic blaster"]
  },
  "confidence": 0.85
}
```

```yaml
actual:
  identity_features: ["长枪杆身", "尖锐枪头", "古老磨损质感", "枪尖喷雾开口"]
  visual_features: ["long straight shaft", "pointed spearhead", "ancient weathered material", "mist emission point at tip"]
expected: at least one genuine structural equivalent
saved_rule: substring or shared Latin token
```

The four pairs are semantic translations, but the v1 matcher tokenized only Latin text and therefore could never match the Chinese side. The v1.1 forensic replay accepts the frozen fixture through generic structural concepts such as shaft/杆身 and spearhead/枪头. No spear-specific behavior mapping was added.

There is a second, non-causal v1 design defect in this input: `name_zh` and `name_en` include the ice-mist effect/emitter. Contract v1.1 would represent canonical identity as `古老长枪` / `ancient spear` and place the fantasy/effect wording only in display names. This was not the recorded Case 13 failure and is not presented as one.

### Case 17 — singleton action hint did not fit an array-only schema

```yaml
case_id: "17"
tool_name: request_forge_clarification
provider_response_id: msg_011CdenJhYLRz2TWWY34f9hW
tool_use_id: toolu_01L78RUm5xAycS2TqoUZhViL
schema_stage: FAIL
cross_field_stage: NOT_RUN
failure_path: /known_action_hints
failure_type: schema_type_mismatch
actual: "非常快"
expected_v1: array<string>, 0..4 items, each 1..80 characters
failure_category_immediate: "1. model output shape error"
remediation_category: "2. tool schema too strict for a semantically valid singleton"
root_cause_owner_immediate: model output shape
remediation_owner: contract
```

Actual `tool_use.input`:

```json
{
  "question_zh": "请问这个红色的东西具体是什么物品？（例如家具、工具、玩具等）",
  "ambiguity_type": "identity_unclear",
  "known_identity_hint": "红色的东西",
  "known_action_hints": "非常快"
}
```

The v1 schema explicitly requested an array, so the immediate failure is model shape non-conformance. However, a single string carries exactly one action hint without semantic loss. v1.1 explicitly accepts either one non-empty string or an array of zero to four non-empty strings. The validator returns the original value unchanged; it does not coerce the string into an array. The question asks only what the object is, as required.

The question mark followed by a parenthetical example would also have been rejected by the old terminal-punctuation rule, but Schema validation stopped first. That is a latent replay finding, not an additional saved failure path.

### Case 18 — one behavior decision was misclassified by punctuation count

```yaml
case_id: "18"
tool_name: request_forge_clarification
provider_response_id: msg_011CdenJtyfnN2q9ozXGTsB9
tool_use_id: toolu_01Ba8uw1n5g2X3JPVmvRMDXP
schema_stage: PASS
cross_field_stage: FAIL
failure_path: /question_zh
failure_type: question_mark_count_false_positive
failure_category: "4. cross-field rule error"
root_cause_owner: contract/local validator
```

Actual `tool_use.input`:

```json
{
  "question_zh": "这件武器是持续握在手中喷火，还是整体飞出去撞击后返回?这两种行为冲突,请问以哪种为主?",
  "ambiguity_type": "behavior_conflict",
  "known_identity_hint": "未指明具体物体，仅描述了攻击行为",
  "known_action_hints": ["持续喷火", "整件飞出去撞人", "撞后返回"]
}
```

```yaml
actual: two ASCII question marks, one exclusive behavior choice
expected_v1: exactly one question mark and it must terminate the string
semantic_requirement: one key answer focus
```

Both clauses ask the same decision: keep holding it to spray fire, or throw the whole object and have it return. No identity question is mixed in. v1.1 accepts repeated question punctuation only for an explicit `behavior_conflict` option choice containing “还是/或是/或者”, while retaining the checks for Chinese text, multiple interrogative focuses, and mixed identity/behavior focus. A genuine two-question input remains rejected.

## 3. Clarification null/empty decision

No saved failure contains `known_identity_hint: null`.

- Case 17 has useful partial evidence: `"红色的东西"`.
- Case 18 has a prose statement that no identity was supplied.
- The v1 schema already allowed `known_identity_hint: ""` because it was a string with no `minLength`.

Therefore v1.1 keeps the field string-only, defines `""` as the canonical “unknown identity” value, and continues to reject `null`. The prompt tells future models to use the empty string rather than a prose sentinel when no identity evidence exists.

## 4. Frozen real-response regression fixtures

The unmodified `tool_use.input` objects are stored at:

- `tests/fixtures/postmortem_3a/case_10_tool_input.json`
- `tests/fixtures/postmortem_3a/case_13_tool_input.json`
- `tests/fixtures/postmortem_3a/case_17_tool_input.json`
- `tests/fixtures/postmortem_3a/case_18_tool_input.json`
- `tests/fixtures/postmortem_3a/manifest.json`

Every offline run reloads the four original redacted responses, selects the sole `tool_use`, and deep-compares its name, ID, and input with the fixture. Fixtures cannot be edited to suit the implementation without failing that source-equality test.

Regression outcomes:

| Case | v1.1/postmortem replay outcome | Mutation or repair |
|---|---|---|
| 10 | rejected with the exact five JSON Pointers | none; no unwrap |
| 13 | accepted by frozen-v1 forensic validator with revised bilingual structure matching | none |
| 17 | accepted by v1.1 clarification contract as a singleton string hint | none; no string-to-array coercion |
| 18 | accepted as one explicit behavior-choice focus | none; question unchanged |

“Correctly processed” does not mean silently accepting Case 10. Its arbitrary wrapper is neither a legitimate alternate representation nor a semantic synonym, so accurate rejection is the required regression result.

## 5. Contract v1 → v1.1

| Concern | v1 | v1.1 |
|---|---|---|
| Contract version | `forge-semantic-v1` | `forge-semantic-v1.1` |
| Object identity | `name_zh`, `name_en` mixed base identity and fantasy effects | `canonical_name_zh/en` contain only the original object identity |
| Fantasy name | no separate field | `display_name_zh/en` may contain faithful effect/combat wording |
| Required structure | `preserved_features` mixed structure, material, silhouette, and identity labels | `required_identity_parts`, 2–5 concrete structural parts |
| Material | could obtain structural credit | `material_hints` is separate and material-only required parts are rejected |
| Silhouette | mixed with other features | `silhouette_hints`; exact name repetition is rejected |
| Forge ornament | no typed boundary | `optional_decorations`; never identity-bearing |
| Visual propagation | any broad lexical intersection passed | every required part must occur verbatim or through an approved structural concept in `visual.must_preserve` |
| Positive prompt identity | must include `name_en` | must include `canonical_name_en` |
| Canonical pollution | not checked | explicit combat/effect modifiers are rejected in canonical names; display names remain free |
| Action hints | array only | one string or array; input is never coerced |
| Unknown identity hint | implicit empty string support | empty string explicitly selected; `null` rejected |
| One clarification | exactly one question mark at terminal position | one answer focus; narrow allowance for an explicit behavior option setup |
| Failure diagnostics | Schema and cross-field both written false | explicit stage, nullable stage results, exact issues and JSON Pointers |
| Historical compatibility | live schema only | frozen v1 schema exists solely for evidence replay; production dispatch is v1.1 |

Canonical effect validation is deterministic and intentionally conservative. A lexicalized object name such as “electric guitar” or “fire extinguisher” may collide with the banned-modifier vocabulary. This is **TO VALIDATE** before using the rule outside this Spike; no silent exception was added.

## 6. Behavior/category audit

Case 10's nested combat value and Case 13's direct combat value are both:

```json
{
  "behavior_family": "sustained_ranged",
  "delivery": "continuous_emission",
  "impact_mode": "continuous_stream",
  "cadence_hint": "continuous"
}
```

The v1 and v1.1 validators branch on `behavior_family` and never use `identity.category` to select or reject a family. Offline tests validate the same sustained-emission skeleton for both an `instrument` and a `traditional_weapon`. Therefore:

- 铜钟持续发出冲击音波 remains `sustained_ranged`.
- 长枪枪尖持续喷出冰雾 remains `sustained_ranged`.
- No bell, spear, or object-name keyword behavior map was added.

The system prompt now says explicitly that the described primary action overrides category/traditional use, while incompatible simultaneous main actions still require clarification.

## 7. Evaluator audit and synonym normalization

The old evaluator was not full-string equality, but its English matching required each configured alias as a contiguous literal phrase. It could not recognise modifier insertion, singular/plural variants, or bilingual structural equivalents. At the same time, the contract validator accepted any shared non-generic token, allowing unsafe matches such as material/category words standing in for parts. The two implementations disagreed.

The v1.1 policy is:

1. Apply NFKC, case folding, punctuation/hyphen, and whitespace normalization.
2. Keep identity matching strict and separate; canonical names must match approved object aliases before feature credit matters.
3. Match structural features through a reviewed concept table, not fuzzy similarity or arbitrary shared tokens.
4. Read structural evidence from `required_identity_parts`; read material and silhouette from their typed lists. Never read `optional_decorations` or the generated prompt as evidence of a missing part.
5. Require `visual.must_preserve` to propagate the required structure separately.
6. Do not combine unrelated fields to manufacture a feature. For example, `rectangular box body` plus material `wood` is not automatically a `wooden box` claim.
7. Use no second model call and no model self-scoring.

Approved examples:

| Expected concept | Accepted expression | Reason |
|---|---|---|
| table legs | `table legs` | exact structural alias |
| table legs | `four legs` | reviewed leg concept after table identity is independently confirmed |
| table legs | `wooden legs` | reviewed leg concept; modifier does not hide the part |
| table legs | `four sturdy wooden legs` | reviewed leg concept with inserted modifiers |
| wings | `folded paper wing structure` | reviewed singular/plural wing concept |
| pan body | `round flat pan head` | reviewed pan-body concept |
| side rails | `两侧梯腿` | reviewed bilingual ladder-rail concept |

Required rejection:

| Expected concept | Rejected expression | Reason |
|---|---|---|
| table legs | `wooden furniture` | no leg/structural-head evidence |
| wings | `paper decoration` | material and decoration do not establish a wing |
| teapot body | `weapon body` | broad “body” token is not an identity-scoped part |

The evaluator-only labels were also corrected: broad labels such as “toolbox identity”, “food identity”, “metal cookware identity”, and “abstract identity” were replaced with concrete structure or silhouette evidence rather than weakened through extra aliases.

Read-only diagnostic re-score of the immutable run:

| Metric | Historical report | Revised offline diagnostic |
|---|---:|---:|
| `preserved_features_quality=2` | 6/20 | 14/20 (14/16 compiled successes) |
| Identity correct | 15/20 | 15/20 |
| Behavior correct | 16/20 | 16/20 |
| Historical Schema valid | 16/20 | 16/20; saved records remain authoritative |
| Historical clarification correct | 0/2 | 0/2; saved `result=null` is not rewritten |

The two honest remaining feature misses are Case 05 (umbrella ribs absent) and Case 19 (`rectangular box body` plus `wood` is not synthesized into `wooden box`). This demonstrates that synonym support did not lower the identity/structure requirement. The diagnostic numbers were printed only; no Gate A CSV, summary, or report was overwritten.

## 8. Offline verification

Command:

```powershell
.\tools\semantic\scripts\test_semantic.ps1
```

Result:

- **121/121 tests passed**.
- `SEMANTIC_SECRET_SCAN=PASS findings=0`.
- Credentials are removed before the offline Python process starts.
- HTTP tests use local doubles/mocks only.
- The four fixtures equal their saved redacted source inputs.
- Case 10 exact Pointer set is stable and no repair occurs.
- Cases 13, 17, and 18 process unchanged under the revised rules.
- Canonical identity rejects effect pollution; display names allow it.
- Pure-material required-part lists fail.
- A real multi-focus clarification still fails.
- Instrument and traditional-weapon categories both accept sustained emission.
- Unknown fields fail closed.
- The historical run's complete SHA-256 manifest, including all 20 results and archived reports, still matches byte for byte.
- The scope tests confirm Gate B and ComfyUI startup paths are absent and protected Godot/gameplay files match their baseline.

No external network request, Anthropic call, ComfyUI process, Gate B operation, or V2/gameplay modification occurred during 3A.

## 9. Recommendation

**Recommend a limited real retest: yes, but only under a new explicit approval. Suggested size: 6 cases.**

Recommended composition:

1. The four failed cases: 10, 13, 17, and 18.
2. One structure-synonym control from the existing corpus, such as Case 01.
3. One canonical/display separation control with an effect-heavy description, such as Case 03.

Six calls are enough to test the repaired failure layers without immediately repeating the full 20-call Gate. Acceptance for that limited retest should require:

- Case 10 emits no unknown root wrapper and is accepted without local repair.
- Case 13 uses clean canonical identity, effect-bearing display identity, correct sustained behavior, and propagated structure.
- Case 17 asks only what the object is.
- Case 18 asks only which of the two primary behaviors should win.
- Both controls preserve identity and required parts under v1.1.

Even if all six pass, Gate B must remain stopped. A later full Gate A rerun would still require separate approval and a new budget decision.

## 10. Unresolved risks

- **TO VALIDATE:** lexical effect bans can collide with lexicalized canonical objects such as “electric guitar”.
- **TO VALIDATE:** an open-world object may use an unregistered structural synonym. v1.1 falls back to exact phrases rather than fuzzy matching, so this fails closed but may create false negatives.
- The `known_action_hints` union creates two legal representations. No coercion occurs, so future consumers must explicitly support both.
- Historical per-case request bodies and dedicated validator logs do not exist. A future approved runner revision should store a key-free request hash and structured validation stage, not the system prompt or credential.
- This postmortem proves local contract behavior only. It does not prove that the approved model will consistently emit v1.1-compliant tool input.

Postmortem 3A stops here. No real retest was performed.
