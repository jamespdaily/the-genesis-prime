"""Runs the test files a branch adds or changes many times at once, so a test that depends on timing fails in the pull request that brings it.

    python3.13 -I dev/repeat_tests.py BASE
    python3.13 -I dev/repeat_tests.py --list BASE

BASE is the branch the pull request goes into (CI passes origin/<base branch>). The files are
the `test/**/*_test.gleam` files added or changed between `git merge-base BASE HEAD` and HEAD
(a deleted file, a support module and a file the branch leaves alone are not; a renamed file
is a file at its new path). `--list` prints them one per line and runs nothing. With none, a
run prints that and exits 0.

GENESIS_REPEAT_RUNS (default 40) is the number of VM starts in all; each file gets
max(2, GENESIS_REPEAT_RUNS // files) of them, so a pull request with many test files gets
fewer runs of each. Each run is a VM of its own on the code `gleam build` already built,
with its own random seed, GENESIS_REPEAT_AT_ONCE VMs at a time (default the number of
CPUs), so every run is under the load of the others. A VM takes the file as its one argument
because unitest runs one file per start. The skip variables are the ones ./check's test run
sets: the tests tagged serial (they share a machine-wide resource, so VMs side by side
would break them), world_data, client_rows and dev_tool are not run.

A time limit never fails the run, only a wrong result does. GENESIS_REPEAT_SECONDS (default
450) is the budget for all the runs together: once it has passed, runs not yet started do not
start, and one `check WARNING:` line says how many runs of each file were done of how many were
planned. The default is the 15-minute job less about 90 seconds of setup less the 300 seconds
a run already going at the budget may still take. A run still going after
GENESIS_REPEAT_RUN_SECONDS (default 300) is killed so the job ends, and is printed as a
`check WARNING:` line with its file, seed and the command that repeats it; it is not counted
as a failure. A file whose every test is skipped (or that has none) runs 0 tests; it is
reported as "not repeated", never as passed, and its later runs do not start.

Each failing run is printed as soon as it ends: its file, seed, why it failed (failing
tests, killed by a signal, a non-zero exit, no result line), the command that repeats it (`gleam test -- FILE --seed SEED`)
and the part of its output that says why. The output of every run is kept in the folder
the failure names. The script exits 1 only when a run's tests failed or the run crashed, 2 for a setting or a
git answer it cannot use, and 0 otherwise, warnings included. It starts `erl` from PATH, so run it with the patched OTP first on PATH,
as ./check does.
"""

import concurrent.futures
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DEFAULT_RUNS = 40
MINIMUM_RUNS_PER_FILE = 2
DEFAULT_RUN_SECONDS = 300
DEFAULT_BUDGET_SECONDS = 450
WARNING = "check WARNING:"

# The variables ./check's gleam_test sets for its first test run (test/genesis_prime_test.gleam
# reads them), less the literal peak file.
SKIP_VARIABLES = (
    "GENESIS_TEST_SKIP_SERIAL",
    "GENESIS_TEST_SKIP_WORLD_DATA",
    "GENESIS_TEST_SKIP_CLIENT_ROWS",
    "GENESIS_TEST_SKIP_DEV_TOOL",
)

# unitest's status line: "6 passed, no failures", "0 passed, no failures, 12 skipped",
# "5 passed, 1 failures".
PASSED_COUNT = re.compile(r"^(\d+) passed, ", re.MULTILINE)
FAILING_TEST = re.compile(r"^\s*\d+\) (\S+) \(", re.MULTILINE)
FAILURES_MARK = "Failures:"
EXCERPT_LINES = 60
TAIL_LINES = 20


@dataclass(frozen=True)
class Run:
    number: int
    file: str
    seed: int


@dataclass(frozen=True)
class Outcome:
    run: Run
    # passed, failed, no_tests (ran 0 tests), not_run (its file was found to run 0 tests),
    # timed_out (killed at the run limit) or not_started (the budget had passed).
    kind: str
    reason: str
    log: Path | None


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


def describe_status(status: int) -> str:
    if status < 0:
        return "killed by signal %d" % -status
    return "exit status %d" % status


def execute(run: Run, logs: Path, seconds: int, without_tests: set[str], deadline: float) -> Outcome:
    """Starts the run's VM and classifies how it ended; `without_tests` holds the files found to run 0 tests."""
    if run.file in without_tests:
        return Outcome(run, "not_run", "", None)
    if time.monotonic() >= deadline:
        return Outcome(run, "not_started", "", None)
    log = logs / ("run-%d.log" % run.number)
    environment = {**os.environ, **{variable: "1" for variable in SKIP_VARIABLES}}
    with open(log, "w") as output:
        try:
            done = subprocess.run(
                built_command(run.file, run.seed), cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                stdout=output, stderr=subprocess.STDOUT, timeout=seconds,
            )
        except subprocess.TimeoutExpired:
            return Outcome(run, "timed_out", "still going after %d seconds and was killed" % seconds, log)
    if done.returncode != 0:
        return Outcome(run, "failed", describe_status(done.returncode), log)
    counted = PASSED_COUNT.search(log.read_text(errors="replace"))
    if counted is None:
        return Outcome(run, "failed", "exit status 0 but no unitest result line", log)
    if int(counted.group(1)) == 0:
        without_tests.add(run.file)
        return Outcome(run, "no_tests", "", log)
    return Outcome(run, "passed", "", log)


