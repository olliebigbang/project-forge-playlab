from __future__ import annotations

import ast
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import gate_b_4b_runner as runner  # noqa: E402


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _metrics(status: str, failure_reason: str = "") -> dict[str, object]:
    value: dict[str, object] = {
        "status": status,
        "foreground_coverage": 0.22,
        "edge_contact_ratio": 0.0,
        "background_residual_ratio": 0.01,
        "internal_hole_ratio": 0.0,
        "component_count": 2,
        "kept_component_count": 2,
        "removed_component_count": 1,
        "removed_area": 37,
        "smallest_kept_component_area": 91,
        "object_bbox": [20, 22, 92, 88],
        "soft_edge_pixel_ratio": 0.12,
        "shadow_residual_score": 0.01,
        "segmentation_confidence": 0.88,
        "postprocess_seconds": 0.01,
    }
    if failure_reason:
        value["failure_reason"] = failure_reason
    return value


def _write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, sort_keys=True), encoding="utf-8")


class FakeProcessor:
    def __init__(self, reject_ordinal: int | None = None, malformed_ordinal: int | None = None) -> None:
        self.calls: list[tuple[Path, Path, bool]] = []
        self.reject_ordinal = reject_ordinal
        self.malformed_ordinal = malformed_ordinal

    def __call__(self, source: Path, destination: Path, *, debug: bool) -> dict[str, object]:
        self.calls.append((source, destination, debug))
        ordinal = len(self.calls)
        if ordinal == self.malformed_ordinal:
            raise RuntimeError("synthetic interrupted processor")
        destination.mkdir(parents=True)
        if ordinal == self.reject_ordinal:
            metrics = _metrics("rejected", "LOW_SEGMENTATION_CONFIDENCE")
            _write_json(destination / "metrics.json", metrics)
            debug_dir = destination / "debug"
            debug_dir.mkdir()
            Image.new("L", (32, 32), 127).save(debug_dir / "final_failure_region.png")
            raise runner.SpritePostprocessError(
                "LOW_SEGMENTATION_CONFIDENCE",
                metrics=metrics,
                evidence_path=destination,
            )
        metrics = _metrics("success")
        sprite = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        opaque = Image.new("RGBA", (48, 48), (30, 120, 220, 255))
        sprite.alpha_composite(opaque, (24, 24))
        sprite.save(destination / "processed_sprite.png")
        sprite.getchannel("A").save(destination / "alpha_mask.png")
        _write_json(destination / "metrics.json", metrics)
        return metrics


