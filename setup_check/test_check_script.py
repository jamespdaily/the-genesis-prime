"""./check: what the script does with the parts it runs, tested on a planted repository.

Each test copies ./check and setup_check/environment.sh into a temporary
repository and runs that copy with a PATH of planted tools, so no test touches
the real toolchain, the real database or the real client:

- ./setup-check is a stub that succeeds (after PLANT_SETUP_SECONDS, when set);
- `gleam` and `psql` are stubs that write their command line to PLANT_LOG and
  succeed, except that `gleam format --check` fails when a file under src,
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
import tempfile
import time
import unittest
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
case "$1" in
  format)
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


class PlantedCheckControlTest(PlantedCheckCase):
    """The planted repository passes when nothing is planted, so a failure in
    the tests below is the thing planted."""

    def test_the_full_check_of_a_planted_repository_with_nothing_wrong_passes(self):
        done = self.run_check()
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertIn("check passed", done.stdout)

    def test_the_fast_check_of_a_planted_repository_with_nothing_wrong_passes(self):
        done = self.run_check("fast")
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertIn("check passed", done.stdout)

    def test_an_argument_other_than_fast_is_refused_with_the_usage_and_runs_nothing(self):
        done = self.run_check("everything")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("usage", self.output(done).lower())
        self.assertEqual(self.commands(), [])


class PartThatNeverRanTest(PlantedCheckCase):
    """Issue 109, item 1: a part that ends without writing its status fails the check."""

    def test_a_part_that_ends_without_writing_its_status_is_reported_as_failed_by_name(self):
        # The planted setup-suite part's own shell ends before the check can write
        # its status; every other part writes its own.
        done = self.run_check(PLANT_SETUP_SUITE_NEVER_WRITES="1")
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertNotRegex(output, r"(?m)^check passed")
        self.assertRegex(self.failed_line(output), r"setup-suite")
        part_line = next(line for line in output.splitlines() if line.strip().startswith("setup-suite"))
        self.assertIn("FAILED", part_line, "the part's own line says it failed: " + part_line)

    def test_the_parts_that_did_write_their_status_are_not_named_failed(self):
        done = self.run_check(PLANT_SETUP_SUITE_NEVER_WRITES="1")
        failed = self.failed_line(self.output(done))
        for part in ("format", "gleam-build", "glinter", "gleam-test", "migrations", "client-suite"):
            with self.subTest(part=part):
                self.assertNotRegex(failed, r"\b%s\b" % re.escape(part))


class BudgetTest(PlantedCheckCase):
    """Issue 109, item 2: the budget is a check, counted from the start of the script.

    The tests set GENESIS_CHECK_BUDGET_SECONDS to 1 second and plant 3 seconds
    of delay, so the time stays small; the real budget is 2 minutes (CLAUDE.md:
    "the full check passes in under 2 minutes")."""

    def assert_over_budget(self, done: subprocess.CompletedProcess, budget: int) -> None:
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
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
        done = self.run_check(GENESIS_CHECK_BUDGET_SECONDS="1", PLANT_SETUP_SUITE_SECONDS="3")
        self.assert_over_budget(done, budget=1)

    def test_the_time_of_the_setup_check_counts_towards_the_budget(self):
        # Every part is instant; only ./setup-check is slow.
        done = self.run_check(GENESIS_CHECK_BUDGET_SECONDS="1", PLANT_SETUP_SECONDS="3")
        self.assert_over_budget(done, budget=1)

    def test_a_check_inside_its_budget_passes(self):
        done = self.run_check(GENESIS_CHECK_BUDGET_SECONDS="30", PLANT_SETUP_SUITE_SECONDS="1")
        self.assertEqual(done.returncode, 0, self.output(done))

    def test_the_budget_without_the_setting_is_120_seconds(self):
        source = CHECK.read_text()
        defaults = re.findall(r"GENESIS_CHECK_BUDGET_SECONDS:-(\d+)", source)
        self.assertEqual(defaults, ["120"], "CLAUDE.md: the full check passes in under 2 minutes")


SCRIPTS_FILE = str(SCRIPTS / "formulas_by_hand.py")


class HungPartTest(PlantedCheckCase):
    """The budget is a deadline, not only a comparison at the end: a part that
    hangs, or a setup check that does, is stopped when the budget is reached, with
    everything it started, and the check fails naming it.

    A hang is a planted `sleep` of 600 seconds and a fraction that is unique to the
    test, so `pgrep -f` finds exactly the processes this test planted. The budget
    is 3 seconds; the check must end within a few seconds of it."""

    BUDGET = 3
    FEW_SECONDS = 8

    def hang(self) -> str:
        """600 seconds and a fraction no other test uses; whatever of it is still
        running at the end of the test is killed."""
        seconds = "600.%d" % (time.time_ns() % 1_000_000_000)
        self.addCleanup(subprocess.run, ["pkill", "-f", "sleep %s" % seconds.replace(".", "\\.")])
        return seconds

    def left_running(self, seconds: str) -> list[str]:
        done = subprocess.run(["pgrep", "-f", "sleep %s" % seconds.replace(".", "\\.")], capture_output=True, text=True)
        return done.stdout.split()

    def run_hung(self, seconds: str, budget: int = BUDGET, **settings: str) -> tuple[subprocess.CompletedProcess, float]:
        started = time.monotonic()
        done = self.run_check(timeout=30, GENESIS_CHECK_BUDGET_SECONDS=str(budget), **settings)
        return done, time.monotonic() - started

    def assert_stopped_at_the_budget(self, done, took: float, seconds: str, part: str | None, budget: int = BUDGET) -> None:
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertLess(took, budget + self.FEW_SECONDS, "the check ran %.1f s past a budget of %d s" % (took, budget))
        self.assertRegex(self.failed_line(output), r"over the budget of %ds" % budget)
        if part:
            self.assertRegex(self.failed_line(output), r"\b%s\b" % re.escape(part), "the unfinished part is named")
            part_line = next(line for line in output.splitlines() if line.strip().startswith(part))
            self.assertIn("FAILED", part_line)
        self.assertRegex(output, r"wall time \d+s")
        self.assertEqual(self.left_running(seconds), [], "the planted sleep is still running")

    def test_a_part_that_hangs_is_stopped_at_the_budget_and_named(self):
        seconds = self.hang()
        done, took = self.run_hung(seconds, PLANT_SETUP_SUITE_SECONDS=seconds)
        self.assert_stopped_at_the_budget(done, took, seconds, "setup-suite")

    def test_the_database_is_dropped_when_the_budget_stops_the_check(self):
        seconds = self.hang()
        done, took = self.run_hung(seconds, PLANT_SETUP_SUITE_SECONDS=seconds)
        self.assertTrue(any("drop database" in command for command in self.commands()), self.commands())

    def test_a_gleam_run_that_hangs_is_stopped_with_what_it_started(self):
        # The sleep is a grandchild of the check: its subshell runs `gleam`, which runs it.
        seconds = self.hang()
        done, took = self.run_hung(seconds, PLANT_GLEAM_TEST_SECONDS=seconds)
        self.assert_stopped_at_the_budget(done, took, seconds, "gleam-test")

    def test_a_setup_check_that_hangs_is_stopped_at_the_budget(self):
        seconds = self.hang()
        done, took = self.run_hung(seconds, PLANT_SETUP_SECONDS=seconds)
        self.assert_stopped_at_the_budget(done, took, seconds, None)
        self.assertEqual(self.commands(), [], "no part ran after a setup check that did not end")

    def test_the_deadline_is_the_raised_budget_when_the_integration_tests_run(self):
        # The usual budget is 1 s, the raised one 6 s: a hung setup check is stopped at 6.
        self.commit_change(SCRIPTS_FILE)
        seconds = self.hang()
        done, took = self.run_hung(
            seconds, budget=1, client=True, GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="6", PLANT_SETUP_SECONDS=seconds
        )
        self.assert_stopped_at_the_budget(done, took, seconds, None, budget=6)
        self.assertGreaterEqual(took, 5, "the check was stopped at the usual budget, not the raised one")


class FastBudgetTest(PlantedCheckCase):
    """Issue 109, item 6: the fast check's budget is set from its measured time,
    and is its own setting: GENESIS_CHECK_FAST_BUDGET_SECONDS."""

    def test_a_fast_check_past_its_budget_fails_naming_the_time_and_the_budget(self):
        done = self.run_check("fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="1", PLANT_SETUP_SECONDS="3")
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertRegex(output, r"budget[^\n]*\b1\s*s")

    def test_the_fast_checks_budget_without_the_setting_is_9_seconds_from_its_measured_time(self):
        # 6, 7 and 7 s in 3 runs on 2026-10-27 (issue 109): 7 x 1.25, rounded up.
        source = CHECK.read_text()
        self.assertEqual(re.findall(r"GENESIS_CHECK_FAST_BUDGET_SECONDS:-(\d+)", source), ["9"])


class ClientIntegrationTest(PlantedCheckCase):
    """Issue 109, item 3 (changed 2026-10-27): the query process's integration
    tests run in the full check when the branch changes a file under the client
    scripts folder, compared with its merge base with main (origin/main when
    there is one); otherwise they are skipped and the output says so. Where they
    run, the budget is raised and the output says why."""

    def part_line(self, output: str) -> str:
        return next((line for line in output.splitlines() if "client-integration" in line), "")

    def test_where_the_branch_changes_a_file_of_the_scripts_folder_a_gated_test_runs(self):
        self.commit_change(SCRIPTS_FILE)
        done = self.run_check(client=True)
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertTrue(self.marker.exists(), "the planted integration test did not run:\n" + self.output(done))

    def test_a_planted_failing_integration_test_fails_the_check_by_part_name(self):
        self.plant_integration_test(fails=True)
        self.commit_change(SCRIPTS_FILE)
        done = self.run_check(client=True)
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertRegex(self.failed_line(output), r"client-integration")
        self.assertIn("planted integration failure", output, "the failed part's log is printed")

    def test_a_change_made_but_not_yet_committed_counts_as_a_change(self):
        self.settle()
        with open(self.repository / SCRIPTS_FILE, "a") as changed:
            changed.write("\n# edited, not committed\n")
        done = self.run_check(client=True)
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertTrue(self.marker.exists(), "an edit under the scripts folder did not start the gated tests")

    def test_where_the_branch_changes_nothing_there_the_gated_tests_are_skipped_and_the_output_says_so(self):
        self.plant_integration_test(fails=True)
        self.settle()
        done = self.run_check(client=True)
        output = self.output(done)
        self.assertEqual(done.returncode, 0, output)
        self.assertFalse(self.marker.exists(), "an integration test ran with no change under the scripts folder")
        line = self.part_line(output)
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + output)
        self.assertIn("unchanged", line, "and why:\n" + output)

    def test_a_change_outside_the_scripts_folder_does_not_start_them(self):
        self.settle()
        (self.repository / "src" / "planted.gleam").write_text("// a file outside the scripts folder\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "a change outside the scripts folder")
        done = self.run_check(client=True)
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertFalse(self.marker.exists())
        self.assertIn("skipped", self.part_line(self.output(done)))

    def test_the_merge_base_is_with_origin_main_when_there_is_one(self):
        # origin/main is at the first commit, while the local main has moved on with
        # the change: against origin/main the branch changes the scripts folder.
        self.settle()
        self.git("checkout", "-q", "main")
        self.commit_change(SCRIPTS_FILE)
        self.git("update-ref", "refs/remotes/origin/main", self.git("rev-parse", "main~1"))
        self.git("checkout", "-q", "feature")
        self.git("reset", "-q", "--hard", "main")
        done = self.run_check(client=True)
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertTrue(self.marker.exists(), "the merge base was taken with main, not origin/main")

    def test_without_a_main_to_compare_with_they_run_and_the_output_says_the_base_was_not_found(self):
        self.settle()
        self.git("branch", "-q", "-m", "main", "trunk")
        done = self.run_check(client=True)
        output = self.output(done)
        self.assertEqual(done.returncode, 0, output)
        self.assertTrue(self.marker.exists(), "with no merge base, the safe course is to run them")
        self.assertIn("main", self.part_line(output) + output)

    def test_where_there_is_no_client_the_gated_tests_are_skipped_and_the_output_says_so(self):
        self.plant_integration_test(fails=True)
        self.commit_change(SCRIPTS_FILE)
        done = self.run_check(client=False)
        output = self.output(done)
        self.assertEqual(done.returncode, 0, output)
        self.assertFalse(self.marker.exists(), "an integration test ran with GENESIS_NO_CLIENT=1")
        line = self.part_line(output)
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + output)
        self.assertIn("GENESIS_NO_CLIENT", line, "and why:\n" + output)

    def test_an_exported_genesis_integration_does_not_open_the_gate_of_the_unit_suite(self):
        # GENESIS_INTEGRATION=1 in the caller's environment would run the 450 s
        # tests inside the client-suite part, in the usual budget.
        self.plant_integration_test(fails=True)
        self.settle()
        for client in (True, False):
            with self.subTest(client=client):
                done = self.run_check(client=client, GENESIS_INTEGRATION="1")
                self.assertEqual(done.returncode, 0, self.output(done))
                self.assertFalse(self.marker.exists(), "a gated test ran with nothing changed")

    def test_the_fast_check_does_not_run_the_integration_tests(self):
        self.commit_change(SCRIPTS_FILE)
        done = self.run_check("fast", client=True)
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertFalse(self.marker.exists())

    def test_where_they_run_the_budget_is_raised_and_the_output_says_why(self):
        # The usual budget (1 s) would fail the 3 s the planted setup suite takes;
        # the raised one (30 s) holds. The line names the raised budget and the reason.
        self.commit_change(SCRIPTS_FILE)
        done = self.run_check(
            client=True,
            GENESIS_CHECK_BUDGET_SECONDS="1",
            GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="30",
            PLANT_SETUP_SUITE_SECONDS="3",
        )
        output = self.output(done)
        self.assertEqual(done.returncode, 0, output)
        raised = [line for line in output.splitlines() if "budget" in line.lower() and "raised" in line.lower()]
        self.assertTrue(raised, "a line says the budget was raised:\n" + output)
        self.assertRegex(raised[0], r"\b30\s*s", "it names the raised budget")
        self.assertIn("integration", raised[0].lower(), "and the reason")

    def test_where_they_are_skipped_the_budget_is_not_raised(self):
        self.settle()
        done = self.run_check(
            client=True,
            GENESIS_CHECK_BUDGET_SECONDS="1",
            GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="30",
            PLANT_SETUP_SUITE_SECONDS="3",
        )
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, "3 s over a 1 s budget: " + output)
        self.assertFalse([l for l in output.splitlines() if "raised" in l.lower()], output)

    def test_the_raised_budget_without_the_setting_is_583_seconds_from_the_worst_measured_run(self):
        # 466 s (the slowest of 3 runs on 2026-10-26, issue 109) x 1.25, rounded up.
        source = CHECK.read_text()
        self.assertEqual(re.findall(r"GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS:-(\d+)", source), ["583"])


class FastModeTest(PlantedCheckCase):
    """Issue 109, item 6: `./check fast` is the format check, the build with
    warnings as errors, glinter and the code-rule tests, and nothing else.

    The planted `gleam` stands for the tools: it fails the format check on a
    planted format error and any run of tests on a planted breach of a code
    rule. What these tests hold is that the fast check runs each of those four
    and fails, naming the part, when one fails."""

    def test_a_planted_format_error_fails_the_fast_check_naming_the_format_part(self):
        (self.repository / "src" / "planted.gleam").write_text("// PLANTED_FORMAT_ERROR\n")
        done = self.run_check("fast")
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertRegex(self.failed_line(output), r"\bformat\b")

    def test_a_planted_code_rule_breach_fails_the_fast_check_naming_the_code_rules_part(self):
        (self.repository / "test" / "code_rule" / "planted_test.gleam").write_text("// PLANTED_BREACH\n")
        done = self.run_check("fast")
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertRegex(self.failed_line(output), r"\bcode-rules\b")

    def test_the_fast_check_runs_the_four_parts_and_no_other(self):
        done = self.run_check("fast")
        output = self.output(done)
        self.assertEqual(done.returncode, 0, output)
        listed = re.findall(r"^\s*([a-z-]+)\s+(?:ok|FAILED)\b", output, re.MULTILINE)
        self.assertEqual(sorted(listed), ["code-rules", "format", "gleam-build", "glinter"])
        commands = self.commands()
        self.assertTrue(any(c.startswith("gleam format --check") for c in commands), commands)
        self.assertIn("gleam build --warnings-as-errors", commands)
        self.assertIn("gleam run -m glinter", commands)
        self.assertFalse([c for c in commands if c.startswith(("psql", "python3.13"))], commands)
        for module in NOT_TEST_RUNS:
            if module != "glinter":
                self.assertFalse([c for c in commands if module in c], commands)

    def test_the_fast_check_never_runs_the_whole_test_suite(self):
        self.run_check("fast")
        suites = [c for c in self.commands() if re.fullmatch(r"gleam test( -- --workers \d+)?", c)]
        self.assertEqual(suites, [], "the fast check runs the code-rule tests only")

    def test_a_failing_build_fails_the_fast_check_naming_it(self):
        executable(self.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))
        done = self.run_check("fast")
        output = self.output(done)
        self.assertNotEqual(done.returncode, 0, output)
        self.assertRegex(self.failed_line(output), r"gleam-build")


class WorkerCountTest(PlantedCheckCase):
    """Issue 109, items 7 and 8: the worker count is one setting of the check,
    and the setting names the measurement it comes from."""

    def test_the_setting_is_given_to_the_test_run_as_the_worker_count(self):
        done = self.run_check(GENESIS_TEST_WORKERS="3")
        self.assertEqual(done.returncode, 0, self.output(done))
        self.assertIn("gleam test -- --workers 3", self.commands())

    def test_the_default_worker_count_has_the_measurement_that_chose_it_beside_it(self):
        lines = CHECK.read_text().splitlines()
        at = next(i for i, line in enumerate(lines) if "GENESIS_TEST_WORKERS:-" in line)
        self.assertRegex(lines[at], r"GENESIS_TEST_WORKERS:-\d+\}", "a number, not unset")
        beside = " ".join(lines[max(0, at - 4) : at + 4]).lower()
        self.assertIn("measured", beside, "the smallest count that leaves 25% of the budget spare, and the measurement")


if __name__ == "__main__":
    unittest.main()
