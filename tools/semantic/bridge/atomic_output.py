"""Validated, non-overwriting atomic directory delivery for semantic results."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Callable


class AtomicOutputError(RuntimeError):
    pass


class AtomicValidationError(AtomicOutputError):
    pass


class AtomicDestinationExistsError(AtomicOutputError):
    pass


def _lexists(path: Path) -> bool:
    return os.path.lexists(os.fspath(path))


def _validate_tree_is_local(source: Path) -> None:
    entries = list(source.rglob("*"))
    if not entries:
        raise AtomicValidationError("Temporary result directory is empty.")
    for entry in entries:
        if entry.is_symlink():
            raise AtomicValidationError(
                "Temporary result directory contains a symbolic link."
            )


def atomic_deliver(
    temp_dir: str | os.PathLike[str],
    final_dir: str | os.PathLike[str],
    validator: Callable[[Path], object],
) -> Path:
    """Validate ``temp_dir`` and atomically move it to a new ``final_dir``.

    The destination is never intentionally overwritten.  Validation failures
    retain the temporary directory for failure evidence and diagnosis.
    ``validator`` may return ``None`` on success; returning exactly ``False``
    rejects delivery.
    """

    if not callable(validator):
        raise TypeError("validator must be callable")

    raw_source = Path(temp_dir)
    if raw_source.is_symlink():
        raise AtomicValidationError("Temporary result directory is a symbolic link.")
    try:
        source = raw_source.resolve(strict=True)
    except FileNotFoundError as exc:
        raise AtomicValidationError(
            "Temporary result directory does not exist."
        ) from exc
    destination = Path(final_dir).resolve(strict=False)
    if not source.is_dir():
        raise AtomicValidationError("Temporary result path is not a directory.")
    if source == destination:
        raise AtomicOutputError("Temporary and final directories must differ.")
    if source in destination.parents or destination in source.parents:
        raise AtomicOutputError(
            "Temporary and final directories must not contain one another."
        )
    if _lexists(destination):
        raise AtomicDestinationExistsError(
            f"Final result directory already exists: {destination}"
        )

    destination.parent.mkdir(parents=True, exist_ok=True)
    _validate_tree_is_local(source)
    if os.stat(source).st_dev != os.stat(destination.parent).st_dev:
        raise AtomicOutputError(
            "Temporary and final directories are on different filesystems."
        )

    validation_result = validator(source)
    if validation_result is False:
        raise AtomicValidationError("Temporary result validation returned False.")
    if _lexists(destination):
        raise AtomicDestinationExistsError(
            f"Final result directory appeared during validation: {destination}"
        )

    try:
        os.replace(source, destination)
    except FileExistsError as exc:
        raise AtomicDestinationExistsError(
            f"Final result directory already exists: {destination}"
        ) from exc
    return destination


__all__ = [
    "AtomicDestinationExistsError",
    "AtomicOutputError",
    "AtomicValidationError",
    "atomic_deliver",
]
