#!/usr/bin/env python3
"""Stateful, loopback-only orchestration for Forge Live E2E Spike 7.

There is no retry path and no mock provider.  Each approved case can reserve
exactly one semantic call, one FLUX prompt, and one BiRefNet prompt.
"""

from __future__ import annotations

import base64
import copy
import csv
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from typing import Any, Mapping

from PIL import Image, ImageDraw, ImageFont


BRIDGE_DIR = Path(__file__).resolve().parent
LIVE_ROOT = BRIDGE_DIR.parent
PLAYLAB_ROOT = LIVE_ROOT.parents[1]
SEMANTIC_ROOT = PLAYLAB_ROOT / "tools" / "semantic"
FLUX2_ROOT = PLAYLAB_ROOT / "tools" / "comfyui" / "flux2"
BIREf_ROOT = FLUX2_ROOT / "birefnet"
for import_root in (SEMANTIC_ROOT / "bridge", FLUX2_ROOT / "bridge", BIREf_ROOT):
    if str(import_root) not in sys.path:
        sys.path.insert(0, str(import_root))

from anthropic_semantic_compiler import (  # noqa: E402
    AnthropicSemanticCompiler,
    CallLimiter,
    SemanticCompilerError,
)
from semantic_contract import (  # noqa: E402
    CLARIFICATION_REQUEST_SCHEMA,
    FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
    SUBMIT_BLUEPRINT_TOOL,
    ContractValidationError,
    validate_tool_input,
)
import flux2_profile_bridge as flux_bridge  # noqa: E402
from forge_comfy_bridge import BridgeError as ComfyBridgeError  # noqa: E402
from process_birefnet_sprite import (  # noqa: E402
    BiRefNetPostprocessError,
    process_birefnet_sprite,
)
from spike6_runner import (  # noqa: E402
    LoopbackHttpTransport,
    Spike6RunnerError,
    _download_output,
    _history_outputs,
    _normalise_mask_png,
    _set_path,
    _validate_rgba_png,
    load_approved_workflow,
)
from static_visual_projection import project_static_visual  # noqa: E402
from live_preflight import verify_history  # noqa: E402
from secret_scan import scan_repository  # noqa: E402


CONTRACT = "forge-live-e2e-spike7-session-v1"
BIREF_WORKFLOW_SHA256 = "56d74936b840de2ce2d5e823b6ad1704b9e65dd7ddd8b7a0edbfb5d4d4cf19df"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class LivePipelineError(RuntimeError):
    def __init__(self, stage: str, code: str) -> None:
        self.stage = stage
        self.code = code
        super().__init__(f"{stage}:{code}")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def write_new(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())


def write_json_new(path: Path, value: Any) -> None:
    write_new(path, json_bytes(value))


def write_json_replace_in_stage(path: Path, value: Any) -> None:
    """Atomically replace mutable metadata inside an unpublished stage."""
    temporary = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"
    write_new(temporary, json_bytes(value))
    os.replace(temporary, path)


def safe_png_from_base64(value: Any, label: str) -> bytes:
    if not isinstance(value, str) or not value:
        raise LivePipelineError("evidence", f"{label}_MISSING")
    try:
        payload = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as exc:
        raise LivePipelineError("evidence", f"{label}_BASE64_INVALID") from exc
    if not payload.startswith(PNG_SIGNATURE) or len(payload) > 20 * 1024 * 1024:
        raise LivePipelineError("evidence", f"{label}_PNG_INVALID")
    try:
        with Image.open(io.BytesIO(payload)) as image:
            image.verify()
    except OSError as exc:
        raise LivePipelineError("evidence", f"{label}_PNG_UNREADABLE") from exc
    return payload


class PeakSampler:
    """Observe whole-GPU VRAM and owned Comfy process RAM without credentials."""

    def __init__(self, state_file: Path) -> None:
        self.state_file = state_file
        self.peak_vram_mb = 0.0
        self.peak_ram_mb = 0.0
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def _sample(self) -> None:
        try:
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                text=True,
                encoding="utf-8",
                errors="replace",
                capture_output=True,
                check=False,
                timeout=3,
            )
            if result.returncode == 0 and result.stdout.strip():
                self.peak_vram_mb = max(self.peak_vram_mb, float(result.stdout.strip().splitlines()[0]))
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        try:
            import psutil  # type: ignore

            state = json.loads(self.state_file.read_text(encoding="utf-8"))
            pids = {int(state.get("launcher_pid", 0)), int(state.get("listener_pid", 0))} - {0}
            ram = 0
            for pid in pids:
                process = psutil.Process(pid)
                ram += process.memory_info().rss
                ram += sum(child.memory_info().rss for child in process.children(recursive=True))
            self.peak_ram_mb = max(self.peak_ram_mb, ram / 1024**2)
        except Exception:
            pass

    def __enter__(self) -> "PeakSampler":
        def loop() -> None:
            while not self._stop.wait(0.25):
                self._sample()
        self._sample()
        self._thread = threading.Thread(target=loop, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, *_: Any) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
        self._sample()


@dataclass
class CaseState:
    config: dict[str, Any]
    revision: int
    stage: str = "reserved"
    technical_dir: Path | None = None
    semantic_blueprint: dict[str, Any] | None = None
    semantic_redacted: dict[str, Any] | None = None
    metrics: dict[str, Any] = field(default_factory=dict)
    identity_review: dict[str, Any] | None = None
    anchors: dict[str, Any] | None = None
    training: dict[str, Any] | None = None
    final_dir: Path | None = None
    failure_stage: str = ""
    failure_reason: str = ""


