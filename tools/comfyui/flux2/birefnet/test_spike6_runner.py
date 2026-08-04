from __future__ import annotations

import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Mapping

from PIL import Image


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import freeze_spike5_evidence as freezer  # noqa: E402
import spike6_runner as runner  # noqa: E402


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_spike5(root: Path) -> Path:
    group = "flux2_matrix_test"
    run = root / "output" / group
    matrix_files: dict[str, Any] = {}
    workflow_hash = "1" * 64
    model_hashes = {"diffusion_model": "2" * 64, "text_encoder": "3" * 64, "vae": "4" * 64}
    model_names = {"diffusion_model": "diffusion.safetensors", "text_encoder": "encoder.safetensors", "vae": "vae.safetensors"}
    workflow_path = root / "workflows" / "source_workflow.json"
    workflow_path.parent.mkdir(parents=True)
    workflow_path.write_bytes(b"source workflow")
    workflow_hash = sha(workflow_path)
    ordinal = 0
    for case in freezer.CASE_ORDER:
        for seed in ("seed_4041001", "seed_4041002"):
            ordinal += 1
            directory = run / case / seed
            directory.mkdir(parents=True)
            (directory / "raw.png").write_bytes(runner.PNG_SIGNATURE + f"raw-{ordinal}".encode())
            write_json(directory / "blueprint_projection.json", {"identity": case})
            write_json(directory / "request_workflow.json", {"node": ordinal})
            write_json(
                directory / "manifest.json",
                {
                    "case_id": case,
                    "run_id": seed,
                    "retry_count": 0,
                    "status": "success",
                    "workflow_sha256": workflow_hash,
                    "workflow_file": workflow_path.name,
                    "models": model_names,
                    "model_sha256": model_hashes,
                },
            )
            if ordinal <= 6:
                (directory / "processed_sprite.png").write_bytes(runner.PNG_SIGNATURE + b"sprite")
                (directory / "alpha_mask.png").write_bytes(runner.PNG_SIGNATURE + b"mask")
            for path in directory.iterdir():
                relative = path.relative_to(root).as_posix()
                matrix_files[f"tools/comfyui/flux2/{relative}"] = {
                    "bytes": path.stat().st_size,
                    "sha256": sha(path),
                }

    reports = root / "reports"
    reports.mkdir(parents=True)
    (reports / "frozen_semantic_blueprints.json").write_text("{}\n", encoding="utf-8")
    blueprint_hash = sha(reports / "frozen_semantic_blueprints.json")
    write_json(
        reports / "flux2_matrix_summary.json",
        {
            "matrix_output_group": group,
            "matrix_run_id": "flux2-matrix-test",
            "technical_results": {"raw_delivered_count": 8},
            "frozen_blueprints_sha256": blueprint_hash,
        },
    )
    for name in (
        "flux2_matrix_results.csv",
        "human_visual_review.csv",
        "human_visual_review_rubric.json",
        "workflow_sources.json",
        "model_download_manifest.json",
        "runtime_install_manifest.json",
    ):
        (reports / name).write_text("{}\n" if name.endswith(".json") else "header\n", encoding="utf-8")
    write_json(
        reports / "model_download_manifest.json",
        {
            "files": [
                {"filename": model_names[role], "sha256": model_hashes[role]}
                for role in model_names
            ]
        },
    )
    write_json(
        reports / "evidence_hashes.json",
        {
            "matrix_run_directory": f"tools/comfyui/flux2/output/{group}",
            "matrix_files": matrix_files,
        },
    )
    return run


def make_approved_config(root: Path, freeze_file: Path) -> Path:
    source_workflow = HERE.parent / "workflows" / "birefnet_remove_background_forge_api.json"
    workflow = json.loads(source_workflow.read_text(encoding="utf-8"))
    workflow_path = root / "workflows" / "workflow.json"
    write_json(workflow_path, workflow)
    config = {
        "contract": runner.CONFIG_CONTRACT,
        "api_base": runner.APPROVED_API_BASE,
        "refuse_if_port_8188_open": True,
        "timeout_seconds": 120,
        "poll_interval_seconds": 0,
        "source_freeze_file": str(freeze_file),
        "source_freeze_sha256": sha(freeze_file),
        "workflow_file": str(workflow_path),
        "workflow_sha256": sha(workflow_path),
        "workflow_audit_status": "APPROVED",
        "output_root": str(root / "birefnet" / "output"),
    }
    path = root / "birefnet" / "config" / "config.json"
    write_json(path, config)
    return path


