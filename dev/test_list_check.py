#!/usr/bin/env python3
"""Lists each test a step's test list names that the step's diff does not define.

    python3 -I dev/test_list_check.py ISSUE BASE HEAD

The test list is the newest comment on ISSUE that holds "test list" (any case),
else the issue's body when it does. A listed test is a backticked name that ends
in `_test` (Gleam, optionally `module.` first) or starts with `test_` (Python).
A test is defined by an added line `pub fn NAME(` or `def NAME(` in
`git diff BASE HEAD`. A name that is a test module's file name is skipped.
A name not defined in the diff is looked up in HEAD's tree, so a listed test
that already existed is told apart from a missing one.

Exit 0 when every listed test is defined in the diff, 1 when one is not,
2 when the issue holds no test list. It replaces the reviewers' by-hand test
list check (Fight retro item C5, 2026-11-07); it gates no merge, so it has no
tests of its own and is checked by use.
"""

import json
import re
import subprocess
import sys

LISTED = re.compile(r"`(?:[a-z0-9_]+\.)*([a-z0-9_]+_test|test_[a-z0-9_]+)`")
DEFINED = re.compile(r"^\+\s*(?:pub fn|def)\s+([a-z0-9_]+)\s*\(", re.MULTILINE)


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def test_list_text(issue: str) -> str | None:
    found = json.loads(run("gh", "issue", "view", issue, "--json", "body,comments"))
    for comment in reversed(found["comments"]):
        if "test list" in comment["body"].lower():
            return comment["body"]
    if "test list" in found["body"].lower():
        return found["body"]
    return None


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.splitlines()[2].strip(), file=sys.stderr)
        return 2
    issue, base, head = sys.argv[1:]
    text = test_list_text(issue)
    if text is None:
        print(f"issue {issue} holds no test list")
        return 2
    files = run("git", "ls-tree", "-r", "--name-only", head).split()
    modules = {f.rsplit("/", 1)[-1].rsplit(".", 1)[0] for f in files}
    # A backticked test module's name (`hit_test`) ends in _test too; it is not a test.
    listed = [n for n in dict.fromkeys(LISTED.findall(text)) if n not in modules]
    defined = set(DEFINED.findall(run("git", "diff", base, head)))
    missing = [name for name in listed if name not in defined]
    for name in missing:
        grep = subprocess.run(
            ["git", "grep", "-lE", rf"(pub fn|def) {name}\(", head],
            capture_output=True,
            text=True,
        )
        where = grep.stdout.split()
        print(f"{name}: not in the diff" + (f", already at {where[0]}" if where else ", missing"))
    print(f"{len(listed) - len(missing)} of {len(listed)} listed tests defined in the diff")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
