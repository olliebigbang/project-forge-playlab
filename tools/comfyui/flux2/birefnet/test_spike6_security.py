from __future__ import annotations

import csv
import hashlib
import json
import re
import socket
import struct
import subprocess
import sys
import unittest
from pathlib import Path

from PIL import Image


HERE = Path(__file__).resolve().parent
FLUX2_ROOT = HERE.parent
REPO_ROOT = HERE.parents[3]
COMFY_ROOT = Path(r"C:\AI\ComfyUI-ForgeFlux2\ComfyUI")
MODEL = COMFY_ROOT / "models" / "background_removal" / "birefnet.safetensors"
RUN = HERE / "output" / "spike6-birefnet-20260803T135800Z"
PACKET = HERE / "review_packets" / "spike6-birefnet-20260803T135800Z-verified"
FREEZE = HERE / "config" / "spike5_evidence.freeze.json"
OFFICIAL_COPY = FLUX2_ROOT / "workflows" / "birefnet_remove_background_official.json"
FORGE_WORKFLOW = FLUX2_ROOT / "workflows" / "birefnet_remove_background_forge_api.json"
EXPECTED_MODEL_SHA = "9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154"
EXPECTED_OFFICIAL_SHA = "ab7bf67d91a17750222da4131790ca38f651d8078ff28213e15cf0ebd86b3354"
EXPECTED_FORGE_SHA = "56d74936b840de2ce2d5e823b6ad1704b9e65dd7ddd8b7a0edbfb5d4d4cf19df"

sys.path.insert(0, str(HERE))
import freeze_spike5_evidence as freezer  # noqa: E402


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def json_object(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"JSON object required: {path}")
    return value