class FakeTransport:
    def __init__(self, fail_prompt: int | None = None, *, rgba_mode: str = "RGBA", colored_mask: bool = False) -> None:
        self.fail_prompt = fail_prompt
        self.rgba_mode = rgba_mode
        self.colored_mask = colored_mask
        self.uploads: list[str] = []
        self.prompts: list[dict[str, Any]] = []
        self.history_calls: list[str] = []

    def get_json(self, path: str) -> dict[str, Any]:
        if path == "/system_stats":
            return {"system": {"ok": True}}
        self.history_calls.append(path)
        prompt_id = path.rsplit("/", 1)[-1]
        return {
            prompt_id: {
                "status": {"status_str": "success"},
                "outputs": {
                    "7": {"images": [{"filename": f"{prompt_id}-rgba.png", "subfolder": "", "type": "output"}]},
                    "8": {"images": [{"filename": f"{prompt_id}-mask.png", "subfolder": "", "type": "output"}]},
                },
            }
        }

    def post_json(self, path: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        self.prompts.append(dict(payload))
        ordinal = len(self.prompts)
        if self.fail_prompt == ordinal:
            raise runner.Spike6RunnerError("MOCK_SUBMISSION_FAILURE")
        return {"prompt_id": f"prompt-{ordinal}"}

    def post_file(self, path: str, *, filename: str, payload: bytes) -> dict[str, Any]:
        self.uploads.append(filename)
        return {"name": filename, "subfolder": "spike6", "type": "input"}

    def get_bytes(self, path: str) -> bytes:
        output = io.BytesIO()
        if "rgba" in path:
            color: Any = (20, 30, 40, 128) if self.rgba_mode == "RGBA" else (20, 30, 40)
            Image.new(self.rgba_mode, (4, 3), color).save(output, format="PNG")
        else:
            color = (80, 90, 80) if self.colored_mask else (80, 80, 80)
            Image.new("RGB", (4, 3), color).save(output, format="PNG")
        return output.getvalue()


class Spike5FreezeTests(unittest.TestCase):
    def test_freeze_exact_eight_and_reject_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "flux2"
            make_spike5(root)
            destination = root / "birefnet" / "config" / "freeze.json"
            document = freezer.freeze_to_file(root, destination)
            self.assertEqual(document["raw_png_count"], 8)
            self.assertEqual(document["manifest_count"], 8)
            self.assertEqual(document["current_processed_sprite_count"], 6)
            self.assertEqual(document["current_alpha_mask_count"], 6)
            self.assertEqual(sum(job["current_alpha_outputs"] == {} for job in document["jobs"]), 2)
            with self.assertRaisesRegex(freezer.Spike5FreezeError, "FREEZE_ALREADY_EXISTS"):
                freezer.freeze_to_file(root, destination)

    def test_verifier_detects_source_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "flux2"
            run = make_spike5(root)
            destination = root / "freeze.json"
            freezer.freeze_to_file(root, destination)
            (run / "b01" / "seed_4041001" / "raw.png").write_bytes(b"changed")
            with self.assertRaisesRegex(freezer.Spike5FreezeError, "FROZEN_SOURCE_CHANGED"):
                freezer.verify_freeze(root, destination)


class Spike6RunnerTests(unittest.TestCase):
    def fixture(self, temporary: str) -> tuple[Path, Path, Path]:
        root = Path(temporary) / "flux2"
        make_spike5(root)
        freeze_file = root / "birefnet" / "config" / "freeze.json"
        freezer.freeze_to_file(root, freeze_file)
        return root, freeze_file, make_approved_config(root, freeze_file)

    def test_serial_eight_job_run_is_atomic_and_no_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config = self.fixture(temporary)
            transport = FakeTransport()
            final = runner.run(config, "spike6-test", transport=transport, port_probe=lambda port: False, sleeper=lambda _: self.fail("unexpected sleep"), flux2_root=root)
            self.assertTrue(final.is_dir())
            self.assertEqual(len(transport.uploads), 8)
            self.assertEqual(len(transport.prompts), 8)
            self.assertEqual(len(transport.history_calls), 8)
            manifest = json.loads((final / "run_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["completed_job_count"], 8)
            self.assertEqual(manifest["retry_count"], 0)
            self.assertTrue(manifest["serial_execution"])
            self.assertEqual([job["ordinal"] for job in manifest["jobs"]], list(range(1, 9)))
            for directory in final.glob("??_*"):
                self.assertTrue((directory / "rgba.png").is_file())
                self.assertTrue((directory / "mask.png").is_file())
                with Image.open(directory / "rgba.png") as rgba:
                    self.assertEqual(rgba.mode, "RGBA")
                with Image.open(directory / "mask.png") as mask:
                    self.assertEqual(mask.mode, "L")

    def test_8188_refusal_happens_before_http(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config = self.fixture(temporary)
            transport = FakeTransport()
            with self.assertRaisesRegex(runner.Spike6RunnerError, "PORT_8188_IS_LISTENING"):
                runner.run(config, "blocked", transport=transport, port_probe=lambda port: port == 8188, flux2_root=root)
            self.assertEqual(transport.uploads, [])
            self.assertEqual(transport.prompts, [])

    def test_submission_failure_is_not_retried_or_published(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config = self.fixture(temporary)
            transport = FakeTransport(fail_prompt=3)
            with self.assertRaisesRegex(runner.Spike6RunnerError, "MOCK_SUBMISSION_FAILURE"):
                runner.run(config, "failure", transport=transport, port_probe=lambda port: False, flux2_root=root)
            self.assertEqual(len(transport.prompts), 3)
            self.assertFalse((root / "birefnet" / "output" / "failure").exists())

    def test_colored_mask_is_rejected_without_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config = self.fixture(temporary)
            transport = FakeTransport(colored_mask=True)
            with self.assertRaisesRegex(runner.Spike6RunnerError, "MASK_NOT_GRAYSCALE"):
                runner.run(config, "colored-mask", transport=transport, port_probe=lambda port: False, flux2_root=root)
            self.assertEqual(len(transport.prompts), 1)
            self.assertFalse((root / "birefnet" / "output" / "colored-mask").exists())

    def test_non_rgba_primary_output_is_rejected_without_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config = self.fixture(temporary)
            transport = FakeTransport(rgba_mode="RGB")
            with self.assertRaisesRegex(runner.Spike6RunnerError, "RGBA_MODE_INVALID:RGB"):
                runner.run(config, "rgb-only", transport=transport, port_probe=lambda port: False, flux2_root=root)
            self.assertEqual(len(transport.prompts), 1)
            self.assertFalse((root / "birefnet" / "output" / "rgb-only").exists())

    def test_config_refuses_non_loopback_or_pending_workflow(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config_path = self.fixture(temporary)
            config = json.loads(config_path.read_text(encoding="utf-8"))
            config["api_base"] = "http://127.0.0.1:8188"
            write_json(config_path, config)
            with self.assertRaisesRegex(runner.Spike6RunnerError, "API_BASE_MUST_BE"):
                runner.load_config(config_path)
            config["api_base"] = runner.APPROVED_API_BASE
            config["workflow_audit_status"] = "PENDING_READ_ONLY_AUDIT"
            write_json(config_path, config)
            with self.assertRaisesRegex(runner.Spike6RunnerError, "WORKFLOW_AUDIT_NOT_APPROVED"):
                runner.load_config(config_path)

    def test_existing_final_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, _freeze, config = self.fixture(temporary)
            final = root / "birefnet" / "output" / "existing"
            final.mkdir(parents=True)
            sentinel = final / "sentinel.txt"
            sentinel.write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(runner.Spike6RunnerError, "ALREADY_EXISTS"):
                runner.run(config, "existing", transport=FakeTransport(), port_probe=lambda port: False, flux2_root=root)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main()
