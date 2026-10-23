"""Exercise actual Git ignore/index behavior using an isolated synthetic repository."""

import importlib.util
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "repository_data", REPOSITORY / "scripts/check-repository-data.py"
)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class RepositoryDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="vpc-data-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "--quiet")
        (self.root / ".gitignore").write_bytes((REPOSITORY / ".gitignore").read_bytes())
        self.git("add", ".gitignore")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, capture_output=True, check=True
        )

    def test_secret_and_export_paths_are_ignored(self):
        paths = [
            ".env", ".env.local", ".env.production", "src/.env.local",
            "export/full/raw/clients/1.json", "private/exports/merged/клиенты.csv",
            "База/clients.json", "data/records.json", "клиенты.csv", "записи.csv",
            "notes/report.xlsx", "local.sqlite", ".orchestration/run.json",
        ]
        for path in paths:
            with self.subTest(path=path):
                self.git("check-ignore", "--no-index", "--", path)

    def test_templates_and_code_remain_trackable(self):
        paths = [
            ".env.example", "src/app/page.tsx", "drizzle/0001.sql",
            "src/app/export/page.tsx", "src/lib/data/clients.ts",
            "docs/yclients/openapi.json", "AGENTS.md", "CLAUDE.md",
            ".github/workflows/repository-safety.yml",
        ]
        for path in paths:
            with self.subTest(path=path):
                result = subprocess.run(
                    ["git", "check-ignore", "--no-index", "--", path], cwd=self.root,
                    capture_output=True,
                )
                self.assertEqual(result.returncode, 1, path)

    def test_force_added_secret_is_rejected_without_printing_contents(self):
        sentinel = "SYNTHETIC_CONTENT_MUST_NOT_APPEAR"
        (self.root / ".env.local").write_text(sentinel)
        self.git("add", "--force", ".env.local")
        output, errors = StringIO(), StringIO()
        with redirect_stdout(output), redirect_stderr(errors):
            status = checker.check_repository(self.root)
        self.assertEqual(status, 1)
        self.assertIn(".env.local", errors.getvalue())
        self.assertNotIn(sentinel, output.getvalue() + errors.getvalue())

    def test_force_added_export_is_rejected(self):
        file = self.root / "private" / "records.json"
        file.parent.mkdir()
        file.write_text('{"synthetic": true}')
        self.git("add", "--force", "private/records.json")
        with redirect_stderr(StringIO()):
            self.assertEqual(checker.check_repository(self.root), 1)

    def test_clean_index_passes(self):
        (self.root / ".env.example").write_text("YCLIENTS_PARTNER_TOKEN=\n")
        self.git("add", ".env.example")
        with redirect_stdout(StringIO()):
            self.assertEqual(checker.check_repository(self.root), 0)


if __name__ == "__main__":
    unittest.main()
