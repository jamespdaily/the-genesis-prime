"""./check: what the script does with the parts it runs, tested on a planted repository.

Each test copies ./check and setup_check/environment.sh into a temporary
repository and runs that copy with a PATH of planted tools, so no test touches
the real toolchain, the real database or the real client:

- ./setup-check is a stub that succeeds (after PLANT_SETUP_SECONDS, when set);
- `gleam` and `psql` are stubs that write their command line to PLANT_LOG and
  succeed (the `psql` that drops the database takes PLANT_PSQL_DROP_SECONDS
  first, when set; `gleam format` takes PLANT_FORMAT_SECONDS, or ends its own
  shell without a word when PLANT_FORMAT_KILLS_PARENT is set), except that `gleam format --check` fails when a file under src,
  test or dev holds PLANTED_FORMAT_ERROR, and any `gleam` run of tests (a `test`
  or a `run -m` of a module other than glinter, squirrel, table_generator and
  generate_messages) fails when a file under test/code_rule holds PLANTED_BREACH;
- `python3.13` is the real one, except for the two runs the stubs stand in for:
  check_facts.py and the setup check's own tests (`-s setup_check`), which
  succeed at once, take PLANT_SETUP_SUITE_SECONDS first when it is set, and
  end their own shell without a word when PLANT_SETUP_SUITE_NEVER_WRITES is set;
- the client query process's scripts are the real check_support.py and
  formulas_by_hand.py with one planted test file whose test is gated by
  check_support.integration_only, so the gate is the real one.

- the planted repository is a git repository on a branch `feature` of `main`
  (the planted files are the first commit), because the integration tests run
  only when the branch changes a file under the client scripts folder, as
  issue 109's item 3 (changed 2026-10-27, Jim's yes) says.

A planted run costs about two seconds, so tests that only read what one run
printed or logged share it (`shared_run`), the whole file stays under a minute,
and tests of what does not depend on the parts' work run `./check fast`, which
has four parts instead of twelve.

Expected values and their sources: issue 109's test list, items 1, 2, 3, 6, 7
and 8. The wall-time budget default is CLAUDE.md's "the full check passes in
under 2 minutes". The part names are the ones ./check prints.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
CHECK = REPOSITORY / "check"
SCRIPTS = Path(".claude") / "skills" / "decoding-the-client" / "scripts"
PYTHON = shutil.which("python3.13")

RUNNABLE = PYTHON is not None and shutil.which("bash") is not None and CHECK.is_file()

# The commands `gleam run -m MODULE` the check makes that are not a run of tests.
NOT_TEST_RUNS = ("glinter", "squirrel", "genesis_prime/table_generator", "genesis_prime/generate_messages")

GLEAM_STUB = """#!/bin/sh
echo "gleam $*" >>"$PLANT_LOG"
echo "gleam $* GENESIS_TEST_SKIP_SERIAL=$GENESIS_TEST_SKIP_SERIAL" >>"$PLANT_LOG.environment"
case "$1" in
  format)
    [ -n "$PLANT_FORMAT_SECONDS" ] && sleep "$PLANT_FORMAT_SECONDS"
    [ -n "$PLANT_FORMAT_KILLS_PARENT" ] && kill -9 "$PPID"
    if grep -rq PLANTED_FORMAT_ERROR src test dev 2>/dev/null; then
      echo "planted format error"
      exit 1
    fi
    exit 0
    ;;
  build) exit 0 ;;
  run)
    case "$3" in
      %(not_tests)s) exit 0 ;;
    esac
    ;;
esac
if [ "$1" = test ]; then
  case "$*" in
    *"--tag serial"*) echo "Seed: 222" ;;
    *) echo "Seed: 111" ;;
  esac
fi
if [ "$1" = test ] && [ -n "$PLANT_GLEAM_TEST_SECONDS" ]; then
  sleep "$PLANT_GLEAM_TEST_SECONDS"
fi
if grep -rq PLANTED_BREACH test/code_rule 2>/dev/null; then
  echo "planted code-rule breach"
  exit 1
