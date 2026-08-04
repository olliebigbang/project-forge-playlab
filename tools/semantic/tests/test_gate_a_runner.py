from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SEMANTIC_ROOT / "bridge"))

import gate_a_runner as runner  # noqa: E402
from anthropic_semantic_compiler import ResponseValidationError  # noqa: E402
from gate_a_evaluator import load_gate_a_cases  # noqa: E402


def _valid_blueprint() -> dict:
    return {
        "identity": {
            "canonical_name_zh": "木桌",
            "canonical_name_en": "wooden table",
            "display_name_zh": "回旋木桌",
            "display_name_en": "Returning Wooden Table",
            "category": "furniture",
            "required_identity_parts": ["wooden tabletop", "four table legs"],
            "material_hints": ["wood"],
            "silhouette_hints": ["wide top above four legs"],
            "optional_decorations": ["small forge brackets"],
        },
        "combat": {
            "behavior_family": "returning_thrown",
            "delivery": "whole_object_return",
            "impact_mode": "whole_body_collision",
            "effect_type": "normal",
            "drawback": "weapon_absent_while_flying",
            "cadence_hint": "single_commit",
        },
        "visual": {
            "prompt_en": (
                "One isolated wooden table fantasy game prop, side view, complete object "
                "visible, wooden tabletop and four table legs, handcrafted forge fittings"
            ),
            "negative_prompt_en": "person, hand, text, UI, scenery, cropped object",
            "must_preserve": ["wooden tabletop", "four table legs"],
            "must_not_replace_with": ["gun", "sword", "umbrella"],
        },
        "confidence": 0.9,
    }


class FakeCompiler:
    def __init__(self, fail_at: int | None = None) -> None:
        self.inputs: list[str] = []
        self._calls_made = 0
        self.fail_at = fail_at

    @property
    def calls_made(self) -> int:
        return self._calls_made

    def compile(self, player_input: str) -> dict:
        self._calls_made += 1
        self.inputs.append(player_input)
        if self.fail_at == self._calls_made:
            raise RuntimeError("synthetic local transport failure")
        return {
            "tool_name": "submit_forge_semantic_blueprint",
            "tool_input": _valid_blueprint(),
            "request_id": f"msg-test-{self._calls_made:02d}",
            "model_id": "exact-test-model",
            "usage": {
                "input_tokens": 10,
                "output_tokens": 5,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 0,
            },
            "stop_reason": "tool_use",
            "raw_response_redacted": "{\"id\":\"redacted-test-response\"}",
        }


class ResponseFailureCompiler(FakeCompiler):
    def compile(self, player_input: str) -> dict:
        self._calls_made += 1
        self.inputs.append(player_input)
        if self._calls_made == 7:
            raise ResponseValidationError(
                "TOOL_USE_COUNT",
                "Anthropic response did not contain exactly one tool.",
                http_status=200,
                raw_response_redacted=json.dumps(
                    {
                        "content": [{"type": "text", "text": "invalid"}],
                        "usage": {"input_tokens": 37, "output_tokens": 11},
                    }
                ),
            )
        self._calls_made -= 1
        self.inputs.pop()
        return super().compile(player_input)


