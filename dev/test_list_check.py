#!/usr/bin/env python3
"""Lists each test a step's test list names that the step's diff does not define.

    python3 -I dev/test_list_check.py ISSUE BASE HEAD

The test list is the newest comment on ISSUE headed "test list" (any case) that
names a test, else the issue's body when it is headed so and names one; a headed
comment naming no test, such as a note on a change to the list, is passed over. Headed means the first non-blank line,
after its leading `#`, `*` and spaces, starts with "test list". A listed test is a
backticked name that ends in `_test` (Gleam, optionally `module.` first) or starts
with `test_` (Python).
A test is defined by an added line `pub fn NAME(` or `def NAME(` in
`git diff BASE HEAD`. A name that is a test module's file name is skipped.
A name not defined in the diff is looked up in HEAD's tree, so a listed test
that already existed is told apart from a missing one.

Exit 0 when every listed test is defined in the diff, 1 when one is not,
2 when no test list on the issue names a test. It replaces the reviewers' by-hand test
list check; it gates no merge, so it has no tests of its own and is checked by
use.
"""

import json
import re
import subprocess
import sys

LISTED = re.compile(r"`(?:[a-z0-9_]+\.)*([a-z0-9_]+_test|test_[a-z0-9_]+)`")
DEFINED = re.compile(r"^\+\s*(?:pub fn|def)\s+([a-z0-9_]+)\s*\(", re.MULTILINE)


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def is_headed_test_list(text: str) -> bool:
    """True when the first non-blank line is a heading or bold line naming the test list."""
    for line in text.splitlines():
        if line.strip():
            return line.lstrip("#* ").lower().startswith("test list")
    return False


def test_list_text(issue: str) -> str | None:
    found = json.loads(run("gh", "issue", "view", issue, "--json", "body,comments"))
    texts = [c["body"] for c in reversed(found["comments"])] + [found["body"]]
    for text in texts:
        if is_headed_test_list(text) and LISTED.search(text):
            return text
    return None


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.splitlines()[2].strip(), file=sys.stderr)
        return 2
    issue, base, head = sys.argv[1:]
    text = test_list_text(issue)
    if text is None:
        print(f"issue {issue} holds no test list naming a test")
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
