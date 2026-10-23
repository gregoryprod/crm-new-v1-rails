"""Run bd against the CRM workspace, never an ancestor's Beads database."""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

VERSION = "1.3.0"
PREFIX = "vpc-crm"


def is_crm_workspace(path: Path) -> bool:
    config = path / "config.yaml"
    return config.is_file() and bool(re.search(
        r"(?m)^issue-prefix:\s*['\"]?vpc-crm['\"]?\s*$", config.read_text()
    ))


def select_workspace(roots: list[Path], explicit: str | None = None) -> Path:
    candidates = [root.resolve() / ".beads" for root in roots]
    if explicit:
        selected = Path(explicit).resolve()
        if selected not in candidates or not is_crm_workspace(selected):
            raise ValueError("BEADS_DIR must identify a vpc-crm workspace in this Git repository.")
        return selected
    valid = [p for p in candidates if is_crm_workspace(p)]
    initialized = [p for p in valid if (p / "metadata.json").is_file()
                   and (p / "embeddeddolt").is_dir()]
    if len(initialized) > 1:
        raise ValueError("Multiple CRM databases: set BEADS_DIR explicitly; do not reinitialize.")
    if initialized:
        return initialized[0]
    if valid:
        return valid[0]  # Primary worktree first; bootstrap restores from origin.
    raise ValueError("No CRM Beads config. Use the Beads branch; do not use the ancestor database.")


def scoped_environment(workspace: Path, source: dict[str, str]) -> dict[str, str]:
    env = source.copy()
    for key in list(env):
        if key in {"BEADS_DB", "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR"} or key.startswith("BEADS_DOLT_"):
            env.pop(key)
    env["BEADS_DIR"] = str(workspace)
    return env


def validate_arguments(args: list[str]) -> None:
    forbidden = {"--db", "--database", "--directory", "--global"}
    if any(arg.split("=", 1)[0] in forbidden or arg.startswith("-C") for arg in args):
        raise ValueError("Database/directory overrides are disabled; use verified BEADS_DIR.")


def main(args: list[str]) -> int:
    validate_arguments(args)
    root = Path(__file__).resolve().parents[1]
    listing = subprocess.check_output(
        ["git", "-C", str(root), "worktree", "list", "--porcelain", "-z"], text=True,
        env=scoped_environment(root / ".beads", os.environ),
    )
    roots = [Path(part[9:]) for part in listing.split("\0") if part.startswith("worktree ")]
    workspace = select_workspace(roots, os.environ.get("BEADS_DIR"))
    local_binary = workspace.parent / ".orchestration" / "bin" / "bd"
    binary = str(local_binary) if local_binary.is_file() else shutil.which("bd")
    if not binary:
        raise ValueError("Install the pinned CLI: python3 scripts/install-beads.py")
    env = scoped_environment(workspace, os.environ)
    version = subprocess.check_output([binary, "version"], cwd=root, env=env, text=True)
    if not re.search(r"\bbd version " + re.escape(VERSION) + r"(?:\s|$)", version):
        raise ValueError("Expected bd 1.3.0. Run python3 scripts/install-beads.py; do not migrate other databases.")
    if args and args[0] == "bootstrap":
        # Fresh clones have config but no DB; bootstrap is the explicit recovery action.
        if (workspace / "metadata.json").is_file() and (workspace / "embeddeddolt").is_dir():
            raise ValueError("CRM database exists; use dolt pull instead of bootstrap.")
    else:
        where = json.loads(subprocess.check_output(
            [binary, "where", "--json"], cwd=root, env=env, text=True
        ))
        if Path(where["path"]).resolve() != workspace or where.get("prefix") != PREFIX:
            raise ValueError("bd resolved another database; stopped before executing the command.")
    return subprocess.call([binary, *args], cwd=root, env=env)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:] or ["prime"]))
    except (ValueError, subprocess.CalledProcessError, OSError, KeyError) as error:
        print(f"Beads: {error}", file=sys.stderr)
        sys.exit(1)
