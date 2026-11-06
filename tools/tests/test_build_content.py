"""Tests for tools/build_content.py.

    python3 -m unittest discover -s tools/tests

Fixtures in fixtures/src hold placeholder strings ("FIXTURE 2:3"), not Qur'an text.
Running these tests also refreshes the Swift test fixture database.
"""

import re
import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import build_content  # noqa: E402
import sources  # noqa: E402

FIXTURE_SRC = HERE / "fixtures" / "src"
SWIFT_FIXTURE = ROOT / "Packages" / "NasuhaCore" / "Tests" / "NasuhaCoreTests" / "Fixtures" / "content-fixture.sqlite"

GOOD_SET = yaml.safe_load((FIXTURE_SRC / "sets" / "fixture-2-3.yaml").read_text())


class BuildTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.src = self.tmp / "src"
        shutil.copytree(FIXTURE_SRC, self.src)
        self.out = self.tmp / "out.sqlite"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write_set(self, data, name="extra.yaml", folder="sets", header=""):
        (self.src / folder / name).write_text(header + yaml.safe_dump(data, allow_unicode=True))

    def variant(self, **changes):
        data = yaml.safe_load(yaml.safe_dump(GOOD_SET))
        data["id"] = "variant"
        for k, v in changes.items():
            if v is None:
                data.pop(k, None)
            else:
                data[k] = v
        return data

    def assertBuildFails(self, pattern):
        with self.assertRaises(build_content.BuildError) as cm:
            build_content.build(self.src, self.out)
        joined = "\n".join(cm.exception.errors)
        self.assertRegex(joined, pattern)
        self.assertFalse(self.out.exists(), "no database is written when the build fails")


class GoodBuild(BuildTestCase):
    def test_builds_and_copies_text_unchanged(self):
        summary = build_content.build(self.src, self.out)
        self.assertEqual(summary["sets"], 3)
        self.assertEqual(summary["samples"], 1)
        con = sqlite3.connect(self.out)
        self.assertEqual(con.execute("SELECT arabic FROM ayah WHERE surah=2 AND ayah=3").fetchone()[0], "FIXTURE 2:3")
        self.assertEqual(con.execute("SELECT text FROM translation WHERE source='fixture_en' AND surah=2 AND ayah=3").fetchone()[0],
                         "FIXTURE en 2:3")
        self.assertEqual(con.execute("SELECT version FROM translation_source WHERE key='fixture_en'").fetchone()[0], "9.9.9")
        self.assertEqual(con.execute("SELECT bismillah FROM surah WHERE number=2").fetchone()[0], "FIXTURE BISMILLAH")
        self.assertEqual(con.execute("SELECT revelation_order FROM surah WHERE number=2").fetchone()[0], 87)
        self.assertEqual(con.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()[0], "1")
        self.assertEqual(con.execute("PRAGMA journal_mode").fetchone()[0], "delete")

    def test_curated_topic_order_then_mushaf_order(self):
        build_content.build(self.src, self.out)
        con = sqlite3.connect(self.out)
        rows = con.execute("SELECT set_id FROM ayah_set_topic WHERE topic='hope' ORDER BY position").fetchall()
        self.assertEqual([r[0] for r in rows], ["fixture-2-3", "fixture-1-2"])
        (self.src / "topic_order.yaml").unlink()
        build_content.build(self.src, self.out)
        con = sqlite3.connect(self.out)
        rows = con.execute("SELECT set_id FROM ayah_set_topic WHERE topic='hope' ORDER BY position").fetchall()
        self.assertEqual([r[0] for r in rows], ["fixture-1-2", "fixture-2-3"])

    def test_samples_are_flagged_and_can_be_left_out(self):
        build_content.build(self.src, self.out)
        con = sqlite3.connect(self.out)
        self.assertEqual(con.execute("SELECT is_sample FROM ayah_set WHERE id='sample-2-4'").fetchone()[0], 1)
        build_content.build(self.src, self.out, include_samples=False)
        con = sqlite3.connect(self.out)
        self.assertIsNone(con.execute("SELECT 1 FROM ayah_set WHERE id='sample-2-4'").fetchone())

    def test_set_without_story_stores_nothing_for_it(self):
        build_content.build(self.src, self.out)
        con = sqlite3.connect(self.out)
        row = con.execute("SELECT has_story, story_one_line, has_when FROM ayah_set WHERE id='fixture-1-2'").fetchone()
        self.assertEqual(row, (0, None, 0))


