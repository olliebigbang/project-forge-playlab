from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SEMANTIC_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SEMANTIC_ROOT.parents[1]
sys.path.insert(0, str(SEMANTIC_ROOT / "bridge"))

from scope_guard import verify_scope_baseline  # noqa: E402


def _gameplay_aggregate() -> str:
    files = [REPO_ROOT / "project.godot"]
    files.extend(
        sorted(
            [*(REPO_ROOT / "scripts").rglob("*"), *(REPO_ROOT / "scenes").rglob("*")],
            key=str,
        )
    )
    records = [
        f"{path.relative_to(REPO_ROOT)}={hashlib.sha256(path.read_bytes()).hexdigest().upper()}"
        for path in files
        if path.is_file()
    ]
    return hashlib.sha256("\n".join(records).encode("utf-8")).hexdigest()


class GateAScopeBoundaryTests(unittest.TestCase):
    def test_secret_scan_subprocess_cannot_load_python_startup_hook_with_key(self) -> None:
        powershell = shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        with tempfile.TemporaryDirectory() as directory:
            probe_root = Path(directory)
            marker = probe_root / "startup-hook-ran.txt"
            (probe_root / "sitecustomize.py").write_text(
                "from pathlib import Path\n"
                "import os\n"
                "Path(os.environ['FORGE_STARTUP_PROBE']).write_text("
                "'seen' if os.environ.get('ANTHROPIC_API_KEY') else 'absent')\n",
                encoding="utf-8",
            )
            child_environment = dict(os.environ)
            child_environment.update(
                {
                    "ANTHROPIC_API_KEY": "in-memory-startup-probe",
                    "FORGE_SEMANTIC_MODEL": "exact-test-model",
                    "FORGE_STARTUP_PROBE": str(marker),
                    "PYTHONPATH": str(probe_root),
                }
            )
            completed = subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SEMANTIC_ROOT / "scripts" / "verify_no_secrets.ps1"),
                ],
                cwd=REPO_ROOT,
                env=child_environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertFalse(marker.exists())

    def test_python_launches_block_startup_hooks_and_preflight_scrubs_credentials(self) -> None:
        scripts = SEMANTIC_ROOT / "scripts"
        test_script = (scripts / "test_semantic.ps1").read_text(encoding="utf-8")
        scan_script = (scripts / "verify_no_secrets.ps1").read_text(encoding="utf-8")
        core_script = (scripts / "invoke_gate_a_core.ps1").read_text(encoding="utf-8")
        for text in (test_script, scan_script):
            self.assertIn("Remove-Item Env:ANTHROPIC_API_KEY", text)
            self.assertIn("Remove-Item Env:FORGE_SEMANTIC_MODEL", text)
            self.assertIn("-E -S -B", text)
            self.assertLess(
                text.index("Remove-Item Env:ANTHROPIC_API_KEY"),
                text.index("& $pythonCommand.Source"),
            )
        self.assertIn("-E -S -B", core_script)

    def test_godot_gameplay_tree_matches_pre_gate_a_baseline(self) -> None:
        baseline = json.loads(
            (SEMANTIC_ROOT / "reports" / "gate_a_scope_baseline.json").read_text(encoding="utf-8")
        )
        self.assertEqual(_gameplay_aggregate(), baseline["aggregate_sha256"])

    def test_full_nonsemantic_scope_matches_pre_execution_baseline(self) -> None:
        snapshot = verify_scope_baseline(
            REPO_ROOT,
            SEMANTIC_ROOT / "reports" / "gate_a_scope_baseline.json",
        )
        self.assertEqual(snapshot["file_count"], 685)

    def test_gate_a_executables_cannot_start_comfyui_or_gate_b(self) -> None:
        executable_files = list((SEMANTIC_ROOT / "bridge").glob("*.py"))
        executable_files.extend((SEMANTIC_ROOT / "scripts").glob("*.ps1"))
        combined = "\n".join(path.read_text(encoding="utf-8") for path in executable_files if path.exists())
        for forbidden in (
            "start_comfyui.ps1",
            "--listen 127.0.0.1",
            "gate_b_runner",
            "run_gate_b",
        ):
            self.assertNotIn(forbidden, combined.lower())


if __name__ == "__main__":
    unittest.main()
