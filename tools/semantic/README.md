# Forge Multilingual Semantic Compiler Spike 3 — Gate A

This directory is an isolated semantic validation layer. It does not start ComfyUI, change Godot gameplay, execute Gate B, or add V2 content.

## Current status

The completed Gate A run `gate-a-20260802T232039017356Z-fddde20a` remains immutable and is **NEEDS WORK**. Contract Postmortem 3A introduced `forge-semantic-v1.1` without rerunning the provider: canonical identity is separated from display naming, structural evidence is typed, clarification is judged by one answer focus, and curated structural synonyms replace broad token overlap. The four failed tool inputs are frozen under `tests/fixtures/postmortem_3a/` and are checked against their saved redacted responses on every offline run.

Mock and the Spike 2 passthrough compiler cannot count as Gate A evidence.

`schema/forge_semantic_blueprint.v1.schema.json` is a forensic snapshot only. Production dispatch uses the closed v1.1 schema in `schema/forge_semantic_blueprint.schema.json`; it never unwraps or migrates v1 failures automatically.

## Approved Limited Retest 3B

Limited Retest 3B is a separate, exactly-six-call v1.1 run over original cases
10, 13, 17, 18, 04, and 01, in that order. It has its own irreversible
reservation file and output namespace; it cannot reset or reuse the historical
20-call Gate A reservation and exposes no `ForceNewRun` option.

The exact model is read from the hash-verified frozen Gate A run. The
interactive script therefore asks only for the API key and refuses any model
alias or upgrade. Production `known_action_hints` is array-only. The scalar in
the frozen Case 17 evidence remains readable only through the explicitly named
forensic replay validator and is never offered to the live tool schema.

From the repository root, run the approved secure entry point once:

```powershell
.\tools\semantic\scripts\run_limited_retest_3b_interactive.ps1
```

The script completes all offline tests, the secret scan, protected-scope check,
historical hash verification, live Schema parity, and unused-budget check
before asking for a key. It performs one request per approved case with no
automatic retry, then permanently closes the six-call reservation.

3B publishes new files only:

- `reports/LIMITED_RETEST_3B_REPORT.md`
- `reports/limited_retest_3b_results.csv`
- `reports/limited_retest_3b_summary.json`
- `reports/limited_retest_3b/<run_id>/raw_response_redacted/`
- `reports/limited_retest_3b/<run_id>/evidence_hashes.json`

Passing 3B does not execute or authorize Gate B. The next permitted action is
to stop and wait for explicit approval of four new blind cases.

## Approved network boundary

The runner permits exactly one remote endpoint:

`POST https://api.anthropic.com/v1/messages`

It uses Python's standard-library `urllib`, sends `anthropic-version: 2023-06-01`, performs no automatic retry, uses a 60-second timeout, omits the model-deprecated `temperature` parameter, caps `max_tokens` at 1200, and stops at 20 calls.

Before any network request, the runner repeats the secret scan, verifies the protected non-semantic repository hash, and atomically claims the Spike's single persistent real-call budget. This prevents two processes from turning the 20-call ceiling into 40 calls. A crashed or completed real-run reservation is never cleared automatically.

The key is read only from `ANTHROPIC_API_KEY`. The exact model ID is read only from `FORGE_SEMANTIC_MODEL`. Neither value is guessed or read from another project.

Every Python subprocess is launched with environment/startup isolation (`-E -S -B`). Offline subprocesses have the key and model removed before Python starts, and real-run scripts clear their process copies in `finally`.

## Safe local execution

From the repository root, run:

```powershell
.\tools\semantic\scripts\run_gate_a_interactive.ps1
```

The interactive script asks for the exact model ID and reads the key with `Read-Host -AsSecureString`. Both variables and the temporary plaintext reference are cleared in `finally`. Do not paste the key into chat or write it to a config file.

For an already prepared current PowerShell process:

```powershell
.\tools\semantic\scripts\run_gate_a.ps1
```

An existing output run is never overwritten. `-ForceNewRun` permits a new unique output directory, but it never bypasses the persistent lifetime real-call reservation or the 20-call ceiling.

## Offline verification

```powershell
.\tools\semantic\scripts\test_semantic.ps1
```

This runs every offline unit/integration test and then performs the high-confidence repository secret scan. The scan checks all non-NUL working-tree text (including ignored config, output, temp and log files) plus canonical Git index blobs while ignoring ambient Git redirection and replacement objects. Unicode-escaped credentials and sensitive filenames are detected without printing matched values; excessive escape nesting, enumeration, index, and read failures fail closed. Tests use mocked HTTP responses only.

## Outputs

Each real request is first staged below `tools/semantic/.tmp/<request_id>/` and atomically delivered under a unique Gate A run directory. Reports are written to:

- `reports/GATE_A_REPORT.md`
- `reports/gate_a_results.csv`
- `reports/gate_a_summary.json`
- `reports/evidence_hashes.json`
- `reports/raw_response_redacted/<run_id>/`
- `reports/compiled_blueprints/<run_id>/`
- `reports/runs/<run_id>/` (immutable per-run report archive)

Report files are first created under a visibly pending directory. The repository is scanned again before any PASS or top-level report is published; a failed scan leaves only a `NEEDS WORK` blocked marker and cannot publish a PASS report.

The expected labels are loaded only after all model calls finish and are never included in an Anthropic payload.
