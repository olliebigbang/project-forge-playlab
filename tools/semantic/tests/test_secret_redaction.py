from __future__ import annotations

import io
import json
import os
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
    CallLimiter,
    ResponseValidationError,
    TransportError,
    redact_sensitive_text,
)


OBJECT_SCHEMA = {"type": "object", "properties": {}}
MODEL_ID = "claude-test-snapshot"


def dummy_secret(marker: str = "Q") -> str:
    # Assemble the credential shape at runtime so no scanner allow-list is
    # needed for a complete dummy credential in source control.
    return "sk" + "-ant-test-" + (marker * 24)


def compiler_with(opener) -> AnthropicSemanticCompiler:
    return AnthropicSemanticCompiler(
        system_prompt="system",
        blueprint_schema=OBJECT_SCHEMA,
        clarification_schema=OBJECT_SCHEMA,
        opener=opener,
        call_limiter=CallLimiter(),
    )


class FakeResponse:
    def __init__(self, body: dict) -> None:
        self._body = json.dumps(body).encode("utf-8")

    def read(self, _limit: int = -1) -> bytes:
        return self._body

    def close(self) -> None:
        pass


class RawResponse:
    def __init__(self, body: bytes) -> None:
        self._body = body

    def read(self, _limit: int = -1) -> bytes:
        return self._body

    def close(self) -> None:
        pass


class SecretRedactionTests(unittest.TestCase):
    def test_unicode_escaped_secret_is_not_recoverable(self) -> None:
        secret = "sk-" + "ant-" + ("U" * 24)
        escaped = secret
        for _ in range(6):
            escaped = "".join(f"\\u{ord(character):04x}" for character in escaped)
        raw = json.dumps({"id": escaped})
        redacted = redact_sensitive_text(raw, (secret,))
        self.assertNotIn(secret, redacted)
        self.assertEqual(redacted, "[REDACTED_SENSITIVE_CONTENT]")
        mixed = redact_sensitive_text(secret + " " + raw, (secret,))
        self.assertEqual(mixed, "[REDACTED_SENSITIVE_CONTENT]")

    def test_linear_nested_unicode_chain_is_redacted_with_bounded_work(self) -> None:
        secret = "sk-" + "ant-" + ("L" * 24)
        escaped = "\\u005c" + ("u005c" * 20000) + "u0073" + secret[1:]
        self.assertEqual(
            redact_sensitive_text(escaped, (secret,)),
            "[REDACTED_SENSITIVE_CONTENT]",
        )

    def test_unicode_escaped_provider_envelope_is_rejected_without_recoverable_raw(self) -> None:
        secret = dummy_secret("U")
        escaped = secret
        for _ in range(6):
            escaped = "".join(f"\\u{ord(character):04x}" for character in escaped)
        body = (
            '{"id":"' + escaped + '","model":"' + MODEL_ID + '",'
            '"content":[{"type":"tool_use","id":"toolu_safe",'
            '"name":"submit_forge_semantic_blueprint","input":{}}],'
            '"stop_reason":"tool_use","usage":{"input_tokens":1,"output_tokens":1}}'
        ).encode("utf-8")
        compiler = compiler_with(lambda request, *, timeout: RawResponse(body))
        with patch.dict(
            os.environ,
            {
                "ANTHROPIC_API_KEY": "in-memory-test-value",
                "FORGE_SEMANTIC_MODEL": MODEL_ID,
            },
            clear=True,
        ):
            with self.assertRaises(ResponseValidationError) as caught:
                compiler.compile("safe player input")
        self.assertEqual(caught.exception.code, "SENSITIVE_RESPONSE_ENVELOPE")
        self.assertNotIn(secret, caught.exception.raw_response_redacted)
        self.assertEqual(
            caught.exception.raw_response_redacted,
            "[REDACTED_SENSITIVE_CONTENT]",
        )

    def test_exact_secret_and_credential_fields_are_redacted(self) -> None:
        secret = dummy_secret()
        text = f"failure {secret}; x-api-key: {secret}; authorization=BearerValue"
        redacted = redact_sensitive_text(text, (secret,))
        self.assertNotIn(secret, redacted)
        self.assertNotIn("BearerValue", redacted)
        self.assertIn("[REDACTED]", redacted)

    def test_http_error_and_raw_body_never_echo_key(self) -> None:
        secret = dummy_secret("R")

        def opener(request, *, timeout):
            del request, timeout
            body = json.dumps({"error": "x-api-key=" + secret}).encode("utf-8")
            raise HTTPError(
                "https://api.anthropic.com/v1/messages",
                429,
                "rate limited " + secret,
                hdrs=None,
                fp=io.BytesIO(body),
            )

        with patch.dict(
            os.environ,
            {"ANTHROPIC_API_KEY": secret, "FORGE_SEMANTIC_MODEL": MODEL_ID},
        ):
            with self.assertRaises(TransportError) as caught:
                compiler_with(opener).compile("player")
        failure = caught.exception.to_failure_record()
        serialized = json.dumps(failure)
        self.assertNotIn(secret, str(caught.exception))
        self.assertNotIn(secret, serialized)
        self.assertEqual(failure["error_code"], "HTTP_429")
        self.assertEqual(failure["http_status"], 429)

    def test_successful_raw_response_is_redacted_before_return(self) -> None:
        secret = dummy_secret("S")
        body = {
            "id": "msg_redaction",
            "model": MODEL_ID,
            "content": [
                {
                    "type": "tool_use",
                    "id": "toolu_redaction",
                    "name": BLUEPRINT_TOOL_NAME,
                    "input": {},
                }
            ],
            "usage": {"input_tokens": 1, "output_tokens": 1},
            "stop_reason": "tool_use",
            "diagnostic": secret,
        }

        with patch.dict(
            os.environ,
            {"ANTHROPIC_API_KEY": secret, "FORGE_SEMANTIC_MODEL": MODEL_ID},
        ):
            result = compiler_with(lambda request, timeout: FakeResponse(body)).compile(
                "player"
            )
        self.assertNotIn(secret, result["raw_response_redacted"])
        self.assertIn("[REDACTED]", result["raw_response_redacted"])

    def test_transport_exception_message_is_redacted(self) -> None:
        secret = dummy_secret("T")

        def opener(request, *, timeout):
            del request, timeout
            raise RuntimeError("transport accidentally mentioned " + secret)

        with patch.dict(
            os.environ,
            {"ANTHROPIC_API_KEY": secret, "FORGE_SEMANTIC_MODEL": MODEL_ID},
        ):
            with self.assertRaises(TransportError) as caught:
                compiler_with(opener).compile("player")
        self.assertNotIn(secret, str(caught.exception))
        self.assertIn("[REDACTED]", str(caught.exception))

    def test_invalid_json_does_not_retain_unredacted_parser_exception(self) -> None:
        secret = dummy_secret("U")
        invalid_body = ("not-json x-api-key=" + secret).encode("utf-8")
        with patch.dict(
            os.environ,
            {"ANTHROPIC_API_KEY": secret, "FORGE_SEMANTIC_MODEL": MODEL_ID},
        ):
            with self.assertRaises(ResponseValidationError) as caught:
                compiler_with(
                    lambda request, timeout: RawResponse(invalid_body)
                ).compile("player")
        self.assertIsNone(caught.exception.__cause__)
        self.assertNotIn(secret, caught.exception.raw_response_redacted)
        self.assertIn("[REDACTED]", caught.exception.raw_response_redacted)


if __name__ == "__main__":
    unittest.main()
