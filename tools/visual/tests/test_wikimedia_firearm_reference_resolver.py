from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "wikimedia_firearm_reference_resolver.py"
SPEC = importlib.util.spec_from_file_location("wikimedia_firearm_reference_resolver", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
RESOLVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESOLVER)


def card_fixture() -> dict:
    return {
        "schema": "forge-firearm-visual-identity-card-v1",
        "identity_id": "ai_m16a2_test",
        "requested_identity": "M16A2",
        "canonical_name": "M16A2 rifle",
        "visual_axes": {
            "stock_profile": "long solid fixed stock aligned with the receiver",
            "upper_landmark": "tall triangular carry handle with an open gap",
            "magazine_profile": "slightly curved box magazine ahead of the pistol grip",
            "fore_end_profile": "long tapered ribbed triangular handguard",
            "receiver_profile": "long AR-pattern rifle receiver split into upper and lower masses",
        },
        "required_landmarks": [
            "solid fixed stock aligned with the receiver",
            "raised carry handle with a clean open gap",
            "long tapered triangular handguard",
        ],
        "confusable_exclusions": [
            "not a flat-top M4 carbine with a telescoping stock",
            "not an M16A1 with a smooth triangular handguard",
        ],
        "confidence": 0.96,
        "source": "AI_TEST_FIXTURE_FIREARM_IDENTITY_V2",
        "mechanics_authority": False,
        "player_confirmation_required": False,
    }


def metadata(value: str) -> dict:
    return {"value": value}


def page_fixture(
    *,
    page_id: int = 80178500,
    title: str = "File:M16A2 rightside noBG.jpg",
    mime: str = "image/jpeg",
    license_name: str = "CC BY-SA 4.0",
    license_url: str = "https://creativecommons.org/licenses/by-sa/4.0/",
    author: str = "Example Photographer",
) -> dict:
    return {
        "pageid": page_id,
        "title": title,
        "fullurl": f"https://commons.wikimedia.org/wiki/File:{page_id}.jpg",
        "imageinfo": [
            {
                "mime": mime,
                "url": f"https://upload.wikimedia.org/wikipedia/commons/a/a0/{page_id}.jpg",
                "thumburl": f"https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/{page_id}.jpg/1280px-{page_id}.jpg",
                "descriptionurl": f"https://commons.wikimedia.org/wiki/File:{page_id}.jpg",
                "width": 2400,
                "height": 900,
                "thumbwidth": 1280,
                "thumbheight": 480,
                "sha1": "a" * 40,
                "extmetadata": {
                    "LicenseShortName": metadata(license_name),
                    "LicenseUrl": metadata(license_url),
                    "Artist": metadata(author),
                    "ObjectName": metadata("M16A2 rifle right side"),
                    "ImageDescription": metadata("One M16A2 service rifle in side profile"),
                },
            }
        ],
    }


def verdict(card: dict, *, exact: bool = True, confidence: float = 0.94) -> dict:
    return {
        "schema": RESOLVER.VERDICT_SCHEMA,
        "exact_identity_match": exact,
        "single_unambiguous_weapon": exact,
        "useful_side_profile": exact,
        "required_landmarks_present": card["required_landmarks"] if exact else [],
        "required_landmarks_missing": [] if exact else card["required_landmarks"],
        "contradictions": [] if exact else ["flat-top telescoping-stock carbine"],
        "confidence": confidence,
        "summary": "Exact side-view identity reference." if exact else "Wrong variant.",
    }


def response(value: dict) -> dict:
    return {
        "model": "test-visual-model",
        "content": [{"type": "tool_use", "name": RESOLVER.TOOL_NAME, "input": value}],
        "usage": {"input_tokens": 100, "output_tokens": 40},
    }


