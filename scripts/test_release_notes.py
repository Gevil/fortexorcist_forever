#!/usr/bin/env python3
"""Unit tests for scripts/release_notes.py:  python3 scripts/test_release_notes.py"""
import os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import release_notes as rn

CHANGELOG = """# Changelog

Preamble that is never part of a release.

---

## [1.0.0] - 2026-11-10

- Added the thing.
- Fixed the other thing.

### Known limits

- Predicted timers.

---

## [1.0.0-rc1] - 2026-11-08

- RC only.

## 0.9.0 (2026-11-01)

- Old.

## v0.10.0 -- title

- Newer than 0.9.0 by number.
"""


class Extract(unittest.TestCase):
    def test_top_section_with_subheadings_and_no_trailing_rule(self):
        got = rn.extract(CHANGELOG, "1.0.0")
        self.assertEqual(got, "## [1.0.0] - 2026-11-10\n\n- Added the thing.\n- Fixed the other thing.\n\n"
                              "### Known limits\n\n- Predicted timers.\n")

    def test_prerelease_is_its_own_section(self):
        self.assertEqual(rn.extract(CHANGELOG, "1.0.0-rc1"), "## [1.0.0-rc1] - 2026-11-08\n\n- RC only.\n")

    def test_heading_styles(self):
        self.assertEqual(rn.extract(CHANGELOG, "0.9.0"), "## 0.9.0 (2026-11-01)\n\n- Old.\n")
        self.assertEqual(rn.extract(CHANGELOG, "0.10.0"), "## v0.10.0 -- title\n\n- Newer than 0.9.0 by number.\n")

    def test_last_section_runs_to_end_of_file(self):
        self.assertTrue(rn.extract(CHANGELOG, "0.10.0").endswith("by number.\n"))

    def test_missing_version_is_none_and_no_partial_token_match(self):
        self.assertIsNone(rn.extract(CHANGELOG, "2.0.0"))
        self.assertIsNone(rn.extract(CHANGELOG, "1.0"))
        self.assertIsNone(rn.extract("## [11.0.0]\n- x\n", "1.0.0"))
        self.assertIsNone(rn.extract("## [1.0.0.1]\n- x\n", "1.0.0"))
        self.assertIsNone(rn.extract("## Unreleased - 2026-11-09\n- x\n", "1.0.0"))

    def test_topmost_wins_on_duplicate(self):
        text = "## [1.0.0] first\n- a\n\n## [1.0.0] second\n- b\n"
        self.assertEqual(rn.extract(text, "1.0.0"), "## [1.0.0] first\n- a\n")

    def test_body_mentioning_the_version_does_not_match(self):
        self.assertIsNone(rn.extract("## Unreleased\n- bumped to 1.0.0\n", "1.0.0"))


class Cli(unittest.TestCase):
    def run_cli(self, changelog, *args):
        with tempfile.TemporaryDirectory() as d:
            cl, out = os.path.join(d, "CHANGELOG.md"), os.path.join(d, "RELEASE_NOTES.md")
            with open(cl, "w", encoding="utf-8") as fh:
                fh.write(changelog)
            p = subprocess.run([sys.executable, os.path.join(HERE, "release_notes.py"),
                                "--changelog", cl, "--out", out, *args], capture_output=True, text=True)
            body = None
            if os.path.exists(out):
                with open(out, encoding="utf-8") as fh:
                    body = fh.read()
            return p, body

    def test_writes_file_and_strips_leading_v(self):
        p, body = self.run_cli(CHANGELOG, "--version", "v1.0.0")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(body.startswith("## [1.0.0] - 2026-11-10\n"))

    def test_missing_version_fails_and_writes_nothing(self):
        p, body = self.run_cli(CHANGELOG, "--version", "3.0.0")
        self.assertEqual(p.returncode, 1)
        self.assertIn("3.0.0", p.stderr)
        self.assertIsNone(body)

    def test_default_version_is_the_VERSION_file(self):
        with open(os.path.join(os.path.dirname(HERE), "VERSION")) as fh:
            v = fh.read().strip()
        p, body = self.run_cli(f"## [{v}] - 2026-01-01\n\n- x\n")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(body, f"## [{v}] - 2026-01-01\n\n- x\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
