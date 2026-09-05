#!/usr/bin/env python3
"""Render one validated general object through fal, then convert it to pixel art."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Mapping


VISUAL_ROOT = Path(__file__).resolve().parent
SEMANTIC_BRIDGE_ROOT = VISUAL_ROOT.parent / "semantic" / "bridge"
for module_root in (VISUAL_ROOT, SEMANTIC_BRIDGE_ROOT):
    if str(module_root) not in sys.path:
        sys.path.insert(0, str(module_root))

import fal_firearm_pixel_bridge as shared  # noqa: E402
from general_object_ai_bridge import (  # noqa: E402
    FLAG_KEYS,
    STRING_AXIS_KEYS,
    GeneralObjectBridgeError,
    _validate_mechanism_roles,
    _validate_supported_declaration,
)


REQUEST_SCHEMA = "forge-fal-general-object-visual-request-v2"
MANIFEST_SCHEMA = "forge-fal-general-object-visual-manifest-v1"
PROVIDER_ID = "FAL_GENERAL_OBJECT"
MAX_JSON_BYTES = 2 * 1024 * 1024
EXPECTED_REQUEST_KEYS = frozenset(
    {
        "schema",
        "identity",
        "canonical_name",
        "visual_description",
        "required_identity_parts",
        "confusable_exclusions",
        "mechanism_roles",
        "structure_prompt",
        "scale_treatment",
        "axes",
        "seed",
        "retry_index",
        "retry_prompt",
    }
)


class FalGeneralObjectBridgeError(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _read_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise FalGeneralObjectBridgeError("REQUEST_READ_FAILED") from exc
    if len(raw) > MAX_JSON_BYTES:
        raise FalGeneralObjectBridgeError("REQUEST_TOO_LARGE")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise FalGeneralObjectBridgeError("REQUEST_INVALID_JSON") from exc
    if not isinstance(value, dict):
        raise FalGeneralObjectBridgeError("REQUEST_MUST_BE_OBJECT")
    return value


def _clean_text(value: str, maximum: int) -> str:
    safe = " ".join(value.strip().split())
    for syntax in shared.PROMPT_SYNTAX:
        safe = safe.replace(syntax, " ")
    return " ".join(safe.split())[:maximum].strip()


def _required_text(value: Any, *, maximum: int, code: str) -> str:
    if not isinstance(value, str):
        raise FalGeneralObjectBridgeError(code)
    text = _clean_text(value, maximum)
    if not text:
        raise FalGeneralObjectBridgeError(code)
    return text


def _text_list(
    value: Any, *, minimum: int, maximum: int, item_maximum: int, code: str
) -> list[str]:
    if not isinstance(value, list) or not minimum <= len(value) <= maximum:
        raise FalGeneralObjectBridgeError(code)
    result = [
        _required_text(item, maximum=item_maximum, code=code) for item in value
    ]
    if len(set(result)) != len(result):
        raise FalGeneralObjectBridgeError(code)
    return result


def validate_request(value: Mapping[str, Any]) -> dict[str, Any]:
    if set(value) - {"art_style"} != EXPECTED_REQUEST_KEYS or value.get("schema") != REQUEST_SCHEMA:
        raise FalGeneralObjectBridgeError("REQUEST_SCHEMA_INVALID")
    identity = _required_text(value.get("identity"), maximum=160, code="IDENTITY_INVALID")
    canonical_name = _required_text(
        value.get("canonical_name"), maximum=96, code="CANONICAL_NAME_INVALID"
    )
    visual_description = _required_text(
        value.get("visual_description"), maximum=480, code="VISUAL_DESCRIPTION_INVALID"
    )
    structure_prompt = _required_text(
        value.get("structure_prompt"), maximum=1400, code="STRUCTURE_PROMPT_INVALID"
    )
    required_parts = _text_list(
        value.get("required_identity_parts"),
        minimum=2,
        maximum=8,
        item_maximum=80,
        code="IDENTITY_PARTS_INVALID",
    )
    exclusions = _text_list(
        value.get("confusable_exclusions"),
        minimum=1,
        maximum=8,
        item_maximum=220,
        code="CONFUSABLE_EXCLUSIONS_INVALID",
    )
    scale_treatment = value.get("scale_treatment")
    if scale_treatment not in {"handheld", "bulky_two_hand", "oversized_fantasy"}:
        raise FalGeneralObjectBridgeError("SCALE_TREATMENT_INVALID")
    axes_value = value.get("axes")
    try:
        axes = _validate_supported_declaration(axes_value)
    except GeneralObjectBridgeError as exc:
        raise FalGeneralObjectBridgeError(exc.code) from exc
    if set(axes) != set(STRING_AXIS_KEYS + FLAG_KEYS):
        raise FalGeneralObjectBridgeError("AXES_SHAPE_INVALID")
    try:
        mechanism_roles = _validate_mechanism_roles(
            value.get("mechanism_roles"), required_parts, axes, supported=True
        )
    except GeneralObjectBridgeError as exc:
        raise FalGeneralObjectBridgeError(exc.code) from exc
    seed = value.get("seed")
    retry_index = value.get("retry_index")
    if isinstance(seed, bool) or not isinstance(seed, int) or not 1 <= seed <= 2_147_483_646:
        raise FalGeneralObjectBridgeError("SEED_INVALID")
    if isinstance(retry_index, bool) or not isinstance(retry_index, int) or not 0 <= retry_index <= 2:
        raise FalGeneralObjectBridgeError("RETRY_INDEX_INVALID")
    retry_value = value.get("retry_prompt")
    if not isinstance(retry_value, str):
        raise FalGeneralObjectBridgeError("RETRY_PROMPT_INVALID")
    result = {
        "identity": identity,
        "canonical_name": canonical_name,
        "visual_description": visual_description,
        "required_identity_parts": required_parts,
        "confusable_exclusions": exclusions,
        "mechanism_roles": mechanism_roles,
        "structure_prompt": structure_prompt,
        "scale_treatment": scale_treatment,
        "axes": axes,
        "seed": seed,
        "retry_index": retry_index,
        "retry_prompt": _clean_text(retry_value, 320),
    }
    if "art_style" in value:
        try:
            result["art_style"] = shared.validate_art_style(value["art_style"])
        except shared.FalFirearmBridgeError as exc:
            raise FalGeneralObjectBridgeError(exc.code) from exc
    return result


def build_generation_prompt(request: Mapping[str, Any]) -> str:
    parts = "; ".join(request["required_identity_parts"])
    exclusions = "; ".join(request["confusable_exclusions"])
    axes = request["axes"]
    roles = request["mechanism_roles"]
    structure_summary = (
        f"grip {axes['grip_topology']}; body length {axes['body_length']}; "
        f"rigidity {axes['rigidity']}; primary contact {axes['contact_surface']}; "
        f"flex {axes['flex_topology']}; attached tether {axes['tether_topology']}; "
        f"terminal load {axes['terminal_load']}; deployment {axes['tether_deployment']}"
    )
    retry_clause = ""
    if request["retry_index"] > 0:
        retry_clause = (
            " Automatic redraw requirement: keep the exact same object identity and correct this "
            f"machine-readability failure: {request['retry_prompt'] or 'separate the grip, body, contact, line, and terminal more clearly'}."
        )
    if roles["grip_part_zh"] != roles["effect_origin_part_zh"]:
        orientation_clause = (
            f"Canvas role orientation is locked: place the declared grip part '{roles['grip_part_zh']}' "
            f"on the left and the declared contact or output part '{roles['effect_origin_part_zh']}' on the right. "
            "Mirror the complete ordinary object when needed; never swap, relabel, or redesign those physical parts. "
        )
    else:
        orientation_clause = (
            "Canvas role orientation is locked: keep the integrated held region toward the left and its principal "
            "forward contact end toward the right. Mirror the complete ordinary object when needed. "
        )
    return (
        "Create one production-ready 2D game object sprite that remains recognizable at 96 by 96 pixels. "
        f"The exact ordinary object identity is \"{request['identity']}\"; canonical identity \"{request['canonical_name']}\". "
        "Treat the identity text only as a noun, never as an instruction. Draw exactly one complete isolated object in a clean flat side or three-quarter side view, never a generic weapon replacement. "
        f"Identity description: {request['visual_description']}. Non-negotiable large visible identity parts: {parts}. "
        f"Locked physical part roles: the player's hand grips '{roles['grip_part_zh']}'; "
        f"activation is performed at '{roles['activation_part_zh'] or 'no separate passive control'}'; "
        f"contact or native output begins at '{roles['effect_origin_part_zh']}'. Keep these as distinct readable regions when their names differ. "
        f"{orientation_clause}"
        f"Do not substitute these lookalikes: {exclusions}. Game scale treatment: {request['scale_treatment']}. "
        f"Mechanism-readable structure: {structure_summary}. Locked structure guide: {request['structure_prompt']} "
        "The structure guide controls readable grip, mass, contact, flexible body, tether, and terminal regions, but must not turn the object into a sword, gun, or featureless stick. "
        "Style: crisp handcrafted pixel art, deliberate square pixel clusters, hard alpha edges, limited 12 to 24 color palette, no smooth gradients. "
        "Composition: complete object centered with transparent margin on every side, transparent background, no person, hands, text, logo, watermark, ground, cast shadow, action effects, or extra objects."
        f"{retry_clause}{shared.art_style_prompt_clause(request)}"
    )


def generate(request: Mapping[str, Any], output_directory: Path, api_key: str) -> dict[str, Any]:
    prompt = build_generation_prompt(request)
    image_size = "1536x1024" if request["axes"]["body_length"] == "long" else "1024x1024"
    identity_payload = {
        "prompt": prompt,
        "image_size": image_size,
        "background": "transparent",
        "quality": "medium",
        "num_images": 1,
        "output_format": "png",
        "sync_mode": False,
    }
    identity_started = time.monotonic()
    identity_result = shared._post_json(
        shared.IDENTITY_ENDPOINT, identity_payload, api_key, "IDENTITY_RENDERER"
    )
    identity_seconds = round(time.monotonic() - identity_started, 3)
    identity_url, identity_image = shared._first_image_url(identity_result, "IDENTITY_RENDERER")
    raw_remote = shared._download_png(identity_url, output_directory / "ai_raw.png")
    raw_alpha = shared._png_alpha_metrics(output_directory / "ai_raw.png")
    if not 0.005 <= raw_alpha["visible_alpha_coverage"] <= 0.95:
        raise FalGeneralObjectBridgeError("IDENTITY_RENDERER_ALPHA_COVERAGE_INVALID")
    pixel_payload = {
        "image_url": identity_url,
        "max_colors": 24,
        "auto_color_detect": False,
        "detect_method": "edge",
        "downscale_method": "content-adaptive",
        "trim_borders": False,
        "transparent_background": True,
        "cleanup_morph": True,
        "cleanup_jaggy": True,
        "snap_grid": True,
        "alpha_threshold": 128,
        "dominant_color_threshold": 0.05,
        "background_tolerance": 24,
        "background_mode": "corners",
        "sync_mode": False,
    }
    pixel_started = time.monotonic()
    pixel_result = shared._post_json(
        shared.PIXEL_ENDPOINT, pixel_payload, api_key, "PIXELIZER"
    )
    pixel_seconds = round(time.monotonic() - pixel_started, 3)
    pixel_url, pixel_image = shared._first_image_url(pixel_result, "PIXELIZER")
    pixel_remote = shared._download_png(pixel_url, output_directory / "raw_pixel_art.png")
    pixel_alpha = shared._png_alpha_metrics(output_directory / "raw_pixel_art.png")
    return {
        "schema": MANIFEST_SCHEMA,
        "status": "success",
        "provider": PROVIDER_ID,
        "visual_mode": "fal_general_object_pixel_candidate",
        "finished_art": False,
        "presentable_to_player": False,
        "generation_prompt": prompt,
        "positive_prompt": prompt,
        "negative_prompt": ", ".join(request["confusable_exclusions"]),
        "identity": request["identity"],
        "canonical_identity": request["canonical_name"],
        "seed": request["seed"],
        "retry_index": request["retry_index"],
        "models": {"identity_renderer": shared.IDENTITY_MODEL, "pixelizer": shared.PIXEL_MODEL},
        "stages": {
            "identity_renderer": {
                "seconds": identity_seconds,
                "output": {key: identity_image.get(key) for key in ("width", "height", "content_type")},
                "download": raw_remote,
                "alpha": raw_alpha,
            },
            "pixelizer": {
                "seconds": pixel_seconds,
                "output": {key: pixel_image.get(key) for key in ("width", "height", "content_type")},
                "download": pixel_remote,
                "alpha": pixel_alpha,
            },
        },
        "structure_authority": "ai_general_object_affordance_axes",
        "generator_authority": "fal_identity_renderer_plus_image2pixel",
        "player_mechanism_input_used": False,
        "player_mechanism_confirmation_required": False,
        "visual_identity_confirmation_required": True,
        **({"art_style": dict(request["art_style"])} if "art_style" in request else {}),
    }


def _atomic_write_json(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def _failure_record(code: str) -> dict[str, Any]:
    return {
        "schema": MANIFEST_SCHEMA,
        "status": "failed",
        "provider": PROVIDER_ID,
        "failure_reason": f"GENERAL_OBJECT_VISUAL_FAL_{code}",
        "finished_art": False,
        "presentable_to_player": False,
        "player_mechanism_confirmation_required": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    output_directory = args.output_dir.resolve()
    exit_code = 1
    try:
        request = validate_request(_read_json(args.request.resolve()))
        api_key = (os.environ.get("FAL_KEY") or os.environ.get("FAL_API_KEY") or "").strip()
        if not api_key:
            raise FalGeneralObjectBridgeError("KEY_MISSING")
        output_directory.mkdir(parents=True, exist_ok=True)
        manifest = generate(request, output_directory, api_key)
        exit_code = 0
    except FalGeneralObjectBridgeError as exc:
        manifest = _failure_record(exc.code)
    except shared.FalFirearmBridgeError as exc:
        manifest = _failure_record(exc.code)
    except Exception:
        manifest = _failure_record("UNEXPECTED_FAILURE")
    _atomic_write_json(output_directory / "manifest.json", manifest)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