class FailingBuilds(BuildTestCase):
    def test_story_without_refs(self):
        data = self.variant()
        data["story"]["refs"] = []
        self.write_set(data)
        self.assertBuildFails(r"story has no refs")

    def test_when_without_refs(self):
        data = self.variant()
        del data["when"]["refs"]
        self.write_set(data)
        self.assertBuildFails(r"when has no refs")

    def test_book_not_on_allowlist(self):
        data = self.variant()
        data["story"]["refs"] = [{"book": "Some Other Book", "number": "1"}]
        self.write_set(data)
        self.assertBuildFails(r"'Some Other Book' is not on the allowlist")

    def test_hadith_without_grade(self):
        data = self.variant()
        data["story"]["refs"] = [{"book": "Sahih Muslim", "number": "1", "numbering": "sunnah.com"}]
        self.write_set(data)
        self.assertBuildFails(r"Sahih Muslim ref has no grade")

    def test_weak_hadith(self):
        data = self.variant()
        data["story"]["refs"] = [{"book": "Sunan Ibn Majah", "number": "1", "numbering": "sunnah.com", "grade": "da'if"}]
        self.write_set(data)
        self.assertBuildFails(r"graded \"da'if\"; only sahih or hasan")

    def test_asbab_report_needs_grade(self):
        data = self.variant()
        data["story"]["refs"] = [{"book": "al-Wahidi", "location": "2:3"}]
        self.write_set(data)
        self.assertBuildFails(r"Asbab al-Nuzul \(al-Wahidi\) ref has no grade")

    def test_hadith_needs_sunnah_com_number(self):
        data = self.variant()
        data["story"]["refs"] = [{"book": "Sahih al-Bukhari", "grade": "sahih"}]
        self.write_set(data)
        self.assertBuildFails(r"has no number")
        self.assertBuildFails(r"sunnah.com numbering")

    def test_ayah_that_does_not_exist(self):
        self.write_set(self.variant(ayah="2:99"))
        self.assertBuildFails(r"ayah 2:99 does not exist")

    def test_context_ayah_that_does_not_exist(self):
        data = self.variant(ayah="2:4")
        data["context"] = {"before": ["2:3"], "after": ["2:9"]}
        self.write_set(data)
        self.assertBuildFails(r"context ayah 2:9 does not exist")

    def test_no_context_ayahs(self):
        self.write_set(self.variant(context={"before": [], "after": []}))
        self.assertBuildFails(r"no context ayahs")

    def test_context_on_the_wrong_side(self):
        data = self.variant()
        data["context"] = {"before": ["2:4"], "after": ["2:5"]}
        self.write_set(data)
        self.assertBuildFails(r"context before 2:4 is not before")

    def test_unknown_topic(self):
        self.write_set(self.variant(topics=["nope"]))
        self.assertBuildFails(r"unknown topic 'nope'")

    def test_ages_must_be_approx(self):
        data = self.variant()
        data["when"]["approx"] = False
        self.write_set(data)
        self.assertBuildFails(r"must be marked approx")

    def test_order_must_match_chronology(self):
        data = self.variant()
        data["when"]["order"] = 3
        self.write_set(data)
        self.assertBuildFails(r"differs from the 1924 Cairo chronology")

    def test_sample_needs_marker(self):
        self.write_set(self.variant(), name="unmarked.yaml", folder="sample")
        self.assertBuildFails(r"must start with '# SAMPLE")

    def test_release_rejects_samples(self):
        with self.assertRaises(build_content.BuildError) as cm:
            build_content.build(self.src, self.out, release=True)
        self.assertRegex("\n".join(cm.exception.errors), r"can't ship in a release build")

    def test_duplicate_id(self):
        self.write_set(self.variant(id="fixture-2-3"))
        self.assertBuildFails(r"duplicate id fixture-2-3")

    def test_missing_quran_text(self):
        (self.src / "tanzil" / "quran-uthmani.xml").unlink()
        self.assertBuildFails(r"missing .*quran-uthmani.xml")

    def test_quranenc_tafsir_must_be_mukhtasar(self):
        p = self.src / "quranenc" / "fixture_mukhtasar_en.json"
        p.write_text(p.read_text().replace("Al-Mukhtasar fi Tafsir al-Qur'an", "Another Tafsir"))
        self.assertBuildFails(r"QuranEnc tafsir must be Al-Mukhtasar")

    def test_tafsir_excerpt_must_be_allowed(self):
        (self.src / "tafsir" / "bad.yaml").write_text(
            '- { book: "Tafsir X", ayah: "2:3", lang: en, text: "FIXTURE", location: "p. 1" }\n')
        self.assertBuildFails(r"'Tafsir X' is not an allowed tafsir")

    def test_all_problems_reported_together(self):
        data = self.variant(ayah="2:99", topics=["nope"])
        data["story"]["refs"] = []
        self.write_set(data)
        with self.assertRaises(build_content.BuildError) as cm:
            build_content.build(self.src, self.out)
        self.assertGreaterEqual(len(cm.exception.errors), 3)


class Allowlist(unittest.TestCase):
    def test_every_book_is_named_in_the_policy(self):
        policy = (ROOT / "CONTENT-POLICY.md").read_text()
        for name, info in sources.BOOKS.items():
            needle = info.get("policy_row", name)
            self.assertIn(needle.lower(), policy.lower(), f"{name} is not in CONTENT-POLICY.md")

    def test_topic_ids_match_swift_catalog(self):
        swift = (ROOT / "Packages/NasuhaCore/Sources/NasuhaCore/Topics/TopicCatalog.swift").read_text()
        ids = re.findall(r'Topic\(id: "([a-z]+)"', swift)
        self.assertEqual(len(ids), 29)
        self.assertEqual(set(ids), build_content.TOPIC_IDS)


class SwiftFixture(unittest.TestCase):
    """Builds the database the Swift ContentStore tests read."""

    def test_write_swift_fixture(self):
        SWIFT_FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        build_content.build(FIXTURE_SRC, SWIFT_FIXTURE)
        self.assertTrue(SWIFT_FIXTURE.exists())


if __name__ == "__main__":
    unittest.main()
