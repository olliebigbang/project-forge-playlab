from __future__ import annotations

import io
import json
import os
import socket
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError


BRIDGE_DIR = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE_DIR))

from anthropic_semantic_compiler import (  # noqa: E402
    BLUEPRINT_TOOL_NAME,
    AnthropicSemanticCompiler,
    CallLimitError,
    CallLimiter,
    TransportError,
)


OBJECT_SCHEMA = {"type": "object", "properties": {}}
MODEL_ID = "claude-test-snapshot"


class FakeResponse:
    def __init__(self, call_number: int) -> None:
        self._body = json.dumps(
            {
                "id": f"msg_{call_number}",
                "model": MODEL_ID,
                "content": [
                    {
                        "type": "tool_use",
                        "id": f"toolu_{call_number}",
                        "name": BLUEPRINT_TOOL_NAME,
                        "input": {},
                    }
                ],
                "usage": {"input_tokens": 1, "output_tokens": 1},
                "stop_reason": "tool_use",
            }
        ).encode("utf-8")

    def read(self, _limit: int = -1) -> bytes:
        return self._body

    def close(self) -> None:
        pass


class FakeStatusResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def read(self, _limit: int = -1) -> bytes:
        return b'{"error":"simulated"}'

    def close(self) -> None:
        pass


def configured_compiler(opener, limiter: CallLimiter) -> AnthropicSemanticCompiler:
    return AnthropicSemanticCompiler(
        system_prompt="system",
        blueprint_schema=OBJECT_SCHEMA,
        clarification_schema=OBJECT_SCHEMA,
        opener=opener,
        call_limiter=limiter,
    )


class CallLimitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.secret = "sk" + "-ant-test-" + ("L" * 24)
        self.environment = patch.dict(
            os.environ,
            {
                "ANTHROPIC_API_KEY": self.secret,
                "FORGE_SEMANTIC_MODEL": MODEL_ID,
            },
        )
        self.environment.start()

    def tearDown(self) -> None:
        self.environment.stop()

    def test_twenty_requests_allowed_and_twenty_first_blocked(self) -> None:
        network_calls = 0

        def opener(request, *, timeout):
            nonlocal network_calls
            del request, timeout
            network_calls += 1
            return FakeResponse(network_calls)

        limiter = CallLimiter(20)
        compiler = configured_compiler(opener, limiter)
        for case_number in range(20):
            result = compiler.compile(f"case {case_number + 1}")
            self.assertEqual(result["tool_name"], BLUEPRINT_TOOL_NAME)
        with self.assertRaises(CallLimitError):
            compiler.compile("case 21")
        self.assertEqual(network_calls, 20)
        self.assertEqual(limiter.calls_made, 20)
        self.assertEqual(limiter.calls_remaining, 0)

    def test_limit_cannot_be_configured_above_twenty(self) -> None:
        with self.assertRaises(ValueError):
            CallLimiter(21)

    def test_429_is_one_failed_call_with_no_retry(self) -> None:
        calls = 0

        def opener(request, *, timeout):
            nonlocal calls
            del request, timeout
            calls += 1
            raise HTTPError(
                "https://api.anthropic.com/v1/messages",
                429,
                "rate limited",
                hdrs=None,
                fp=io.BytesIO(b'{"error":"rate_limit"}'),
            )

        limiter = CallLimiter()
        with self.assertRaises(TransportError) as caught:
            configured_compiler(opener, limiter).compile("one case")
        self.assertEqual(caught.exception.code, "HTTP_429")
        self.assertEqual(calls, 1)
        self.assertEqual(limiter.calls_made, 1)

    def test_5xx_is_one_failed_call_with_no_retry(self) -> None:
        calls = 0

        def opener(request, *, timeout):
            nonlocal calls
            del request, timeout
            calls += 1
            raise HTTPError(
                "https://api.anthropic.com/v1/messages",
                503,
                "unavailable",
                hdrs=None,
                fp=io.BytesIO(b'{"error":"unavailable"}'),
            )

        limiter = CallLimiter()
        with self.assertRaises(TransportError) as caught:
            configured_compiler(opener, limiter).compile("one case")
        self.assertEqual(caught.exception.code, "HTTP_5XX")
        self.assertEqual(calls, 1)
        self.assertEqual(limiter.calls_made, 1)

    def test_timeout_is_one_failed_call_with_no_retry(self) -> None:
        calls = 0

        def opener(request, *, timeout):
            nonlocal calls
            del request, timeout
            calls += 1
            raise socket.timeout("timed out")

        limiter = CallLimiter()
        with self.assertRaises(TransportError) as caught:
            configured_compiler(opener, limiter).compile("one case")
        self.assertEqual(caught.exception.code, "TIMEOUT")
        self.assertEqual(calls, 1)
        self.assertEqual(limiter.calls_made, 1)

    def test_returned_non_success_status_is_explicit_failure_without_retry(self) -> None:
        calls = 0

        def opener(request, *, timeout):
            nonlocal calls
            del request, timeout
            calls += 1
            return FakeStatusResponse(500)

        limiter = CallLimiter()
        with self.assertRaises(TransportError) as caught:
            configured_compiler(opener, limiter).compile("one case")
        self.assertEqual(caught.exception.code, "HTTP_5XX")
        self.assertEqual(caught.exception.http_status, 500)
        self.assertEqual(calls, 1)
        self.assertEqual(limiter.calls_made, 1)


if __name__ == "__main__":
    unittest.main()
