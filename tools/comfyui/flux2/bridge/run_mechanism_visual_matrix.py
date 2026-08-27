from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from flux2_profile_bridge import (
    Flux2BridgeError,
    _load_blueprint,
    generate,
    resolve_profile,
)


REPO_ROOT = Path(__file__).resolve().parents[4]
MATRIX_TOOL = "res://tools/comfyui/flux2/bridge/mechanism_visual_matrix_tool.gd"
MATRIX_CONTRACT = "forge-mechanism-visual-flux-matrix-v1"
SUMMARY_CONTRACT = "forge-mechanism-visual-flux-matrix-summary-v1"
PROMPT_POLICY = "forge-open-identity-v3"
MAX_REDRAWS = 2


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise Flux2BridgeError(f"JSON_ROOT_INVALID:{path.name}")
    return value


def _atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _run_godot(godot: Path, workspace: Path, *user_args: str) -> None:
    command = [
        str(godot),
        "--headless",
        "--path",
        str(workspace),
        "--script",
        MATRIX_TOOL,
        "--",
        *user_args,
    ]
    completed = subprocess.run(
        command,
        cwd=workspace,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=300,
        check=False,
    )
    combined = f"{completed.stdout}\n{completed.stderr}"
    if completed.returncode != 0 or any(token in combined for token in ("SCRIPT ERROR", "Parse Error", "Compile Error")):
        raise Flux2BridgeError(f"GODOT_MATRIX_TOOL_FAILED:{combined[-2000:]}")


def _retry_prompt(base_prompt: str, instruction: str) -> str:
    safe_instruction = " ".join(str(instruction).split()).strip()
    if not safe_instruction:
        safe_instruction = (
            "Redraw the same object with every mechanism structure visibly distinct in the 96 pixel silhouette."
        )
    clause = f" Automatic structural redraw instruction: {safe_instruction.rstrip('. ')}."
    marker = " Prompt policy:"
    if marker in base_prompt:
        return base_prompt.replace(marker, clause + marker, 1)
    return base_prompt.rstrip() + clause


def _attempt_record(
    *,
    case_id: str,
    attempt: int,
    seed: int,
    result_directory: Path,
    manifest: dict[str, Any],
    gate: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "case_id": case_id,
        "attempt": attempt,
        "seed": seed,
        "retry_count": attempt,
        "generation_status": str(manifest.get("status", "missing_manifest")),
        "generation_failure_reason": str(manifest.get("failure_reason", "")),
        "gate_ok": bool(gate.get("ok", False)) if gate else False,
        "gate_error": str(gate.get("error", "")) if gate else "",
        "retry_required": bool(gate.get("retry_required", False)) if gate else False,
        "output_directory": str(result_directory),
        "generation_seconds": float(manifest.get("generation_seconds", 0.0)),
        "total_wall_seconds": float(manifest.get("total_wall_seconds", 0.0)),
    }


