"""Lists the test files a step's change can affect, and runs them.

    python3 -I dev/affected_tests.py BASE HEAD
    python3 -I dev/affected_tests.py BASE HEAD --run

The changed files are the `.gleam` files under src/, dev/ and test/ that differ between
`git merge-base BASE HEAD` and HEAD (a deleted file included). A `test/**/*_test.gleam` file is
listed, one per line and sorted, when any of these holds:
  - it is changed itself;
  - its imports reach a changed module, directly or through other modules, not walking past the
    HARNESS_MODULES unless one of them changed (the import graph is
    read from the text of every `.gleam` file under src/, dev/ and test/ in the working tree,
    so it needs no build, and a cycle is walked once);
  - its text holds a changed module's file path (`genesis_prime/m.gleam`), as a test that reads a
    source file by path does.

A module's name is its path under src/, dev/ or test/ without `.gleam`. A changed file that is
not Gleam (a `.erl` foreign module, a table file) reaches no test here.

`--run` runs each listed file by itself with `gleam test -- FILE`, prints `FILE: LAST LINE` for
each (the last unitest status line such as `6 passed, no failures`, else the last line of its
output), keeps each file's whole output in a folder it names when one fails, and exits 1 when a
file failed, 0 otherwise. With no file listed it prints that and exits 0.

Exit 2 for a git answer or usage it cannot use. It decides nothing about CI; it names what a
builder runs before handing back and what the coordinator checks.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_FOLDERS = ("src", "dev", "test")
IMPORT = re.compile(r"^import\s+([a-z0-9_/]+)", re.MULTILINE)
# Test modules every test imports to set up its run (owned_test starts each body in its own process
# under a deadline; fixed_seed derives the run's dice and imports the server to start it). They carry
# no game code into a test's subject, but they import the server, so walking through them would
# list every test for a change to the server. A change to one of them itself lists every importer.
HARNESS_MODULES = frozenset({"fixed_seed", "owned_test"})
STATUS_LINE = re.compile(r"^\d+ passed, ", re.MULTILINE)


class Unusable(Exception):
    """A usage or git answer the script cannot work with."""


def git(*arguments: str) -> str:
    done = subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        raise Unusable("git %s failed: %s" % (" ".join(arguments), done.stderr.strip()))
    return done.stdout.strip()


def module_path(path: str) -> str | None:
    """The path a Gleam file under a source folder is imported by, else None."""
    folder, _, rest = path.partition("/")
    if folder in SOURCE_FOLDERS and rest.endswith(".gleam"):
        return rest[: -len(".gleam")]
    return None


def changed_files(base: str, head: str) -> list[str]:
    merge_base = git("merge-base", base, head)
    names = git("-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", merge_base, head)
    return [name for name in names.splitlines() if module_path(name) is not None]


def source_files() -> dict[str, list[Path]]:
    """Every Gleam file of the working tree, by the module name it is imported by."""
    files: dict[str, list[Path]] = {}
    for folder in SOURCE_FOLDERS:
        for path in sorted((ROOT / folder).rglob("*.gleam")):
            name = module_path(path.relative_to(ROOT).as_posix())
            assert name is not None
            files.setdefault(name, []).append(path)
    return files


def importers_of(files: dict[str, list[Path]]) -> dict[str, set[str]]:
    """For each module name, the module names that import it."""
    importers: dict[str, set[str]] = {}
    for name, paths in files.items():
        for path in paths:
            for imported in IMPORT.findall(path.read_text(errors="replace")):
                importers.setdefault(imported, set()).add(name)
    return importers


def reaching(importers: dict[str, set[str]], start: set[str]) -> set[str]:
    """The modules whose imports reach one of start, start included; each is walked once.

    A harness module reached only through other modules is listed but not walked past."""
    seen = set(start)
    pending = list(start)
    while pending:
        module = pending.pop()
        if module in HARNESS_MODULES and module not in start:
            continue
        for importer in importers.get(module, ()):
            if importer not in seen:
                seen.add(importer)
                pending.append(importer)
    return seen


def affected_tests(base: str, head: str) -> list[str]:
    changed = changed_files(base, head)
    files = source_files()
    reached = reaching(importers_of(files), {module_path(name) or "" for name in changed})
    changed_paths = [name.partition("/")[2] for name in changed]
    listed: set[str] = set()
    for name, paths in files.items():
        for path in paths:
            relative = path.relative_to(ROOT).as_posix()
            if not relative.startswith("test/") or not relative.endswith("_test.gleam"):
                continue
            text = path.read_text(errors="replace")
            if name in reached or any(changed_path in text for changed_path in changed_paths):
                listed.add(relative)
    return sorted(listed)


def last_line(output: str) -> str:
    statuses = [line for line in output.splitlines() if STATUS_LINE.match(line)]
    if statuses:
        return statuses[-1]
    lines = [line for line in output.splitlines() if line.strip()]
    return lines[-1] if lines else "no output"


def run_each(files: list[str]) -> int:
    logs = Path(tempfile.mkdtemp(prefix="genesis-affected-tests-"))
    failed = 0
    for number, file in enumerate(files):
        done = subprocess.run(
            ["gleam", "test", "--", file], cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True
        )
        output = done.stdout + done.stderr
        (logs / ("%d.log" % number)).write_text(output)
        mark = "" if done.returncode == 0 else " (FAILED, exit status %d)" % done.returncode
        print("%s: %s%s" % (file, last_line(output), mark), flush=True)
        failed += done.returncode != 0
    if failed:
        print("%d of %d files failed; the output of each is in %s" % (failed, len(files), logs))
        return 1
    print("all %d files passed" % len(files))
    return 0


def main(arguments: list[str]) -> int:
    run = "--run" in arguments
    positional = [argument for argument in arguments if argument != "--run"]
    if len(positional) != 2:
        print("usage: python3 -I dev/affected_tests.py BASE HEAD [--run]")
        return 2
    try:
        files = affected_tests(*positional)
    except Unusable as problem:
        print(problem)
        return 2
    if not run:
        for file in files:
            print(file)
        return 0
    if not files:
        print("no affected test file, so nothing to run")
        return 0
    return run_each(files)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