class GateB4BRunnerTests(unittest.TestCase):
    def test_frozen_4a_tree_and_exactly_eight_raws_verify_byte_for_byte(self) -> None:
        frozen, audit = runner.verify_frozen_inputs()

        self.assertEqual(_hash(runner.FROZEN_4A_PATH), runner.EXPECTED_FROZEN_4A_SHA256)
        self.assertEqual(audit["gate_4a"]["frozen_tree_file_count"], 78)
        self.assertEqual(audit["gate_4a"]["frozen_raw_count"], 8)
        self.assertEqual(
            tuple((item["case_id"], item["seed"]) for item in frozen["case_matrix"]),
            runner.EXPECTED_PAIRS,
        )
        self.assertEqual(len({item["raw"]["path"] for item in frozen["case_matrix"]}), 8)

    def test_gameplay_freeze_verifies_and_detects_byte_change_offline(self) -> None:
        _, audit = runner._load_and_verify_gameplay()
        self.assertEqual(audit["file_count"], 84)
        self.assertEqual(_hash(runner.FROZEN_GAMEPLAY_PATH), runner.EXPECTED_FROZEN_GAMEPLAY_SHA256)

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            for directory in runner.GAMEPLAY_DIRECTORIES:
                (project / directory).mkdir()
            records: dict[str, dict[str, object]] = {}
            for relative in runner.GAMEPLAY_ROOT_FILES:
                path = project / relative
                path.write_bytes(b"frozen")
                records[relative] = {"size": 6, "sha256": _hash(path)}
            payload = {"file_count": len(records), "files": records}
            runner._verify_gameplay_payload(payload, project)
            (project / "project.godot").write_bytes(b"changed")
            with self.assertRaisesRegex(runner.GateB4BRunnerError, "MISMATCH:gameplay"):
                runner._verify_gameplay_payload(payload, project)

    def test_offline_eight_image_run_is_atomic_and_never_overwrites_v1(self) -> None:
        frozen = json.loads(runner.FROZEN_4A_PATH.read_text(encoding="utf-8"))
        v1 = next(item["v1_processed_sprite"] for item in frozen["case_matrix"] if item["v1_processed_sprite"])
        v1_path = runner.PROJECT_ROOT / v1["path"]
        v1_before = _hash(v1_path)
        processor = FakeProcessor(reject_ordinal=2)

        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            summary = runner.run_gate_b_4b(
                output_root=base / "output",
                reservation_root=base / "reservations",
                processor=processor,
            )
            final = Path(summary["run_directory"])

            self.assertTrue((final / "RUN_COMPLETE.json").is_file())
            self.assertEqual(len(processor.calls), 8)
            self.assertTrue(all(call[2] is True for call in processor.calls))
            self.assertEqual(summary["processor_invocation_count"], 8)
            self.assertEqual(summary["v2_success_count"], 7)
            self.assertEqual(summary["v2_rejected_count"], 1)
            self.assertEqual(summary["automatic_retry_count"], 0)
            self.assertEqual(len(list(final.glob("B*/seed_*"))), 8)
            self.assertFalse(any((base / "output" / ".tmp").iterdir()))
            rejected = final / "B01" / "seed_4041002"
            self.assertFalse((rejected / "processed_sprite.png").exists())
            self.assertFalse((rejected / "alpha_mask.png").exists())
            self.assertTrue((rejected / "debug" / "final_failure_region.png").is_file())
            rejection_record = json.loads((rejected / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(rejection_record["v2"]["failure_reason"], "LOW_SEGMENTATION_CONFIDENCE")
            self.assertEqual(rejection_record["v2"]["processor_invocation_count"], 1)
            self.assertEqual(_hash(v1_path), v1_before)
            self.assertEqual(_hash(runner.FROZEN_4A_PATH), runner.EXPECTED_FROZEN_4A_SHA256)
            self.assertEqual(_hash(runner.FROZEN_GAMEPLAY_PATH), runner.EXPECTED_FROZEN_GAMEPLAY_SHA256)

    def test_interrupted_processor_leaves_no_partial_final_run(self) -> None:
        processor = FakeProcessor(malformed_ordinal=3)
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            with self.assertRaisesRegex(RuntimeError, "synthetic interrupted"):
                runner.run_gate_b_4b(
                    output_root=base / "output",
                    reservation_root=base / "reservations",
                    processor=processor,
                )
            reservations = list((base / "reservations").glob("*.json"))
            self.assertEqual(len(reservations), 1)
            reserved = json.loads(reservations[0].read_text(encoding="utf-8"))
            self.assertFalse(Path(reserved["output_directory"]).exists())
            self.assertFalse(any((base / "output" / ".tmp").iterdir()))

    def test_run_reservation_is_exclusive_and_immutable(self) -> None:
        real_open = runner.os.open
        observed_flags: list[int] = []

        def observing_open(path: object, flags: int, *args: object, **kwargs: object) -> int:
            observed_flags.append(flags)
            return real_open(path, flags, *args, **kwargs)

        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            with mock.patch.object(runner.os, "open", side_effect=observing_open):
                first_id, first_path, _ = runner._reserve_unique_run(base / "reservations", base / "output")
                first_hash = _hash(first_path)
                second_id, second_path, _ = runner._reserve_unique_run(base / "reservations", base / "output")

            self.assertNotEqual(first_id, second_id)
            self.assertNotEqual(first_path, second_path)
            self.assertEqual(_hash(first_path), first_hash)
            self.assertTrue(all(flags & runner.os.O_EXCL for flags in observed_flags))

    def test_runner_has_no_external_service_or_process_launch_capability(self) -> None:
        source = Path(runner.__file__).read_text(encoding="utf-8")
        tree = ast.parse(source)
        imports: set[str] = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imports.add(node.module.split(".")[0])
        self.assertTrue(imports.isdisjoint({"socket", "requests", "urllib", "http", "subprocess", "anthropic"}))
        for forbidden in ("ANTHROPIC_API_KEY", "Start-Process", "subprocess.Popen", "requests.post"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