class Spike6SecurityTests(unittest.TestCase):
    def test_01_spike5_frozen_evidence_is_unchanged(self) -> None:
        verified = freezer.verify_freeze(FLUX2_ROOT, FREEZE)
        self.assertEqual(verified["job_count"], 8)
        self.assertEqual(sha256(FREEZE), "57b1de80841d4c5f3da4c07b5cb0dee606a3a3dbfffbbb1ba387d617f59f7af8")

    def test_02_model_hash_header_and_partial_state(self) -> None:
        self.assertTrue(MODEL.is_file())
        self.assertEqual(MODEL.stat().st_size, 444473596)
        self.assertEqual(sha256(MODEL), EXPECTED_MODEL_SHA)
        self.assertFalse(Path(str(MODEL) + ".partial").exists())
        with MODEL.open("rb") as handle:
            header_length = struct.unpack("<Q", handle.read(8))[0]
            header = json.loads(handle.read(header_length).decode("utf-8"))
        self.assertEqual(header_length, 86776)
        self.assertIn("bb.layers.1.blocks.0.attn.relative_position_index", header)

    def test_03_official_workflow_is_unchanged_byte_copy(self) -> None:
        installed = COMFY_ROOT / "blueprints" / "Remove Background (BiRefNet).json"
        self.assertEqual(sha256(installed), EXPECTED_OFFICIAL_SHA)
        self.assertEqual(sha256(OFFICIAL_COPY), EXPECTED_OFFICIAL_SHA)
        self.assertEqual(installed.read_bytes(), OFFICIAL_COPY.read_bytes())

    def test_04_forge_workflow_is_native_segmentation_only(self) -> None:
        self.assertEqual(sha256(FORGE_WORKFLOW), EXPECTED_FORGE_SHA)
        workflow = json_object(FORGE_WORKFLOW)
        allowed = {
            "LoadImage",
            "LoadBackgroundRemovalModel",
            "RemoveBackground",
            "MaskToImage",
            "InvertMask",
            "JoinImageWithAlpha",
            "SaveImage",
        }
        class_types = {node.get("class_type") for key, node in workflow.items() if key != "_forge"}
        self.assertEqual(class_types, allowed)
        serialized = json.dumps(workflow, sort_keys=True).lower()
        for forbidden in ("ksampler", "samplercustom", "unetloader", "cliploader", "fluxguidance"):
            self.assertNotIn(forbidden, serialized)
        self.assertEqual(workflow["2"]["inputs"]["bg_removal_name"], "birefnet.safetensors")

    def test_05_runtime_was_loopback_only_and_both_ports_are_closed(self) -> None:
        lifecycle = json_object(HERE / "logs" / "lifecycle_last.json")
        self.assertEqual(lifecycle["status"], "PASS")
        self.assertEqual(lifecycle["action"], "stopped")
        self.assertTrue(lifecycle["port_8188_closed"])
        self.assertTrue(lifecycle["port_8190_closed"])
        for port in (8188, 8190):
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                probe.settimeout(0.25)
                self.assertNotEqual(probe.connect_ex(("127.0.0.1", port)), 0)

    def test_06_run_is_exactly_eight_serial_jobs_with_zero_retry(self) -> None:
        run = json_object(RUN / "run_manifest.json")
        self.assertEqual(run["api_base"], "http://127.0.0.1:8190")
        self.assertEqual(run["planned_job_count"], 8)
        self.assertEqual(run["completed_job_count"], 8)
        self.assertEqual(run["retry_count"], 0)
        self.assertTrue(run["serial_execution"])
        self.assertEqual(len(run["jobs"]), 8)
        self.assertTrue(all(job["retry_count"] == 0 and job["status"] == "success" for job in run["jobs"]))

    def test_07_all_rgba_mask_and_delivery_pairs_are_valid(self) -> None:
        job_dirs = sorted(path for path in RUN.iterdir() if path.is_dir())
        self.assertEqual(len(job_dirs), 8)
        for job in job_dirs:
            with Image.open(job / "rgba.png") as rgba:
                self.assertEqual((rgba.format, rgba.mode, rgba.size), ("PNG", "RGBA", (512, 512)))
            with Image.open(job / "mask.png") as mask:
                self.assertEqual((mask.format, mask.mode, mask.size), ("PNG", "L", (512, 512)))
            with Image.open(job / "delivery" / "processed_sprite.png") as sprite:
                self.assertEqual((sprite.format, sprite.mode, sprite.size), ("PNG", "RGBA", (96, 96)))
                sprite_alpha = sprite.getchannel("A").tobytes()
            with Image.open(job / "delivery" / "alpha_mask.png") as alpha:
                self.assertEqual((alpha.format, alpha.mode, alpha.size), ("PNG", "L", (96, 96)))
                alpha_bytes = alpha.tobytes()
            self.assertEqual(sprite_alpha, alpha_bytes)
            self.assertNotEqual(set(alpha_bytes), {0})

    def test_08_verified_review_packet_covers_inputs_and_artifacts(self) -> None:
        manifest = json_object(PACKET / "review_packet_manifest.json")
        self.assertEqual(manifest["status"], "PASS")
        self.assertEqual(manifest["job_count"], 8)
        self.assertEqual(manifest["input_file_count"], 64)
        self.assertEqual(manifest["artifact_file_count"], 5)
        for record in manifest["input_files"]:
            path = (FLUX2_ROOT / record["path"]).resolve(strict=True)
            path.relative_to(FLUX2_ROOT)
            self.assertEqual(path.stat().st_size, record["bytes"])
            self.assertEqual(sha256(path), record["sha256"])
        for record in manifest["artifacts"]:
            path = (PACKET / record["path"]).resolve(strict=True)
            path.relative_to(PACKET)
            self.assertEqual(path.stat().st_size, record["bytes"])
            self.assertEqual(sha256(path), record["sha256"])

    def test_09_human_review_is_complete_and_meets_declared_gate(self) -> None:
        with (HERE / "reviews" / "human_structure_review.csv").open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 8)
        self.assertEqual(sum(row["usable_sprite"] == "TRUE" for row in rows), 7)
        self.assertEqual(sum(row["identity_recognizable_96"] == "TRUE" for row in rows), 8)
        self.assertEqual(sum(row["serious_structure_loss"] == "TRUE" for row in rows), 0)
        self.assertEqual(sum(row["no_background_residual"] == "FALSE" for row in rows), 0)
        self.assertEqual(sum(row["no_shadow_residual"] == "FALSE" for row in rows), 0)
        self.assertTrue(all(int(row["required_parts_visible_count"]) >= 2 for row in rows))

    def test_10_postprocessor_does_not_regenerate_mask_or_keep_only_largest(self) -> None:
        source = (HERE / "process_birefnet_sprite.py").read_text(encoding="utf-8").lower()
        for forbidden in ("grabcut", "floodfill", "flood_fill", "largest_component_only\": true"):
            self.assertNotIn(forbidden, source)
        self.assertIn('"largest_component_only": false', source)
        self.assertIn('"segmentation_source": "official_birefnet_rgba_plus_mask"', source)

    def test_11_no_provider_secret_or_anthropic_runtime_reference(self) -> None:
        candidates = [
            HERE / "spike6_runner.py",
            HERE / "process_birefnet_sprite.py",
            HERE / "scripts" / "start_birefnet_comfyui.ps1",
            FORGE_WORKFLOW,
        ]
        secret_pattern = re.compile(r"sk" + r"-ant-[A-Za-z0-9_-]{16,}")
        provider_import = "import " + "anthropic"
        provider_endpoint = "api." + "anthropic.com"
        for path in candidates:
            text = path.read_text(encoding="utf-8", errors="ignore")
            self.assertIsNone(secret_pattern.search(text))
            self.assertNotIn(provider_import, text.lower())
            self.assertNotIn(provider_endpoint, text.lower())

    def test_12_model_is_ignored_and_not_git_tracked(self) -> None:
        relative = MODEL.relative_to(COMFY_ROOT).as_posix()
        ignored = subprocess.run(
            ["git", "-C", str(COMFY_ROOT), "check-ignore", "-q", relative],
            check=False,
        )
        tracked = subprocess.run(
            ["git", "-C", str(COMFY_ROOT), "ls-files", "--error-unmatch", relative],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.assertEqual(ignored.returncode, 0)
        self.assertNotEqual(tracked.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
