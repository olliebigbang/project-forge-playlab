#!/usr/bin/env python3
"""Loopback JSON bridge between the explicit Spike 7 Godot scene and pipeline."""

from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from live_orchestrator import LivePipelineError, LiveSession


MAX_REQUEST_BYTES = 25 * 1024 * 1024


class LiveHandler(BaseHTTPRequestHandler):
    server_version = "ForgeLiveE2E/1"

    @property
    def session(self) -> LiveSession:
        return self.server.session  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: Any) -> None:
        # Do not echo request bodies, credentials, or user input into console logs.
        sys.stderr.write("LIVE_BRIDGE %s %s\n" % (self.command, self.path.split("?", 1)[0]))

    def _send(self, status: int, value: Any) -> None:
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def _payload(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise LivePipelineError("request", "CONTENT_LENGTH_INVALID") from exc
        if length <= 0 or length > MAX_REQUEST_BYTES:
            raise LivePipelineError("request", "REQUEST_SIZE_INVALID")
        try:
            value = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise LivePipelineError("request", "JSON_INVALID") from exc
        if not isinstance(value, dict):
            raise LivePipelineError("request", "JSON_OBJECT_REQUIRED")
        return value

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._send(200, self.session.health())
            return
        self._send(404, {"status": "error", "failure_reason": "ROUTE_NOT_FOUND"})

    def do_POST(self) -> None:  # noqa: N802
        routes = {
            "/case/start": self.session.start_case,
            "/case/identity": self.session.confirm_identity,
            "/case/anchors": self.session.confirm_anchors,
            "/case/training": self.session.complete_training,
            "/session/finalize": self.session.finalize,
        }
        handler = routes.get(self.path)
        if handler is None:
            self._send(404, {"status": "error", "failure_reason": "ROUTE_NOT_FOUND"})
            return
        try:
            result = handler(self._payload())
        except LivePipelineError as exc:
            sys.stderr.write(f"LIVE_BRIDGE_ERROR stage={exc.stage} code={exc.code}\n")
            self._send(
                409 if exc.stage == "request" else 422,
                {"status": "error", "failure_stage": exc.stage, "failure_reason": exc.code, "retry_count": 0, "mock_fallback": False},
            )
            return
        except Exception as exc:
            # Unknown failures are intentionally opaque; raw exception text could
            # contain paths or provider material and is kept out of HTTP evidence.
            sys.stderr.write(f"LIVE_BRIDGE_ERROR stage=bridge code=UNEXPECTED_LOCAL_FAILURE type={type(exc).__name__}\n")
            self._send(500, {"status": "error", "failure_stage": "bridge", "failure_reason": "UNEXPECTED_LOCAL_FAILURE", "retry_count": 0, "mock_fallback": False})
            return
        self._send(200, result)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--forge-live-e2e-spike7", action="store_true")
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--preflight-file", type=Path, required=True)
    parser.add_argument("--resume-from-session-id")
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()
    if not args.forge_live_e2e_spike7:
        print("LIVE_E2E_EXPLICIT_LAUNCH_REQUIRED", file=sys.stderr)
        return 2
    if args.port != 8767:
        print("LIVE_E2E_BRIDGE_PORT_MUST_BE_8767", file=sys.stderr)
        return 2
    server = ThreadingHTTPServer(("127.0.0.1", args.port), LiveHandler)
    server.daemon_threads = False
    server.session = LiveSession(  # type: ignore[attr-defined]
        session_id=args.session_id,
        run_id=args.run_id,
        preflight_file=args.preflight_file,
        resume_from_session_id=args.resume_from_session_id,
    )
    print(json.dumps({"status": "LISTENING", "address": "127.0.0.1", "port": args.port, "run_id": args.run_id}))
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