fi
exit 0
""" % {"not_tests": "|".join(NOT_TEST_RUNS)}

PSQL_STUB = """#!/bin/sh
echo "psql $*" >>"$PLANT_LOG"
case "$*" in
  *"drop database"*)
    [ -n "$PLANT_PSQL_DROP_SECONDS" ] && sleep "$PLANT_PSQL_DROP_SECONDS"
    ;;
esac
exit 0
"""

PYTHON_STUB = """#!/bin/sh
echo "python3.13 $*" >>"$PLANT_LOG"
case "$*" in
  *check_facts.py*) exit 0 ;;
  *"-s setup_check"*)
    [ -n "$PLANT_SETUP_SUITE_SECONDS" ] && sleep "$PLANT_SETUP_SUITE_SECONDS"
    [ -n "$PLANT_SETUP_SUITE_NEVER_WRITES" ] && kill -9 "$PPID"
    exit 0
    ;;
esac
exec "$PLANT_REAL_PYTHON" "$@"
"""

SETUP_CHECK_STUB = """#!/bin/sh
[ -n "$PLANT_SETUP_SECONDS" ] && sleep "$PLANT_SETUP_SECONDS"
echo "setup check passed"
exit 0
"""

INTEGRATION_TEST = '''import os
import unittest
from pathlib import Path

import check_support


class PlantedIntegrationTest(unittest.TestCase):
    @check_support.integration_only
    def test_it_ran_and_it_%(outcome)s(self):
        Path(os.environ["PLANT_MARKER"]).write_text("ran")
        %(body)s
'''


def executable(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class PlantedCheckCase(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="genesis-check-script-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.repository = self.root / "repository"
        self.log = self.root / "commands.log"
        self.marker = self.root / "integration-ran"
        self.log.write_text("")
        self.settled = False
        self.plant_repository()

    def plant_repository(self) -> None:
        repository = self.repository
        repository.mkdir()
        shutil.copyfile(CHECK, repository / "check")
        (repository / "check").chmod(0o755)
        (repository / "setup_check").mkdir()
        shutil.copyfile(HERE / "environment.sh", repository / "setup_check" / "environment.sh")
        shutil.copyfile(REPOSITORY / ".tool-versions", repository / ".tool-versions")
        executable(repository / "setup-check", SETUP_CHECK_STUB)
        (repository / "priv" / "migrations").mkdir(parents=True)
        for folder in ("src", "dev", "test/code_rule"):
            (repository / folder).mkdir(parents=True)
        (repository / "test" / "code_rule" / "planted_test.gleam").write_text("// a code-rule test\n")
        scripts = repository / SCRIPTS
        scripts.mkdir(parents=True)
        for name in ("check_support.py", "formulas_by_hand.py"):
            shutil.copyfile(REPOSITORY / SCRIPTS / name, scripts / name)
        self.plant_integration_test(fails=False)
        tools = self.root / "tools"
        executable(tools / "gleam", GLEAM_STUB)
        executable(tools / "psql", PSQL_STUB)
        executable(tools / "python3.13", PYTHON_STUB)

    def git(self, *arguments: str) -> str:
        done = subprocess.run(
            ["git", "-c", "user.name=Planted", "-c", "user.email=planted@example.invalid", *arguments],
            cwd=self.repository, capture_output=True, text=True, check=True,
        )
        return done.stdout.strip()

    def settle(self) -> None:
        """Commits what is planted as `main`, and moves to a branch `feature` of it.
        Done once, before the first run, so a test may plant first."""
        if self.settled:
            return
        self.settled = True
        (self.repository / ".gitignore").write_text("__pycache__/\n")
        self.git("init", "-q", "-b", "main")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "planted repository")
        self.git("checkout", "-q", "-b", "feature")

    def commit_change(self, path: str) -> None:
        """A commit on the branch that changes the file at path (from the repository's folder)."""
        self.settle()
        with open(self.repository / path, "a") as changed:
            changed.write("\n# changed on the branch\n")
        self.git("commit", "-q", "-am", "change %s" % path)

    def plant_integration_test(self, fails: bool) -> None:
        test = INTEGRATION_TEST % {
            "outcome": "fails" if fails else "passes",
            "body": 'self.fail("planted integration failure")' if fails else "pass",
        }
        (self.repository / SCRIPTS / "test_planted_integration.py").write_text(test)

    def run_check(
        self, *arguments: str, client: bool = False, timeout: float = 120, **settings: str
    ) -> subprocess.CompletedProcess:
        """Runs the planted repository's ./check in a session of its own. `client`
        leaves GENESIS_NO_CLIENT unset, as on a machine with the client; `settings`
        are more variables. A check that has not ended after `timeout` seconds
        fails the test, and its whole session is killed."""
        self.settle()
        home = self.root / "home"
        home.mkdir(exist_ok=True)
        env = {
            "PATH": "%s:/usr/bin:/bin:/usr/sbin:/sbin" % (self.root / "tools"),
            "HOME": str(home),
            "GENESIS_HOME": str(home / ".genesis-prime"),
            "PLANT_LOG": str(self.log),
            "PLANT_MARKER": str(self.marker),
            "PLANT_REAL_PYTHON": PYTHON,
        }
        if not client:
            env["GENESIS_NO_CLIENT"] = "1"
        env.update(settings)
        process = subprocess.Popen(
            [str(self.repository / "check"), *arguments],
            cwd=self.repository,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            self.fail("the check had not ended after %s seconds" % timeout)
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def environment_log(self) -> str:
        """The gleam commands with the value of GENESIS_TEST_SKIP_SERIAL each saw."""
        path = Path(str(self.log) + ".environment")
        return path.read_text() if path.exists() else ""

    def commands(self) -> list[str]:
        return [line for line in self.log.read_text().splitlines() if line.strip()]

    @staticmethod
    def output(done: subprocess.CompletedProcess) -> str:
        return done.stdout + done.stderr

    def failed_line(self, output: str) -> str:
        """The line `check FAILED: a, b` that names the failed parts."""
        lines = [line for line in output.splitlines() if line.startswith("check FAILED")]
        self.assertEqual(len(lines), 1, "one summary line names the failed parts:\n" + output)
        return lines[0]


@dataclass
class Run:
    """What one planted run of ./check left: its result, the commands the stubs saw,
    how long it took, whether the planted integration test ran, and what of the
    planted hang was still running when it ended."""

    done: subprocess.CompletedProcess
    commands: list[str]
    environment: str
    took: float
    marker_ran: bool
    hang: str
    left_running: list[str]

    @property
    def output(self) -> str:
        return self.done.stdout + self.done.stderr


_runs: dict[str, Run] = {}


def hang_pattern(seconds: str) -> str:
    return "sleep %s" % seconds.replace(".", "\\.")


def shared_run(key: str, *arguments: str, client: bool = False, prepare=None, hang=None, timeout: float = 120, **settings: str) -> Run:
    """Runs a planted check once for the whole file, whichever test asks first.
    `prepare(case)` plants before the run; `hang(seconds)` gives settings that make
    something sleep for 600 seconds and a fraction that is unique to the run, so
    `pgrep -f` finds exactly the processes the run planted."""
    if key in _runs:
        return _runs[key]
    case = PlantedCheckCase("setUp")
    case.setUp()
    seconds = ""
    try:
        if prepare:
            prepare(case)
        if hang:
            seconds = "600.%d" % (time.time_ns() % 1_000_000_000)
            settings = {**settings, **hang(seconds)}
        started = time.monotonic()
        done = case.run_check(*arguments, client=client, timeout=timeout, **settings)
        took = time.monotonic() - started
        left = subprocess.run(["pgrep", "-f", hang_pattern(seconds)], capture_output=True, text=True).stdout.split() if seconds else []
        run = Run(done, case.commands(), case.environment_log(), took, case.marker.exists(), seconds, left)
    finally:
        if seconds:
            subprocess.run(["pkill", "-f", hang_pattern(seconds)])
        case.doCleanups()
    _runs[key] = run
    return run


def failed_line(testcase: unittest.TestCase, output: str) -> str:
    """The line `check FAILED: a, b` that names the failed parts."""
    lines = [line for line in output.splitlines() if line.startswith("check FAILED")]
    testcase.assertEqual(len(lines), 1, "one summary line names the failed parts:\n" + output)
    return lines[0]


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ControlTest(unittest.TestCase):
    """The planted repository passes when nothing is planted, so a failure in the
    tests below is the thing planted."""

    def test_the_full_check_of_a_planted_repository_with_nothing_wrong_passes(self):
        run = shared_run("full")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("check passed", run.done.stdout)

    def test_the_fast_check_of_a_planted_repository_with_nothing_wrong_passes(self):
        run = shared_run("fast", "fast")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("check passed", run.done.stdout)

    def test_an_argument_other_than_fast_is_refused_with_the_usage_and_runs_nothing(self):
        run = shared_run("usage", "everything")
        self.assertNotEqual(run.done.returncode, 0)
        self.assertIn("usage", run.output.lower())
        self.assertEqual(run.commands, [])


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class PartThatNeverRanTest(unittest.TestCase):
    """Issue 109, item 1: a part that ends without writing its status fails the check.
    The planted format part's own shell ends before the check can write its status;
    every other part writes its own."""

    def run_it(self) -> Run:
        return shared_run("never-wrote", "fast", PLANT_FORMAT_KILLS_PARENT="1")

    def test_a_part_that_ends_without_writing_its_status_is_reported_as_failed_by_name(self):
        run = self.run_it()
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertNotRegex(run.output, r"(?m)^check passed")
        self.assertRegex(failed_line(self, run.output), r"\bformat\b")
        part_line = next(line for line in run.output.splitlines() if line.strip().startswith("format"))
        self.assertIn("FAILED", part_line, "the part's own line says it failed: " + part_line)

    def test_the_parts_that_did_write_their_status_are_not_named_failed(self):
        failed = failed_line(self, self.run_it().output)
        for part in ("gleam-build", "glinter", "code-rules"):
            with self.subTest(part=part):
                self.assertNotRegex(failed, r"\b%s\b" % re.escape(part))


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class BudgetTest(unittest.TestCase):
    """Issue 109, item 2: the budget is a check, counted from the start of the script.

    The tests run `./check fast`, whose budget is GENESIS_CHECK_FAST_BUDGET_SECONDS
    (the full check's is GENESIS_CHECK_BUDGET_SECONDS; the logic is the same code),
    set to 1 second with 3 seconds of delay planted, so the time stays small; the
    real budget is 2 minutes (CLAUDE.md: "the full check passes in under 2 minutes")."""

    def assert_over_budget(self, run: Run, budget: int) -> None:
        output = run.output
        self.assertNotEqual(run.done.returncode, 0, output)
        self.assertNotRegex(output, r"(?m)^check passed")
        self.assertIn("check FAILED", output)
        budget_lines = [line for line in output.splitlines() if "budget" in line.lower()]
        self.assertTrue(budget_lines, "a line names the budget:\n" + output)
        self.assertTrue(
            any(re.search(r"\b%d\s*(s\b|sec)" % budget, line) for line in budget_lines),
            "the budget (%ds) is printed: %r" % (budget, budget_lines),
        )
        times = re.findall(r"wall time (\d+)s", output)
        self.assertTrue(times, "the wall time is printed:\n" + output)
        self.assertGreaterEqual(int(times[-1]), budget, "the printed time reaches the budget")

    def test_a_slow_part_takes_the_check_past_its_budget(self):
        run = shared_run("slow-part", "fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="1", PLANT_FORMAT_SECONDS="3")
        self.assert_over_budget(run, budget=1)

    def test_the_time_of_the_setup_check_counts_towards_the_budget(self):
        # Every part is instant; only ./setup-check is slow.
        run = shared_run("slow-setup", "fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="1", PLANT_SETUP_SECONDS="3")
        self.assert_over_budget(run, budget=1)

    def test_a_check_inside_its_budget_passes(self):
        run = shared_run("in-budget", "fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="30", PLANT_FORMAT_SECONDS="1")
        self.assertEqual(run.done.returncode, 0, run.output)

    def test_the_budget_without_the_setting_is_120_seconds(self):
        source = CHECK.read_text()
        defaults = re.findall(r"GENESIS_CHECK_BUDGET_SECONDS:-(\d+)", source)
        self.assertEqual(defaults, ["120"], "CLAUDE.md: the full check passes in under 2 minutes")

    def test_the_fast_checks_budget_without_the_setting_is_13_seconds_from_its_cold_build_time(self):
        # 10, 9 and 9 s in 3 runs on 2026-10-27 (issue 109), each after removing
        # build/dev/erlang/genesis_prime: 10 x 1.25, rounded up.
        source = CHECK.read_text()
        self.assertEqual(re.findall(r"GENESIS_CHECK_FAST_BUDGET_SECONDS:-(\d+)", source), ["13"])


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class HungPartTest(unittest.TestCase):
    """The budget is a deadline, not only a comparison at the end: a part that hangs,
    or a setup check that does, is stopped when the budget is reached, with everything
    it started, and the check fails naming it, in budget plus a few seconds.

    A hang is a planted `sleep` of 600 seconds and a fraction unique to the run. The
    budget is 2 seconds."""

    BUDGET = 2
    FEW_SECONDS = 8

    def assert_stopped_at_the_budget(self, run: Run, part: str | None, budget: int = BUDGET) -> None:
        output = run.output
        self.assertNotEqual(run.done.returncode, 0, output)
        self.assertLess(run.took, budget + self.FEW_SECONDS, "the check ran %.1f s past a budget of %d s" % (run.took, budget))
        self.assertRegex(failed_line(self, output), r"over the budget of %ds" % budget)
        if part:
            self.assertRegex(failed_line(self, output), r"\b%s\b" % re.escape(part), "the unfinished part is named")
            part_line = next(line for line in output.splitlines() if line.strip().startswith(part))
            self.assertIn("FAILED", part_line)
        self.assertRegex(output, r"wall time \d+s")
        self.assertEqual(run.left_running, [], "the planted sleep is still running")

    def part_and_drop(self) -> Run:
        # Postgres stops answering as well: the psql that drops the database at the
        # end would wait for ever.
        return shared_run(
            "hung-part-and-drop",
            hang=lambda seconds: dict(PLANT_SETUP_SUITE_SECONDS=seconds, PLANT_PSQL_DROP_SECONDS=seconds),
            timeout=30,
            GENESIS_CHECK_BUDGET_SECONDS=str(self.BUDGET),
        )

    def test_a_part_that_hangs_is_stopped_at_the_budget_and_named(self):
        self.assert_stopped_at_the_budget(self.part_and_drop(), "setup-suite")

    def test_the_database_is_dropped_when_the_budget_stops_the_check(self):
        self.assertTrue(any("drop database" in command for command in self.part_and_drop().commands))

    def test_a_database_drop_that_hangs_does_not_hold_the_check_past_its_budget(self):
        # The same run: the planted psql sleeps 600 s on the drop, and the check still
        # ended within the budget and a few seconds, with the sleep ended.
        run = self.part_and_drop()
        self.assertLess(run.took, self.BUDGET + self.FEW_SECONDS)
        self.assertEqual(run.left_running, [])

    def test_a_gleam_run_that_hangs_is_stopped_with_what_it_started(self):
        # The sleep is a grandchild of the check: its subshell runs `gleam`, which runs it.
        run = shared_run(
            "hung-gleam", "fast", hang=lambda seconds: dict(PLANT_GLEAM_TEST_SECONDS=seconds), timeout=30,
            GENESIS_CHECK_FAST_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_at_the_budget(run, "code-rules")

    def test_a_setup_check_that_hangs_is_stopped_at_the_budget(self):
        run = shared_run(
            "hung-setup", "fast", hang=lambda seconds: dict(PLANT_SETUP_SECONDS=seconds), timeout=30,
            GENESIS_CHECK_FAST_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_at_the_budget(run, None)
        self.assertEqual(run.commands, [], "no part ran after a setup check that did not end")

    def test_the_deadline_is_the_raised_budget_when_the_integration_tests_run(self):
        # The usual budget is 1 s, the raised one 6 s: a hung setup check is stopped at 6.
        run = shared_run(
            "hung-raised", client=True, prepare=lambda case: case.commit_change(SCRIPTS_FILE),
            hang=lambda seconds: dict(PLANT_SETUP_SECONDS=seconds), timeout=30,
            GENESIS_CHECK_BUDGET_SECONDS="1", GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="6",
        )
        self.assert_stopped_at_the_budget(run, None, budget=6)
        self.assertGreaterEqual(run.took, 5, "the check was stopped at the usual budget, not the raised one")

    def test_a_database_drop_that_hangs_does_not_hold_a_check_that_ended_in_time(self):
        run = shared_run(
            "hung-drop-in-time", hang=lambda seconds: dict(PLANT_PSQL_DROP_SECONDS=seconds), timeout=30,
        )
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertLess(run.took, self.FEW_SECONDS + 4, "the check waited %.1f s for the drop" % run.took)
        self.assertEqual(run.left_running, [], "the planted sleep is still running")


SCRIPTS_FILE = str(SCRIPTS / "formulas_by_hand.py")


def plant_failing_gated_test(case: PlantedCheckCase) -> None:
    case.plant_integration_test(fails=True)


def change_the_scripts(case: PlantedCheckCase) -> None:
    case.commit_change(SCRIPTS_FILE)


def change_something_else(case: PlantedCheckCase) -> None:
    case.settle()
    (case.repository / "src" / "planted.gleam").write_text("// a file outside the scripts folder\n")
    case.git("add", "-A")
    case.git("commit", "-q", "-m", "a change outside the scripts folder")


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ClientIntegrationTest(unittest.TestCase):
    """Issue 109, item 3 (changed 2026-10-27): the query process's integration
    tests run in the full check when the branch changes a file under the client
    scripts folder, compared with its merge base with main (origin/main when
    there is one); otherwise they are skipped and the output says so. Where they
    run, the budget is raised and the output says why."""

    @staticmethod
    def part_line(output: str) -> str:
        return next((line for line in output.splitlines() if "client-integration" in line), "")

    def changed(self) -> Run:
        # The planted gated test fails; the usual budget (1 s) is raised to 30 s, which
        # holds the 3 s the planted setup suite takes.
        return shared_run(
            "integration-changed", client=True,
            prepare=lambda case: (plant_failing_gated_test(case), change_the_scripts(case)),
            GENESIS_CHECK_BUDGET_SECONDS="1", GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="30",
            PLANT_SETUP_SUITE_SECONDS="3",
        )

    def test_where_the_branch_changes_a_file_of_the_scripts_folder_a_gated_test_runs(self):
        run = self.changed()
        self.assertTrue(run.marker_ran, "the planted integration test did not run:\n" + run.output)

    def test_a_planted_failing_integration_test_fails_the_check_by_part_name(self):
        run = self.changed()
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"client-integration")
        self.assertNotIn("over the budget", failed_line(self, run.output))
        self.assertIn("planted integration failure", run.output, "the failed part's log is printed")

    def test_where_they_run_the_budget_is_raised_and_the_output_says_why(self):
        raised = [line for line in self.changed().output.splitlines() if "budget" in line.lower() and "raised" in line.lower()]
        self.assertTrue(raised, "a line says the budget was raised:\n" + self.changed().output)
        self.assertRegex(raised[0], r"\b30\s*s", "it names the raised budget")
        self.assertIn("integration", raised[0].lower(), "and the reason")

    def test_a_change_made_but_not_yet_committed_counts_as_a_change(self):
        def edit(case):
            case.settle()
            with open(case.repository / SCRIPTS_FILE, "a") as changed:
                changed.write("\n# edited, not committed\n")

        run = shared_run("integration-uncommitted", client=True, prepare=edit)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertTrue(run.marker_ran, "an edit under the scripts folder did not start the gated tests")

    def unchanged(self) -> Run:
        # A change outside the scripts folder, a failing gated test, and an exported
        # GENESIS_INTEGRATION=1, which would open the gate of the unit suite.
        return shared_run(
            "integration-unchanged", client=True,
            prepare=lambda case: (plant_failing_gated_test(case), change_something_else(case)),
            GENESIS_INTEGRATION="1",
        )

    def test_where_the_branch_changes_nothing_there_the_gated_tests_are_skipped_and_the_output_says_so(self):
        run = self.unchanged()
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertFalse(run.marker_ran, "an integration test ran with no change under the scripts folder")
        line = self.part_line(run.output)
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + run.output)
        self.assertIn("unchanged", line, "and why:\n" + run.output)

    def test_where_they_are_skipped_the_budget_is_not_raised(self):
        self.assertFalse([l for l in self.unchanged().output.splitlines() if "raised" in l.lower()])

    def test_an_exported_genesis_integration_does_not_open_the_gate_of_the_unit_suite(self):
        # GENESIS_INTEGRATION=1 in the caller's environment would run the 450 s tests
        # inside the client-suite part, in the usual budget: with the client present
        # (the unchanged run above) and without it.
        run = shared_run(
            "integration-no-client", prepare=lambda case: (plant_failing_gated_test(case), change_the_scripts(case)),
            GENESIS_INTEGRATION="1",
        )
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertFalse(run.marker_ran, "an integration test ran with GENESIS_NO_CLIENT=1")

    def test_where_there_is_no_client_the_gated_tests_are_skipped_and_the_output_says_so(self):
        run = shared_run(
            "integration-no-client", prepare=lambda case: (plant_failing_gated_test(case), change_the_scripts(case)),
            GENESIS_INTEGRATION="1",
        )
        line = self.part_line(run.output)
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + run.output)
        self.assertIn("GENESIS_NO_CLIENT", line, "and why:\n" + run.output)

    def test_the_merge_base_is_with_origin_main_when_there_is_one(self):
        # origin/main is at the first commit, while the local main has moved on with
        # the change: against origin/main the branch changes the scripts folder.
        def plant(case):
            case.settle()
            case.git("checkout", "-q", "main")
            case.commit_change(SCRIPTS_FILE)
            case.git("update-ref", "refs/remotes/origin/main", case.git("rev-parse", "main~1"))
            case.git("checkout", "-q", "feature")
            case.git("reset", "-q", "--hard", "main")

        run = shared_run("integration-origin", client=True, prepare=plant)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertTrue(run.marker_ran, "the merge base was taken with main, not origin/main")

    def test_without_a_main_to_compare_with_they_run_and_the_output_says_the_base_was_not_found(self):
        def plant(case):
            case.settle()
            case.git("branch", "-q", "-m", "main", "trunk")

        run = shared_run("integration-no-main", client=True, prepare=plant)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertTrue(run.marker_ran, "with no merge base, the safe course is to run them")
        self.assertIn("main", self.part_line(run.output) + run.output)

    def test_the_fast_check_does_not_run_the_integration_tests(self):
        run = shared_run("fast-changed", "fast", client=True, prepare=change_the_scripts)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertFalse(run.marker_ran)

    def test_the_raised_budget_without_the_setting_is_583_seconds_from_the_worst_measured_run(self):
        # 466 s (the slowest of 3 runs on 2026-10-26, issue 109) x 1.25, rounded up.
        source = CHECK.read_text()
        self.assertEqual(re.findall(r"GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS:-(\d+)", source), ["583"])


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class FastModeTest(unittest.TestCase):
    """Issue 109, item 6: `./check fast` is the format check, the build with
    warnings as errors, glinter and the code-rule tests, and nothing else.

    The planted `gleam` stands for the tools: it fails the format check on a
    planted format error and any run of tests on a planted breach of a code
    rule. What these tests hold is that the fast check runs each of those four
    and fails, naming the part, when one fails."""

    def test_a_planted_format_error_fails_the_fast_check_naming_the_format_part(self):
        run = shared_run("fast-format-error", "fast", prepare=lambda case: (case.repository / "src" / "planted.gleam").write_text("// PLANTED_FORMAT_ERROR\n"))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bformat\b")

    def test_a_planted_code_rule_breach_fails_the_fast_check_naming_the_code_rules_part(self):
        run = shared_run("fast-breach", "fast", prepare=lambda case: (case.repository / "test" / "code_rule" / "planted_test.gleam").write_text("// PLANTED_BREACH\n"))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bcode-rules\b")

    def test_the_fast_check_runs_the_four_parts_and_no_other(self):
        run = shared_run("fast", "fast")
        self.assertEqual(run.done.returncode, 0, run.output)
        listed = re.findall(r"^\s*([a-z-]+)\s+(?:ok|FAILED)\b", run.output, re.MULTILINE)
        self.assertEqual(sorted(listed), ["code-rules", "format", "gleam-build", "glinter"])
        commands = run.commands
        self.assertTrue(any(c.startswith("gleam format --check") for c in commands), commands)
        self.assertIn("gleam build --warnings-as-errors", commands)
        self.assertIn("gleam run -m glinter", commands)
        self.assertFalse([c for c in commands if c.startswith(("psql", "python3.13"))], commands)
        for module in NOT_TEST_RUNS:
            if module != "glinter":
                self.assertFalse([c for c in commands if module in c], commands)

    def test_the_fast_check_never_runs_the_whole_test_suite(self):
        suites = [c for c in shared_run("fast", "fast").commands if re.fullmatch(r"gleam test( -- --workers \d+)?", c)]
        self.assertEqual(suites, [], "the fast check runs the code-rule tests only")

    def test_a_failing_build_fails_the_fast_check_naming_it(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))

        run = shared_run("fast-build-fails", "fast", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"gleam-build")


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class SeedTest(unittest.TestCase):
    """The seeds of the test runs are printed whether the check passes or fails, so
    a failure can be run again with the same order (`gleam test -- --seed N`)."""

    def test_the_seeds_of_both_test_runs_are_printed_when_the_check_passes(self):
        run = shared_run("full")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.done.stdout, r"(?m)^  gleam-test seeds: 111 222$")


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class SerialTestsTest(unittest.TestCase):
    """Tests that share a machine-wide resource (a child node's epmd and ports)
    are tagged `serial`: the test run skips them while it runs the others
    together (GENESIS_TEST_SKIP_SERIAL=1), and a second run, with no workers,
    runs only them one at a time (`gleam test -- --tag serial`)."""

    def test_the_full_check_runs_the_serial_tests_in_a_second_run_one_at_a_time(self):
        suites = [c for c in shared_run("full").commands if c.startswith("gleam test")]
        self.assertEqual(suites, ["gleam test -- --workers %s" % TEST_WORKERS, "gleam test -- --tag serial"])

    def test_the_run_of_the_other_tests_skips_the_serial_ones(self):
        runs = [line for line in shared_run("full").environment.splitlines() if line.startswith("gleam test")]
        self.assertEqual(runs[0], "gleam test -- --workers %s GENESIS_TEST_SKIP_SERIAL=1" % TEST_WORKERS)
        self.assertEqual(runs[1], "gleam test -- --tag serial GENESIS_TEST_SKIP_SERIAL=")

    def test_a_failure_in_the_serial_run_fails_the_gleam_test_part(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'if [ "$*" = "test -- --tag serial" ]; then exit 1; fi\nif [ "$1" = test ] &&'))

        run = shared_run("serial-fails", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")

    def test_the_fast_check_runs_no_serial_run(self):
        self.assertFalse([c for c in shared_run("fast", "fast").commands if "--tag serial" in c])


def default_workers() -> str:
    """The worker count the check gives `gleam test` when the setting is not set."""
    found = re.findall(r"test_workers=\$\{GENESIS_TEST_WORKERS:-(\d+)\}", CHECK.read_text())
    assert len(found) == 1, found
    return found[0]


TEST_WORKERS = default_workers() if RUNNABLE else "1"


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class WorkerCountTest(unittest.TestCase):
    """Issue 109, items 7 and 8: the worker count is one setting of the check,
    and the setting names the measurement it comes from."""

    def test_the_setting_is_given_to_the_test_run_as_the_worker_count(self):
        run = shared_run("workers-3", GENESIS_TEST_WORKERS="3")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("gleam test -- --workers 3", run.commands)

    def test_the_default_worker_count_has_the_measurement_that_chose_it_beside_it(self):
        lines = CHECK.read_text().splitlines()
        at = next(i for i, line in enumerate(lines) if "GENESIS_TEST_WORKERS:-" in line)
        self.assertRegex(lines[at], r"GENESIS_TEST_WORKERS:-\d+\}", "a number, not unset")
        beside = " ".join(lines[max(0, at - 6) : at + 4]).lower()
        self.assertIn("measured", beside, "the smallest count that leaves 25% of the budget spare, and the measurement")


if __name__ == "__main__":
    unittest.main()
