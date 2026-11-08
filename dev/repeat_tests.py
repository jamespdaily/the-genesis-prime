"""Runs the test files a branch adds or changes many times at once, so a test that depends on timing fails in the pull request that brings it.

    python3.13 -I dev/repeat_tests.py BASE

BASE is the branch the pull request goes into (CI passes origin/<base branch>). The files are
the `test/**/*_test.gleam` files added or changed between `git merge-base BASE HEAD` and HEAD
(a deleted file, a support module and a file the branch leaves alone are not). With none, it
prints that and exits 0.

Each file is run on the code `gleam build` already built, in a VM of its own, GENESIS_REPEAT_RUNS
times (default 20), each run with its own random seed, GENESIS_REPEAT_AT_ONCE VMs at a time
(default the number of CPUs), so every run is under the load of the others. A VM takes the
file as its one argument because unitest runs one file per start. The skip variables are the
ones ./check's test run sets: the tests tagged serial (they share a machine-wide resource,
so VMs side by side would break them), world_data, client_rows and dev_tool are not run.

The script fails (exit 1) when any run fails, after every run has ended, and prints each failing
run's file, seed, failing tests and the command that repeats it (`gleam test -- FILE --seed
SEED`), with the part of its output that says why; the output of every run is kept in the
folder it names. It exits 2 for a setting or a git answer it cannot use. It starts `erl` from
PATH, so run it with the patched OTP first on PATH, as ./check does.
"""

import concurrent.futures
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DEFAULT_RUNS = 20

# The variables ./check's gleam_test sets for its first test run (test/genesis_prime_test.gleam
# reads them), less the literal peak file.
SKIP_VARIABLES = (
    "GENESIS_TEST_SKIP_SERIAL",
    "GENESIS_TEST_SKIP_WORLD_DATA",
    "GENESIS_TEST_SKIP_CLIENT_ROWS",
    "GENESIS_TEST_SKIP_DEV_TOOL",
)

FAILING_TEST = re.compile(r"^\s*\d+\) (\S+) \(", re.MULTILINE)
FAILURES_MARK = "Failures:"
EXCERPT_LINES = 60


@dataclass(frozen=True)
class Run:
    number: int
    file: str
    seed: int


@dataclass(frozen=True)
class Outcome:
    run: Run
    status: int
    log: Path


class Unusable(Exception):
    """A setting or a git answer the script cannot work with."""


def git(*arguments: str) -> str:
    done = subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        raise Unusable("git %s failed: %s" % (" ".join(arguments), done.stderr.strip()))
    return done.stdout.strip()


def changed_test_files(base: str) -> list[str]:
    """The test files added or changed since the merge base of base and HEAD, sorted."""
    merge_base = git("merge-base", base, "HEAD")
    names = git(
        "-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", "--diff-filter=d", merge_base, "HEAD", "--", "test"
    )
    return sorted(name for name in names.splitlines() if name.endswith("_test.gleam"))


def setting(name: str, default: int) -> int:
    text = os.environ.get(name)
    if text is None:
        return default
    if not text.isdecimal() or int(text) < 1:
        raise Unusable("%s is %r, not a whole number of at least 1" % (name, text))
    return int(text)


def built_command(file: str, seed: int) -> list[str]:
    """The VM `./check`'s run_built starts for genesis_prime_test, with the arguments unitest reads."""
    command = ["erl"]
    for ebin in sorted(ROOT.glob("build/dev/erlang/*/ebin")):
        command += ["-pa", str(ebin)]
    command += ["-eval", "genesis_prime@@main:run(genesis_prime_test)", "-noshell", "-extra"]
    return command + [file, "--seed", str(seed), "--no-color"]


def execute(run: Run, logs: Path) -> Outcome:
    log = logs / ("run-%d.log" % run.number)
    environment = {**os.environ, **{variable: "1" for variable in SKIP_VARIABLES}}
    with open(log, "w") as output:
        done = subprocess.run(
            built_command(run.file, run.seed), cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
            stdout=output, stderr=subprocess.STDOUT,
        )
    return Outcome(run, done.returncode, log)


def report_failure(outcome: Outcome) -> None:
    text = outcome.log.read_text(errors="replace")
    run = outcome.run
    print()
    print("FAILED %s with seed %d (exit status %d)" % (run.file, run.seed, outcome.status))
    names = FAILING_TEST.findall(text[text.find(FAILURES_MARK):] if FAILURES_MARK in text else "")
    print("  failing tests: %s" % (", ".join(names) if names else "none named, see the output"))
    print("  repeat it: gleam test -- %s --seed %d" % (run.file, run.seed))
    print("  output: %s" % outcome.log)
    lines = text.splitlines()
    start = lines.index(FAILURES_MARK) if FAILURES_MARK in lines else max(len(lines) - 20, 0)
    for line in lines[start:start + EXCERPT_LINES]:
        print("    " + line)


def main(arguments: list[str]) -> int:
    if len(arguments) != 1:
        print("usage: python3.13 -I dev/repeat_tests.py BASE")
        return 2
    try:
        files = changed_test_files(arguments[0])
        runs_per_file = setting("GENESIS_REPEAT_RUNS", DEFAULT_RUNS)
        at_once = setting("GENESIS_REPEAT_AT_ONCE", os.process_cpu_count() or 1)
    except Unusable as problem:
        print(problem)
        return 2
    if not files:
        print("no added or changed test file since the merge base with %s, so nothing to repeat" % arguments[0])
        return 0
    total = runs_per_file * len(files)
    seeds = random.SystemRandom().sample(range(100_000_000, 1_000_000_000), total)
    runs = [
        Run(round_index * len(files) + position + 1, file, seeds[round_index * len(files) + position])
        for round_index in range(runs_per_file)
        for position, file in enumerate(files)
    ]
    print(
        "repeating %d test file(s) %d times each, %d VMs at once: %s"
        % (len(files), runs_per_file, at_once, ", ".join(files)),
        flush=True,
    )
    logs = Path(tempfile.mkdtemp(prefix="genesis-repeat-tests-"))
    with concurrent.futures.ThreadPoolExecutor(max_workers=at_once) as pool:
        outcomes = list(pool.map(lambda run: execute(run, logs), runs))
    failed = [outcome for outcome in outcomes if outcome.status != 0]
    for outcome in failed:
        report_failure(outcome)
    print()
    if failed:
        print("%d of %d runs failed; the output of every run is in %s" % (len(failed), total, logs))
        return 1
    print("all %d runs passed" % total)
    shutil.rmtree(logs)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
