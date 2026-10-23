"""Reject ignored secrets/data in the Git index; never print their contents."""

import subprocess
import sys
from pathlib import Path


def check_repository(root: Path) -> int:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--ignored", "--exclude-standard", "-z"],
        cwd=root, check=True, capture_output=True,
    )
    forbidden = [p.decode("utf-8") for p in result.stdout.split(b"\0") if p]
    if forbidden:
        print("Ignored secrets/data are tracked or staged. Stop before push:", file=sys.stderr)
        for path in forbidden:
            print(f"  {path}", file=sys.stderr)
        return 1
    print("Git index contains no files excluded by the repository ignore rules.")
    return 0


if __name__ == "__main__":
    sys.exit(check_repository(Path(__file__).resolve().parents[1]))