class GateARunnerTests(unittest.TestCase):
    def _tree(self, root: Path) -> Path:
        semantic = root / "tools" / "semantic"
        for name in ("cases", "schema", "prompts"):
            shutil.copytree(SEMANTIC_ROOT / name, semantic / name)
        return semantic

    def test_missing_environment_stops_before_output_or_compiler(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            compiler = FakeCompiler()
            with self.assertRaisesRegex(runner.GateARunnerError, "ANTHROPIC_API_KEY"):
                runner.execute_gate_a(
                    semantic_root=semantic,
                    repository_root=root,
                    compiler=compiler,
                    environ={},
                )
            self.assertEqual(compiler.calls_made, 0)
            self.assertFalse((semantic / "output").exists())

    def test_real_call_budget_has_one_cross_process_reservation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            semantic = Path(directory) / "tools" / "semantic"
            first = runner._claim_real_call_budget(semantic, "gate-a-first")
            self.assertTrue(first.is_file())
            with self.assertRaisesRegex(runner.GateARunnerError, "already reserved"):
                runner._claim_real_call_budget(semantic, "gate-a-second")
            ledger = json.loads(first.read_text(encoding="utf-8"))
            self.assertEqual(ledger["max_real_calls"], 20)
            self.assertEqual(ledger["attempts_reserved"], 0)

    def test_real_transport_rejects_an_alternate_environment_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            with self.assertRaisesRegex(runner.GateARunnerError, "process environment"):
                runner.execute_gate_a(
                    semantic_root=semantic,
                    repository_root=root,
                    environ={
                        "ANTHROPIC_API_KEY": "alternate-value",
                        "FORGE_SEMANTIC_MODEL": "exact-test-model",
                    },
                )
            self.assertFalse((semantic / "output").exists())

    def test_unsafe_tls_environment_stops_before_persistent_budget_claim(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            with mock.patch.dict(
                os.environ,
                {
                    "ANTHROPIC_API_KEY": "in-memory-test-value",
                    "FORGE_SEMANTIC_MODEL": "exact-test-model",
                    "SSL_CERT_FILE": "unapproved-certificates.pem",
                },
                clear=True,
            ):
                with self.assertRaisesRegex(runner.GateARunnerError, "SSL_CERT_FILE"):
                    runner.execute_gate_a(
                        semantic_root=semantic,
                        repository_root=root,
                    )
            self.assertFalse((semantic / "output").exists())
            self.assertFalse(
                (semantic / "reports" / "gate_a_real_call_reservation.json").exists()
            )

    def test_model_id_cannot_equal_or_resemble_a_credential(self) -> None:
        with self.assertRaisesRegex(runner.GateARunnerError, "credential material"):
            runner.require_environment(
                {
                    "ANTHROPIC_API_KEY": "same-value",
                    "FORGE_SEMANTIC_MODEL": "same-value",
                }
            )
        credential_shaped = "sk-" + "ant-" + ("x" * 20)
        with self.assertRaisesRegex(runner.GateARunnerError, "credential material"):
            runner.require_environment(
                {
                    "ANTHROPIC_API_KEY": "different-value",
                    "FORGE_SEMANTIC_MODEL": credential_shaped,
                }
            )

    def test_secret_scan_failure_stops_before_compiler_or_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            compiler = FakeCompiler()
            with mock.patch.object(runner, "scan_repository", return_value=[object()]):
                with self.assertRaisesRegex(runner.GateARunnerError, "secret scan failed"):
                    runner.execute_gate_a(
                        semantic_root=semantic,
                        repository_root=root,
                        compiler=compiler,
                        environ={
                            "ANTHROPIC_API_KEY": "in-memory-test-value",
                            "FORGE_SEMANTIC_MODEL": "exact-test-model",
                        },
                    )
            self.assertEqual(compiler.calls_made, 0)
            self.assertFalse((semantic / "output").exists())

    def test_expected_labels_are_loaded_only_after_all_twenty_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            compiler = FakeCompiler()
            real_loader = runner.load_gate_a_expected
            calls_seen: list[int] = []

            def observing_loader(path: Path):
                calls_seen.append(compiler.calls_made)
                return real_loader(path)

            with mock.patch.object(runner, "load_gate_a_expected", observing_loader):
                summary = runner.execute_gate_a(
                    semantic_root=semantic,
                    repository_root=root,
                    compiler=compiler,
                    environ={
                        "ANTHROPIC_API_KEY": "in-memory-test-value",
                        "FORGE_SEMANTIC_MODEL": "exact-test-model",
                    },
                )

            cases = load_gate_a_cases(semantic / "cases" / "gate_a_cases.json")
            self.assertEqual(compiler.inputs, [case["input_text"] for case in cases])
            self.assertTrue(calls_seen)
            self.assertEqual(calls_seen[0], 20)
            self.assertEqual(summary["call_count"], 0)
            self.assertFalse(summary["real_ai_calls_performed"])
            self.assertEqual(summary["status"], "NEEDS WORK")

            run_root = semantic / "output" / "gate_a" / summary["run_id"]
            self.assertEqual(
                sorted(path.name for path in run_root.iterdir()),
                [f"{index:02d}" for index in range(1, 21)],
            )
            self.assertFalse(any((semantic / ".tmp").iterdir()))
            for index in range(1, 21):
                record = json.loads(
                    (run_root / f"{index:02d}" / "result.json").read_text(
                        encoding="utf-8"
                    )
                )
                self.assertEqual(record["provider"], "test-double")
                self.assertFalse(record["ai_interpretation_used"])

    def test_failure_is_delivered_once_and_never_retried(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            compiler = FakeCompiler(fail_at=7)
            summary = runner.execute_gate_a(
                semantic_root=semantic,
                repository_root=root,
                compiler=compiler,
                environ={
                    "ANTHROPIC_API_KEY": "in-memory-test-value",
                    "FORGE_SEMANTIC_MODEL": "exact-test-model",
                },
            )
            self.assertEqual(compiler.calls_made, 20)
            failed = json.loads(
                (
                    semantic
                    / "output"
                    / "gate_a"
                    / summary["run_id"]
                    / "07"
                    / "result.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(failed["result_type"], "failed")
            self.assertEqual(failed["retry_count"], 0)
            self.assertFalse(failed["schema_valid"])

    def test_http_200_response_failure_preserves_status_and_available_usage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            semantic = self._tree(root)
            compiler = ResponseFailureCompiler()
            summary = runner.execute_gate_a(
                semantic_root=semantic,
                repository_root=root,
                compiler=compiler,
                environ={
                    "ANTHROPIC_API_KEY": "in-memory-test-value",
                    "FORGE_SEMANTIC_MODEL": "exact-test-model",
                },
            )
            self.assertEqual(compiler.calls_made, 20)
            failed = json.loads(
                (
                    semantic
                    / "output"
                    / "gate_a"
                    / summary["run_id"]
                    / "07"
                    / "result.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(failed["api_status"], 200)
            self.assertEqual(failed["input_tokens"], 37)
            self.assertEqual(failed["output_tokens"], 11)
            self.assertEqual(failed["retry_count"], 0)


if __name__ == "__main__":
    unittest.main()