def report_failure(outcome: Outcome) -> None:
    assert outcome.log is not None
    text = outcome.log.read_text(errors="replace")
    run = outcome.run
    print()
    print("FAILED %s with seed %d (%s)" % (run.file, run.seed, outcome.reason))
    names = FAILING_TEST.findall(text[text.find(FAILURES_MARK):] if FAILURES_MARK in text else "")
    print("  failing tests: %s" % (", ".join(names) if names else "none named, see the output"))
    print("  repeat it: gleam test -- %s --seed %d" % (run.file, run.seed))
    print("  output: %s" % outcome.log)
    lines = text.splitlines()
    start = lines.index(FAILURES_MARK) if FAILURES_MARK in lines else max(len(lines) - TAIL_LINES, 0)
    for line in lines[start:start + EXCERPT_LINES]:
        print("    " + line)
    sys.stdout.flush()


def report_timeout(outcome: Outcome) -> None:
    run = outcome.run
    print(
        "%s %s with seed %d was %s, so it counts as neither passed nor failed; repeat it: gleam test -- %s --seed %d"
        % (WARNING, run.file, run.seed, outcome.reason, run.file, run.seed),
        flush=True,
    )


def schedule(files: list[str], runs_per_file: int) -> list[Run]:
    """The runs, one round over the files after another, each with its own seed."""
    total = runs_per_file * len(files)
    seeds = random.SystemRandom().sample(range(100_000_000, 1_000_000_000), total)
    return [
        Run(round_index * len(files) + position + 1, file, seeds[round_index * len(files) + position])
        for round_index in range(runs_per_file)
        for position, file in enumerate(files)
    ]


def main(arguments: list[str]) -> int:
    list_only = arguments[:1] == ["--list"]
    if len(arguments) != (2 if list_only else 1):
        print("usage: python3.13 -I dev/repeat_tests.py [--list] BASE")
        return 2
    base = arguments[-1]
    try:
        files = changed_test_files(base)
        total = setting("GENESIS_REPEAT_RUNS", DEFAULT_RUNS)
        at_once = setting("GENESIS_REPEAT_AT_ONCE", os.process_cpu_count() or 1)
        seconds = setting("GENESIS_REPEAT_RUN_SECONDS", DEFAULT_RUN_SECONDS)
        budget = setting("GENESIS_REPEAT_SECONDS", DEFAULT_BUDGET_SECONDS)
    except Unusable as problem:
        print(problem)
        return 2
    if list_only:
        for file in files:
            print(file)
        return 0
    if not files:
        print("no added or changed test file since the merge base with %s, so nothing to repeat" % base)
        return 0
    if shutil.which("erl") is None:
        print("erl is not on PATH; put the patched OTP's bin first, as ./check does")
        return 2
    runs_per_file = max(MINIMUM_RUNS_PER_FILE, total // len(files))
    runs = schedule(files, runs_per_file)
    print(
        "repeating %d test file(s) %d times each, %d VMs at once, %d seconds at most per run and %d in all: %s"
        % (len(files), runs_per_file, at_once, seconds, budget, ", ".join(files)),
        flush=True,
    )
    logs = Path(tempfile.mkdtemp(prefix="genesis-repeat-tests-"))
    without_tests: set[str] = set()
    passed = failed = 0
    done: Counter[str] = Counter()
    unstarted = False
    deadline = time.monotonic() + budget
    with concurrent.futures.ThreadPoolExecutor(max_workers=at_once) as pool:
        pending = [pool.submit(execute, run, logs, seconds, without_tests, deadline) for run in runs]
        for future in concurrent.futures.as_completed(pending):
            outcome = future.result()
            if outcome.kind == "not_started":
                unstarted = True
            elif outcome.kind != "not_run":
                done[outcome.run.file] += 1
            if outcome.kind == "failed":
                failed += 1
                report_failure(outcome)
            elif outcome.kind == "timed_out":
                report_timeout(outcome)
            elif outcome.kind == "passed":
                passed += 1
    print()
    if unstarted:
        print(
            "%s the %d second budget passed, so runs were not started; done of planned: %s"
            % (WARNING, budget, ", ".join("%s %d of %d" % (file, done[file], runs_per_file) for file in files))
        )
    for file in sorted(without_tests):
        print("not repeated: %s (every test in it is skipped or it has none)" % file)
    if failed:
        print("%d of %d runs failed; the output of every run is in %s" % (failed, passed + failed, logs))
        return 1
    shutil.rmtree(logs)
    if passed == 0:
        print("no run ran a test, so nothing was repeated")
        return 0
    print("all %d runs passed" % passed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
