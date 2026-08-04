from __future__ import annotations

import os
import sys
import tempfile
import unittest
import subprocess
from pathlib import Path
from unittest import mock


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SEMANTIC_ROOT / "bridge"))

import secret_scan  # noqa: E402
from secret_scan import scan_repository  # noqa: E402


class SecretScanTests(unittest.TestCase):
    def test_safe_repository_fixture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "safe.py").write_text(
                "import os\nkey = os.environ.get('ANTHROPIC_API_KEY')\n",
                encoding="utf-8",
            )
            self.assertEqual(scan_repository(root), [])

    def test_dummy_secret_is_detected_without_storing_one_in_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dummy = "sk-" + "ant-" + "unit_test_value_1234567890"
            (root / "leak.semantic-secret-test").write_text(dummy, encoding="utf-8")
            findings = scan_repository(root)
            self.assertEqual(len(findings), 1)
            self.assertEqual(findings[0].rule, "anthropic_key_shape")
            self.assertNotIn(dummy, repr(findings))

    def test_ignored_env_and_local_config_are_still_scanned(self) -> None:
        marker = "sk-" + "ant-" + ("Q" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env_file = root / ".env"
            config_file = (
                root
                / "tools"
                / "semantic"
                / "config"
                / "semantic_compiler_config.local.json"
            )
            config_file.parent.mkdir(parents=True)
            env_file.write_text("TOKEN=" + marker, encoding="utf-8")
            config_file.write_text('{"value":"' + marker + '"}', encoding="utf-8")
            findings = scan_repository(root)
            self.assertEqual(
                {finding.path for finding in findings},
                {
                    ".env",
                    "tools/semantic/config/semantic_compiler_config.local.json",
                },
            )

    def test_git_visible_toml_and_extensionless_text_are_scanned(self) -> None:
        marker = "sk-" + "ant-" + ("R" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            toml = root / "secrets.toml"
            extensionless = root / "credentials"
            toml.write_text('token="' + marker + '"', encoding="utf-8")
            extensionless.write_text("token=" + marker, encoding="utf-8")
            findings = scan_repository(root)
            self.assertEqual(
                {finding.path for finding in findings},
                {"secrets.toml", "credentials"},
            )

    def test_git_listing_child_does_not_inherit_semantic_credentials(self) -> None:
        with mock.patch.dict(
            secret_scan.os.environ,
            {
                "ANTHROPIC_API_KEY": "in-memory-test-value",
                "FORGE_SEMANTIC_MODEL": "exact-test-model",
                "GIT_INDEX_FILE": "alternate-index",
                "GIT_DIR": "alternate-git-directory",
                "GIT_OBJECT_DIRECTORY": "alternate-objects",
            },
        ):
            child_environment = secret_scan._git_child_environment()
        self.assertNotIn("ANTHROPIC_API_KEY", child_environment)
        self.assertNotIn("FORGE_SEMANTIC_MODEL", child_environment)
        self.assertFalse(any(name.upper().startswith("GIT_") for name in child_environment))

    def test_ignored_non_env_text_is_scanned(self) -> None:
        marker = "sk-" + "ant-" + ("I" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"], cwd=root, check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            (root / ".gitignore").write_text("*.ignored\n", encoding="utf-8")
            (root / "local-cache.ignored").write_text(marker, encoding="utf-8")
            findings = scan_repository(root)
            self.assertIn("local-cache.ignored", {finding.path for finding in findings})

    def test_staged_blob_is_scanned_even_when_worktree_is_safe(self) -> None:
        marker = "sk-" + "ant-" + ("S" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"], cwd=root, check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            staged = root / "staged.txt"
            staged.write_text(marker, encoding="utf-8")
            subprocess.run(
                ["git", "add", "staged.txt"], cwd=root, check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            staged.write_text("safe working tree content", encoding="utf-8")
            findings = scan_repository(root)
            self.assertIn("git-index:staged.txt", {finding.path for finding in findings})

    def test_ambient_alternate_index_cannot_hide_canonical_staged_blob(self) -> None:
        marker = "sk-" + "ant-" + ("A" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"], cwd=root, check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            staged = root / "staged.txt"
            staged.write_text(marker, encoding="utf-8")
            subprocess.run(["git", "add", "staged.txt"], cwd=root, check=True)
            staged.write_text("safe working tree content", encoding="utf-8")

            alternate_index = root / "alternate-index"
            alternate_environment = dict(os.environ)
            alternate_environment["GIT_INDEX_FILE"] = str(alternate_index)
            subprocess.run(
                ["git", "add", "staged.txt"],
                cwd=root,
                check=True,
                env=alternate_environment,
            )
            with mock.patch.dict(
                secret_scan.os.environ,
                {"GIT_INDEX_FILE": str(alternate_index)},
            ):
                findings = scan_repository(root)
            self.assertIn("git-index:staged.txt", {finding.path for finding in findings})

    def test_git_replace_cannot_substitute_safe_content_for_staged_blob(self) -> None:
        marker = "sk-" + "ant-" + ("G" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"], cwd=root, check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            staged = root / "staged.txt"
            staged.write_text(marker, encoding="utf-8")
            subprocess.run(["git", "add", "staged.txt"], cwd=root, check=True)
            secret_object = subprocess.run(
                ["git", "rev-parse", ":staged.txt"],
                cwd=root,
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            safe_object = subprocess.run(
                ["git", "hash-object", "-w", "--stdin"],
                cwd=root,
                check=True,
                input="safe replacement content",
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "replace", secret_object, safe_object], cwd=root, check=True
            )
            staged.write_text("safe working tree content", encoding="utf-8")
            findings = scan_repository(root)
            self.assertIn("git-index:staged.txt", {finding.path for finding in findings})

    def test_unicode_escaped_secret_is_detected(self) -> None:
        marker = "sk-" + "ant-" + ("U" * 24)
        escaped = marker
        for _ in range(6):
            escaped = "".join(f"\\u{ord(character):04x}" for character in escaped)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "escaped.json").write_text(escaped, encoding="utf-8")
            findings = scan_repository(root)
            self.assertEqual(
                {finding.rule for finding in findings}, {"anthropic_key_shape"}
            )

    def test_linear_nested_unicode_escape_chain_is_scanned(self) -> None:
        marker = "sk-" + "ant-" + ("L" * 24)
        escaped = "\\u005c" + ("u005c" * 20000) + "u0073" + marker[1:]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "linear-escaped.json").write_text(escaped, encoding="utf-8")
            findings = scan_repository(root)
            self.assertIn(
                "unicode_projection_depth_exceeded",
                {finding.rule for finding in findings},
            )

    def test_sensitive_filename_is_detected_without_echoing_it(self) -> None:
        marker = "sk-" + "ant-" + ("P" * 24)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / f"{marker}.txt").write_text("safe content", encoding="utf-8")
            findings = scan_repository(root)
            self.assertIn("sensitive_path_name", {finding.rule for finding in findings})
            self.assertNotIn(marker, repr(findings))

    def test_unreadable_candidate_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "cannot-read.txt"
            candidate.write_text("safe", encoding="utf-8")
            original_read_bytes = Path.read_bytes

            def guarded_read(path: Path) -> bytes:
                if path.name == candidate.name:
                    raise PermissionError
                return original_read_bytes(path)

            with mock.patch.object(Path, "read_bytes", guarded_read):
                findings = scan_repository(root)
            self.assertIn("file_unreadable", {finding.rule for finding in findings})


if __name__ == "__main__":
    unittest.main()
