"""Rescale an already-finished sprite so its length reflects the real object.

Why this exists as a separate tool: process_sprite.py consumes a raw flat-chroma
render, and the raw images for frying_pan, old_mop and giant_wooden_spoon are not
in the repository -- only their finished 96x96 sprites survived. This applies the
same scale formula to the best source that still exists, so all four objects can be
compared on one ruler. Sprites rebuilt this way come from a lossy source and are
evidence, not production assets.

Usage:
    python rescale_to_real_length.py <in.png> <out.png> --object-id old_mop
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from process_sprite import (  # noqa: E402
    PX_PER_CM,
    REAL_LENGTH_CM,
    SpritePostprocessError,
    _harden_alpha,
    _principal_axis_length,
    _resize_premultiplied,
)


def rescale_to_real_length(
    source_path: Path,
    output_path: Path,
    *,
    real_length_cm: float,
    px_per_cm: float = PX_PER_CM,
    sprite_size: int = 96,
    alpha_threshold: int = 128,
) -> dict:
    source = Image.open(source_path).convert("RGBA")
    source.load()
    alpha = np.array(source.getchannel("A"), dtype=np.uint8)
    silhouette = alpha >= alpha_threshold
    if not silhouette.any():
        raise SpritePostprocessError("NO_SUBJECT_ALPHA")

    source_axis_px = _principal_axis_length(silhouette)
    if source_axis_px <= 0.0:
        raise SpritePostprocessError("DEGENERATE_PRINCIPAL_AXIS")

    ys, xs = np.nonzero(silhouette)
    cropped = source.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))

    scale = (real_length_cm * px_per_cm) / source_axis_px
    resized_size = (max(1, int(round(cropped.width * scale))), max(1, int(round(cropped.height * scale))))
    if resized_size[0] > sprite_size or resized_size[1] > sprite_size:
        raise SpritePostprocessError("REAL_LENGTH_EXCEEDS_SPRITE_FRAME")
    resized = _resize_premultiplied(cropped, resized_size)

    sprite = Image.new("RGBA", (sprite_size, sprite_size), (0, 0, 0, 0))
    sprite.alpha_composite(resized, ((sprite_size - resized.width) // 2, (sprite_size - resized.height) // 2))
    sprite = _harden_alpha(sprite, alpha_threshold)

    output_alpha = np.array(sprite.getchannel("A"), dtype=np.uint8)
    if output_alpha.max(initial=0) == 0:
        raise SpritePostprocessError("NO_SUBJECT_ALPHA")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sprite.save(output_path, format="PNG", optimize=True)
    return {
        "source": str(source_path),
        "real_length_cm": real_length_cm,
        "px_per_cm": px_per_cm,
        "source_axis_px": round(source_axis_px, 2),
        "target_axis_px": round(real_length_cm * px_per_cm, 2),
        "measured_axis_px": round(_principal_axis_length(output_alpha >= alpha_threshold), 2),
        "scale": round(scale, 4),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source_png", type=Path)
    parser.add_argument("output_png", type=Path)
    parser.add_argument("--object-id", choices=sorted(REAL_LENGTH_CM))
    parser.add_argument("--real-length-cm", type=float)
    parser.add_argument("--px-per-cm", type=float, default=PX_PER_CM)
    parser.add_argument("--size", type=int, default=96)
    parser.add_argument("--alpha-threshold", type=int, default=128)
    args = parser.parse_args()

    real_length_cm = args.real_length_cm
    if real_length_cm is None and args.object_id is not None:
        real_length_cm = REAL_LENGTH_CM[args.object_id]
    if real_length_cm is None:
        raise SystemExit("pass --object-id or --real-length-cm")

    try:
        result = rescale_to_real_length(
            args.source_png,
            args.output_png,
            real_length_cm=real_length_cm,
            px_per_cm=args.px_per_cm,
            sprite_size=args.size,
            alpha_threshold=args.alpha_threshold,
        )
    except SpritePostprocessError as exc:
        print(json.dumps({"status": "failed", "failure_reason": str(exc)}))
        return 2
    print(json.dumps({"status": "success", **result}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
