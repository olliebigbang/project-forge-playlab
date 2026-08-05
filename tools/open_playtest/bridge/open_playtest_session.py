#!/usr/bin/env python3
"""Stateful, local-only Open Playtest orchestration.

The real model chain is inherited from the frozen Live E2E implementation.  This
adapter changes only case scheduling, status reporting and local playtest logs;
it never adds object mappings, prompt branches, retries or a Mock fallback.
"""

from __future__ import annotations

import base64
import copy
import csv
import hashlib
import json
import os
import re
import shutil
import sys
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping


BRIDGE_DIR = Path(__file__).resolve().parent
OPEN_ROOT = BRIDGE_DIR.parent
PLAYLAB_ROOT = OPEN_ROOT.parents[1]
LIVE_BRIDGE = PLAYLAB_ROOT / "tools" / "live_e2e" / "bridge"
if str(LIVE_BRIDGE) not in sys.path:
    sys.path.insert(0, str(LIVE_BRIDGE))

import live_orchestrator as live  # noqa: E402


OPEN_CONTRACT = "forge-open-playtest-mode-v1"
TERMINAL_STAGES = frozenset({"identity_rejected", "completed", "failed"})
PIPELINE_STAGES = (
    "semantic_compiling",
    "image_generating",
    "background_removing",
    "sprite_processing",
    "confirm_identity",
    "confirm_anchors",
    "ready_in_training_zone",
)
BEHAVIOR_ANCHORS = {
    "sustained_ranged": ("EffectOrigin", "力量从哪里发出？"),
    "returning_thrown": ("SpinPivot", "它应该围绕哪里旋转？"),
    "heavy_melee": ("StrikePoint", "你想用哪一部分击中目标？"),
}
HISTORY_FIELDS = [
    "timestamp",
    "session_id",
    "round_id",
    "revision",
    "user_input",
    "semantic_summary",
    "behavior_family",
    "canonical_identity",
    "display_name",
    "raw_image_path",
    "processed_sprite_path",
    "identity_confirmed",
    "anchor_confirmed",
    "entered_training",
    "user_notes",
    "subjective_rating",
    "keep_idea",
    "saved_locally",
    "total_forge_seconds",
    "stage_timings_json",
    "status",
    "failure_stage",
    "failure_reason",
]


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _atomic_replace(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"
    with temporary.open("xb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def _relative(path: Path) -> str:
    return path.resolve().relative_to(PLAYLAB_ROOT.resolve()).as_posix()


def _normalise_notes(value: Any, *, maximum: int = 1000) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise live.LivePipelineError("request", "NOTES_MUST_BE_TEXT")
    return value.strip()[:maximum]


def _valid_request_id(value: Any) -> bool:
    return isinstance(value, str) and bool(re.fullmatch(r"[A-Za-z0-9_-]{8,100}", value))


class ClarificationAwareCompiler:
    """Preserve the one-call contract while surfacing the model's one question."""

    def __init__(self, delegate: Any) -> None:
        self.delegate = delegate

    @property
    def calls_made(self) -> int:
        return int(self.delegate.calls_made)

    def compile(self, player_input: str) -> dict[str, Any]:
        parsed = self.delegate.compile(player_input)
        if parsed.get("tool_name") == "request_forge_clarification":
            try:
                clarification = live.validate_tool_input(
                    str(parsed["tool_name"]), parsed.get("tool_input")
                )
            except live.ContractValidationError as exc:
                raise live.SemanticCompilerError(
                    "CLARIFICATION_CONTRACT_INVALID", str(exc)
                ) from exc
            question = str(clarification.get("question_zh", "")).strip()
            raise live.SemanticCompilerError(
                f"CLARIFICATION_REQUIRED:{question}",
                "The model requested one player clarification.",
            )
        return parsed


class LocalHistoryStore:
    """Atomic JSON/CSV persistence.  The UI exposes only the latest ten rows."""

    def __init__(self, root: Path, history_limit: int = 200) -> None:
        self.root = root
        self.json_path = root / "playtest_history.json"
        self.csv_path = root / "playtest_history.csv"
        self.history_limit = history_limit
        self.lock = threading.RLock()
        self.records: list[dict[str, Any]] = []
        if self.json_path.is_file():
            loaded = json.loads(self.json_path.read_text(encoding="utf-8"))
            if not isinstance(loaded, Mapping) or not isinstance(loaded.get("records"), list):
                raise live.LivePipelineError("history", "LOCAL_HISTORY_INVALID")
            self.records = [dict(item) for item in loaded["records"] if isinstance(item, Mapping)]

    def upsert(self, record: Mapping[str, Any]) -> None:
        with self.lock:
            round_id = record.get("round_id")
            self.records = [item for item in self.records if item.get("round_id") != round_id]
            self.records.append(copy.deepcopy(dict(record)))
            self.records = self.records[-self.history_limit :]
            self._flush()

    def recent(self, limit: int) -> list[dict[str, Any]]:
        with self.lock:
            return copy.deepcopy(list(reversed(self.records[-limit:])))

    def _flush(self) -> None:
        document = {
            "contract": "forge-open-playtest-local-history-v1",
            "updated_at_utc": live.utc_now(),
            "records": self.records,
        }
        _atomic_replace(self.json_path, _json_bytes(document))
        temporary = self.csv_path.parent / f".{self.csv_path.name}.{uuid.uuid4().hex}.tmp"
        temporary.parent.mkdir(parents=True, exist_ok=True)
        with temporary.open("x", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=HISTORY_FIELDS, extrasaction="ignore")
            writer.writeheader()
            for source in self.records:
                row = copy.deepcopy(source)
                row["stage_timings_json"] = json.dumps(
                    row.get("stage_timings", {}), ensure_ascii=False, separators=(",", ":")
                )
                writer.writerow(row)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, self.csv_path)


@dataclass
class OpenRound:
    state: live.CaseState
    player_input: str
    client_request_id: str
    started_at_utc: str
    started_monotonic: float
    stage_started_monotonic: float
    stage_timings: dict[str, float] = field(default_factory=dict)
    output_dir: Path | None = None
    user_notes: str = ""
    subjective_rating: int | None = None
    keep_idea: bool | None = None
    saved_locally: bool = False


class OpenPlaytestSession(live.LiveSession):
    """One explicit local session supporting sequential arbitrary inputs."""

    def __init__(self, *, session_id: str, preflight_file: Path, config_file: Path) -> None:
        self.config = json.loads(config_file.read_text(encoding="utf-8"))
        if self.config.get("contract") != OPEN_CONTRACT:
            raise live.LivePipelineError("preflight", "OPEN_CONFIG_CONTRACT_INVALID")
        if self.config.get("default_player_mode") != "MOCK" or self.config.get("mock_fallback") is not False:
            raise live.LivePipelineError("preflight", "OPEN_MODE_BOUNDARY_INVALID")
        if int(self.config.get("retry_limit", -1)) != 0:
            raise live.LivePipelineError("preflight", "RETRY_MUST_BE_DISABLED")
        if not 1 <= int(self.config.get("session_call_limit", 0)) <= 20:
            raise live.LivePipelineError("preflight", "SESSION_CALL_LIMIT_INVALID")
        if self.config.get("approved_model_id") != "claude-sonnet-5":
            raise live.LivePipelineError("preflight", "MODEL_ID_CHANGED")
        if self.config.get("semantic_contract") != "forge-semantic-v1.1":
            raise live.LivePipelineError("preflight", "SEMANTIC_CONTRACT_CHANGED")
        if self.config.get("bridge_base") != "http://127.0.0.1:8771" or self.config.get("comfyui_base") != "http://127.0.0.1:8190":
            raise live.LivePipelineError("preflight", "LOOPBACK_CONFIG_INVALID")
        if self.config.get("training_only") is not True or self.config.get("sketch_enabled") is not False:
            raise live.LivePipelineError("preflight", "PLAYTEST_SCOPE_INVALID")
        if self.config.get("providers") != ["Claude", "FLUX.2 Klein 4B", "BiRefNet"]:
            raise live.LivePipelineError("preflight", "PROVIDER_SET_CHANGED")
        preflight = json.loads(preflight_file.read_text(encoding="utf-8"))
        if (
            preflight.get("status") != "PASS"
            or preflight.get("model_id") != "claude-sonnet-5"
            or preflight.get("semantic_contract") != "forge-semantic-v1.1"
            or preflight.get("default_player_mode") != "MOCK"
        ):
            raise live.LivePipelineError("preflight", "PREFLIGHT_EVIDENCE_INVALID")
        self.session_id = session_id
        self.run_id = session_id
        self.preflight_file = preflight_file.resolve()
        self.runtime_root = OPEN_ROOT / "runtime" / session_id
        self.pipeline_root = self.runtime_root / "pipeline"
        self.output_root = OPEN_ROOT / "output" / "sessions" / session_id
        self.report_root = self.output_root
        self.output_root.mkdir(parents=True, exist_ok=False)
        self.runtime_root.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.revision = 0
        self.rounds: dict[str, OpenRound] = {}
        self.active_round_id: str | None = None
        self.request_ids: set[str] = set()
        base_compiler = live.AnthropicSemanticCompiler(
            system_prompt=(live.SEMANTIC_ROOT / "prompts" / "semantic_compiler_system_prompt.md").read_text(encoding="utf-8"),
            blueprint_schema=live.FORGE_SEMANTIC_BLUEPRINT_SCHEMA,
            clarification_schema=live.CLARIFICATION_REQUEST_SCHEMA,
            call_limiter=live.CallLimiter(max_calls=int(self.config["session_call_limit"])),
        )
        self.compiler = ClarificationAwareCompiler(base_compiler)
        self.technical_contract = "forge-open-playtest-technical-v1"
        self.flux_output_group = "open_playtest_stage"
        self.biref_output_namespace = "ForgeOpenPlaytest"
        self.history = LocalHistoryStore(
            OPEN_ROOT / "local_history", int(self.config.get("history_limit", 200))
        )
        live.write_json_new(
            self.output_root / "session_manifest.json",
            {
                "contract": OPEN_CONTRACT,
                "session_id": session_id,
                "started_at_utc": live.utc_now(),
                "mode": "OPEN PLAYTEST MODE",
                "default_player_mode": "MOCK",
                "explicit_launch_required": True,
                "model_id": self.config["approved_model_id"],
                "providers": self.config["providers"],
                "retry_limit": 0,
                "mock_fallback": False,
                "training_only": True,
                "preflight_file": str(self.preflight_file),
                "preflight_sha256": live.sha256_file(self.preflight_file),
            },
        )

    def health(self) -> dict[str, Any]:
        return {
            "status": "ok",
            "contract": OPEN_CONTRACT,
            "session_id": self.session_id,
            "mode": "OPEN PLAYTEST MODE",
            "providers": self.config["providers"],
            "calls_made": self.compiler.calls_made,
            "call_limit": self.config["session_call_limit"],
            "retry_limit": 0,
            "mock_fallback": False,
            "default_player_mode": "MOCK",
        }

    def _notify_pipeline_stage(self, state: live.CaseState, stage: str) -> None:
        with self.lock:
            open_round = self.rounds.get(str(state.config["case_id"]))
            if open_round is None or open_round.state.revision != state.revision:
                return
            now = time.monotonic()
            previous = open_round.state.stage
            if previous in PIPELINE_STAGES:
                open_round.stage_timings[previous] = round(
                    open_round.stage_timings.get(previous, 0.0)
                    + now - open_round.stage_started_monotonic,
                    3,
                )
            open_round.state.stage = stage
            open_round.stage_started_monotonic = now

    def start_round(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            self._require_session(payload)
            request_id = payload.get("client_request_id")
            if not _valid_request_id(request_id):
                raise live.LivePipelineError("request", "CLIENT_REQUEST_ID_INVALID")
            if request_id in self.request_ids:
                raise live.LivePipelineError("request", "DUPLICATE_REQUEST_REJECTED")
            if self.active_round_id:
                active = self.rounds[self.active_round_id]
                if active.state.stage not in TERMINAL_STAGES:
                    raise live.LivePipelineError("request", "ROUND_IN_PROGRESS")
            player_input = payload.get("player_input")
            if not isinstance(player_input, str):
                raise live.LivePipelineError("request", "PLAYER_INPUT_MUST_BE_TEXT")
            player_input = player_input.strip()
            if not player_input:
                raise live.LivePipelineError("request", "PLAYER_INPUT_EMPTY")
            if len(player_input) > int(self.config["input_max_characters"]):
                raise live.LivePipelineError("request", "PLAYER_INPUT_TOO_LONG")
            self.revision += 1
            round_id = f"R{self.revision:04d}-{uuid.uuid4().hex[:8]}"
            seed = int.from_bytes(os.urandom(4), "big") & 0x7FFFFFFF
            state = live.CaseState(
                config={"case_id": round_id, "seed": seed},
                revision=self.revision,
                stage="semantic_compiling",
            )
            now = time.monotonic()
            open_round = OpenRound(
                state=state,
                player_input=player_input,
                client_request_id=str(request_id),
                started_at_utc=live.utc_now(),
                started_monotonic=now,
                stage_started_monotonic=now,
            )
            self.rounds[round_id] = open_round
            self.request_ids.add(str(request_id))
            self.active_round_id = round_id
            self._upsert_history(open_round)
            worker = threading.Thread(
                target=self._execute_round, args=(round_id,), daemon=True,
                name=f"open-forge-{round_id}",
            )
            worker.start()
            return {
                "status": "accepted",
                "round_id": round_id,
                "revision": state.revision,
                "stage": state.stage,
                "retry_count": 0,
                "mock_fallback": False,
            }

    def _execute_round(self, round_id: str) -> None:
        open_round = self.rounds[round_id]
        state = open_round.state
        try:
            self._run_technical(state, open_round.player_input)
            assert state.semantic_blueprint is not None
            identity = state.semantic_blueprint["identity"]
            combat = state.semantic_blueprint["combat"]
            family = str(combat["behavior_family"])
            if family not in BEHAVIOR_ANCHORS:
                raise live.LivePipelineError("semantic", f"BEHAVIOR_FAMILY_UNSUPPORTED:{family}")
            second_anchor, question = BEHAVIOR_ANCHORS[family]
            parts = identity.get("required_identity_parts")
            if not isinstance(parts, list) or len(parts) < 2:
                raise live.LivePipelineError("semantic", "REQUIRED_IDENTITY_PARTS_INVALID")
            state.config.update(
                {
                    "required_identity_parts": [str(item) for item in parts],
                    "second_anchor_type": second_anchor,
                    "second_anchor_question": question,
                    "expected_behavior_family": family,
                }
            )
            self._finish_observed_stage(open_round)
            state.stage = "confirm_identity"
            self._publish_technical(open_round)
        except live.LivePipelineError as exc:
            self._finish_observed_stage(open_round)
            state.stage = "failed"
            state.failure_stage = exc.stage
            state.failure_reason = exc.code
            self._publish_failure(open_round)
        except Exception as exc:  # fail closed without exposing secrets
            self._finish_observed_stage(open_round)
            state.stage = "failed"
            state.failure_stage = "internal"
            state.failure_reason = f"UNEXPECTED_{type(exc).__name__.upper()}"
            self._publish_failure(open_round)
        finally:
            self._upsert_history(open_round)

    def _finish_observed_stage(self, open_round: OpenRound) -> None:
        now = time.monotonic()
        stage = open_round.state.stage
        if stage in PIPELINE_STAGES:
            open_round.stage_timings[stage] = round(
                open_round.stage_timings.get(stage, 0.0)
                + now - open_round.stage_started_monotonic,
                3,
            )
        open_round.stage_started_monotonic = now

    def round_status(self, query: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            self._require_session(query)
            open_round = self._require_round(query)
            state = open_round.state
            response: dict[str, Any] = {
                "status": "failed" if state.stage == "failed" else "ok",
                "round_id": state.config["case_id"],
                "revision": state.revision,
                "stage": state.stage,
                "player_input": open_round.player_input,
                "failure_stage": state.failure_stage,
                "failure_reason": state.failure_reason,
                "retry_count": 0,
                "mock_fallback": False,
            }
            if state.stage in {"confirm_identity", "confirm_anchors", "ready_in_training_zone", "completed", "identity_rejected"}:
                response.update(self._result_payload(open_round))
            return response

    def confirm_identity(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            open_round = self._require_action(payload, "confirm_identity")
            confirmed = payload.get("identity_confirmed")
            if not isinstance(confirmed, bool):
                raise live.LivePipelineError("identity_confirmation", "IDENTITY_CONFIRMATION_INVALID")
            open_round.user_notes = _normalise_notes(payload.get("user_notes"))
            open_round.state.identity_review = {
                "identity_confirmed": confirmed,
                "user_notes": open_round.user_notes,
                "confirmed_at_utc": live.utc_now(),
            }
            self._write_round_json(open_round, "identity_review.json", open_round.state.identity_review)
            if confirmed:
                open_round.state.stage = "confirm_anchors"
                status = "identity_confirmed"
            else:
                open_round.state.stage = "identity_rejected"
                open_round.state.failure_stage = "identity_confirmation"
                open_round.state.failure_reason = "PLAYER_REJECTED_IDENTITY"
                status = "identity_rejected"
            self._write_round_state(open_round)
            self._upsert_history(open_round)
            return {"status": status, "can_enter_anchors": confirmed}

    def confirm_anchors(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            open_round = self._require_action(payload, "confirm_anchors")
            anchors = payload.get("anchors")
            if not isinstance(anchors, Mapping):
                raise live.LivePipelineError("anchor_confirmation", "ANCHOR_PAYLOAD_INVALID")
            needed = ["GripPrimary", open_round.state.config["second_anchor_type"]]
            corrected = anchors.get("corrected_anchors")
            sources = anchors.get("anchor_source")
            required = anchors.get("required_anchor_types")
            if not isinstance(required, list) or not all(item in required for item in needed):
                raise live.LivePipelineError("anchor_confirmation", "REQUIRED_ANCHORS_MISSING")
            if not isinstance(corrected, Mapping) or not isinstance(sources, Mapping):
                raise live.LivePipelineError("anchor_confirmation", "ANCHOR_PAYLOAD_INVALID")
            for name in needed:
                point = corrected.get(name)
                if not isinstance(point, list) or len(point) != 2 or not all(
                    isinstance(value, (int, float)) and 0 <= value <= 95 for value in point
                ):
                    raise live.LivePipelineError("anchor_confirmation", f"ANCHOR_POINT_INVALID:{name}")
                if not str(sources.get(name, "")).startswith("player"):
                    raise live.LivePipelineError("anchor_confirmation", f"PLAYER_CONFIRMATION_REQUIRED:{name}")
            open_round.state.anchors = copy.deepcopy(dict(anchors))
            open_round.state.training = {
                "entered_training": True,
                "moved": False,
                "attacked": False,
                "dodged": False,
                "completed": False,
            }
            open_round.state.stage = "ready_in_training_zone"
            self._write_round_json(open_round, "anchors.json", open_round.state.anchors)
            self._write_round_state(open_round)
            self._upsert_history(open_round)
            return {"status": "anchors_confirmed", "can_enter_training": True}

    def complete_training(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            open_round = self._require_action(payload, "ready_in_training_zone")
            for field_name in ("moved", "attacked", "dodged"):
                if not isinstance(payload.get(field_name), bool):
                    raise live.LivePipelineError("training", "TRAINING_OBSERVATIONS_INVALID")
            open_round.user_notes = _normalise_notes(payload.get("user_notes", open_round.user_notes))
            rating = payload.get("subjective_rating")
            if rating is not None and (isinstance(rating, bool) or not isinstance(rating, int) or not 1 <= rating <= 5):
                raise live.LivePipelineError("training", "SUBJECTIVE_RATING_INVALID")
            keep = payload.get("keep_idea")
            if keep is not None and not isinstance(keep, bool):
                raise live.LivePipelineError("training", "KEEP_IDEA_INVALID")
            open_round.subjective_rating = rating
            open_round.keep_idea = keep
            open_round.state.training = {
                "moved": bool(payload["moved"]),
                "attacked": bool(payload["attacked"]),
                "dodged": bool(payload["dodged"]),
                "entered_training": True,
                "completed": True,
                "completed_at_utc": live.utc_now(),
            }
            open_round.state.stage = "completed"
            self._write_round_json(open_round, "training_review.json", open_round.state.training)
            self._write_round_state(open_round)
            self._upsert_history(open_round)
            return {"status": "training_completed", "round_id": open_round.state.config["case_id"]}

    def save_result(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        with self.lock:
            self._require_session(payload)
            open_round = self._require_round(payload)
            if open_round.state.stage not in TERMINAL_STAGES:
                raise live.LivePipelineError("save", "ROUND_NOT_FINISHED")
            open_round.user_notes = _normalise_notes(payload.get("user_notes", open_round.user_notes))
            rating = payload.get("subjective_rating", open_round.subjective_rating)
            if rating is not None and (isinstance(rating, bool) or not isinstance(rating, int) or not 1 <= rating <= 5):
                raise live.LivePipelineError("save", "SUBJECTIVE_RATING_INVALID")
            keep = payload.get("keep_idea", open_round.keep_idea)
            if keep is not None and not isinstance(keep, bool):
                raise live.LivePipelineError("save", "KEEP_IDEA_INVALID")
            open_round.subjective_rating = rating
            open_round.keep_idea = keep
            open_round.saved_locally = True
            self._write_round_state(open_round)
            self._upsert_history(open_round)
            return {"status": "saved_locally", "round_id": open_round.state.config["case_id"]}

    def recent(self) -> dict[str, Any]:
        return {"status": "ok", "records": self.history.recent(int(self.config["recent_limit"]))}

    def finalize(self) -> dict[str, Any]:
        """Freeze the session index; safe to call once before launcher cleanup."""
        summary_path = self.output_root / "OPEN_PLAYTEST_SESSION_SUMMARY.json"
        if summary_path.is_file():
            return json.loads(summary_path.read_text(encoding="utf-8"))
        records = [item for item in self.history.recent(int(self.config["history_limit"])) if item.get("session_id") == self.session_id]
        summary = {
            "contract": "forge-open-playtest-session-summary-v1",
            "session_id": self.session_id,
            "status": "closed_by_user",
            "closed_at_utc": live.utc_now(),
            "round_count": len(records),
            "completed_count": sum(item.get("status") == "completed" for item in records),
            "identity_rejected_count": sum(item.get("status") == "identity_rejected" for item in records),
            "failed_count": sum(item.get("status") == "failed" for item in records),
            "semantic_calls": self.compiler.calls_made,
            "retry_count": 0,
            "mock_fallback": False,
            "active_stage_at_close": self.rounds[self.active_round_id].state.stage if self.active_round_id else None,
        }
        live.write_json_new(summary_path, summary)
        hash_path = self.output_root / "evidence_hashes.json"
        if not hash_path.exists():
            live.write_json_new(hash_path, evidence_hashes(self.output_root))
        return summary

    def finalize_request(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        self._require_session(payload)
        return self.finalize()

    def _result_payload(self, open_round: OpenRound) -> dict[str, Any]:
        state = open_round.state
        assert state.semantic_blueprint is not None and state.technical_dir is not None
        identity = state.semantic_blueprint["identity"]
        combat = state.semantic_blueprint["combat"]
        return {
            "semantic_summary": f"{identity['display_name_zh']} · {combat['behavior_family']} · {combat['effect_type']}",
            "canonical_name_zh": identity["canonical_name_zh"],
            "canonical_name_en": identity["canonical_name_en"],
            "display_name_zh": identity["display_name_zh"],
            "behavior_family": combat["behavior_family"],
            "delivery": combat["delivery"],
            "impact_mode": combat["impact_mode"],
            "effect_type": combat["effect_type"],
            "drawback": combat["drawback"],
            "cadence_hint": combat["cadence_hint"],
            "required_identity_parts": state.config["required_identity_parts"],
            "second_anchor_type": state.config["second_anchor_type"],
            "second_anchor_question": state.config["second_anchor_question"],
            "raw_png_base64": base64.b64encode((state.technical_dir / "flux_raw.png").read_bytes()).decode("ascii"),
            "sprite_png_base64": base64.b64encode((state.technical_dir / "processed_sprite.png").read_bytes()).decode("ascii"),
            "stage_timings": copy.deepcopy(open_round.stage_timings),
            "total_forge_seconds": state.metrics.get("total_forge_seconds"),
            "round_output_path": str(open_round.output_dir.resolve()) if open_round.output_dir else "",
        }

    def _publish_technical(self, open_round: OpenRound) -> None:
        state = open_round.state
        assert state.technical_dir is not None
        final = self.output_root / "rounds" / str(state.config["case_id"])
        stage = final.parent / f".{final.name}.{uuid.uuid4().hex}.tmp"
        final.parent.mkdir(parents=True, exist_ok=True)
        if final.exists():
            raise live.LivePipelineError("delivery", "ROUND_OUTPUT_ALREADY_EXISTS")
        shutil.copytree(state.technical_dir, stage)
        os.replace(stage, final)
        open_round.output_dir = final
        self._write_round_state(open_round)

    def _publish_failure(self, open_round: OpenRound) -> None:
        state = open_round.state
        final = self.output_root / "rounds" / str(state.config["case_id"])
        stage = final.parent / f".{final.name}.{uuid.uuid4().hex}.tmp"
        final.parent.mkdir(parents=True, exist_ok=True)
        stage.mkdir(parents=True, exist_ok=False)
        if state.technical_dir and state.technical_dir.is_dir():
            for source in state.technical_dir.iterdir():
                if source.is_file():
                    shutil.copy2(source, stage / source.name)
        live.write_json_new(stage / "failure_manifest.json", {
            "contract": OPEN_CONTRACT,
            "round_id": state.config["case_id"],
            "revision": state.revision,
            "player_input": open_round.player_input,
            "failure_stage": state.failure_stage,
            "failure_reason": state.failure_reason,
            "retry_count": 0,
            "mock_fallback": False,
            "failed_at_utc": live.utc_now(),
        })
        os.replace(stage, final)
        open_round.output_dir = final
        self._write_round_state(open_round)

    def _write_round_state(self, open_round: OpenRound) -> None:
        if open_round.output_dir is None:
            return
        _atomic_replace(open_round.output_dir / "open_playtest_round.json", _json_bytes(self._record(open_round)))

    def _write_round_json(self, open_round: OpenRound, name: str, value: Any) -> None:
        if open_round.output_dir is None:
            raise live.LivePipelineError("delivery", "ROUND_OUTPUT_NOT_PUBLISHED")
        path = open_round.output_dir / name
        if path.exists():
            raise live.LivePipelineError("delivery", f"REFUSING_TO_OVERWRITE:{name}")
        live.write_json_new(path, value)

    def _record(self, open_round: OpenRound) -> dict[str, Any]:
        state = open_round.state
        identity = state.semantic_blueprint.get("identity", {}) if state.semantic_blueprint else {}
        combat = state.semantic_blueprint.get("combat", {}) if state.semantic_blueprint else {}
        total = state.metrics.get("total_forge_seconds")
        raw_path = ""
        sprite_path = ""
        if open_round.output_dir:
            raw = open_round.output_dir / "flux_raw.png"
            sprite = open_round.output_dir / "processed_sprite.png"
            raw_path = _relative(raw) if raw.is_file() else ""
            sprite_path = _relative(sprite) if sprite.is_file() else ""
        identity_confirmed = None if state.identity_review is None else bool(state.identity_review.get("identity_confirmed"))
        return {
            "timestamp": open_round.started_at_utc,
            "session_id": self.session_id,
            "round_id": state.config["case_id"],
            "revision": state.revision,
            "user_input": open_round.player_input,
            "semantic_summary": f"{identity.get('display_name_zh', '')} · {combat.get('behavior_family', '')} · {combat.get('effect_type', '')}".strip(" ·"),
            "behavior_family": combat.get("behavior_family", ""),
            "canonical_identity": identity.get("canonical_name_zh", ""),
            "display_name": identity.get("display_name_zh", ""),
            "raw_image_path": raw_path,
            "processed_sprite_path": sprite_path,
            "identity_confirmed": identity_confirmed,
            "anchor_confirmed": state.anchors is not None,
            "entered_training": bool(state.training and state.training.get("entered_training")),
            "user_notes": open_round.user_notes,
            "subjective_rating": open_round.subjective_rating,
            "keep_idea": open_round.keep_idea,
            "saved_locally": open_round.saved_locally,
            "total_forge_seconds": total,
            "stage_timings": copy.deepcopy(open_round.stage_timings),
            "status": state.stage,
            "failure_stage": state.failure_stage,
            "failure_reason": state.failure_reason,
        }

    def _upsert_history(self, open_round: OpenRound) -> None:
        self.history.upsert(self._record(open_round))

    def _require_session(self, payload: Mapping[str, Any]) -> None:
        if payload.get("session_id") != self.session_id:
            raise live.LivePipelineError("request", "SESSION_ID_MISMATCH")

    def _require_round(self, payload: Mapping[str, Any]) -> OpenRound:
        round_id = str(payload.get("round_id", ""))
        open_round = self.rounds.get(round_id)
        if open_round is None:
            raise live.LivePipelineError("request", "ROUND_NOT_FOUND")
        revision_value = payload.get("revision")
        if revision_value is not None and revision_value != open_round.state.revision:
            raise live.LivePipelineError("request", "STALE_REQUEST_REJECTED")
        return open_round

    def _require_action(self, payload: Mapping[str, Any], expected_stage: str) -> OpenRound:
        self._require_session(payload)
        open_round = self._require_round(payload)
        if payload.get("revision") != open_round.state.revision:
            raise live.LivePipelineError("request", "STALE_REQUEST_REJECTED")
        if open_round.state.stage != expected_stage:
            raise live.LivePipelineError("request", f"ROUND_STAGE_INVALID:{open_round.state.stage}:{expected_stage}")
        return open_round


def evidence_hashes(root: Path) -> dict[str, Any]:
    files: dict[str, str] = {}
    if root.is_dir():
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.name != "evidence_hashes.json":
                files[path.relative_to(root).as_posix()] = live.sha256_file(path)
    return {"algorithm": "SHA-256", "files": files}


__all__ = [
    "BEHAVIOR_ANCHORS",
    "HISTORY_FIELDS",
    "LocalHistoryStore",
    "OPEN_CONTRACT",
    "OpenPlaytestSession",
    "PIPELINE_STAGES",
    "evidence_hashes",
]
