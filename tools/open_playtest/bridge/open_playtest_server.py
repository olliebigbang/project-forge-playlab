#!/usr/bin/env python3
"""Loopback HTTP adapter for Forge Open Playtest Mode."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Mapping

from open_playtest_session import (
    OPEN_CONTRACT,
    SEMANTIC_MODES,
    OpenPlaytestSession,
    evidence_hashes,
)

import live_orchestrator as live


MAX_REQUEST_BYTES = 24 * 1024 * 1024


class OpenPlaytestServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, address: tuple[str, int], session: OpenPlaytestSession) -> None:
        super().__init__(address, OpenPlaytestHandler)
        self.session = session


class OpenPlaytestHandler(BaseHTTPRequestHandler):
    server: OpenPlaytestServer

    def log_message(self, _format: str, *_args: Any) -> None:
        # Player inputs and credentials must not drift into HTTP access logs.
        return

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        query = {key: values[-1] for key, values in urllib.parse.parse_qs(parsed.query).items()}
        try:
            if parsed.path == "/health":
                self._send(200, self.server.session.health())
            elif parsed.path == "/round/status":
                if "revision" in query:
                    query["revision"] = int(query["revision"])
                self._send(200, self.server.session.round_status(query))
            elif parsed.path in {"/history", "/summary"}:
                if query.get("session_id") != self.server.session.session_id:
                    raise live.LivePipelineError("request", "SESSION_ID_MISMATCH")
                self._send(200, self.server.session.recent())
            else:
                self._send(404, {"failure_stage": "request", "failure_reason": "ROUTE_NOT_FOUND"})
        except (OSError, ValueError, live.LivePipelineError) as exc:
            self._send_error(exc)

    def do_POST(self) -> None:  # noqa: N802
        try:
            payload = self._read_json()
            routes = {
                "/round/start": self.server.session.start_round,
                "/round/identity": self.server.session.confirm_identity,
                "/round/anchors": self.server.session.confirm_anchors,
                "/round/training": self.server.session.complete_training,
                "/round/save": self.server.session.save_result,
                "/session/finalize": self.server.session.finalize_request,
            }
            handler = routes.get(urllib.parse.urlparse(self.path).path)
            if handler is None:
                self._send(404, {"failure_stage": "request", "failure_reason": "ROUTE_NOT_FOUND"})
                return
            body = handler(payload)
            status = 202 if body.get("status") == "accepted" else 200
            self._send(status, body)
        except (json.JSONDecodeError, UnicodeDecodeError, OSError, ValueError, live.LivePipelineError) as exc:
            self._send_error(exc)

    def _read_json(self) -> dict[str, Any]:
        content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
        if content_type != "application/json":
            raise live.LivePipelineError("request", "CONTENT_TYPE_MUST_BE_JSON")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise live.LivePipelineError("request", "CONTENT_LENGTH_INVALID") from exc
        if length <= 0 or length > MAX_REQUEST_BYTES:
            raise live.LivePipelineError("request", "REQUEST_SIZE_INVALID")
        value = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(value, Mapping):
            raise live.LivePipelineError("request", "REQUEST_ROOT_MUST_BE_OBJECT")
        return dict(value)

    def _send_error(self, exc: Exception) -> None:
        if isinstance(exc, live.LivePipelineError):
            stage, reason = exc.stage, exc.code
            code = 409 if reason in {"ROUND_IN_PROGRESS", "DUPLICATE_REQUEST_REJECTED", "STALE_REQUEST_REJECTED"} or reason.startswith("ROUND_STAGE_INVALID") else 400
        elif isinstance(exc, OSError):
            stage, reason, code = "storage", "LOCAL_STORAGE_ERROR", 500
        elif isinstance(exc, json.JSONDecodeError):
            stage, reason, code = "request", "REQUEST_JSON_INVALID", 400
        else:
            stage, reason, code = "request", "REQUEST_VALUE_INVALID", 400
        self._send(code, {"status": "failed", "failure_stage": stage, "failure_reason": reason})

    def _send(self, status: int, value: Mapping[str, Any]) -> None:
        payload = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--forge-open-playtest", action="store_true", required=True)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--preflight-file", type=Path, required=True)
    parser.add_argument("--config-file", type=Path, required=True)
    parser.add_argument("--semantic-mode", choices=sorted(SEMANTIC_MODES), default="v1_1")
    parser.add_argument("--port", type=int, default=8771)
    args = parser.parse_args()
    if not re.fullmatch(r"open-[a-z0-9-]{8,80}", args.session_id):
        print("OPEN_SESSION_ID_INVALID", file=sys.stderr)
        return 2
    if args.port != 8771:
        print("OPEN_BRIDGE_PORT_MUST_BE_8771", file=sys.stderr)
        return 2
    if os.environ.get("FORGE_SEMANTIC_MODEL") != "claude-sonnet-5":
        print("MODEL_ID_MUST_BE_EXACTLY_CLAUDE_SONNET_5", file=sys.stderr)
        return 2
    try:
        session = OpenPlaytestSession(
            session_id=args.session_id,
            preflight_file=args.preflight_file,
            config_file=args.config_file,
            semantic_mode=args.semantic_mode,
        )
        server = OpenPlaytestServer(("127.0.0.1", args.port), session)
    except (OSError, ValueError, live.LivePipelineError) as exc:
        print(f"OPEN_SERVER_START_FAILED:{type(exc).__name__}", file=sys.stderr)
        return 2
    print(json.dumps({
        "status": "OPEN_PLAYTEST_BRIDGE_READY",
        "contract": OPEN_CONTRACT,
        "session_id": args.session_id,
        "listen": f"127.0.0.1:{args.port}",
        "mock_fallback": False,
        "semantic_mode": args.semantic_mode,
        "semantic_contract": session.semantic_contract,
    }, ensure_ascii=False), flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        session.finalize()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
