"""Offline compatibility and rejection checks; no credentials or live calls."""
from __future__ import annotations

import copy
import unittest

from test_fal_firearm_pixel_bridge import BRIDGE as firearm, request_fixture
from test_fal_general_object_pixel_bridge import bridge as general, request_payload


def style_contract() -> dict:
    return {
        "id": "church_v1",
        "version": "church-pixel-v1.0",
        "prompt": "Strict side view with purple-blue shadows and warm highlights; preserve identity.",
    }


def general_fixture() -> dict:
    value = request_payload()
    # This legacy visual test fixture predates the three state/output axes.
    value["axes"].update({
        "state_topology": "fixed", "activation_mode": "passive", "functional_output": "contact_only"
    })
    return value


class ChurchStyleContractTests(unittest.TestCase):
    def test_sunny_contract_reaches_both_pipelines_without_changing_mechanics(self):
        style = {"id": "sunny_v1", "version": "sunny-pixel-v1.0", "prompt": "Sunny daylight, clean teal outlines, warm sand highlights, preserve identity."}
        for bridge, fixture, error in self.cases():
            baseline = bridge.validate_request(fixture())
            request = fixture()
            request["art_style"] = dict(style)
            styled = bridge.validate_request(request)
            self.assertIn(style["prompt"], bridge.build_generation_prompt(styled))
            self.assertEqual(styled.pop("art_style"), style)
            self.assertEqual(styled, baseline)
            request["art_style"]["version"] = "church-pixel-v1.0"
            with self.assertRaisesRegex(error, "ART_STYLE_UNSUPPORTED"):
                bridge.validate_request(request)

    def cases(self):
        return (
            (firearm, request_fixture, firearm.FalFirearmBridgeError),
            (general, general_fixture, general.FalGeneralObjectBridgeError),
        )

    def test_legacy_request_is_unchanged_and_contains_no_style(self):
        for bridge, fixture, _ in self.cases():
            with self.subTest(bridge=bridge.PROVIDER_ID):
                request = bridge.validate_request(fixture())
                self.assertNotIn("art_style", request)
                self.assertNotIn("Locked shared game art direction", bridge.build_generation_prompt(request))

    def test_opt_in_style_preserves_identity_axes_and_required_parts(self):
        for bridge, fixture, _ in self.cases():
            with self.subTest(bridge=bridge.PROVIDER_ID):
                baseline = bridge.validate_request(fixture())
                value = fixture()
                value["art_style"] = style_contract()
                styled = bridge.validate_request(value)
                self.assertEqual(styled.pop("art_style"), style_contract())
                self.assertEqual(styled, baseline)
                styled["art_style"] = style_contract()
                prompt = bridge.build_generation_prompt(styled)
                self.assertIn(style_contract()["prompt"], prompt)
                self.assertIn("never object identity", prompt)
                self.assertIn(styled["identity"], prompt)

    def test_unknown_style_or_version_fails_closed(self):
        for bridge, fixture, error in self.cases():
            for key, bad in (("id", "other_style"), ("version", "church-pixel-v0")):
                with self.subTest(bridge=bridge.PROVIDER_ID, key=key):
                    value = fixture()
                    value["art_style"] = style_contract()
                    value["art_style"][key] = bad
                    with self.assertRaisesRegex(error, "ART_STYLE_UNSUPPORTED"):
                        bridge.validate_request(value)

    def test_style_contract_rejects_unknown_fields_wrong_types_and_empty_values(self):
        malformed = [None, [], {}, {**style_contract(), "damage": 100}]
        malformed += [{**style_contract(), "prompt": prompt} for prompt in (None, "", "  ", "x" * 2401, "line\nbreak")]
        for bridge, fixture, error in self.cases():
            for bad in malformed:
                with self.subTest(bridge=bridge.PROVIDER_ID, bad=repr(bad)[:80]):
                    value = fixture()
                    value["art_style"] = copy.deepcopy(bad)
                    with self.assertRaisesRegex(error, "ART_STYLE_"):
                        bridge.validate_request(value)

    def test_optional_style_does_not_open_other_top_level_keys(self):
        for bridge, fixture, error in self.cases():
            value = fixture()
            value["art_style"] = style_contract()
            value["mechanism_override"] = "shoot"
            with self.assertRaisesRegex(error, "REQUEST_SCHEMA_INVALID"):
                bridge.validate_request(value)

    def test_style_has_no_new_models_or_reference_upload(self):
        value = request_fixture()
        value["art_style"] = style_contract()
        request = firearm.validate_request(value)
        endpoint, model, payload = firearm.build_identity_renderer_call(
            request, firearm.build_generation_prompt(request)
        )
        self.assertEqual(endpoint, firearm.IDENTITY_ENDPOINT)
        self.assertEqual(model, firearm.IDENTITY_MODEL)
        self.assertEqual(payload["num_images"], 1)
        self.assertNotIn("image_urls", payload)


if __name__ == "__main__":
    unittest.main()
