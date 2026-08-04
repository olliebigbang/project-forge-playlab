"""Strict Anthropic Messages API transport for Forge Semantic Gate A.

This module deliberately owns transport validation only.  The semantic tool
input is validated against the repository schemas by ``semantic_contract``
after :func:`parse_anthropic_response` returns it.

There is no retry path in this module.  One call to :meth:`compile` reserves
one call-limit slot and performs at most one HTTP request.
"""

from __future__ import annotations

import copy
import json
import os
import re
import socket
import ssl
import threading
from dataclasses import dataclass
from typing import Any, Callable, Mapping
from urllib.error import HTTPError, URLError
from urllib.request import (
    HTTPRedirectHandler,
    HTTPSHandler,
    ProxyHandler,
    Request,
    build_opener,
)


ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"
MAX_TOKENS = 1200
REQUEST_TIMEOUT_SECONDS = 60
MAX_REAL_CALLS = 20
MAX_RESPONSE_BYTES = 2 * 1024 * 1024

BLUEPRINT_TOOL_NAME = "submit_forge_semantic_blueprint"
CLARIFICATION_TOOL_NAME = "request_forge_clarification"
ALLOWED_TOOL_NAMES = frozenset({BLUEPRINT_TOOL_NAME, CLARIFICATION_TOOL_NAME})

_ANTHROPIC_KEY_PATTERN = re.compile(r"\bsk-ant-[A-Za-z0-9_-]{6,}\b")
_SECRET_ASSIGNMENT_PATTERN = re.compile(
    r"(?i)(\b(?:x-api-key|anthropic_api_key|authorization)\b"
    r"\s*[\"']?\s*[:=]\s*[\"']?)([^\s\"',;}]+)"
)
_JSON_UNICODE_ESCAPE_PATTERN = re.compile(r"\\+u([0-9A-Fa-f]{4})")
_MAX_UNICODE_PROJECTION_DEPTH = 8