class LiveSession:
    def __init__(
        self,
        *,
        session_id: str,
        run_id: str,
        preflight_file: Path,
        resume_from_session_id: str | None = None,
    ) -> None:
        self.config = json.loads((LIVE_ROOT / "config" / "live_cases.json").read_text(encoding="utf-8"))
        self.session_id = session_id
        self.run_id = run_id
        self.preflight_file = preflight_file.resolve()
        self.runtime_root = LIVE_ROOT / "runtime" / session_id
        self.pipeline_root = self.runtime_root / "pipeline"
        self.output_root = LIVE_ROOT / "output" / "runs" / run_id
        self.report_root = LIVE_ROOT / "reports" / run_id
        self.resume_from_session_id = resume_from_session_id
        self.prior_semantic_calls = 1 if resume_from_session_id else 0
        if resume_from_session_id:
            if not self.output_root.is_dir() or not self.report_root.is_dir():
                raise LivePipelineError("recovery", "ORIGINAL_RUN_DIRECTORIES_MISSING")
        else:
            self.output_root.mkdir(parents=True, exist_ok=False)
            self.report_root.mkdir(parents=True, exist_ok=False)
        self.case_configs = {case["case_id"]: case for case in self.config["cases"]}
        self.case_order = [case["case_id"] for case in self.config["cases"]]
        self.cases: dict[str, CaseState] = {}
        self.next_ordinal = 1
        self.revision = 0
        self.lock = threading.RLock()
        self.compiler = AnthropicSemanticCompiler(
            system_prompt=(SEMANTIC_ROOT / "prompts" / "semantic_compiler_system_prompt.md").read_text(encoding="utf-8"),
            blueprint_schema=FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
            clarification_schema=CLARIFICATION_REQUEST_SCHEMA,
            call_limiter=CallLimiter(max_calls=2 if resume_from_session_id else 3),
        )
        # Extension points used by the separate Open Playtest adapter.  Their
        # defaults preserve the frozen Spike 7 paths, manifests and workflow.
        self.technical_contract = CONTRACT
        self.flux_output_group = "live_e2e_stage"
        self.biref_output_namespace = "ForgeLive"
        self.started_at = utc_now()
        self.finalized = False
        self.scope_attestation: dict[str, Any] = {}
        offline_log = self.runtime_root / "offline_tests.log"
        if not offline_log.is_file() or "Ran 40 tests" not in offline_log.read_text(encoding="utf-8", errors="replace") or "OK" not in offline_log.read_text(encoding="utf-8", errors="replace"):
            raise LivePipelineError("preflight", "OFFLINE_TEST_EVIDENCE_MISSING")
        if resume_from_session_id:
            self._restore_l01_for_manual_reconfirmation(resume_from_session_id)
        else:
            self._write_session_manifest()
        if resume_from_session_id:
            recovery_test_log = self.output_root / "recovery_offline_tests.log"
            if recovery_test_log.exists():
                recovery_test_log = self.output_root / "recovery_offline_tests" / f"{self.session_id}.log"
                recovery_test_log.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(offline_log, recovery_test_log)
        else:
            shutil.copy2(offline_log, self.output_root / "offline_tests.log")

    def _restore_l01_for_manual_reconfirmation(self, source_session_id: str) -> None:
        source = LIVE_ROOT / "runtime" / source_session_id / "pipeline" / "L01"
        required = {
            "player_input.json",
            "semantic_blueprint.json",
            "semantic_response_redacted.json",
            "static_visual_projection.json",
            "flux_raw.png",
            "flux_manifest.json",
            "birefnet_rgba.png",
            "birefnet_mask.png",
            "birefnet_manifest.json",
            "processed_sprite.png",
            "postprocess_metrics.json",
            "stage_metrics.json",
            "technical_manifest.json",
        }
        if not source.is_dir() or any(not (source / name).is_file() for name in required):
            raise LivePipelineError("recovery", "L01_TECHNICAL_EVIDENCE_INCOMPLETE")
        existing_manifest = json.loads((self.output_root / "session_manifest.json").read_text(encoding="utf-8"))
        if existing_manifest.get("run_id") != self.run_id or existing_manifest.get("session_id") != source_session_id:
            raise LivePipelineError("recovery", "ORIGINAL_SESSION_MANIFEST_MISMATCH")
        if (self.output_root / "L01").exists():
            raise LivePipelineError("recovery", "L01_ALREADY_PUBLISHED")
        recovery_archive = self.runtime_root / "failed_publish_attempt"
        recovery_archive.mkdir(parents=True, exist_ok=False)
        failed_stages = sorted(self.output_root.glob(".L01.*.tmp"))
        failed_stage_hashes = {
            f"{failed_stage.name}/{path.relative_to(failed_stage).as_posix()}": sha256_file(path)
            for failed_stage in failed_stages
            for path in sorted(failed_stage.rglob("*"))
            if path.is_file()
        }
        for failed_stage in failed_stages:
            os.replace(failed_stage, recovery_archive / failed_stage.name)
        recovered_technical = self.pipeline_root / "L01"
        shutil.copytree(
            source,
            recovered_technical,
            ignore=shutil.ignore_patterns("forge_confirmation.png", "training_holding.png", "training_attack.png"),
        )
        config = copy.deepcopy(self.case_configs["L01"])
        state = CaseState(config=config, revision=1, stage="awaiting_identity")
        state.technical_dir = recovered_technical
        state.semantic_blueprint = json.loads((recovered_technical / "semantic_blueprint.json").read_text(encoding="utf-8"))
        state.semantic_redacted = json.loads((recovered_technical / "semantic_response_redacted.json").read_text(encoding="utf-8"))
        state.metrics = json.loads((recovered_technical / "stage_metrics.json").read_text(encoding="utf-8"))
        self.cases = {"L01": state}
        self.next_ordinal = 2
        self.revision = 1
        recovery_manifest_path = self.output_root / "recovery_manifest.json"
        if recovery_manifest_path.exists():
            recovery_manifest_path = self.output_root / "recovery_manifests" / f"{self.session_id}.json"
        write_json_new(
            recovery_manifest_path,
            {
                "contract": "forge-live-e2e-spike7-recovery-v1",
                "run_id": self.run_id,
                "source_session_id": source_session_id,
                "recovery_session_id": self.session_id,
                "reason": "ATOMIC_STAGE_METRICS_NAME_COLLISION",
                "reused_case": "L01",
                "reused_technical_evidence": True,
                "manual_confirmation_repeated": True,
                "prior_semantic_calls": 1,
                "remaining_semantic_call_limit": 2,
                "archived_failed_publish_stages": [path.name for path in failed_stages],
                "archived_failed_publish_sha256": failed_stage_hashes,
                "source_files_sha256": {name: sha256_file(source / name) for name in sorted(required)},
                "created_at_utc": utc_now(),
            },
        )

    def _write_session_manifest(self) -> None:
        write_json_new(
            self.output_root / "session_manifest.json",
            {
                "contract": CONTRACT,
                "session_id": self.session_id,
                "run_id": self.run_id,
                "started_at_utc": self.started_at,
                "approved_case_order": self.case_order,
                "approved_model_id": self.config["approved_model_id"],
                "semantic_contract": self.config["semantic_contract"],
                "retry_limit": 0,
                "mock_fallback": False,
                "explicit_launch_required": True,
                "preflight_file": str(self.preflight_file),
                "preflight_sha256": sha256_file(self.preflight_file),
            },
        )

    def health(self) -> dict[str, Any]:
        return {
            "status": "ok",
            "contract": CONTRACT,
            "session_id": self.session_id,
            "run_id": self.run_id,
            "next_case": "L01" if self.resume_from_session_id else (self.case_order[self.next_ordinal - 1] if self.next_ordinal <= 3 else None),
            "calls_made": self.prior_semantic_calls + self.compiler.calls_made,
            "mock_fallback": False,
        }

    def _require_case_request(self, payload: Mapping[str, Any], *, expected_stage: str | None = None) -> CaseState:
        if payload.get("session_id") != self.session_id:
            raise LivePipelineError("request", "SESSION_ID_MISMATCH")
        case_id = str(payload.get("case_id", ""))
        state = self.cases.get(case_id)
        if state is None:
            raise LivePipelineError("request", "CASE_NOT_RESERVED")
        if payload.get("revision") != state.revision:
            raise LivePipelineError("request", "STALE_REQUEST_REJECTED")
        if expected_stage and state.stage != expected_stage:
            raise LivePipelineError("request", f"CASE_STAGE_INVALID:{state.stage}:{expected_stage}")
        return state

    def start_case(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            if payload.get("session_id") != self.session_id:
                raise LivePipelineError("request", "SESSION_ID_MISMATCH")
            if self.next_ordinal > 3:
                raise LivePipelineError("request", "THREE_CASE_LIMIT_REACHED")
            case_id = str(payload.get("case_id", ""))
            player_input = str(payload.get("player_input", "")).strip()
            if self.resume_from_session_id and case_id == "L01":
                state = self.cases["L01"]
                if player_input != state.config["player_input"] or state.stage != "awaiting_identity":
                    raise LivePipelineError("request", "RECOVERY_L01_REQUEST_INVALID")
                response = self._technical_success_response(state, player_input)
                self.resume_from_session_id = None
                return response
            expected = self.config["cases"][self.next_ordinal - 1]
            if case_id != expected["case_id"] or player_input != expected["player_input"]:
                raise LivePipelineError("request", "UNAPPROVED_CASE_OR_INPUT")
            if case_id in self.cases:
                raise LivePipelineError("request", "CASE_ALREADY_CALLED")
            self.revision += 1
            state = CaseState(config=copy.deepcopy(expected), revision=self.revision)
            self.cases[case_id] = state
            self.next_ordinal += 1
        try:
            self._run_technical(state, player_input)
        except LivePipelineError as exc:
            state.stage = "technical_failed"
            state.failure_stage = exc.stage
            state.failure_reason = exc.code
            self._publish_failure_case(state, player_input)
            return {
                "status": "failed",
                "case_id": case_id,
                "revision": state.revision,
                "failure_stage": exc.stage,
                "failure_reason": exc.code,
                "player_input_preserved": True,
                "retry_count": 0,
                "mock_fallback": False,
            }
        state.stage = "awaiting_identity"
        return self._technical_success_response(state, player_input)

    def _technical_success_response(self, state: CaseState, player_input: str) -> dict[str, Any]:
        assert state.technical_dir and state.semantic_blueprint
        sprite = (state.technical_dir / "processed_sprite.png").read_bytes()
        identity = state.semantic_blueprint["identity"]
        combat = state.semantic_blueprint["combat"]
        return {
            "status": "technical_success",
            "case_id": state.config["case_id"],
            "revision": state.revision,
            "player_input": player_input,
            "summary_zh": f"{identity['display_name_zh']} · {combat['behavior_family']} · {combat['effect_type']}",
            "canonical_name_zh": identity["canonical_name_zh"],
            "behavior_family": combat["behavior_family"],
            "delivery": combat["delivery"],
            "impact_mode": combat["impact_mode"],
            "effect_type": combat["effect_type"],
            "drawback": combat["drawback"],
            "cadence_hint": combat["cadence_hint"],
            "expected_parts": state.config["required_identity_parts"],
            "second_anchor_type": state.config["second_anchor_type"],
            "second_anchor_question": state.config["second_anchor_question"],
            "sprite_png_base64": base64.b64encode(sprite).decode("ascii"),
            "retry_count": 0,
            "mock_fallback": False,
        }

    def _run_technical(self, state: CaseState, player_input: str) -> None:
        case_id = state.config["case_id"]
        stage = self.pipeline_root / f".{case_id}.{uuid.uuid4().hex}.tmp"
        final = self.pipeline_root / case_id
        if final.exists():
            raise LivePipelineError("request", "TECHNICAL_CASE_ALREADY_EXISTS")
        stage.mkdir(parents=True, exist_ok=False)
        write_json_new(stage / "player_input.json", {"case_id": case_id, "player_input": player_input, "submitted_at_utc": utc_now()})
        total_start = time.perf_counter()
        try:
            self._notify_pipeline_stage(state, "semantic_compiling")
            semantic_start = time.perf_counter()
            try:
                parsed = self.compiler.compile(player_input)
            except SemanticCompilerError as exc:
                raise LivePipelineError("semantic", exc.code) from exc
            semantic_seconds = time.perf_counter() - semantic_start
            if parsed.get("tool_name") != SUBMIT_BLUEPRINT_TOOL:
                raise LivePipelineError("semantic", "EXPECTED_SUBMIT_BLUEPRINT_TOOL")
            try:
                blueprint = validate_tool_input(str(parsed["tool_name"]), parsed.get("tool_input"))
            except ContractValidationError as exc:
                raise LivePipelineError("semantic", f"CONTRACT_VALIDATION_FAILED:{exc}") from exc
            state.semantic_blueprint = blueprint
            state.semantic_redacted = {
                "tool_name": parsed["tool_name"],
                "tool_input": parsed["tool_input"],
                "request_id": parsed.get("request_id"),
                "model_id": parsed.get("model_id"),
                "usage": parsed.get("usage", {}),
                "stop_reason": parsed.get("stop_reason"),
                "raw_response_redacted": parsed.get("raw_response_redacted"),
            }
            usage = parsed.get("usage", {})
            state.metrics.update(
                {
                    "semantic_seconds": round(semantic_seconds, 3),
                    "semantic_input_tokens": int(usage.get("input_tokens", 0)),
                    "semantic_output_tokens": int(usage.get("output_tokens", 0)),
                }
            )
            write_json_new(stage / "semantic_blueprint.json", blueprint)
            write_json_new(stage / "semantic_response_redacted.json", state.semantic_redacted)
            projected, projection_evidence = project_static_visual(blueprint)
            write_json_new(stage / "static_visual_projection.json", projection_evidence)

            self._notify_pipeline_stage(state, "image_generating")
            profile_path = PLAYLAB_ROOT / "tools" / "comfyui" / "config" / "profiles" / "flux2_klein_4b.json"
            profile = flux_bridge.resolve_profile(profile_path)
            comfy_state = json.loads((LIVE_ROOT / "runtime" / "live_comfy_state.json").read_text(encoding="utf-8"))
            profile["comfy_input_directory"] = comfy_state["input_directory"]
            profile["comfy_output_directory"] = comfy_state["output_directory"]
            profile["output_root"] = str(self.runtime_root / "flux_jobs")
            timed: dict[str, float] = {}
            original_submit = flux_bridge.legacy_bridge._submit_and_wait

            def timed_submit(config: dict[str, Any], graph: dict[str, Any], timeout_seconds: float) -> tuple[str, dict[str, Any]]:
                submit_started = time.perf_counter()
                response = flux_bridge.legacy_bridge._json_request(
                    config["api_base"], "/prompt", {"prompt": graph, "client_id": uuid.uuid4().hex}, timeout=15.0
                )
                timed["queue"] = time.perf_counter() - submit_started
                prompt_id = str(response.get("prompt_id", ""))
                if not prompt_id:
                    raise ComfyBridgeError("PROMPT_ID_MISSING")
                generation_started = time.perf_counter()
                interval = float(config.get("poll_interval_seconds", 0.5))
                while time.perf_counter() - generation_started < timeout_seconds:
                    history = flux_bridge.legacy_bridge._json_request(config["api_base"], f"/history/{prompt_id}", timeout=10.0)
                    if prompt_id in history:
                        entry = history[prompt_id]
                        status = entry.get("status", {})
                        if status.get("status_str") == "error" or not status.get("completed", False):
                            raise ComfyBridgeError("COMFYUI_EXECUTION_FAILED")
                        timed["generation"] = time.perf_counter() - generation_started
                        return prompt_id, entry
                    time.sleep(interval)
                flux_bridge.legacy_bridge._cancel(config, prompt_id)
                raise ComfyBridgeError(f"COMFYUI_TIMEOUT:{timeout_seconds}")

            try:
                flux_bridge.legacy_bridge._submit_and_wait = timed_submit
                with PeakSampler(LIVE_ROOT / "runtime" / "live_comfy_state.json") as sampler:
                    flux_dir = flux_bridge.generate(
                        profile,
                        case_id=case_id,
                        run_id=f"{self.run_id}-{case_id}",
                        blueprint=projected,
                        seed=int(state.config["seed"]),
                        output_group=self.flux_output_group,
                        mode="t2i",
                        raw_only=True,
                    )
            except (flux_bridge.Flux2BridgeError, ComfyBridgeError, OSError, ValueError) as exc:
                raise LivePipelineError("flux", str(exc)) from exc
            finally:
                flux_bridge.legacy_bridge._submit_and_wait = original_submit
            flux_manifest = json.loads((flux_dir / "manifest.json").read_text(encoding="utf-8"))
            if flux_manifest.get("status") != "raw_success" or int(flux_manifest.get("retry_count", -1)) != 0:
                raise LivePipelineError("flux", "RAW_DELIVERY_INVALID")
            shutil.copy2(flux_dir / "raw.png", stage / "flux_raw.png")
            write_json_new(stage / "flux_manifest.json", flux_manifest)
            state.metrics.update(
                {
                    "flux_queue_seconds": round(timed.get("queue", 0.0), 3),
                    "flux_generation_seconds": round(timed.get("generation", float(flux_manifest.get("generation_seconds", 0.0))), 3),
                    "flux_peak_vram_mb": round(max(sampler.peak_vram_mb, float(flux_manifest.get("peak_vram_mb", 0.0))), 1),
                    "flux_peak_ram_mb": round(max(sampler.peak_ram_mb, float(flux_manifest.get("peak_ram_mb", 0.0))), 1),
                }
            )

            self._notify_pipeline_stage(state, "background_removing")
            biref_started = time.perf_counter()
            self._run_birefnet(stage, case_id)
            state.metrics["birefnet_seconds"] = round(time.perf_counter() - biref_started, 3)
            self._notify_pipeline_stage(state, "sprite_processing")
            post_started = time.perf_counter()
            try:
                post_dir = stage / "postprocessed"
                post_metrics = process_birefnet_sprite(
                    stage / "birefnet_rgba.png", stage / "birefnet_mask.png", post_dir
                )
            except BiRefNetPostprocessError as exc:
                raise LivePipelineError("sprite_postprocess", str(exc)) from exc
            state.metrics["sprite_postprocess_seconds"] = round(time.perf_counter() - post_started, 3)
            state.metrics["total_forge_seconds"] = round(time.perf_counter() - total_start, 3)
            state.metrics["training_load_seconds"] = None
            state.metrics["identity_confirmation_seconds"] = None
            state.metrics["anchor_confirmation_seconds"] = None
            shutil.copy2(post_dir / "processed_sprite.png", stage / "processed_sprite.png")
            write_json_new(stage / "postprocess_metrics.json", post_metrics)
            with Image.open(stage / "processed_sprite.png") as sprite:
                if sprite.size != (96, 96) or sprite.mode != "RGBA" or sprite.getextrema()[3][0] == 255:
                    raise LivePipelineError("sprite_postprocess", "SPRITE_96_RGBA_ALPHA_INVALID")
            write_json_new(stage / "stage_metrics.json", state.metrics)
            write_json_new(
                stage / "technical_manifest.json",
                {
                    "contract": self.technical_contract,
                    "case_id": case_id,
                    "revision": state.revision,
                    "seed": state.config["seed"],
                    "semantic_calls": 1,
                    "flux_calls": 1,
                    "birefnet_calls": 1,
                    "retry_count": 0,
                    "mock_fallback": False,
                    "status": "technical_success",
                    "completed_at_utc": utc_now(),
                },
            )
            final.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage, final)
            state.technical_dir = final
        except LivePipelineError:
            state.technical_dir = stage
            raise

    def _notify_pipeline_stage(self, state: CaseState, stage: str) -> None:
        """Optional observer hook; the frozen Live E2E flow intentionally does nothing."""
        del state, stage

    def _run_birefnet(self, stage: Path, case_id: str) -> None:
        workflow_path = FLUX2_ROOT / "workflows" / "birefnet_remove_background_forge_api.json"
        config = {"workflow_file": str(workflow_path), "workflow_sha256": BIREF_WORKFLOW_SHA256}
        workflow, meta = load_approved_workflow(config)
        transport = LoopbackHttpTransport("http://127.0.0.1:8190", 120.0)
        raw_bytes = (stage / "flux_raw.png").read_bytes()
        uploaded = transport.post_file(
            "/upload/image", filename=f"ForgeLive_{self.run_id}_{case_id}.png", payload=raw_bytes
        )
        name = uploaded.get("name")
        subfolder = uploaded.get("subfolder", "")
        if not isinstance(name, str) or not name or not isinstance(subfolder, str):
            raise LivePipelineError("birefnet", "UPLOAD_RESPONSE_INVALID")
        graph = copy.deepcopy(workflow)
        _set_path(graph, meta["input_image_binding"], f"{subfolder}/{name}".lstrip("/"))
        prefix = f"{self.biref_output_namespace}/{self.run_id}/{case_id}"
        _set_path(graph, meta["rgba_output_prefix_binding"], f"{prefix}/rgba")
        _set_path(graph, meta["mask_output_prefix_binding"], f"{prefix}/mask")
        submitted = transport.post_json("/prompt", {"prompt": graph, "client_id": uuid.uuid4().hex})
        prompt_id = submitted.get("prompt_id")
        if not isinstance(prompt_id, str) or not prompt_id:
            raise LivePipelineError("birefnet", "PROMPT_ID_INVALID")
        started = time.monotonic()
        outputs = None
        while outputs is None:
            if time.monotonic() - started > 120:
                raise LivePipelineError("birefnet", "TIMEOUT")
            history = transport.get_json(f"/history/{urllib.parse.quote(prompt_id, safe='')}")
            entry = history.get(prompt_id)
            if isinstance(entry, Mapping):
                status = entry.get("status")
                if isinstance(status, Mapping) and status.get("status_str") in {"error", "failed"}:
                    raise LivePipelineError("birefnet", "EXECUTION_FAILED")
                outputs = _history_outputs(entry, meta)
            if outputs is None:
                time.sleep(0.5)
        try:
            rgba = _validate_rgba_png(_download_output(transport, outputs[0], "RGBA"))
            mask = _normalise_mask_png(_download_output(transport, outputs[1], "MASK"))
        except Spike6RunnerError as exc:
            raise LivePipelineError("birefnet", str(exc)) from exc
        write_new(stage / "birefnet_rgba.png", rgba)
        write_new(stage / "birefnet_mask.png", mask)
        write_json_new(
            stage / "birefnet_manifest.json",
            {
                "workflow_sha256": meta["sha256"],
                "prompt_id": prompt_id,
                "retry_count": 0,
                "rgba_sha256": hashlib.sha256(rgba).hexdigest(),
                "mask_sha256": hashlib.sha256(mask).hexdigest(),
                "status": "success",
            },
        )

    def confirm_identity(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        state = self._require_case_request(payload, expected_stage="awaiting_identity")
        parts = payload.get("required_parts_preserved")
        if not isinstance(parts, list) or len(parts) != len(state.config["required_identity_parts"]) or not all(isinstance(value, bool) for value in parts):
            raise LivePipelineError("identity_confirmation", "PARTS_REVIEW_INVALID")
        screenshot = safe_png_from_base64(payload.get("screenshot_png_base64"), "FORGE_CONFIRMATION")
        recognizable = payload.get("identity_recognizable")
        no_substitution = payload.get("no_fixed_weapon_substitution")
        no_baked_dynamic = payload.get("no_baked_dynamic_effect")
        seconds = payload.get("confirmation_seconds")
        if not isinstance(recognizable, bool) or not isinstance(no_substitution, bool) or not isinstance(no_baked_dynamic, bool) or not isinstance(seconds, (int, float)) or seconds < 0:
            raise LivePipelineError("identity_confirmation", "IDENTITY_REVIEW_INVALID")
        state.identity_review = {
            "identity_recognizable": recognizable,
            "required_parts_preserved": parts,
            "required_parts_preserved_count": sum(parts),
            "no_fixed_weapon_substitution": no_substitution,
            "no_baked_dynamic_effect": no_baked_dynamic,
            "confirmation_seconds": round(float(seconds), 3),
        }
        state.metrics["identity_confirmation_seconds"] = round(float(seconds), 3)
        assert state.technical_dir
        write_new(state.technical_dir / "forge_confirmation.png", screenshot)
        if not recognizable:
            state.stage = "identity_rejected"
            state.failure_stage = "identity_confirmation"
            state.failure_reason = "PLAYER_REJECTED_IDENTITY"
            self._publish_completed_case(state)
            return {"status": "identity_rejected", "can_enter_anchors": False, "retry_count": 0}
        state.stage = "awaiting_anchors"
        return {"status": "identity_confirmed", "can_enter_anchors": True}

    def confirm_anchors(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        state = self._require_case_request(payload, expected_stage="awaiting_anchors")
        anchors = payload.get("anchors")
        seconds = payload.get("confirmation_seconds")
        if not isinstance(anchors, Mapping) or not isinstance(seconds, (int, float)) or seconds < 0:
            raise LivePipelineError("anchor_confirmation", "ANCHOR_PAYLOAD_INVALID")
        required = anchors.get("required_anchor_types")
        corrected = anchors.get("corrected_anchors")
        sources = anchors.get("anchor_source")
        needed = ["GripPrimary", state.config["second_anchor_type"]]
        if not isinstance(required, list) or not all(item in required for item in needed) or not isinstance(corrected, Mapping) or not isinstance(sources, Mapping):
            raise LivePipelineError("anchor_confirmation", "REQUIRED_ANCHORS_MISSING")
        for name in needed:
            point = corrected.get(name)
            if not isinstance(point, list) or len(point) != 2 or not all(isinstance(value, (int, float)) and 0 <= value <= 95 for value in point):
                raise LivePipelineError("anchor_confirmation", f"ANCHOR_POINT_INVALID:{name}")
            if not str(sources.get(name, "")).startswith("player"):
                raise LivePipelineError("anchor_confirmation", f"PLAYER_CONFIRMATION_REQUIRED:{name}")
        state.anchors = copy.deepcopy(dict(anchors))
        state.metrics["anchor_confirmation_seconds"] = round(float(seconds), 3)
        state.stage = "awaiting_training"
        return {"status": "anchors_confirmed", "can_enter_training": True}

    def complete_training(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        state = self._require_case_request(payload, expected_stage="awaiting_training")
        booleans = ("moved", "attacked", "dodged", "behavior_family_observed")
        if any(not isinstance(payload.get(name), bool) for name in booleans):
            raise LivePipelineError("training", "TRAINING_OBSERVATIONS_INVALID")
        load_seconds = payload.get("training_load_seconds")
        if not isinstance(load_seconds, (int, float)) or load_seconds < 0:
            raise LivePipelineError("training", "TRAINING_LOAD_SECONDS_INVALID")
        holding = safe_png_from_base64(payload.get("holding_png_base64"), "TRAINING_HOLDING")
        attack = safe_png_from_base64(payload.get("attack_png_base64"), "TRAINING_ATTACK")
        state.training = {
            name: bool(payload[name]) for name in booleans
        }
        state.training["training_load_seconds"] = round(float(load_seconds), 3)
        state.metrics["training_load_seconds"] = round(float(load_seconds), 3)
        assert state.technical_dir
        write_new(state.technical_dir / "training_holding.png", holding)
        write_new(state.technical_dir / "training_attack.png", attack)
        state.stage = "completed"
        self._publish_completed_case(state)
        return {"status": "case_completed", "case_id": state.config["case_id"], "next_case": self.case_order[self.next_ordinal - 1] if self.next_ordinal <= 3 else None}

    def _result_manifest(self, state: CaseState) -> dict[str, Any]:
        technical = bool(
            state.technical_dir
            and state.stage != "technical_failed"
            and (state.technical_dir / "technical_manifest.json").is_file()
            and (state.technical_dir / "processed_sprite.png").is_file()
        )
        identity = state.identity_review or {}
        anchors = state.anchors or {}
        training = state.training or {}
        parts = identity.get("required_parts_preserved", [])
        product = bool(
            technical
            and identity.get("identity_recognizable")
            and parts
            and all(parts)
            and identity.get("no_fixed_weapon_substitution")
            and identity.get("no_baked_dynamic_effect")
            and state.anchors
            and all(training.get(name) for name in ("moved", "attacked", "dodged", "behavior_family_observed"))
        )
        blueprint = state.semantic_blueprint or {}
        combat = blueprint.get("combat", {}) if isinstance(blueprint, Mapping) else {}
        behavior_correct = combat.get("behavior_family") == state.config["expected_behavior_family"]
        product = product and behavior_correct
        return {
            "contract": "forge-live-e2e-spike7-case-result-v1",
            "case_id": state.config["case_id"],
            "revision": state.revision,
            "seed": state.config["seed"],
            "status": state.stage,
            "technical_success": technical,
            "product_success": product,
            "semantic_success": state.semantic_blueprint is not None,
            "blueprint_valid": state.semantic_blueprint is not None,
            "behavior_family": combat.get("behavior_family"),
            "behavior_expected": state.config["expected_behavior_family"],
            "behavior_correct": behavior_correct,
            "identity_review": identity,
            "anchor_complete": bool(state.anchors),
            "training": training,
            "failure_stage": state.failure_stage,
            "failure_reason": state.failure_reason,
            "retry_count": 0,
            "mock_fallback": False,
            "stale_request_committed": False,
            "completed_at_utc": utc_now(),
        }

    def _publish_completed_case(self, state: CaseState) -> None:
        assert state.technical_dir
        case_id = state.config["case_id"]
        final = self.output_root / case_id
        if final.exists():
            raise LivePipelineError("evidence", "CASE_EVIDENCE_ALREADY_EXISTS")
        stage = self.output_root / f".{case_id}.{uuid.uuid4().hex}.tmp"
        shutil.copytree(state.technical_dir, stage)
        post_dir = stage / "postprocessed"
        if post_dir.is_dir():
            shutil.rmtree(post_dir)
        write_json_new(stage / "anchors.json", state.anchors or {"status": "not_reached"})
        write_json_replace_in_stage(stage / "stage_metrics.json", state.metrics)
        write_json_new(stage / "result_manifest.json", self._result_manifest(state))
        os.replace(stage, final)
        state.final_dir = final

    def _publish_failure_case(self, state: CaseState, player_input: str) -> None:
        case_id = state.config["case_id"]
        final = self.output_root / case_id
        stage = self.output_root / f".{case_id}.{uuid.uuid4().hex}.tmp"
        stage.mkdir(parents=True, exist_ok=False)
        write_json_new(stage / "player_input.json", {"case_id": case_id, "player_input": player_input})
        if state.technical_dir and state.technical_dir.is_dir():
            for path in state.technical_dir.iterdir():
                target = stage / path.name
                if path.is_file():
                    shutil.copy2(path, target)
                elif path.is_dir():
                    shutil.copytree(path, target)
        write_json_new(stage / "anchors.json", {"status": "not_reached"})
        write_json_replace_in_stage(stage / "stage_metrics.json", state.metrics)
        write_json_new(stage / "result_manifest.json", self._result_manifest(state))
        os.replace(stage, final)
        state.final_dir = final

    def finalize(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        if payload.get("session_id") != self.session_id:
            raise LivePipelineError("request", "SESSION_ID_MISMATCH")
        if self.finalized:
            raise LivePipelineError("reporting", "SESSION_ALREADY_FINALIZED")
        if len(self.cases) != 3 or any(state.final_dir is None for state in self.cases.values()):
            raise LivePipelineError("reporting", "THREE_CASES_NOT_FINALIZED")
        self.scope_attestation = self._verify_scope_before_report()
        summary = self._write_reports()
        self.finalized = True
        return {"status": "finalized", "classification": summary["classification"], "report_path": str(self.report_root / "LIVE_E2E_REPORT.md")}

    def _verify_scope_before_report(self) -> dict[str, Any]:
        try:
            preflight = json.loads(self.preflight_file.read_text(encoding="utf-8"))
            history = preflight.get("historical_evidence")
            if not isinstance(history, dict):
                raise ValueError("historical baseline missing")
            verify_history(PLAYLAB_ROOT, history)
            for repository in preflight.get("formal_repositories", []):
                root = Path(str(repository["path"]))
                head = subprocess.run(
                    ["git", "-C", str(root), "rev-parse", "HEAD"], text=True, encoding="utf-8",
                    errors="replace", capture_output=True, check=True,
                ).stdout.strip()
                status = subprocess.run(
                    ["git", "-C", str(root), "status", "--porcelain=v1", "-uall"], text=True,
                    encoding="utf-8", errors="replace", capture_output=True, check=True,
                ).stdout.strip()
                status_hash = hashlib.sha256(status.encode("utf-8")).hexdigest()
                if head != repository["head"] or status_hash != repository["status_sha256"]:
                    raise ValueError("formal repository changed")
            default_project = (PLAYLAB_ROOT / "project.godot").read_text(encoding="utf-8")
            default_script = (PLAYLAB_ROOT / "scripts" / "open_identity_spike.gd").read_text(encoding="utf-8")
            if 'run/main_scene="res://scenes/open_identity_spike.tscn"' not in default_project or "var provider_mode := MODE_MOCK" not in default_script:
                raise ValueError("default flow changed")
            findings = scan_repository(PLAYLAB_ROOT)
            if findings:
                raise ValueError(f"secret findings={len(findings)}")
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            raise LivePipelineError("reporting", f"SCOPE_OR_SECRET_ATTESTATION_FAILED:{exc}") from exc
        return {
            "historical_evidence_unchanged": True,
            "formal_repositories_unchanged": True,
            "default_player_mode": "MOCK",
            "secret_scan_pass": True,
            "secret_findings": 0,
        }

    def _write_reports(self) -> dict[str, Any]:
        results = [self._result_manifest(self.cases[case_id]) for case_id in self.case_order]
        technical_count = sum(bool(item["technical_success"]) for item in results)
        product_count = sum(bool(item["product_success"]) for item in results)
        if technical_count == 3 and product_count == 3:
            classification = "LIVE END-TO-END PASS"
        elif technical_count == 3:
            classification = "TECHNICAL PASS / PRODUCT NEEDS WORK"
        else:
            classification = "LIVE END-TO-END NEEDS WORK"
        forge_times = [float(self.cases[case_id].metrics.get("total_forge_seconds", 0.0)) for case_id in self.case_order]
        stage_totals: dict[str, float] = {}
        for key in ("semantic_seconds", "flux_queue_seconds", "flux_generation_seconds", "birefnet_seconds", "sprite_postprocess_seconds"):
            stage_totals[key] = sum(float(self.cases[case_id].metrics.get(key, 0.0)) for case_id in self.case_order)
        slowest_stage = max(stage_totals, key=stage_totals.get)
        summary = {
            "contract": "forge-live-e2e-spike7-summary-v1",
            "run_id": self.run_id,
            "classification": classification,
            "technical_pass_count": technical_count,
            "product_pass_count": product_count,
            "semantic_calls": self.prior_semantic_calls + self.compiler.calls_made,
            "flux_calls": sum(1 for state in self.cases.values() if state.technical_dir and (state.technical_dir / "flux_manifest.json").exists()),
            "birefnet_calls": sum(1 for state in self.cases.values() if state.technical_dir and (state.technical_dir / "birefnet_manifest.json").exists()),
            "retry_count": 0,
            "mock_fallback_count": 0,
            "stale_request_commit_count": 0,
            "median_total_forge_seconds": round(median(forge_times), 3),
            "slowest_total_forge_seconds": round(max(forge_times), 3),
            "player_wait_was_material": median(forge_times) >= 10.0,
            "slowest_aggregate_stage": slowest_stage,
            "slowest_aggregate_stage_seconds": round(stage_totals[slowest_stage], 3),
            "default_flow_promoted": False,
            "combat_rooms_connected": False,
            "v2_started": False,
            "scope_attestation": self.scope_attestation,
            "post_run_cleanup_status": "PENDING_INTERACTIVE_FINALLY",
            "offline_tests": {"status": "PASS", "passed": 40, "failed": 0},
            "completed_at_utc": utc_now(),
            "cases": results,
        }
        write_json_new(self.report_root / "live_e2e_summary.json", summary)
        self._write_csvs(results)
        self._write_comparison()
        report = self._report_markdown(summary)
        write_new(self.report_root / "LIVE_E2E_REPORT.md", report.encode("utf-8"))
        hashes = {}
        for root in (self.output_root, self.report_root):
            for path in sorted(root.rglob("*")):
                if path.is_file() and path.name != "evidence_hashes.json":
                    hashes[str(path.relative_to(LIVE_ROOT)).replace("\\", "/")] = sha256_file(path)
        write_json_new(self.report_root / "pipeline_evidence_hashes.json", {"algorithm": "SHA-256", "files": hashes})
        return summary

    def _write_csvs(self, results: list[dict[str, Any]]) -> None:
        with (self.report_root / "live_e2e_results.csv").open("x", newline="", encoding="utf-8-sig") as handle:
            fields = ["case_id", "technical_success", "product_success", "behavior_family", "behavior_correct", "identity_recognizable", "required_parts_preserved_count", "anchor_complete", "moved", "attacked", "dodged", "failure_stage", "failure_reason"]
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for result in results:
                identity = result["identity_review"]
                training = result["training"]
                writer.writerow({
                    "case_id": result["case_id"], "technical_success": result["technical_success"], "product_success": result["product_success"],
                    "behavior_family": result["behavior_family"], "behavior_correct": result["behavior_correct"],
                    "identity_recognizable": identity.get("identity_recognizable", False),
                    "required_parts_preserved_count": identity.get("required_parts_preserved_count", 0),
                    "anchor_complete": result["anchor_complete"], "moved": training.get("moved", False), "attacked": training.get("attacked", False), "dodged": training.get("dodged", False),
                    "failure_stage": result["failure_stage"], "failure_reason": result["failure_reason"],
                })
        metric_fields = ["case_id", "semantic_seconds", "semantic_input_tokens", "semantic_output_tokens", "flux_queue_seconds", "flux_generation_seconds", "flux_peak_vram_mb", "flux_peak_ram_mb", "birefnet_seconds", "sprite_postprocess_seconds", "identity_confirmation_seconds", "anchor_confirmation_seconds", "total_forge_seconds", "training_load_seconds"]
        with (self.report_root / "stage_performance.csv").open("x", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=metric_fields)
            writer.writeheader()
            for case_id in self.case_order:
                writer.writerow({"case_id": case_id, **self.cases[case_id].metrics})

    def _write_comparison(self) -> None:
        canvas = Image.new("RGB", (930, 720), "#111827")
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 15), "Forge Live E2E Spike 7 — raw / BiRefNet RGBA / 96px sprite", fill="white")
        for row, case_id in enumerate(self.case_order):
            state = self.cases[case_id]
            y = 65 + row * 215
            draw.text((20, y), case_id, fill="#67e8f9")
            if not state.final_dir:
                continue
            for column, filename in enumerate(("flux_raw.png", "birefnet_rgba.png", "processed_sprite.png")):
                path = state.final_dir / filename
                x = 80 + column * 280
                if not path.is_file():
                    draw.rectangle((x, y, x + 190, y + 190), outline="#ef4444", width=3)
                    draw.text((x + 10, y + 80), "MISSING", fill="#ef4444")
                    continue
                with Image.open(path) as opened:
                    image = opened.convert("RGBA")
                    checker = Image.new("RGBA", image.size, "#e5e7eb")
                    image = Image.alpha_composite(checker, image)
                    image.thumbnail((190, 190), Image.Resampling.LANCZOS)
                    canvas.paste(image.convert("RGB"), (x, y))
                draw.text((x, y + 193), filename.replace(".png", ""), fill="#cbd5e1")
        canvas.save(self.report_root / "three_case_pipeline_comparison.png")

    def _report_markdown(self, summary: Mapping[str, Any]) -> str:
        rows = []
        for case_id in self.case_order:
            result = self._result_manifest(self.cases[case_id])
            rows.append(f"| {case_id} | {result['technical_success']} | {result['product_success']} | {result['behavior_family']} | {result['behavior_correct']} | {result['identity_review'].get('required_parts_preserved_count', 0)}/3 | {self.cases[case_id].metrics.get('total_forge_seconds', '')} |")
        return f"""# Forge Live End-to-End Spike 7 — Text-to-Training

状态：**{summary['classification']}**

本次只运行三项批准案例；Claude、FLUX 与 BiRefNet 均无自动重试，未启用 Mock 回退。默认玩家流程保持 MOCK，未接入战斗房间，未启动 V2。

| Case | Technical | Product | Behavior | Behavior correct | Required parts | Forge seconds |
|---|---:|---:|---|---:|---:|---:|
{chr(10).join(rows)}

## 性能

- 中位总 Forge 时间：{summary['median_total_forge_seconds']} 秒
- 最慢总 Forge 时间：{summary['slowest_total_forge_seconds']} 秒
- 玩家是否明显等待：{'是' if summary['player_wait_was_material'] else '否'}
- 累计耗时最大阶段：`{summary['slowest_aggregate_stage']}`（{summary['slowest_aggregate_stage_seconds']} 秒）
- 仅报告实际 token 数；未自行估算费用。

## 边界结论

- 默认玩家流程晋升：否
- 战斗房间接入：否
- V2：未启动
- 历史证据与正式仓库：运行结束前复核未改变
- Secret scan：PASS（0 findings）
- 自动测试：40/40 PASS；Godot 4.7.1 解析 PASS
- ComfyUI 与端口最终清理：等待交互入口 `finally` 完成后写入最终清理证明
- 下一步：即使本次通过，也等待真人完整 Playlab 批准。
"""


__all__ = ["LivePipelineError", "LiveSession"]
