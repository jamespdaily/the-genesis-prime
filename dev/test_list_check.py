#!/usr/bin/env python3
"""Lists each test a step's test list names that the step's diff does not define.

    python3 -I dev/test_list_check.py ISSUE BASE HEAD
    python3 -I dev/test_list_check.py --existing BASE LIST

The test list is the newest comment on ISSUE headed "test list" (any case) that
names a test, else the issue's body when it is headed so and names one; a headed
comment naming no test, such as a note on a change to the list, is passed over. Headed means the first non-blank line,
after its leading `#`, `*` and spaces, starts with "test list". A listed test is a
backticked name that ends in `_test` (Gleam, optionally `module.` first) or starts
with `test_` (Python).
A test is defined by an added line `pub fn NAME(` or `def NAME(` in
`git diff BASE HEAD`, or gains a row when the diff adds lines inside an existing
`pub fn NAME(` (the hunk's header names the function, as git finds it for a Gleam file;
a hunk between that function's end and the next one counts for it too, so a reviewer reads the rows).
A name that is a test module's file name is skipped.
A name not defined in the diff is looked up in HEAD's tree, so a listed test
that already existed is told apart from a missing one.

Exit 0 when every listed test is defined in the diff, 1 when one is not,
2 when no test list on the issue names a test. It replaces the reviewers' by-hand test
list check; it gates no merge, so it has no tests of its own and is checked by
use.

`--existing BASE LIST` runs before the build: LIST is an issue number (its test list as above)
or the path of a draft file (the whole file), and each backticked listed test already defined at BASE
is printed as `NAME: already at FILE, write it plainly` (a list backticks only the tests its step adds),
unless a line of the list that names it also says "row": a new row of an existing table test, printed as
`NAME: a new row of FILE`. A test list is sized by the decisions a step adds, and a decision that fits an
existing table test is a row there, not a new function (Jim, 2026-11-22).
Exit 1 when a test is printed as already there, 0 when none is, 2 when the list names no test.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

LISTED = re.compile(r"`(?:[a-z0-9_]+\.)*([a-z0-9_]+_test|test_[a-z0-9_]+)`")
DEFINED = re.compile(r"^\+\s*(?:pub fn|def)\s+([a-z0-9_]+)\s*\(", re.MULTILINE)
# A -U0 hunk inside an existing function, whose header names it, followed by an added line.
ROW_ADDED = re.compile(r"^@@ [^@]* @@ \s*(?:pub fn|def)\s+([a-z0-9_]+)\s*\(.*\n\+", re.MULTILINE)
ROW_WORD = re.compile(r"\brows?\b", re.IGNORECASE)


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def defined_at(ref: str, name: str) -> list[str]:
    """The files of ref's tree that define a function called name."""
    grep = subprocess.run(["git", "grep", "-lE", rf"(pub fn|def) {name}\(", ref], capture_output=True, text=True)
    return [line.split(":", 1)[1] for line in grep.stdout.split()]


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


def listed_names(text: str, ref: str) -> list[str]:
    """The tests the text lists in backticks, once each, leaving out the names of test modules at ref."""
    files = run("git", "ls-tree", "-r", "--name-only", ref).split()
    modules = {f.rsplit("/", 1)[-1].rsplit(".", 1)[0] for f in files}
    # A backticked test module's name (`hit_test`) ends in _test too; it is not a test.
    return [n for n in dict.fromkeys(LISTED.findall(text)) if n not in modules]


def existing(base: str, source: str) -> int:
    """Prints each listed test already defined at base; the source is an issue number or a draft's path."""
    path = Path(source)
    text = path.read_text() if path.is_file() else test_list_text(source)
    if text is None or not LISTED.search(text):
        print(f"{source} holds no test list naming a test")
        return 2
    found = 0
    for name in listed_names(text, base):
        where = defined_at(base, name)
        if not where:
            continue
        if any(f"`{name}`" in line and ROW_WORD.search(line) for line in text.splitlines()):
            print(f"{name}: a new row of {where[0]}")
        else:
            print(f"{name}: already at {where[0]}, write it plainly")
            found += 1
    print(f"{found} listed tests already exist at {base}")
    return 1 if found else 0


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "--existing":
        return existing(sys.argv[2], sys.argv[3])
    if len(sys.argv) != 4:
        print("\n".join(line.strip() for line in __doc__.splitlines()[2:4]), file=sys.stderr)
        return 2
    issue, base, head = sys.argv[1:]
    text = test_list_text(issue)
    if text is None:
        print(f"issue {issue} holds no test list naming a test")
        return 2
    listed = listed_names(text, head)
    diff = run("git", "diff", "-U0", base, head)
    defined = set(DEFINED.findall(diff))
    rows = set(ROW_ADDED.findall(diff)) - defined
    for name in listed:
        if name in rows:
            print(f"{name}: rows added to an existing test")
    missing = [name for name in listed if name not in defined and name not in rows]
    for name in missing:
        where = defined_at(head, name)
        print(f"{name}: not in the diff" + (f", already at {where[0]}" if where else ", missing"))
    print(f"{len(listed) - len(missing)} of {len(listed)} listed tests defined or given rows in the diff")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