class _NoRedirectHandler(HTTPRedirectHandler):
    """Reject redirects so the transport can reach only the approved URL."""

    def redirect_request(  # type: ignore[override]
        self,
        req: Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> None:
        return None


_TLS_ENVIRONMENT_VARIABLES = ("SSLKEYLOGFILE", "SSL_CERT_FILE", "SSL_CERT_DIR")


def require_safe_tls_environment() -> None:
    """Reject ambient settings that can expose or redirect TLS trust.

    The default transport deliberately does not inherit proxies.  Python's TLS
    layer can separately honour these three variables, so they must be absent
    before a context is created or a real-call slot is reserved.
    """

    configured = [name for name in _TLS_ENVIRONMENT_VARIABLES if os.environ.get(name)]
    if configured:
        raise ConfigurationError(
            "UNSAFE_TLS_ENVIRONMENT",
            f"{', '.join(configured)} must be unset for a semantic API request.",
        )


def _build_tls_context() -> ssl.SSLContext:
    """Build a fresh verified client context after the environment guard."""

    require_safe_tls_environment()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_default_certs(ssl.Purpose.SERVER_AUTH)
    # Defence in depth: never emit TLS session secrets even if Python's defaults
    # or a future caller change independently enables key logging.
    context.keylog_filename = None
    return context


def _strict_open(request: Request, *, timeout: int) -> Any:
    # Construct the opener lazily so unsafe certificate/key-log environment
    # settings present at process start cannot taint a reusable global context.
    opener = build_opener(
        ProxyHandler({}),
        _NoRedirectHandler(),
        HTTPSHandler(context=_build_tls_context()),
    )
    return opener.open(request, timeout=timeout)


def redact_sensitive_text(value: Any, secrets: tuple[str, ...] = ()) -> str:
    """Return text with explicit and recognisable Anthropic secrets removed.

    Only caller-provided secret values and credential-shaped fields are
    inspected.  The function never scans the environment or other files.
    """

    text = str(value)
    for secret in secrets:
        if secret:
            text = text.replace(secret, "[REDACTED]")
    text = _ANTHROPIC_KEY_PATTERN.sub("[REDACTED]", text)
    text = _SECRET_ASSIGNMENT_PATTERN.sub(r"\1[REDACTED]", text)
    # Provider JSON can contain a credential encoded as one or more layers of
    # ``\\uXXXX`` escapes. Such content is reversible after JSON decoding, so
    # inspect a projection with every run of Unicode-escape backslashes
    # collapsed. If that projection is sensitive, discard the whole value
    # instead of attempting a lossy partial rewrite of the original encoding.
    projected = text
    for _ in range(_MAX_UNICODE_PROJECTION_DEPTH):
        decoded = _JSON_UNICODE_ESCAPE_PATTERN.sub(
            lambda match: chr(int(match.group(1), 16)), projected
        )
        if decoded == projected:
            break
        projected = decoded
        projected_sanitized = projected
        for secret in secrets:
            if secret:
                projected_sanitized = projected_sanitized.replace(
                    secret, "[REDACTED]"
                )
        projected_sanitized = _ANTHROPIC_KEY_PATTERN.sub(
            "[REDACTED]", projected_sanitized
        )
        projected_sanitized = _SECRET_ASSIGNMENT_PATTERN.sub(
            r"\1[REDACTED]", projected_sanitized
        )
        if projected_sanitized != projected:
            return "[REDACTED_SENSITIVE_CONTENT]"
    if _JSON_UNICODE_ESCAPE_PATTERN.search(projected):
        # More than the bounded depth is treated as sensitive. This keeps CPU
        # and memory O(n) with a small constant even for adversarial nesting.
        return "[REDACTED_SENSITIVE_CONTENT]"
    return text


class SemanticCompilerError(RuntimeError):
    """Base class for explicit, redacted Gate A transport failures."""

    def __init__(
        self,
        code: str,
        message: str,
        *,
        http_status: int | None = None,
        raw_response_redacted: str = "",
    ) -> None:
        super().__init__(message)
        self.code = code
        self.http_status = http_status
        self.raw_response_redacted = raw_response_redacted

    def to_failure_record(self) -> dict[str, Any]:
        return {
            "error_code": self.code,
            "http_status": self.http_status,
            "failure_reason": str(self),
            "raw_response_redacted": self.raw_response_redacted,
        }


class ConfigurationError(SemanticCompilerError):
    pass


class CallLimitError(SemanticCompilerError):
    pass


class ResponseValidationError(SemanticCompilerError):
    pass


class TransportError(SemanticCompilerError):
    pass


class CallLimiter:
    """Thread-safe, non-resettable reservation counter capped at twenty."""

    def __init__(self, max_calls: int = MAX_REAL_CALLS) -> None:
        if isinstance(max_calls, bool) or not isinstance(max_calls, int):
            raise TypeError("max_calls must be an integer")
        if max_calls < 1 or max_calls > MAX_REAL_CALLS:
            raise ValueError(f"max_calls must be between 1 and {MAX_REAL_CALLS}")
        self._max_calls = max_calls
        self._calls_made = 0
        self._lock = threading.Lock()

    @property
    def max_calls(self) -> int:
        return self._max_calls

    @property
    def calls_made(self) -> int:
        with self._lock:
            return self._calls_made

    @property
    def calls_remaining(self) -> int:
        with self._lock:
            return self._max_calls - self._calls_made

    def reserve(self) -> int:
        """Reserve one real request, returning its one-based call number."""

        with self._lock:
            if self._calls_made >= self._max_calls:
                raise CallLimitError(
                    "CALL_LIMIT_EXCEEDED",
                    f"Gate A real-call limit of {self._max_calls} has been reached.",
                )
            self._calls_made += 1
            return self._calls_made


# Default compiler instances share a process-wide cap.  Gate A itself is one
# process/run, so constructing another transport cannot silently reset the cap.
_PROCESS_CALL_LIMITER = CallLimiter()


def _require_nonempty_string(name: str, value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string")
    return value


def _copy_object_schema(name: str, schema: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(schema, Mapping):
        raise TypeError(f"{name} must be a JSON object schema")
    copied = copy.deepcopy(dict(schema))
    if copied.get("type") != "object":
        raise ValueError(f"{name} must declare type=object")
    return copied


def build_anthropic_payload(
    system_prompt: str,
    player_input: str,
    model_id: str,
    blueprint_schema: Mapping[str, Any],
    clarification_schema: Mapping[str, Any],
) -> dict[str, Any]:
    """Build the key-free request body with both forced-choice client tools."""

    system_prompt = _require_nonempty_string("system_prompt", system_prompt)
    player_input = _require_nonempty_string("player_input", player_input)
    model_id = _require_nonempty_string("model_id", model_id)

    return {
        "model": model_id,
        "max_tokens": MAX_TOKENS,
        "system": system_prompt,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": player_input}],
            }
        ],
        "tools": [
            {
                "name": BLUEPRINT_TOOL_NAME,
                "description": (
                    "Submit one strict Forge semantic blueprint when identity "
                    "and one combat behavior are sufficiently clear."
                ),
                "input_schema": _copy_object_schema(
                    "blueprint_schema", blueprint_schema
                ),
            },
            {
                "name": CLARIFICATION_TOOL_NAME,
                "description": (
                    "Ask exactly one key clarification when identity is unclear, "
                    "behavior conflicts, or information is insufficient."
                ),
                "input_schema": _copy_object_schema(
                    "clarification_schema", clarification_schema
                ),
            },
        ],
        # `any` requires a tool call; disabling parallel use limits the model to
        # one tool.  Response parsing independently enforces exactly one.
        "tool_choice": {"type": "any", "disable_parallel_tool_use": True},
    }


def _parse_json_object(response: Mapping[str, Any] | str | bytes) -> dict[str, Any]:
    if isinstance(response, bytes):
        try:
            response = response.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ResponseValidationError(
                "INVALID_RESPONSE_ENCODING",
                "Anthropic response was not valid UTF-8.",
            ) from None
    if isinstance(response, str):
        try:
            response = json.loads(response)
        except json.JSONDecodeError as exc:
            raise ResponseValidationError(
                "INVALID_RESPONSE_JSON",
                "Anthropic response was not valid JSON.",
            ) from None
    if not isinstance(response, Mapping):
        raise ResponseValidationError(
            "INVALID_RESPONSE_ROOT",
            "Anthropic response root must be an object.",
        )
    return dict(response)


def _parse_nonnegative_usage(usage: Any) -> dict[str, int]:
    if not isinstance(usage, Mapping):
        raise ResponseValidationError(
            "MISSING_USAGE", "Anthropic response did not include a usage object."
        )
    result: dict[str, int] = {}
    for field in ("input_tokens", "output_tokens"):
        value = usage.get(field)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ResponseValidationError(
                "INVALID_USAGE", f"Anthropic usage.{field} must be a non-negative integer."
            )
        result[field] = value
    for field in ("cache_creation_input_tokens", "cache_read_input_tokens"):
        value = usage.get(field, 0)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ResponseValidationError(
                "INVALID_USAGE", f"Anthropic usage.{field} must be a non-negative integer."
            )
        result[field] = value
    return result


def parse_anthropic_response(
    response: Mapping[str, Any] | str | bytes,
) -> dict[str, Any]:
    """Extract exactly one legal tool call and its trusted API envelope.

    Tool input remains untrusted semantic data and must be passed to the local
    schema/cross-field validator by the caller.
    """

    root = _parse_json_object(response)
    request_id = root.get("id")
    model_id = root.get("model")
    if not isinstance(request_id, str) or not request_id.strip():
        raise ResponseValidationError(
            "MISSING_REQUEST_ID", "Anthropic response did not include a request id."
        )
    if not isinstance(model_id, str) or not model_id.strip():
        raise ResponseValidationError(
            "MISSING_MODEL_ID", "Anthropic response did not include a model id."
        )

    content = root.get("content")
    if not isinstance(content, list):
        raise ResponseValidationError(
            "INVALID_CONTENT", "Anthropic response content must be an array."
        )
    tool_blocks = [
        block
        for block in content
        if isinstance(block, Mapping) and block.get("type") == "tool_use"
    ]
    if len(tool_blocks) != 1:
        raise ResponseValidationError(
            "TOOL_USE_COUNT",
            f"Anthropic response must contain exactly one tool_use; got {len(tool_blocks)}.",
        )
    # A text answer, thinking block, or other side channel is not a successful
    # Gate A result.  The sole response content must be the selected tool call.
    if len(content) != 1:
        raise ResponseValidationError(
            "EXTRA_RESPONSE_CONTENT",
            "Anthropic response contained content outside the single tool_use.",
        )

    tool_block = tool_blocks[0]
    tool_name = tool_block.get("name")
    if tool_name not in ALLOWED_TOOL_NAMES:
        raise ResponseValidationError(
            "UNKNOWN_TOOL", "Anthropic response selected an unknown tool."
        )
    tool_input = tool_block.get("input")
    if not isinstance(tool_input, Mapping):
        raise ResponseValidationError(
            "INVALID_TOOL_INPUT", "Anthropic tool_use.input must be an object."
        )

    return {
        "tool_name": tool_name,
        "tool_input": copy.deepcopy(dict(tool_input)),
        "request_id": request_id,
        "model_id": model_id,
        "usage": _parse_nonnegative_usage(root.get("usage")),
        "stop_reason": root.get("stop_reason"),
    }


@dataclass(frozen=True)
class _CompilerInputs:
    system_prompt: str
    blueprint_schema: Mapping[str, Any]
    clarification_schema: Mapping[str, Any]


class AnthropicSemanticCompiler:
    """One-request Anthropic transport with environment-only credentials."""

    def __init__(
        self,
        *,
        system_prompt: str | None = None,
        blueprint_schema: Mapping[str, Any] | None = None,
        clarification_schema: Mapping[str, Any] | None = None,
        opener: Callable[..., Any] | None = None,
        call_limiter: CallLimiter | None = None,
    ) -> None:
        self._defaults = (
            _CompilerInputs(system_prompt, blueprint_schema, clarification_schema)
            if system_prompt is not None
            and blueprint_schema is not None
            and clarification_schema is not None
            else None
        )
        if any(
            value is not None
            for value in (system_prompt, blueprint_schema, clarification_schema)
        ) and self._defaults is None:
            raise ValueError(
                "system_prompt, blueprint_schema, and clarification_schema "
                "must be supplied together"
            )
        self._opener = opener or _strict_open
        self._call_limiter = call_limiter or _PROCESS_CALL_LIMITER

    @property
    def calls_made(self) -> int:
        return self._call_limiter.calls_made

    def compile(
        self,
        player_input: str,
        system_prompt: str | None = None,
        blueprint_schema: Mapping[str, Any] | None = None,
        clarification_schema: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Perform one non-retried request and return one parsed tool call."""

        supplied = (system_prompt, blueprint_schema, clarification_schema)
        if all(value is None for value in supplied):
            if self._defaults is None:
                raise ConfigurationError(
                    "MISSING_COMPILER_INPUTS",
                    "Semantic compiler prompt and schemas were not configured.",
                )
            inputs = self._defaults
        elif any(value is None for value in supplied):
            raise ConfigurationError(
                "INCOMPLETE_COMPILER_INPUTS",
                "Semantic compiler prompt and both schemas are required together.",
            )
        else:
            inputs = _CompilerInputs(
                system_prompt,  # type: ignore[arg-type]
                blueprint_schema,  # type: ignore[arg-type]
                clarification_schema,  # type: ignore[arg-type]
            )

        api_key: str | None = os.environ.get("ANTHROPIC_API_KEY")
        model_id = os.environ.get("FORGE_SEMANTIC_MODEL")
        headers: dict[str, str] = {}
        request: Request | None = None
        try:
            require_safe_tls_environment()
            if not api_key:
                raise ConfigurationError(
                    "MISSING_API_KEY",
                    "ANTHROPIC_API_KEY is missing from the current process environment.",
                )
            if not model_id:
                raise ConfigurationError(
                    "MISSING_MODEL_ID",
                    "FORGE_SEMANTIC_MODEL is missing from the current process environment.",
                )

            try:
                payload = build_anthropic_payload(
                    inputs.system_prompt,
                    player_input,
                    model_id,
                    inputs.blueprint_schema,
                    inputs.clarification_schema,
                )
                body = json.dumps(
                    payload, ensure_ascii=False, separators=(",", ":")
                ).encode("utf-8")
                if api_key.encode("utf-8") in body:
                    raise ValueError(
                        "The current API credential appeared in the request body."
                    )
            except (TypeError, ValueError) as exc:
                raise ConfigurationError(
                    "INVALID_COMPILER_INPUTS",
                    redact_sensitive_text(exc, (api_key,)),
                ) from exc

            headers = {
                "content-type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": ANTHROPIC_VERSION,
            }
            request = Request(
                ANTHROPIC_MESSAGES_URL,
                data=body,
                headers=headers,
                method="POST",
            )
            self._call_limiter.reserve()

            response: Any = None
            raw_bytes = b""
            http_status: int | None = None
            try:
                response = self._opener(request, timeout=REQUEST_TIMEOUT_SECONDS)
                status = getattr(response, "status", None)
                if status is None:
                    getcode = getattr(response, "getcode", None)
                    status = getcode() if callable(getcode) else 200
                http_status = (
                    status
                    if isinstance(status, int) and not isinstance(status, bool)
                    else None
                )
                raw_bytes = response.read(MAX_RESPONSE_BYTES + 1)
                if len(raw_bytes) > MAX_RESPONSE_BYTES:
                    raise ResponseValidationError(
                        "RESPONSE_TOO_LARGE",
                        "Anthropic response exceeded the local size limit.",
                        http_status=http_status,
                    )
                if (
                    isinstance(status, int)
                    and not isinstance(status, bool)
                    and not 200 <= status <= 299
                ):
                    redacted_body = redact_sensitive_text(
                        raw_bytes.decode("utf-8", errors="replace"), (api_key,)
                    )
                    if status == 429:
                        code = "HTTP_429"
                    elif 500 <= status <= 599:
                        code = "HTTP_5XX"
                    else:
                        code = "HTTP_ERROR"
                    raise TransportError(
                        code,
                        f"Anthropic API returned HTTP {status}; request was not retried.",
                        http_status=status,
                        raw_response_redacted=redacted_body,
                    )
            except HTTPError as exc:
                try:
                    error_body = exc.read(MAX_RESPONSE_BYTES + 1).decode(
                        "utf-8", errors="replace"
                    )
                except Exception:
                    error_body = ""
                redacted_body = redact_sensitive_text(error_body, (api_key,))
                if exc.code == 429:
                    code = "HTTP_429"
                elif 500 <= exc.code <= 599:
                    code = "HTTP_5XX"
                else:
                    code = "HTTP_ERROR"
                raise TransportError(
                    code,
                    f"Anthropic API returned HTTP {exc.code}; request was not retried.",
                    http_status=exc.code,
                    raw_response_redacted=redacted_body,
                ) from None
            except (socket.timeout, TimeoutError) as exc:
                raise TransportError(
                    "TIMEOUT",
                    "Anthropic API request timed out after 60 seconds; request was not retried.",
                ) from None
            except URLError as exc:
                if isinstance(exc.reason, (socket.timeout, TimeoutError)):
                    raise TransportError(
                        "TIMEOUT",
                        "Anthropic API request timed out after 60 seconds; request was not retried.",
                    ) from None
                safe_reason = redact_sensitive_text(exc.reason, (api_key,))[:500]
                raise TransportError(
                    "NETWORK_ERROR",
                    f"Anthropic API request failed without retry: {safe_reason}",
                ) from None
            except SemanticCompilerError:
                raise
            except Exception as exc:
                safe_reason = redact_sensitive_text(exc, (api_key,))[:500]
                raise TransportError(
                    "TRANSPORT_ERROR",
                    f"Anthropic API request failed without retry: {safe_reason}",
                ) from None
            finally:
                if response is not None:
                    close = getattr(response, "close", None)
                    if callable(close):
                        try:
                            close()
                        except Exception:
                            # Closing must not replace the already classified
                            # request outcome or expose an exception message.
                            pass

            raw_text = raw_bytes.decode("utf-8", errors="replace")
            redacted_raw = redact_sensitive_text(raw_text, (api_key,))
            try:
                parsed = parse_anthropic_response(raw_bytes)
            except ResponseValidationError as exc:
                exc.http_status = http_status
                exc.raw_response_redacted = redacted_raw
                raise
            response_request_id = str(parsed["request_id"])
            if (
                redact_sensitive_text(response_request_id, (api_key,))
                != response_request_id
            ):
                raise ResponseValidationError(
                    "SENSITIVE_RESPONSE_ENVELOPE",
                    "Anthropic response envelope contained credential-shaped material.",
                    http_status=http_status,
                    raw_response_redacted=redacted_raw,
                )
            if parsed["model_id"] != model_id:
                raise ResponseValidationError(
                    "MODEL_ID_MISMATCH",
                    "Anthropic response model id did not match FORGE_SEMANTIC_MODEL.",
                    http_status=http_status,
                    raw_response_redacted=redacted_raw,
                )
            parsed["raw_response_redacted"] = redacted_raw
            return parsed
        finally:
            # The environment remains owned by the caller.  Clear every local
            # plaintext reference, including the Request object's header maps.
            if request is not None:
                request.headers.clear()
                request.unredirected_hdrs.clear()
            headers.clear()
            request = None
            api_key = None


__all__ = [
    "ALLOWED_TOOL_NAMES",
    "ANTHROPIC_MESSAGES_URL",
    "ANTHROPIC_VERSION",
    "AnthropicSemanticCompiler",
    "BLUEPRINT_TOOL_NAME",
    "CLARIFICATION_TOOL_NAME",
    "CallLimitError",
    "CallLimiter",
    "ConfigurationError",
    "MAX_REAL_CALLS",
    "MAX_TOKENS",
    "REQUEST_TIMEOUT_SECONDS",
    "ResponseValidationError",
    "SemanticCompilerError",
    "TransportError",
    "build_anthropic_payload",
    "parse_anthropic_response",
    "redact_sensitive_text",
    "require_safe_tls_environment",
]
