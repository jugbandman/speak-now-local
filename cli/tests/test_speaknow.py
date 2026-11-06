"""Tests for the speaknow CLI. Run from the repo root:

    python3 -m unittest discover -s cli/tests

Each test points SPEAKNOW_HOME and HOME at a temp folder, so nothing real is touched.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest

CLI = os.path.join(os.path.dirname(__file__), "..", "speaknow")


def load_cli(home):
    os.environ["HOME"] = home
    os.environ["SPEAKNOW_HOME"] = os.path.join(home, ".speaknow")
    loader = importlib.machinery.SourceFileLoader("speaknow_cli", CLI)
    spec = importlib.util.spec_from_loader("speaknow_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def run(mod, *argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        mod.main(list(argv))
    return out.getvalue()


class SpeaknowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.old_home = os.environ.get("HOME")
        self.mod = load_cli(self.home)

    def tearDown(self):
        if self.old_home:
            os.environ["HOME"] = self.old_home
        os.environ.pop("SPEAKNOW_HOME", None)
        self.tmp.cleanup()

    # config

    def test_config_set_and_get_keeps_types_and_unknown_keys(self):
        os.makedirs(self.mod.ROOT)
        with open(self.mod.CONFIG, "w") as f:
            json.dump({"myOwnKey": 1, "model": "medium"}, f)
        run(self.mod, "config", "set", "autoPaste", "yes")
        run(self.mod, "config", "set", "claudeFolders", "~/a, ~/b")
        with open(self.mod.CONFIG) as f:
            cfg = json.load(f)
        self.assertIs(cfg["autoPaste"], True)
        self.assertEqual(cfg["claudeFolders"], [os.path.join(self.home, "a"), os.path.join(self.home, "b")])
        self.assertEqual(cfg["myOwnKey"], 1)
        self.assertEqual(run(self.mod, "config", "get", "model").strip(), "medium")

    def test_config_bool_rejects_nonsense(self):
        with self.assertRaises(SystemExit):
            run(self.mod, "config", "set", "sounds", "maybe")

    # corrections

    def test_fix_creates_and_merges(self):
        run(self.mod, "fix", "Belair", "Velare")
        run(self.mod, "fix", "Valair", "velare")
        run(self.mod, "fix", "belair", "Velare")
        with open(self.mod.CORRECTIONS) as f:
            items = self.mod.parse_corrections(f.read())
        self.assertEqual(items, [("Velare", ["Belair", "Valair"])])

    def test_parse_corrections_skips_comments_and_bad_lines(self):
        text = "# Title\n\nSome prose without the separator\n- FareHarbor: fair harbor, fare harbour\nTito:\n"
        self.assertEqual(self.mod.parse_corrections(text),
                         [("FareHarbor", ["fair harbor", "fare harbour"])])

    # transcripts

    def write_transcript(self, name, category, body, raw=None, summary=None):
        folder = os.path.join(self.home, "Documents", "SpeakNowLocal", "Transcripts")
        os.makedirs(folder, exist_ok=True)
        fm = "---\ndate: x\nmodel: small.en\nduration: 1.0s\nprocessed: false\ncategory: %s\n" % category
        if summary:
            fm += "summary: %s\n" % summary
        fm += "---\n\n"
        text = ("**%s**\n\n" % summary if summary else "") + body
        if raw:
            text += "\n\n---\n\n*Original transcript:*\n\n" + raw
        with open(os.path.join(folder, name), "w") as f:
            f.write(fm + text)

    def test_last_and_last_prompt(self):
        self.write_transcript("2026-11-01-09-00-00-transcript.md", "PROMPT", "Shaped prompt", raw="raw takes", summary="Login fix")
        self.write_transcript("2026-11-02-09-00-00-transcript.md", "NOTE", "Newest note")
        self.assertEqual(run(self.mod, "last").strip(), "Newest note")
        self.assertEqual(run(self.mod, "last", "--prompt").strip(), "Shaped prompt")
        self.assertEqual(run(self.mod, "last", "--prompt", "--raw").strip(), "raw takes")

    def test_dumps_filters_by_category(self):
        self.write_transcript("2026-11-01-09-00-00-transcript.md", "PROMPT", "A prompt")
        self.write_transcript("2026-11-02-09-00-00-transcript.md", "NOTE", "A note")
        out = run(self.mod, "dumps", "--category", "note")
        self.assertIn("A note", out)
        self.assertNotIn("A prompt", out)

    def test_parse_since(self):
        self.assertTrue(self.mod.parse_since("7d") < self.mod.dt.datetime.now())
        with self.assertRaises(SystemExit):
            self.mod.parse_since("soon")

    # ideas

    def test_ideas_groups_by_bucket_and_counts_dumps(self):
        os.makedirs(self.mod.ROOT)
        data = {
            "cards": [
                {"id": "c1", "title": "Prompt mode gaps", "bucket": "product", "ideaIDs": ["i1", "i2"]},
                {"id": "c2", "title": "Carpool", "bucket": "personal", "ideaIDs": ["i3"]},
            ],
            "ideas": [
                {"id": "i1", "text": "ask what done means", "entryID": "e1", "date": "2026-11-03T10:00:00Z"},
                {"id": "i2", "text": "check the gaps", "entryID": "e2", "date": "2026-11-04T10:00:00Z"},
                {"id": "i3", "text": "hockey carpool", "entryID": "e3", "date": "2026-11-02T10:00:00Z"},
            ],
        }
        with open(self.mod.IDEAS, "w") as f:
            json.dump(data, f)
        out = run(self.mod, "ideas")
        self.assertIn("## Product", out)
        self.assertIn("Prompt mode gaps", out)
        self.assertIn("raised 2 times", out)
        self.assertLess(out.index("## Product"), out.index("## Personal"))
        only = run(self.mod, "ideas", "--bucket", "personal")
        self.assertNotIn("Product", only)

    def test_ideas_empty(self):
        self.assertIn("No ideas", run(self.mod, "ideas"))


if __name__ == "__main__":
    unittest.main()
