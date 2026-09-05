"""Offline regression for the publication gate; all credentials are synthetic."""
import unittest

import audit_upload as audit


class UploadAuditTests(unittest.TestCase):
    def test_provider_token_is_redacted_to_rule(self):
        value = ("sk-" + "proj-" + "x" * 40).encode()
        self.assertIn("provider_key", audit.content_rules(value))

    def test_escaped_token_is_detected(self):
        value = "sk-" + "x" * 40
        escaped = "".join("\\u%04x" % ord(c) for c in value).encode()
        self.assertIn("provider_key", audit.content_rules(escaped))

    def test_credential_urls_have_only_one_exact_fixture_exception(self):
        self.assertNotIn("credential_in_url", audit.content_rules(b"http://127.0.0.1:8188@evil.example"))
        value = ("https://" + "fixture-user" + ":fixture-password@host.invalid").encode()
        self.assertIn("credential_in_url", audit.content_rules(value))

    def test_paths_are_local_only(self):
        for path in ("sessions/sample.json", "weapons/sample.json", ".tools/cache.png", ".env", ".env.production", "a.local.json", "a.log", "a.png.import", "a.zip"):
            with self.subTest(path=path):
                self.assertTrue(audit.path_rules(path))

    def test_safe_sources_remain_uploadable(self):
        for path in (".env.example", "assets/church_expedition_starters/weapon.json", "tests/fixture.json", "assets/dead_revolver_player_v1/Sprites/frame.png"):
            self.assertFalse(audit.path_rules(path))

    def test_personal_path_and_generic_placeholder(self):
        personal = ("C:/" + "Users/" + "private-person/file.txt").encode()
        self.assertIn("personal_windows_path", audit.content_rules(personal))
        self.assertNotIn("personal_windows_path", audit.content_rules(b"<USERPROFILE>/file.txt"))

    def test_binary_texture_is_not_treated_as_text(self):
        self.assertFalse(audit.content_rules(b"\x89PNG\0binary"))


if __name__ == "__main__":
    unittest.main()
