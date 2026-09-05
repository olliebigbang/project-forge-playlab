from __future__ import annotations

import importlib.util
import io
import json
import os
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "fal_firearm_pixel_bridge.py"
SPEC = importlib.util.spec_from_file_location("fal_firearm_pixel_bridge", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


def request_fixture() -> dict:
    return {
        "schema": BRIDGE.REQUEST_SCHEMA,
        "identity": "M4A1",
        "identity_prompt_text": "M4A1",
        "canonical_name": "M4A1",
        "visual_description": "recognizable M4A1 conventional carbine with telescoping stock",
        "required_identity_parts": ["telescoping stock", "magazine ahead of grip"],
        "structure_prompt": "Use a conventional rifle layout with separate stock, grip, magazine and muzzle.",
        "identity_reference_id": "",
        "identity_card": {
            "schema": "forge-firearm-visual-identity-card-v1",
            "identity_id": "m4a1",
            "requested_identity": "M4A1",
            "canonical_name": "M4A1",
            "visual_axes": {
                "stock_profile": "collapsible_polymer_stock_on_buffer_tube",
                "upper_landmark": "low_flat_receiver_rail",
                "magazine_profile": "box_magazine_ahead_of_primary_grip",
                "fore_end_profile": "compact_carbine_rail_handguard",
                "receiver_profile": "split_upper_lower_carbine_receiver",
            },
            "required_landmarks": [
                "compact collapsible polymer stock attached by a visible buffer tube",
                "box magazine visibly ahead of the primary grip",
            ],
            "confusable_exclusions": ["not an M16 with a full fixed stock or permanent carry handle"],
            "confidence": 0.97,
            "source": "CURATED_AI_FIREARM_IDENTITY_V1",
            "mechanics_authority": False,
            "player_confirmation_required": False,
        },
        "axes": {
            "layout": "conventional_rifle",
            "stock_structure": "telescoping",
            "feed_position": "ahead_of_grip",
            "magazine_shape": "straight",
            "barrel_length": "medium",
            "upper_profile": "top_rail",
            "support_mode": "two_hand_shouldered",
            "finish_palette": "gunmetal_black",
        },
        "seed": 44001,
        "retry_index": 0,
        "retry_prompt": "",
    }


class StocklessSupportTests(unittest.TestCase):
    def test_stockless_two_hand_layout_reaches_visual_prompt(self) -> None:
        request = request_fixture()
        request["axes"]["stock_structure"] = "none"
        request["axes"]["support_mode"] = "two_hand_free"
        validated = BRIDGE.validate_request(request)
        self.assertEqual(validated["axes"]["support_mode"], "two_hand_free")
        request["axes"]["support_mode"] = "two_hand_shouldered"
        with self.assertRaisesRegex(BRIDGE.FalFirearmBridgeError, "CONVENTIONAL_CONFLICT"):
            BRIDGE.validate_request(request)


class FalFirearmPixelBridgeTests(unittest.TestCase):
    def test_prompt_keeps_identity_and_forbids_generic_replacement(self) -> None:
        request = BRIDGE.validate_request(request_fixture())
        prompt = BRIDGE.build_generation_prompt(request)
        self.assertIn('exactly the firearm identity named "M4A1"', prompt)
        self.assertIn("telescoping stock", prompt)
        self.assertIn("must never be copied as finished art", prompt)
        self.assertIn("do not replace it with a generic rifle", prompt)
        self.assertIn("absolutely no full fixed triangular stock", prompt)
        self.assertIn("absolutely no tall carry-handle arch", prompt)
        self.assertIn("collapsible polymer stock on buffer tube", prompt)
        self.assertIn("not an M16 with a full fixed stock", prompt)

    def test_invalid_axis_relationship_is_rejected_before_api_use(self) -> None:
        value = request_fixture()
        value["axes"]["feed_position"] = "behind_grip"
        with self.assertRaisesRegex(BRIDGE.FalFirearmBridgeError, "AXES_CONVENTIONAL_CONFLICT"):
            BRIDGE.validate_request(value)

    def test_v5_shotgun_revolver_and_belt_fed_layouts_reach_the_renderer(self) -> None:
        cases = [
            (
                {
                    "layout": "conventional_shotgun",
                    "stock_structure": "fixed",
                    "feed_position": "under_barrel",
                    "magazine_shape": "tube",
                    "barrel_length": "medium",
                    "upper_profile": "ribbed_barrel",
                    "support_mode": "two_hand_shouldered",
                },
                "tubular magazine",
                "1536x1024",
            ),
            (
                {
                    "layout": "revolver",
                    "stock_structure": "none",
                    "feed_position": "cylinder_center",
                    "magazine_shape": "cylinder",
                    "barrel_length": "medium",
                    "upper_profile": "revolver_frame",
                    "support_mode": "one_hand",
                },
                "exposed round cylinder",
                "1024x1024",
            ),
            (
                {
                    "layout": "belt_fed_support",
                    "stock_structure": "fixed",
                    "feed_position": "side_feed",
                    "magazine_shape": "belt_box",
                    "barrel_length": "long",
                    "upper_profile": "feed_cover",
                    "support_mode": "two_hand_shouldered",
                },
                "side-hanging belt box",
                "1536x1024",
            ),
        ]
        for axes, prompt_evidence, image_size in cases:
            with self.subTest(layout=axes["layout"]):
                value = request_fixture()
                value["axes"].update(axes)
                request = BRIDGE.validate_request(value)
                prompt = BRIDGE.build_generation_prompt(request)
                _, _, payload = BRIDGE.build_identity_renderer_call(request, prompt)
                self.assertIn(prompt_evidence, prompt)
                self.assertEqual(payload["image_size"], image_size)

    def test_belt_fed_prompt_requires_a_separate_feed_cover_hump(self) -> None:
        value = request_fixture()
        value["axes"].update(
            {
                "layout": "belt_fed_support",
                "stock_structure": "fixed",
                "feed_position": "side_feed",
                "magazine_shape": "belt_box",
                "barrel_length": "long",
                "upper_profile": "feed_cover",
                "support_mode": "two_hand_shouldered",
                "finish_palette": "olive_black",
            }
        )
        prompt = BRIDGE.build_generation_prompt(BRIDGE.validate_request(value))
        self.assertIn("raised broad rectangular feed-cover hump", prompt)
        self.assertIn("backward-leaning arched carrying handle", prompt)
        self.assertIn("short visible linked ammunition belt", prompt)
        self.assertIn("No loose ammunition outside the short linked belt", prompt)
        self.assertNotIn("hands, ammunition", prompt)

    def test_curated_reference_uses_high_fidelity_edit_without_exposing_player_url(self) -> None:
        value = request_fixture()
        value["identity"] = "81杠"
        value["identity_prompt_text"] = "81杠"
        value["canonical_name"] = "81杠"
        value["identity_card"]["identity_id"] = "type_81"
        value["identity_card"]["requested_identity"] = "81杠"
        value["identity_card"]["canonical_name"] = "81杠"
        value["identity_reference_id"] = "type_81_museum_cc_by_sa_v1"
        request = BRIDGE.validate_request(value)
        prompt = BRIDGE.build_generation_prompt(request)
        endpoint, model, payload = BRIDGE.build_identity_renderer_call(request, prompt)
        self.assertEqual(endpoint, BRIDGE.IDENTITY_EDIT_ENDPOINT)
        self.assertEqual(model, BRIDGE.IDENTITY_EDIT_MODEL)
        self.assertEqual(payload["input_fidelity"], "high")
        self.assertEqual(len(payload["image_urls"]), 1)
        self.assertIn("upload.wikimedia.org", payload["image_urls"][0])
        self.assertIn("one fixed-stock Type 81", prompt)
        provenance = BRIDGE._reference_provenance(request["identity_reference"])
        self.assertTrue(provenance["used"])
        self.assertNotIn("image_url", provenance)
        self.assertFalse(provenance["mechanics_authority"])

    def test_uncurated_reference_id_is_rejected_before_api_use(self) -> None:
        value = request_fixture()
        value["identity_reference_id"] = "player_supplied_url"
        with self.assertRaisesRegex(BRIDGE.FalFirearmBridgeError, "IDENTITY_REFERENCE_NOT_CURATED"):
            BRIDGE.validate_request(value)

    def test_auto_reference_is_dynamic_only_and_becomes_verified_edit_input(self) -> None:
        value = request_fixture()
        value["identity"] = "M16A2"
        value["identity_prompt_text"] = "M16A2"
        value["canonical_name"] = "M16A2"
        value["identity_card"]["identity_id"] = "ai_m16a2"
        value["identity_card"]["requested_identity"] = "M16A2"
        value["identity_card"]["canonical_name"] = "M16A2"
        value["identity_reference_id"] = BRIDGE.AUTO_REFERENCE_ID
        request = BRIDGE.validate_request(value)
        image = b"\xff\xd8\xffverified-reference"
        digest = __import__("hashlib").sha256(image).hexdigest()
        reference = {
            "reference_id": f"wikimedia_42_{digest[:12]}",
            "identity_id": "ai_m16a2",
            "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/test.jpg/1280px-test.jpg",
            "source_page": "https://commons.wikimedia.org/wiki/File:test.jpg",
            "license": "CC BY-SA 4.0",
            "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
            "author": "Example Photographer",
            "media_type": "image/jpeg",
            "sha256": digest,
            "source_title": "File:M16A2 rightside noBG.jpg",
            "source_page_id": 42,
            "source_file_sha1": "a" * 40,
            "discovery_mode": "wikimedia_commons_api_v1",
            "selection_instruction": "Use the verified exact M16A2 side profile.",
        }
        verification = {
            "schema": "forge-wikimedia-firearm-reference-verification-v1",
            "passed": True,
            "mechanics_authority": False,
        }
        resolved = {
            "reference": reference,
            "image_bytes": image,
            "verification": verification,
            "fetch": {"bytes": len(image), "sha256": digest, "cache_hit": False},
        }
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            BRIDGE, "resolve_wikimedia_reference", return_value=resolved
        ):
            prepared, data_uri, fetch, prepared_bytes, prepared_verification = (
                BRIDGE._prepare_identity_reference(request, Path(directory))
            )
        self.assertTrue(data_uri.startswith("data:image/jpeg;base64,"))
        self.assertEqual(prepared_bytes, image)
        self.assertFalse(fetch["cache_hit"])
        self.assertTrue(prepared_verification["passed"])
        prompt = BRIDGE.build_generation_prompt(prepared)
        endpoint, model, payload = BRIDGE.build_identity_renderer_call(
            prepared, prompt, data_uri
        )
        self.assertEqual(endpoint, BRIDGE.IDENTITY_EDIT_ENDPOINT)
        self.assertEqual(model, BRIDGE.IDENTITY_EDIT_MODEL)
        self.assertEqual(payload["image_urls"], [data_uri])
        provenance = BRIDGE._reference_provenance(prepared["identity_reference"])
        self.assertEqual(provenance["source_page_id"], 42)
        self.assertNotIn("image_url", provenance)

        curated_value = request_fixture()
        curated_value["identity_reference_id"] = BRIDGE.AUTO_REFERENCE_ID
        with self.assertRaisesRegex(
            BRIDGE.FalFirearmBridgeError, "AUTO_REQUIRES_DYNAMIC_IDENTITY"
        ):
            BRIDGE.validate_request(curated_value)

    def test_missing_public_reference_falls_back_to_strict_candidate_verification(self) -> None:
        value = request_fixture()
        value["identity_card"]["identity_id"] = "ai_m4a1"
        value["identity_reference_id"] = BRIDGE.AUTO_REFERENCE_ID
        request = BRIDGE.validate_request(value)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            BRIDGE,
            "resolve_wikimedia_reference",
            side_effect=BRIDGE.WikimediaReferenceError("NO_VISUALLY_VERIFIED_REFERENCE"),
        ):
            prepared, data_uri, fetch, image_bytes, verification = (
                BRIDGE._prepare_identity_reference(request, Path(directory))
            )
        self.assertEqual(prepared["identity_reference"], {})
        self.assertEqual(data_uri, "")
        self.assertEqual(fetch, {})
        self.assertEqual(image_bytes, b"")
        self.assertTrue(verification["fallback_used"])
        self.assertTrue(verification["candidate_verification_still_required"])

    def test_public_reference_network_failure_still_fails_closed(self) -> None:
        value = request_fixture()
        value["identity_card"]["identity_id"] = "ai_m4a1"
        value["identity_reference_id"] = BRIDGE.AUTO_REFERENCE_ID
        request = BRIDGE.validate_request(value)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            BRIDGE,
            "resolve_wikimedia_reference",
            side_effect=BRIDGE.WikimediaReferenceError("API_NETWORK_FAILED"),
        ):
            with self.assertRaisesRegex(
                BRIDGE.FalFirearmBridgeError,
                "IDENTITY_REFERENCE_API_NETWORK_FAILED",
            ):
                BRIDGE._prepare_identity_reference(request, Path(directory))

    def test_two_stage_generation_uses_transparency_and_bounded_palette(self) -> None:
        request = BRIDGE.validate_request(request_fixture())
        identity_result = {"images": [{"url": "https://v3.fal.media/files/a/raw.png", "width": 1536, "height": 1024}]}
        pixel = {
            "images": [
                {"url": "https://v3.fal.media/files/a/pixel.png", "width": 1008, "height": 504},
                {"url": "https://v3.fal.media/files/a/small.png", "width": 48, "height": 24},
            ],
            "pixel_scale": 18,
            "num_colors": 18,
            "palette": ["#111111", "#333333"],
        }
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(BRIDGE, "require_visual_verifier_configuration", return_value=("key", "model")):
                with mock.patch.object(BRIDGE, "_post_json", side_effect=[identity_result, pixel]) as post:
                    with mock.patch.object(
                        BRIDGE,
                        "_download_png",
                        return_value={"host": "v3.fal.media", "bytes": 100, "sha256": "a", "url_sha256": "b"},
                    ) as download:
                        with mock.patch.object(
                            BRIDGE,
                            "_png_alpha_metrics",
                            return_value={"width": 1008, "height": 504, "visible_alpha_coverage": 0.2, "opaque_alpha_coverage": 0.2},
                        ):
                            with mock.patch.object(
                                BRIDGE,
                                "verify_candidate",
                                return_value={
                                    "schema": "forge-firearm-ai-visual-verification-v1",
                                    "ok": True,
                                    "passed": True,
                                    "player_confirmation_required": False,
                                },
                            ):
                                manifest = BRIDGE.generate(request, Path(directory), "secret-that-must-not-be-recorded")
        self.assertEqual(post.call_count, 2)
        identity_payload = post.call_args_list[0].args[1]
        pixel_payload = post.call_args_list[1].args[1]
        self.assertEqual(post.call_args_list[0].args[0], BRIDGE.IDENTITY_ENDPOINT)
        self.assertEqual(identity_payload["background"], "transparent")
        self.assertEqual(identity_payload["image_size"], "1536x1024")
        self.assertEqual(identity_payload["quality"], "medium")
        self.assertIn("M16-style fixed stock", identity_payload["prompt"])
        self.assertIn("M16-style fixed stock", manifest["negative_prompt"])
        self.assertIn("M16 carry handle", manifest["negative_prompt"])
        self.assertTrue(pixel_payload["transparent_background"])
        self.assertEqual(pixel_payload["max_colors"], 24)
        self.assertTrue(pixel_payload["snap_grid"])
        self.assertIn("pixel.png", download.call_args_list[1].args[0])
        self.assertNotIn("secret-that-must-not-be-recorded", json.dumps(manifest))
        self.assertFalse(manifest["presentable_to_player"])
        self.assertTrue(manifest["ai_visual_identity_verification"]["passed"])

    def test_provider_http_error_body_maps_to_closed_non_secret_reason(self) -> None:
        error = urllib.error.HTTPError(
            BRIDGE.IDENTITY_ENDPOINT,
            403,
            "Forbidden",
            {},
            io.BytesIO(b'{"detail":"Exhausted account balance; add credits"}'),
        )
        self.assertEqual(BRIDGE._safe_http_error_detail(error), "ACCOUNT_BALANCE")

        unknown = urllib.error.HTTPError(
            BRIDGE.IDENTITY_ENDPOINT,
            403,
            "Forbidden",
            {},
            io.BytesIO(b'{"detail":"opaque provider refusal","request_id":"abc"}'),
        )
        self.assertEqual(BRIDGE._safe_http_error_detail(unknown), "")

    def test_missing_key_writes_redacted_atomic_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request_fixture()), encoding="utf-8")
            with mock.patch.dict(os.environ, {}, clear=True):
                exit_code = BRIDGE.main(["--request", str(request_path), "--output-dir", str(root)])
            manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(exit_code, 1)
        self.assertEqual(manifest["failure_reason"], "FIREARM_VISUAL_FAL_KEY_MISSING")
        self.assertNotIn("traceback", json.dumps(manifest).lower())


if __name__ == "__main__":
    unittest.main()