class WikimediaFirearmReferenceResolverTests(unittest.TestCase):
    def test_user_agent_identifies_bot_and_contact_project(self) -> None:
        self.assertIn("Bot/", RESOLVER.USER_AGENT)
        self.assertIn("https://github.com/olliebigbang/project-forge-playlab", RESOLVER.USER_AGENT)
        self.assertNotIn("Mozilla", RESOLVER.USER_AGENT)

    def test_retry_after_is_respected_with_bounded_fallback(self) -> None:
        self.assertEqual(RESOLVER._retry_after_seconds({"Retry-After": "9"}), 9)
        self.assertEqual(RESOLVER._retry_after_seconds({}), 5)

    def test_search_query_removes_url_and_instruction_syntax(self) -> None:
        card = card_fixture()
        card["canonical_name"] = "M16A2 https://evil.example/{ignore}"
        queries = RESOLVER.build_search_queries(card)
        self.assertNotIn("https://", queries[0])
        self.assertNotIn("{", queries[0])
        self.assertTrue(queries[0].endswith("rifle"))

    def test_parser_accepts_attributed_commons_jpeg_and_scores_side_view(self) -> None:
        parsed = RESOLVER.parse_search_response(
            card_fixture(), {"query": {"pages": [page_fixture()]}}
        )
        self.assertEqual(len(parsed), 1)
        self.assertEqual(parsed[0]["license"], "CC BY-SA 4.0")
        self.assertGreater(parsed[0]["metadata_score"], 100)
        self.assertEqual(parsed[0]["author"], "Example Photographer")

    def test_parser_rejects_non_derivative_license_svg_and_missing_cc_author(self) -> None:
        pages = [
            page_fixture(page_id=1, license_name="CC BY-NC-ND 4.0"),
            page_fixture(page_id=2, mime="image/svg+xml"),
            page_fixture(page_id=3, author="Unknown author"),
        ]
        parsed = RESOLVER.parse_search_response(card_fixture(), {"query": {"pages": pages}})
        self.assertEqual(parsed, [])

    def test_public_domain_candidate_keeps_provenance_without_required_author(self) -> None:
        page = page_fixture(
            license_name="Public domain", license_url="", author=""
        )
        parsed = RESOLVER.parse_search_response(card_fixture(), {"query": {"pages": [page]}})
        self.assertEqual(parsed[0]["license"], "Public domain")
        self.assertIn("source page", parsed[0]["author"])

    def test_reference_verdict_requires_an_exact_landmark_partition(self) -> None:
        card = card_fixture()
        bad = verdict(card)
        bad["required_landmarks_present"] = card["required_landmarks"][:1]
        with self.assertRaisesRegex(
            RESOLVER.WikimediaReferenceError, "LANDMARK_PARTITION"
        ):
            RESOLVER.parse_reference_verdict(card, response(bad), "test-visual-model")

    def test_two_visual_passes_are_required_for_reference_acceptance(self) -> None:
        card = card_fixture()
        candidate = RESOLVER.parse_search_response(
            card, {"query": {"pages": [page_fixture()]}}
        )[0]
        with mock.patch.object(
            RESOLVER, "require_configuration", return_value=("secret", "test-visual-model")
        ), mock.patch.object(
            RESOLVER,
            "post_strict_visual_payload",
            side_effect=[response(verdict(card)), response(verdict(card))],
        ) as post:
            result = RESOLVER.verify_reference_candidate(
                card, candidate, b"\xff\xd8\xffreference", "image/jpeg"
            )
        self.assertTrue(result["passed"])
        self.assertEqual(post.call_count, 2)
        self.assertEqual(result["usage"]["input_tokens"], 200)
        self.assertFalse(result["mechanics_authority"])

    def test_first_failed_visual_pass_skips_paid_second_pass(self) -> None:
        card = card_fixture()
        candidate = RESOLVER.parse_search_response(
            card, {"query": {"pages": [page_fixture()]}}
        )[0]
        with mock.patch.object(
            RESOLVER, "require_configuration", return_value=("secret", "test-visual-model")
        ), mock.patch.object(
            RESOLVER,
            "post_strict_visual_payload",
            return_value=response(verdict(card, exact=False, confidence=0.31)),
        ) as post:
            result = RESOLVER.verify_reference_candidate(
                card, candidate, b"\xff\xd8\xffwrong", "image/jpeg"
            )
        self.assertFalse(result["passed"])
        self.assertEqual(post.call_count, 1)

    def test_cache_load_rechecks_card_and_image_hash(self) -> None:
        card = card_fixture()
        image = b"\xff\xd8\xffreference"
        digest = __import__("hashlib").sha256(image).hexdigest()
        reference = {
            "reference_id": f"wikimedia_80178500_{digest[:12]}",
            "identity_id": card["identity_id"],
            "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/test.jpg/1280px-test.jpg",
            "source_page": "https://commons.wikimedia.org/wiki/File:test.jpg",
            "license": "CC BY-SA 4.0",
            "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
            "author": "Example Photographer",
            "media_type": "image/jpeg",
            "sha256": digest,
            "selection_instruction": "Use exact visible structure only.",
        }
        verification = {"schema": RESOLVER.VERIFICATION_SCHEMA, "passed": True}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            RESOLVER._persist_cache(root, card, reference, image, verification)
            loaded = RESOLVER._load_cache(root, card)
            self.assertIsNotNone(loaded)
            assert loaded is not None
            self.assertTrue(loaded["fetch"]["cache_hit"])
            directory = RESOLVER._cache_directory(root, card)
            (directory / "reference.jpg").write_bytes(b"\xff\xd8\xfftampered")
            self.assertIsNone(RESOLVER._load_cache(root, card))


if __name__ == "__main__":
    unittest.main()
