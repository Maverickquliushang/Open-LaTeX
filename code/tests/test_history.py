"""Exercise real Git safety boundaries using only independently authored files."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "paper_history", Path(__file__).resolve().parents[1] / "src/tools/paper_history.py")
history = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(history)


class HistorySafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="open-latex-history-", dir="/work")
        self.root = Path(self.temp.name)
        self.repo = self.root / "papers" / "Original Example"
        self.repo.mkdir(parents=True)
        self.doc = self.repo / "main.tex"
        self.doc.write_text("Original first version.\n", encoding="utf-8")
        history.initialize(self.repo)
        history.snapshot(self.repo)

    def tearDown(self):
        self.temp.cleanup()

    def test_unchanged_does_not_commit_and_staged_work_is_preserved(self):
        before = history.git(self.repo, "rev-parse", "HEAD").stdout
        self.assertEqual(history.snapshot(self.repo), "unchanged")
        self.doc.write_text("User staged edit.\n", encoding="utf-8")
        history.git(self.repo, "add", "main.tex")
        with self.assertRaises(RuntimeError):
            history.snapshot(self.repo)
        self.assertEqual(before, history.git(self.repo, "rev-parse", "HEAD").stdout)
        self.assertIn("User staged edit", history.git(self.repo, "show", ":main.tex").stdout)

    def test_restore_keeps_recovery_point_and_excludes_generated_outputs(self):
        target = history.git(self.repo, "rev-parse", "HEAD").stdout.strip()
        self.doc.write_text("Saved edit before restore.\n", encoding="utf-8")
        (self.repo / "new-source.tex").write_text("Additional source.\n", encoding="utf-8")
        output = self.repo / "output"
        output.mkdir()
        (output / "main.pdf").write_bytes(b"test output")
        backup = history.restore(self.repo, target)
        self.assertEqual(self.doc.read_text(), "Original first version.\n")
        self.assertIn("Saved edit before restore", history.git(self.repo, "show", backup + ":main.tex").stdout)
        self.assertIn("Additional source", history.git(self.repo, "show", backup + ":new-source.tex").stdout)
        self.assertEqual((output / "main.pdf").read_bytes(), b"test output")
        self.assertNotIn("output/", history.git(self.repo, "ls-files").stdout)
        self.assertTrue(history.git(self.repo, "tag", "--list", "before-restore-*").stdout.strip())

    def test_foreign_repository_is_not_adopted(self):
        foreign = self.root / "foreign"
        foreign.mkdir()
        history.git(foreign, "init")
        with self.assertRaises(RuntimeError):
            history.initialize(foreign)
        self.assertFalse(history.managed(foreign))

    def test_deployment_gate_blocks_history_mutations(self):
        tools = self.root / '.latex-tools'
        tools.mkdir()
        (tools / '.deployment-in-progress.json').write_text('{}')
        with self.assertRaises(RuntimeError):
            with history.lock(self.repo.parent):
                self.fail('History mutation must not run while deployment is active.')


if __name__ == "__main__":
    unittest.main(verbosity=2)