def _write_csv(path: Path, records: list[dict[str, Any]]) -> None:
    fields = [
        "case_id",
        "attempt",
        "seed",
        "retry_count",
        "generation_status",
        "generation_failure_reason",
        "gate_ok",
        "gate_error",
        "retry_required",
        "generation_seconds",
        "total_wall_seconds",
        "output_directory",
    ]
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows({field: record.get(field, "") for field in fields} for record in records)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def run_matrix(profile_name: str, godot: Path, workspace: Path, matrix_root: Path | None) -> Path:
    profile = resolve_profile(profile_name)
    run_id = datetime.now(timezone.utc).strftime("mechanism-visual-%Y%m%dT%H%M%S%fZ")
    output_group = run_id.replace("-", "_").lower()
    evidence_root = (matrix_root or (workspace / "output" / "mechanism_visual_flux_matrix" / run_id)).resolve()
    evidence_root.mkdir(parents=True, exist_ok=False)
    _run_godot(godot, workspace, "--mode=prepare", f"--matrix-root={evidence_root}")
    matrix_contract_path = evidence_root / "matrix_contract.json"
    matrix = _read_json(matrix_contract_path)
    if matrix.get("contract") != MATRIX_CONTRACT or matrix.get("identity_is_constant_across_cases") is not True:
        raise Flux2BridgeError("MECHANISM_VISUAL_MATRIX_CONTRACT_INVALID")

    output_root = Path(profile["output_root"])
    print(
        json.dumps(
            {"event": "matrix_prepared", "case_count": len(matrix.get("cases", [])), "evidence_root": str(evidence_root)},
            ensure_ascii=False,
        ),
        flush=True,
    )
    attempts: list[dict[str, Any]] = []
    case_results: list[dict[str, Any]] = []
    for case_value in matrix.get("cases", []):
        if not isinstance(case_value, dict):
            raise Flux2BridgeError("MECHANISM_VISUAL_MATRIX_CASE_INVALID")
        case_id = str(case_value["case_id"])
        base_seed = int(case_value["seed"])
        request_path = evidence_root / str(case_value["request"])
        brief_path = evidence_root / str(case_value["visual_structure_brief"])
        request = _read_json(request_path)
        base_prompt = str(request["generation_prompt"])
        retry_instruction = ""
        final_gate: dict[str, Any] | None = None
        final_status = "failed"
        used_redraws = 0
        for attempt in range(MAX_REDRAWS + 1):
            seed = base_seed + attempt
            prompt = base_prompt if attempt == 0 else _retry_prompt(base_prompt, retry_instruction)
            run_name = f"attempt_{attempt}_seed_{seed}"
            result_directory = output_root / output_group / case_id / run_name
            manifest: dict[str, Any] = {}
            print(
                json.dumps(
                    {"event": "generation_start", "case_id": case_id, "attempt": attempt, "seed": seed},
                    ensure_ascii=False,
                ),
                flush=True,
            )
            try:
                generate(
                    profile,
                    case_id=case_id,
                    run_id=run_name,
                    output_group=output_group,
                    blueprint=_load_blueprint(None, prompt),
                    seed=seed,
                    prompt_policy_version=PROMPT_POLICY,
                    visual_structure_brief_path=brief_path,
                    visual_retry_count=attempt,
                )
            except (Flux2BridgeError, OSError, ValueError, json.JSONDecodeError) as exc:
                manifest = {"status": "failed", "failure_reason": str(exc)}
            manifest_path = result_directory / "manifest.json"
            if manifest_path.is_file():
                manifest = _read_json(manifest_path)
            gate: dict[str, Any] | None = None
            if manifest.get("status") == "success" and (result_directory / "processed_sprite.png").is_file():
                _run_godot(
                    godot,
                    workspace,
                    "--mode=evaluate",
                    f"--request={request_path}",
                    f"--result={result_directory}",
                )
                gate = _read_json(result_directory / "mechanism_visual_gate.json")
            record = _attempt_record(
                case_id=case_id,
                attempt=attempt,
                seed=seed,
                result_directory=result_directory,
                manifest=manifest,
                gate=gate,
            )
            attempts.append(record)
            print(
                json.dumps(
                    {
                        "event": "generation_complete",
                        "case_id": case_id,
                        "attempt": attempt,
                        "generation_status": record["generation_status"],
                        "gate_ok": record["gate_ok"],
                        "gate_error": record["gate_error"],
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
            final_gate = gate
            if gate and gate.get("ok") is True:
                final_status = "passed"
                used_redraws = attempt
                break
            if not gate or gate.get("retry_required") is not True or attempt >= MAX_REDRAWS:
                used_redraws = attempt
                break
            retry_instruction = str(gate.get("retry_prompt", ""))
        case_results.append(
            {
                "case_id": case_id,
                "base_seed": base_seed,
                "status": final_status,
                "redraw_count": used_redraws,
                "final_gate_error": str(final_gate.get("error", "")) if final_gate else "",
                "final_gate_path": (
                    attempts[-1]["output_directory"] + "/mechanism_visual_gate.json" if final_gate else ""
                ),
            }
        )

    first_pass_count = sum(1 for item in attempts if int(item["attempt"]) == 0 and item["gate_ok"] is True)
    final_pass_count = sum(1 for item in case_results if item["status"] == "passed")
    summary = {
        "contract": SUMMARY_CONTRACT,
        "run_id": run_id,
        "output_group": output_group,
        "matrix_contract": str(matrix_contract_path),
        "identity_constant": matrix.get("identity_constant", ""),
        "identity_is_constant_across_cases": True,
        "planned_case_count": len(case_results),
        "attempted_generation_count": len(attempts),
        "first_pass_count": first_pass_count,
        "first_pass_rate": first_pass_count / max(1, len(case_results)),
        "final_pass_count": final_pass_count,
        "final_pass_rate": final_pass_count / max(1, len(case_results)),
        "automatic_redraw_count": sum(max(0, int(item["redraw_count"])) for item in case_results),
        "exhausted_or_failed_count": len(case_results) - final_pass_count,
        "maximum_redraws_per_case": MAX_REDRAWS,
        "player_confirmation_required": False,
        "playtest_performed": False,
        "feel_tuning_performed": False,
        "case_results": case_results,
        "attempts": attempts,
        "completed_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    summary_path = evidence_root / "matrix_summary.json"
    _atomic_json(summary_path, summary)
    _write_csv(evidence_root / "matrix_attempts.csv", attempts)
    return summary_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the anonymous mechanism-axis FLUX visual matrix.")
    parser.add_argument("--profile", default="flux2_klein_4b")
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--workspace", type=Path, default=REPO_ROOT)
    parser.add_argument("--matrix-root", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        godot = args.godot.resolve()
        workspace = args.workspace.resolve()
        if not godot.is_file():
            raise Flux2BridgeError("GODOT_EXECUTABLE_MISSING")
        if workspace != REPO_ROOT.resolve():
            raise Flux2BridgeError("MECHANISM_VISUAL_MATRIX_WORKSPACE_MISMATCH")
        summary = run_matrix(args.profile, godot, workspace, args.matrix_root)
        print(json.dumps({"status": "COMPLETE", "summary": str(summary)}, ensure_ascii=False, indent=2))
        return 0
    except (Flux2BridgeError, OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as exc:
        print(json.dumps({"status": "FAIL", "failure_reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
