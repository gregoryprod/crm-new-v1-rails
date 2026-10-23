"""Prevent CRM task operations from silently reaching the client's parent DB."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("crm_beads", Path(__file__).resolve().parents[1] / "scripts" / "beads.py")
beads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(beads)


class RoutingTests(unittest.TestCase):
    def workspace(self, root, prefix="vpc-crm", initialized=True):
        p = root / ".beads"
        p.mkdir(parents=True)
        (p / "config.yaml").write_text(f"issue-prefix: {prefix}\n")
        if initialized:
            (p / "metadata.json").write_text("{}")
            (p / "embeddeddolt").mkdir()
        return p.resolve()

    def test_ancestor_database_is_never_selected(self):
        with tempfile.TemporaryDirectory() as d:
            parent = Path(d)
            foreign = self.workspace(parent, "vpc")
            root = parent / "crm"
            root.mkdir()
            with self.assertRaises(ValueError):
                beads.select_workspace([root])
            with self.assertRaises(ValueError):
                beads.select_workspace([root], str(foreign))

    def test_linked_worktrees_share_the_initialized_crm_database(self):
        with tempfile.TemporaryDirectory() as d:
            primary = Path(d) / "primary"
            feature = Path(d) / "feature"
            pending = self.workspace(primary, initialized=False)
            initialized = self.workspace(feature)
            self.assertEqual(beads.select_workspace([primary, feature]), initialized)
            self.assertEqual(beads.select_workspace([primary]), pending)

    def test_ambiguous_databases_require_explicit_choice(self):
        with tempfile.TemporaryDirectory() as d:
            roots = [Path(d) / "one", Path(d) / "two"]
            databases = [self.workspace(root) for root in roots]
            with self.assertRaises(ValueError):
                beads.select_workspace(roots)
            self.assertEqual(beads.select_workspace(roots, str(databases[1])), databases[1])

    def test_wrong_prefix_and_same_name_outside_repo_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d) / "crm"
            foreign = self.workspace(root, "vpc-crm-other")
            with self.assertRaises(ValueError):
                beads.select_workspace([root], str(foreign))
            outside = self.workspace(Path(d) / "other-repo")
            with self.assertRaises(ValueError):
                beads.select_workspace([root], str(outside))

    def test_ambient_routing_cannot_override_the_chosen_database(self):
        env = beads.scoped_environment(Path("/crm/.beads"), {
            "BEADS_DB": "/other/db", "BEADS_DOLT_SERVER_MODE": "1",
            "BEADS_DOLT_SERVER_PORT": "3307", "GIT_DIR": "/other/.git",
            "BEADS_DIR": "/other/.beads", "BEADS_ACTOR": "Codex", "PATH": "/bin",
        })
        self.assertEqual(env, {"BEADS_DIR": "/crm/.beads", "BEADS_ACTOR": "Codex", "PATH": "/bin"})

    def test_command_flags_cannot_bypass_database_checks(self):
        for args in [["--db", "/other/db", "close", "x"], ["show", "x", "--database=other"],
                     ["--global", "list"], ["-C/other", "ready"], ["--directory=/other", "list"]]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                beads.validate_arguments(args)
        beads.validate_arguments(["--actor", "Codex", "update", "vpc-crm-7p4", "--claim"])


if __name__ == "__main__":
    unittest.main()
