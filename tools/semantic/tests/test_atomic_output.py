from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


BRIDGE_DIR = Path(__file__).resolve().parents[1] / "bridge"
sys.path.insert(0, str(BRIDGE_DIR))

from atomic_output import (  # noqa: E402
    AtomicDestinationExistsError,
    AtomicValidationError,
    atomic_deliver,
)


class AtomicOutputTests(unittest.TestCase):
    def test_validated_directory_is_atomically_delivered(self) -> None:
        with tempfile.TemporaryDirectory() as root_text:
            root = Path(root_text)
            source = root / ".tmp" / "request_1"
            source.mkdir(parents=True)
            (source / "result.json").write_text('{"status":"ok"}', encoding="utf-8")
            destination = root / "output" / "gate_a" / "01"
            validator_calls: list[Path] = []

            def validator(path: Path) -> bool:
                validator_calls.append(path)
                return (path / "result.json").read_text(encoding="utf-8") == '{"status":"ok"}'

            delivered = atomic_deliver(source, destination, validator)
            self.assertEqual(delivered, destination.resolve())
            self.assertEqual(validator_calls, [source.resolve()])
            self.assertFalse(source.exists())
            self.assertTrue((destination / "result.json").is_file())

    def test_failed_validation_retains_temporary_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as root_text:
            root = Path(root_text)
            source = root / ".tmp" / "request_bad"
            source.mkdir(parents=True)
            (source / "result.json").write_text("invalid", encoding="utf-8")
            destination = root / "output" / "gate_a" / "02"
            with self.assertRaises(AtomicValidationError):
                atomic_deliver(source, destination, lambda _path: False)
            self.assertTrue(source.is_dir())
            self.assertFalse(destination.exists())

    def test_existing_destination_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as root_text:
            root = Path(root_text)
            source = root / ".tmp" / "request_2"
            source.mkdir(parents=True)
            (source / "new.txt").write_text("new", encoding="utf-8")
            destination = root / "output" / "gate_a" / "03"
            destination.mkdir(parents=True)
            existing = destination / "existing.txt"
            existing.write_text("keep", encoding="utf-8")

            with self.assertRaises(AtomicDestinationExistsError):
                atomic_deliver(source, destination, lambda _path: True)
            self.assertEqual(existing.read_text(encoding="utf-8"), "keep")
            self.assertTrue(source.is_dir())

    def test_destination_created_during_validation_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as root_text:
            root = Path(root_text)
            source = root / ".tmp" / "request_3"
            source.mkdir(parents=True)
            (source / "new.txt").write_text("new", encoding="utf-8")
            destination = root / "output" / "gate_a" / "04"

            def racing_validator(_path: Path) -> bool:
                destination.mkdir(parents=True)
                (destination / "winner.txt").write_text("keep", encoding="utf-8")
                return True

            with self.assertRaises(AtomicDestinationExistsError):
                atomic_deliver(source, destination, racing_validator)
            self.assertEqual(
                (destination / "winner.txt").read_text(encoding="utf-8"), "keep"
            )
            self.assertTrue(source.exists())

    def test_empty_temporary_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as root_text:
            root = Path(root_text)
            source = root / ".tmp" / "empty"
            source.mkdir(parents=True)
            destination = root / "output" / "gate_a" / "05"
            with self.assertRaises(AtomicValidationError):
                atomic_deliver(source, destination, lambda _path: True)
            self.assertTrue(source.exists())
            self.assertFalse(destination.exists())

    def test_missing_temporary_directory_is_explicitly_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as root_text:
            root = Path(root_text)
            source = root / ".tmp" / "missing"
            destination = root / "output" / "gate_a" / "06"
            with self.assertRaises(AtomicValidationError):
                atomic_deliver(source, destination, lambda _path: True)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
