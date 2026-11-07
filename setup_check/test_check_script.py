"""./check: what the script does with the parts it runs, tested on a planted repository.

Each test copies ./check and setup_check/environment.sh into a temporary
repository and runs that copy with a PATH of planted tools, so no test touches
the real toolchain, the real database or the real client:

- ./setup-check is a stub that succeeds (after PLANT_SETUP_SECONDS, when set);
- `gleam` and `psql` are stubs that write their command line to PLANT_LOG and
  succeed (the `psql` that drops the database takes PLANT_PSQL_DROP_SECONDS
  first, when set, and the one that creates it takes PLANT_PSQL_CREATE_SECONDS
  first, when set, and fails when PLANT_PSQL_CREATE_FAILS is set; `gleam format` takes PLANT_FORMAT_SECONDS, or ends its own
  shell without a word when PLANT_FORMAT_KILLS_PARENT is set), except that `gleam format --check` fails when a file under src,
  test or dev holds PLANTED_FORMAT_ERROR, and any `gleam` run of tests (a `test`
  or a `run -m` of a module other than glinter, squirrel and table_generator)
  fails when a file under test/code_rule holds PLANTED_BREACH; with
  PLANT_RENDEZVOUS set, the plain test run (`gleam test -- --workers N`) waits until
  glinter, table_generator, squirrel and the world-data run have each started, and
  the code-rule run (`gleam test -- --tag code_rule`) until glinter has, so a part
  that is not run beside the test run makes it fail;
- `python3.13` is the real one, except for the run the stub stands in for:
  check_facts.py, which succeeds at once;
- the client query process's scripts are the real check_support.py (with the
  query_client.py and ghidra_env.py it imports) and formulas_by_hand.py with
  one planted test file whose test is gated by
  check_support.integration_only, so the gate is the real one.

- the planted repository is a git repository on a branch `feature` of `main`
  (the planted files are the first commit), because the integration tests run
  only when the branch changes a file under the client scripts folder.

A planted run costs about two seconds, so tests that only read what one run
printed or logged share it (`shared_run`), the whole file stays under a minute,
and tests of what does not depend on the parts' work run `./check fast`, which
has four parts instead of all of them.

The part names are the ones ./check prints.

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
import tomllib
import unittest
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
CHECK = REPOSITORY / "check"
SCRIPTS = Path(".claude") / "skills" / "decoding-the-client" / "scripts"
PLAYING_LIVE_SCRIPTS = Path(".claude") / "skills" / "playing-live" / "scripts"
PYTHON = shutil.which("python3.13")

RUNNABLE = PYTHON is not None and shutil.which("bash") is not None and CHECK.is_file()

# The commands `gleam run -m MODULE` the check makes that are not a run of tests.
NOT_TEST_RUNS = ("glinter", "squirrel", "genesis_prime/table_generator")

GLEAM_STUB = """#!/bin/sh
echo "gleam $*" >>"$PLANT_LOG"
echo "gleam $* GENESIS_TEST_SKIP_SERIAL=$GENESIS_TEST_SKIP_SERIAL GENESIS_TEST_SKIP_WORLD_DATA=$GENESIS_TEST_SKIP_WORLD_DATA" >>"$PLANT_LOG.environment"
if [ -n "$PLANT_RENDEZVOUS" ]; then
  rendezvous="$PLANT_LOG.rendezvous"
  mkdir -p "$rendezvous"
  await() {
    for name in "$@"; do
      waited=0
      until [ -f "$rendezvous/$name" ]; do
        sleep 0.1
        waited=$((waited + 1))
        if [ "$waited" -gt 300 ]; then
          echo "$name had not started while the test run was running"
          exit 1
        fi
      done
    done
  }
  case "$*" in
    "run -m glinter") touch "$rendezvous/glinter" ;;
    "run -m genesis_prime/table_generator check") touch "$rendezvous/table_generator" ;;
    "run -m squirrel check") touch "$rendezvous/squirrel" ;;
    "test -- --tag world_data") touch "$rendezvous/world_data" ;;
    "test -- --workers "*) await glinter table_generator squirrel world_data ;;
    "test -- --tag code_rule") await glinter ;;
  esac
fi
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
  echo "gleam $* peak_file=${GENESIS_LITERAL_PEAK_FILE:+given}" >>"$PLANT_LOG.peak"
  # The run keeps the literal allocator's highest carriers size in the file it is
  # given, as test/genesis_prime_test.gleam does; PLANT_LITERAL_PEAK is that many
  # bytes, and "none" writes no file.
  # PLANT_WORLD_DATA_LITERAL_PEAK is the same for the world-data run alone.
  peak="${PLANT_LITERAL_PEAK:-100000000}"
  case "$*" in
    *"--tag world_data"*) peak="${PLANT_WORLD_DATA_LITERAL_PEAK:-$peak}" ;;
  esac
  if [ -n "$GENESIS_LITERAL_PEAK_FILE" ] && [ "$peak" != none ]; then
    echo "$peak" >"$GENESIS_LITERAL_PEAK_FILE"
  fi
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
  *"create database"*)
    [ -n "$PLANT_PSQL_CREATE_SECONDS" ] && sleep "$PLANT_PSQL_CREATE_SECONDS"
    [ -n "$PLANT_PSQL_CREATE_FAILS" ] && exit 1
    ;;
  *"to_regclass"*) echo f ;;
  *"count(*)"*) echo 0 ;;
esac
exit 0
"""

PYTHON_STUB = """#!/bin/sh
echo "python3.13 $*" >>"$PLANT_LOG"
case "$*" in
  *check_facts.py*) exit 0 ;;
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
        shutil.copyfile(HERE / "sha256.sh", repository / "setup_check" / "sha256.sh")
        shutil.copyfile(REPOSITORY / ".tool-versions", repository / ".tool-versions")
        executable(repository / "setup-check", SETUP_CHECK_STUB)
        (repository / "priv" / "migrations").mkdir(parents=True)
        for folder in ("src", "dev", "test/code_rule"):
            (repository / folder).mkdir(parents=True)
        # The real script, which the migrations part runs; the planted psql answers its questions.
        executable(repository / "dev" / "apply_migrations.sh", (REPOSITORY / "dev" / "apply_migrations.sh").read_text())
        (repository / "test" / "code_rule" / "planted_test.gleam").write_text("// a code-rule test\n")
        scripts = repository / SCRIPTS
        scripts.mkdir(parents=True)
        for name in ("check_support.py", "query_client.py", "ghidra_env.py", "formulas_by_hand.py"):
            shutil.copyfile(REPOSITORY / SCRIPTS / name, scripts / name)
        # The playing-live scripts' folder, whose tests the client-suite part finds by discovery, after
        # the client scripts': one planted test stands for whatever the folder holds.
        (repository / PLAYING_LIVE_SCRIPTS).mkdir(parents=True)
        self.plant_playing_live_test(fails=False)
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

    def plant_playing_live_test(self, fails: bool) -> None:
        body = 'self.fail("planted playing-live failure")' if fails else "pass"
        (self.repository / PLAYING_LIVE_SCRIPTS / "test_planted_playing_live.py").write_text(
            "import unittest\n\n\nclass PlantedPlayingLiveTest(unittest.TestCase):\n"
            "    def test_it_ran_and_it_%s(self):\n        %s\n" % ("fails" if fails else "passes", body)
        )

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

    def peak_log(self) -> str:
        """The gleam test commands with whether each was given the literal peak file."""
        path = Path(str(self.log) + ".peak")
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
    peak: str
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
        run = Run(done, case.commands(), case.environment_log(), case.peak_log(), took, case.marker.exists(), seconds, left)
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
    """A part that ends without writing its status fails the check.
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


WARNING = re.compile(r"(?m)^check WARNING: over its budget, wall time (\d+)s, budget (\d+)s$")


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class BudgetTest(unittest.TestCase):
    """The budget is a target: a run that ends over its budget but within three
    times it passes, with a warning line that names its wall time and its budget.

    The tests set the budget to 3 seconds (GENESIS_CHECK_FAST_BUDGET_SECONDS for
    `./check fast`, GENESIS_CHECK_BUDGET_SECONDS for the full check, which share
    the code) and plant 4 seconds of delay. A planted sleep never ends early, so the
    run is over its budget by construction; the rest of the run (a few instant stubs)
    adds well under the 5 seconds between the delay and the hang limit at 9, which
    is the margin a loaded machine needs. The real budget is 2 minutes (CLAUDE.md:
    "the full check passes in under 2 minutes")."""

    def assert_passed_with_the_warning(self, run: Run, budget: int) -> None:
        output = run.output
        self.assertEqual(run.done.returncode, 0, output)
        self.assertRegex(output, r"(?m)^check passed")
        warnings = WARNING.findall(output)
        self.assertEqual(len(warnings), 1, "one warning line names the wall time and the budget:\n" + output)
        wall_time, printed_budget = map(int, warnings[0])
        self.assertEqual(printed_budget, budget, "the warning names the budget")
        self.assertGreater(wall_time, budget, "the warning names a wall time over the budget")
        self.assertLess(wall_time, 3 * budget, "the run ended before three times its budget")
        self.assertNotIn("check FAILED", output)
        self.assertNotIn("hung", output)

    def test_a_slow_part_takes_the_check_over_its_budget_and_it_passes_with_a_warning(self):
        run = shared_run("slow-part", "fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="3", PLANT_FORMAT_SECONDS="4")
        self.assert_passed_with_the_warning(run, budget=3)

    def test_the_full_check_over_its_budget_passes_with_a_warning(self):
        run = shared_run("slow-part-full", GENESIS_CHECK_BUDGET_SECONDS="3", PLANT_FORMAT_SECONDS="4")
        self.assert_passed_with_the_warning(run, budget=3)

    def test_the_time_of_the_setup_check_counts_towards_the_budget(self):
        # Every part is instant; only ./setup-check is slow.
        run = shared_run("slow-setup", "fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="3", PLANT_SETUP_SECONDS="4")
        self.assert_passed_with_the_warning(run, budget=3)

    def test_the_warning_names_the_raised_budget_when_the_integration_tests_run(self):
        # The usual budget is 1 s, the raised one 3 s: the 4 s of delay is over the raised
        # one and 5 s under three times it (9 s).
        run = shared_run(
            "slow-raised", client=True, prepare=lambda case: case.commit_change(SCRIPTS_FILE),
            GENESIS_CHECK_BUDGET_SECONDS="1", GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="3",
            PLANT_FORMAT_SECONDS="4",
        )
        self.assert_passed_with_the_warning(run, budget=3)

    @staticmethod
    def quick_polls(case: PlantedCheckCase) -> None:
        """Plants a `sleep` that returns at once for the 0.2 second poll of a part's
        status, so a cap on the number of polls, which the check once had, would run
        out in a few seconds. Any other sleep is the real one."""
        executable(case.root / "tools" / "sleep", '#!/bin/sh\ncase "$1" in 0.2) exit 0 ;; esac\nexec /bin/sleep "$@"\n')

    def test_squirrel_waits_for_a_slow_migrations_part_and_still_runs(self):
        # The migrations part takes 8 s, 7 s under the hang limit of 15 (3 times the budget
        # of 5), and the polls are quick: squirrel runs when the part ends, however many
        # polls that took.
        run = shared_run(
            "slow-migrations", prepare=self.quick_polls, timeout=40,
            GENESIS_CHECK_BUDGET_SECONDS="5", PLANT_PSQL_CREATE_SECONDS="8",
        )
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("gleam run -m squirrel check", run.commands)
        self.assertRegex(run.output, r"(?m)^  squirrel +ok\b")

    def test_squirrel_is_skipped_when_the_migrations_part_fails(self):
        run = shared_run("failing-migrations", prepare=self.quick_polls, PLANT_PSQL_CREATE_FAILS="1")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bmigrations\b")
        self.assertNotIn("gleam run -m squirrel check", run.commands)
        self.assertRegex(run.output, r"(?m)^  squirrel +skipped \(a part it needs failed: migrations\)")

    def test_a_check_inside_its_budget_passes_without_a_warning(self):
        run = shared_run("in-budget", "fast", GENESIS_CHECK_FAST_BUDGET_SECONDS="30", PLANT_FORMAT_SECONDS="1")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^check passed, wall time \d+s, budget 30s$")
        self.assertNotIn("WARNING", run.output)
        self.assertNotIn("over its budget", run.output)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class HungPartTest(unittest.TestCase):
    """A run still going at three times its budget is hung: a part that hangs, or a
    setup check that does, is stopped then, with everything it started, and the
    check fails naming it, in three times the budget plus a few seconds.

    A hang is a planted `sleep` of 600 seconds and a fraction unique to the run. The
    budget is 2 seconds, so the hang is ended at 6."""

    BUDGET = 2
    FEW_SECONDS = 8

    def assert_stopped_as_hung(self, run: Run, part: str | None, budget: int = BUDGET) -> None:
        output = run.output
        self.assertNotEqual(run.done.returncode, 0, output)
        self.assertLess(run.took, 3 * budget + self.FEW_SECONDS, "the check ran %.1f s past a budget of %d s" % (run.took, budget))
        self.assertGreaterEqual(run.took, 3 * budget - 1, "the check was stopped before three times its budget")
        line = failed_line(self, output)
        self.assertRegex(line, r"hung, still running at three times its budget of %ds" % budget)
        self.assertNotRegex(output, r"(?m)^check passed")
        if part:
            self.assertRegex(line, r"^check FAILED: %s hung" % re.escape(part), "the hung part is named")
            part_line = next(line for line in output.splitlines() if line.strip().startswith(part))
            self.assertIn("FAILED", part_line)
            self.assertIn("hung", part_line)
        else:
            self.assertRegex(line, r"^check FAILED: the setup check hung")
        self.assertRegex(output, r"wall time \d+s, budget %ds" % budget)
        self.assertEqual(run.left_running, [], "the planted sleep is still running")

    def part_and_drop(self) -> Run:
        # Postgres stops answering as well: the psql that drops the database at the
        # end would wait for ever.
        return shared_run(
            "hung-part-and-drop",
            hang=lambda seconds: dict(PLANT_FORMAT_SECONDS=seconds, PLANT_PSQL_DROP_SECONDS=seconds),
            timeout=40,
            GENESIS_CHECK_BUDGET_SECONDS=str(self.BUDGET),
        )

    def test_a_part_that_hangs_is_stopped_at_three_times_the_budget_and_named(self):
        run = self.part_and_drop()
        self.assert_stopped_as_hung(run, "format")
        self.assertNotIn("WARNING", run.output, "a hung run is failed, not warned")

    def test_the_parts_that_ended_are_not_named_hung(self):
        failed = failed_line(self, self.part_and_drop().output)
        self.assertNotRegex(failed, r"gleam-build|glinter|gleam-test|migrations")

    def test_the_database_is_dropped_when_a_hang_stops_the_check(self):
        self.assertTrue(any("drop database" in command for command in self.part_and_drop().commands))

    def test_a_database_drop_that_hangs_does_not_hold_the_check_past_its_deadline(self):
        # The same run: the planted psql sleeps 600 s on the drop, and the check still
        # ended within three times the budget and a few seconds, with the sleep ended.
        run = self.part_and_drop()
        self.assertLess(run.took, 3 * self.BUDGET + self.FEW_SECONDS)
        self.assertEqual(run.left_running, [])

    def test_a_gleam_run_that_hangs_is_stopped_with_what_it_started(self):
        # The sleep is a grandchild of the check: its subshell runs `gleam`, which runs it.
        run = shared_run(
            "hung-gleam", "fast", hang=lambda seconds: dict(PLANT_GLEAM_TEST_SECONDS=seconds), timeout=40,
            GENESIS_CHECK_FAST_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_as_hung(run, "code-rules")

    def test_a_setup_check_that_hangs_is_stopped_at_three_times_the_budget(self):
        run = shared_run(
            "hung-setup", "fast", hang=lambda seconds: dict(PLANT_SETUP_SECONDS=seconds), timeout=40,
            GENESIS_CHECK_FAST_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_as_hung(run, None)
        self.assertEqual(run.commands, [], "no part ran after a setup check that did not end")

    def test_the_deadline_is_three_times_the_raised_budget_when_the_integration_tests_run(self):
        # The usual budget is 1 s, the raised one 4 s: a hung setup check is stopped at 12,
        # not at 3.
        run = shared_run(
            "hung-raised", client=True, prepare=lambda case: case.commit_change(SCRIPTS_FILE),
            hang=lambda seconds: dict(PLANT_SETUP_SECONDS=seconds), timeout=40,
            GENESIS_CHECK_BUDGET_SECONDS="1", GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="4",
        )
        self.assert_stopped_as_hung(run, None, budget=4)

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


def part_line(output: str, part: str) -> str:
    """The line of the summary that names the part, or an empty string."""
    return next((line for line in output.splitlines() if part in line), "")


def set_origin_main(case: PlantedCheckCase, revision: str) -> None:
    """Makes `origin/main` the planted repository's commit at `revision`, as a fetch would."""
    case.git("update-ref", "refs/remotes/origin/main", case.git("rev-parse", revision))


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class PlayingLiveSuiteTest(unittest.TestCase):
    """The playing-live scripts' tests run in the client-suite part, found by discovery in their
    folder, so a test added there needs no change to ./check, and one that fails fails the part."""

    def failing(self) -> Run:
        return shared_run("playing-live-fails", prepare=lambda case: case.plant_playing_live_test(fails=True))

    def test_a_failing_test_in_the_playing_live_scripts_fails_the_check_by_part_name(self):
        run = self.failing()
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"client-suite")
        self.assertNotIn("hung", failed_line(self, run.output))
        self.assertIn("planted playing-live failure", run.output, "the failed part's log is printed")

    def test_only_the_client_suite_part_fails_for_it(self):
        self.assertNotIn(",", failed_line(self, self.failing().output).split("FAILED:", 1)[1])


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ClientIntegrationTest(unittest.TestCase):
    """The query process's integration
    tests run in the full check when the branch changes a file under the client
    scripts folder, compared with its merge base with main (origin/main when
    there is one); otherwise they are skipped and the output says so. Where they
    run, the budget is raised and the output says why."""

    def changed(self) -> Run:
        # The planted gated test fails; the usual budget (1 s) is raised to 30 s, which
        # holds the 3 s the planted format part takes.
        return shared_run(
            "integration-changed", client=True,
            prepare=lambda case: (plant_failing_gated_test(case), change_the_scripts(case)),
            GENESIS_CHECK_BUDGET_SECONDS="1", GENESIS_CHECK_INTEGRATION_BUDGET_SECONDS="30",
            PLANT_FORMAT_SECONDS="3",
        )

    def test_where_the_branch_changes_a_file_of_the_scripts_folder_a_gated_test_runs(self):
        run = self.changed()
        self.assertTrue(run.marker_ran, "the planted integration test did not run:\n" + run.output)

    def test_a_planted_failing_integration_test_fails_the_check_by_part_name(self):
        run = self.changed()
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"client-integration")
        self.assertNotIn("hung", failed_line(self, run.output))
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
        line = part_line(run.output, "client-integration")
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
        line = part_line(run.output, "client-integration")
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + run.output)
        self.assertIn("GENESIS_NO_CLIENT", line, "and why:\n" + run.output)

    def test_the_merge_base_is_with_origin_main_when_there_is_one(self):
        # origin/main is at the first commit, while the local main has moved on with
        # the change: against origin/main the branch changes the scripts folder.
        def plant(case):
            case.settle()
            case.git("checkout", "-q", "main")
            case.commit_change(SCRIPTS_FILE)
            set_origin_main(case, "main~1")
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
        self.assertIn("main", part_line(run.output, "client-integration") + run.output)

    def test_the_fast_check_does_not_run_the_integration_tests(self):
        run = shared_run("fast-changed", "fast", client=True, prepare=change_the_scripts)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertFalse(run.marker_ran)


def advance_origin_main(case: PlantedCheckCase, commits: int) -> None:
    """`origin/main` gains `commits` commits that the branch `feature` lacks."""
    case.settle()
    case.git("checkout", "-q", "main")
    for _ in range(commits):
        case.commit_change(".gitignore")
    set_origin_main(case, "main")
    case.git("checkout", "-q", "feature")


def plant_branch_holding_origin_main(case: PlantedCheckCase) -> None:
    """`feature` holds the one commit `origin/main` gained, and has a commit of its own."""
    advance_origin_main(case, 1)
    case.git("merge", "-q", "main")
    case.commit_change(".gitignore")


def make_the_repository_shallow(case: PlantedCheckCase) -> None:
    """Replaces the planted repository with a clone of it that keeps one commit of each
    branch, as CI's checkout does: the commits a branch holds are no longer all reachable."""
    clone = case.root / "shallow"
    case.git("clone", "-q", "--depth", "1", "--no-single-branch", "file://%s" % case.repository, str(clone))
    shutil.move(str(case.repository), str(case.root / "full"))
    shutil.move(str(clone), str(case.repository))


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class BranchHoldsMainTest(unittest.TestCase):
    """The full check compares HEAD with `origin/main` as last fetched, first of all:
    a branch that lacks commits of it fails by part name, before any other part runs,
    and says to merge `origin/main` with the count and the tip compared. Where there
    is no `origin/main` (CI's checkout fetches only the merge ref), the part is
    skipped and says why. `./check fast` does not run it."""

    BEHIND = 2

    # The tip of origin/main in the planted repository, kept with the run that is shared.
    tips: dict[str, str] = {}

    def behind(self) -> tuple[Run, str]:
        def plant(case: PlantedCheckCase) -> None:
            advance_origin_main(case, self.BEHIND)
            self.tips["behind"] = case.git("rev-parse", "--short", "origin/main")

        run = shared_run("branch-behind-origin-main", prepare=plant)
        return run, self.tips["behind"]

    def test_a_branch_holding_every_commit_of_origin_main_passes_the_part(self):
        run = shared_run("branch-holds-origin-main", prepare=plant_branch_holding_origin_main)
        self.assertEqual(run.done.returncode, 0, run.output)
        line = part_line(run.output, "branch-current")
        self.assertRegex(line, r"\bok\b", "the part's line says it passed:\n" + run.output)
        self.assertIn("origin/main", line)

    def test_a_branch_missing_commits_of_origin_main_fails_the_check_by_name_with_the_count_and_the_tip(self):
        run, tip = self.behind()
        self.assertNotEqual(run.done.returncode, 0, run.output)
        failed = failed_line(self, run.output)
        self.assertIn("branch-current", failed)
        self.assertRegex(failed, r"\b%d commits\b" % self.BEHIND)
        self.assertIn(tip, failed, "the tip of origin/main that was compared")
        self.assertRegex(failed, r"merge origin/main")

    def test_a_branch_missing_commits_of_origin_main_fails_before_any_other_part_runs(self):
        run, _ = self.behind()
        self.assertEqual(run.commands, [], "no gleam, psql or python command ran")
        self.assertNotIn("setup check passed", run.output, "the setup check did not run")
        self.assertFalse(run.marker_ran)
        self.assertNotRegex(run.output, r"(?m)^\s+(format|gleam-build|migrations)\s+(ok|FAILED)\b", "no part was reported")

    def test_a_repository_with_no_origin_main_skips_the_part_and_says_why(self):
        run = shared_run("full")
        self.assertEqual(run.done.returncode, 0, run.output)
        line = part_line(run.output, "branch-current")
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + run.output)
        self.assertIn("no origin/main", line, "and why")

    def test_a_shallow_repository_skips_the_part_and_says_why(self):
        # The branch holds origin/main, but the clone keeps one commit of each, so a count
        # of the commits HEAD lacks would say 1.
        def plant(case: PlantedCheckCase) -> None:
            plant_branch_holding_origin_main(case)
            make_the_repository_shallow(case)

        run = shared_run("branch-shallow", prepare=plant)
        self.assertEqual(run.done.returncode, 0, run.output)
        line = part_line(run.output, "branch-current")
        self.assertIn("skipped", line, "the part's line says it was skipped:\n" + run.output)
        self.assertIn("the history is shallow, so whether HEAD holds origin/main cannot be established", line)

    def test_the_fast_check_on_a_branch_behind_origin_main_does_not_run_the_part(self):
        run = shared_run("fast-branch-behind", "fast", prepare=lambda case: advance_origin_main(case, self.BEHIND))
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertEqual(part_line(run.output, "branch-current"), "", run.output)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class FastModeTest(unittest.TestCase):
    """`./check fast` is the format check, the build with
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


def commit_new_file(case: PlantedCheckCase, path: str) -> None:
    """A commit on the branch that adds the file at path (from the repository's folder),
    or changes it when the planted repository has it."""
    case.settle()
    target = case.repository / path
    if target.exists():
        case.commit_change(path)
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("# added on the branch\n")
    case.git("add", path)
    case.git("commit", "-q", "-m", "add %s" % path)


def parts_reported(output: str) -> list[str]:
    """The parts the summary lists, in order, whether they ran or were skipped."""
    return re.findall(r"^\s+([a-z-]+)\s+(?:ok|FAILED|skipped)\b", output, re.MULTILINE)


def scope_line(output: str) -> str:
    """The one line that says which scope the run took."""
    lines = [line for line in output.splitlines() if line.startswith("scope: ")]
    return lines[0] if len(lines) == 1 else "\n".join(lines)


# The full check's parts, in the order ./check prints them after branch-current.
EVERY_PART = [
    "format", "gleam-build", "glinter", "generated-tables", "gleam-test", "world-data", "literal-area",
    "migrations", "squirrel", "client-suite", "client-integration", "fact-checker",
]
QUICK_PARTS = ["format", "gleam-build", "glinter", "code-rules"]

# Files that guidance and untested tools are made of (the issue's light set), one per entry.
LIGHT_FILES = [
    "CLAUDE.md",
    ".claude/skills/writing-tests/SKILL.md",
    ".claude/skills/designing-processes/structure.md",
    ".claude/agents/implementer.md",
    ".github/workflows/check.yml",
    "LICENSE",
    ".gitignore",
    "dev/card.sh",
    "dev/step_measure.py",
]


def plant_light_changes(case: PlantedCheckCase, paths=LIGHT_FILES) -> None:
    for path in paths:
        commit_new_file(case, path)


# A `git` that fails the one command PLANT_GIT_FAILS names (diff, ls-files) and runs the real one otherwise.
GIT_STUB = """#!/bin/sh
for argument in "$@"; do
  if [ -n "$PLANT_GIT_FAILS" ] && [ "$argument" = "$PLANT_GIT_FAILS" ]; then
    echo "planted git failure" >&2
    exit 128
  fi
done
exec "%s" "$@"
"""


def plant_failing_git(case: PlantedCheckCase) -> None:
    executable(case.root / "tools" / "git", GIT_STUB % shutil.which("git"))


def scoped_run(key: str, prepare, *arguments: str, **settings: str) -> Run:
    """A planted full check on a machine with the client, where the scope is chosen
    (CI's machine, with GENESIS_NO_CLIENT=1, always runs every part)."""
    return shared_run(key, *arguments, client=True, prepare=prepare, **settings)


def without_branch_current(output: str) -> list[str]:
    return [part for part in parts_reported(output) if part != "branch-current"]


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class LightScopeTest(unittest.TestCase):
    """When every file the branch changes since its merge base with main is guidance
    or a tool no part tests, the full check runs the fast parts and says so; any other
    changed file, or none at all, runs every part. The merge base is the one the
    client scripts' integration tests use. CI's machine always runs every part."""

    def light(self) -> Run:
        return scoped_run("light-only", plant_light_changes)

    def assert_every_part(self, run: Run, named: str = "") -> None:
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertEqual(without_branch_current(run.output), EVERY_PART, run.output)
        line = scope_line(run.output)
        self.assertRegex(line, r"^scope: every part\b", run.output)
        self.assertIn(named, line, "the scope line says why")

    def assert_light(self, run: Run) -> None:
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertEqual(without_branch_current(run.output), QUICK_PARTS, run.output)
        self.assertRegex(scope_line(run.output), r"^scope: light\b", run.output)

    def test_a_branch_changing_only_light_files_runs_the_fast_parts_and_no_other(self):
        run = self.light()
        self.assert_light(run)
        self.assertFalse([c for c in run.commands if c.startswith(("psql", "python3.13"))], run.commands)
        self.assertEqual([c for c in run.commands if re.fullmatch(r"gleam test( -- --workers \d+)?", c)], [])

    def test_a_branch_changing_only_light_files_says_the_scope_and_why(self):
        line = scope_line(self.light().output)
        self.assertIn("merge base", line, "it names what the files were compared with")
        self.assertTrue(any(path in line for path in LIGHT_FILES), "and a file that made it light:\n" + line)

    def test_the_last_line_names_a_light_scope(self):
        self.assertRegex(self.light().output, r"(?m)^check passed \(scope: light\), wall time \d+s, budget \d+s$")

    def test_the_last_line_of_a_run_of_every_part_does_not_name_a_scope(self):
        run = scoped_run("light-and-other", self.plant_light_and_other)
        self.assertRegex(run.output, r"(?m)^check passed, wall time \d+s, budget \d+s$")

    def test_the_setup_check_and_the_branch_current_part_still_run_on_a_light_branch(self):
        run = self.light()
        self.assertIn("setup check passed", run.output)
        self.assertIn("branch-current", run.output)

    @staticmethod
    def plant_light_and_other(case: PlantedCheckCase) -> None:
        commit_new_file(case, "CLAUDE.md")
        commit_new_file(case, "src/planted.gleam")

    def test_one_light_file_and_one_other_file_run_every_part(self):
        self.assert_every_part(scoped_run("light-and-other", self.plant_light_and_other), "src/planted.gleam")

    def test_a_branch_changing_nothing_runs_every_part(self):
        self.assert_every_part(scoped_run("changing-nothing", lambda case: case.settle()), "no file")

    def test_a_file_under_the_skills_folder_that_is_not_markdown_is_not_light(self):
        for path in (
            ".claude/skills/decoding-the-client/references/client-facts.toml",
            ".claude/skills/decoding-the-client/scripts/seed.py",
        ):
            with self.subTest(path=path):
                run = scoped_run("not-light " + path, lambda case, path=path: plant_light_changes(case, ["CLAUDE.md", path]))
                self.assert_every_part(run, path)

    def test_the_check_script_and_its_tests_and_the_compiled_tools_under_dev_are_not_light(self):
        for path in ("check", "setup_check/test_check_script.py", "dev/planted.gleam", "dev/genesis_prime/planted.sh"):
            with self.subTest(path=path):
                run = scoped_run("not-light " + path, lambda case, path=path: plant_light_changes(case, ["CLAUDE.md", path]))
                self.assert_every_part(run, path)

    def test_a_branch_changing_only_the_migration_script_runs_every_part_since_the_migrations_part_runs_it(self):
        run = scoped_run("migration-script-only", lambda case: plant_light_changes(case, ["dev/apply_migrations.sh"]))
        self.assert_every_part(run, "dev/apply_migrations.sh")

    def test_an_edit_not_yet_committed_counts_as_a_change(self):
        def plant(case):
            plant_light_changes(case, ["CLAUDE.md"])
            (case.repository / "src" / "planted.gleam").write_text("// not committed\n")

        self.assert_every_part(scoped_run("light-and-untracked", plant), "src/planted.gleam")

    def test_a_file_deleted_on_the_branch_counts_as_a_change(self):
        def plant(case):
            commit_new_file(case, "CLAUDE.md")
            case.git("rm", "-q", "test/code_rule/planted_test.gleam")
            case.git("commit", "-q", "-m", "delete a file that is not light")

        self.assert_every_part(scoped_run("light-and-deleted", plant), "test/code_rule/planted_test.gleam")

    def test_a_branch_deleting_only_a_light_file_is_light(self):
        def plant(case):
            case.settle()
            case.git("rm", "-q", ".gitignore")
            case.git("commit", "-q", "-m", "delete a light file")

        self.assert_light(scoped_run("light-deleted", plant))

    def test_a_file_renamed_from_a_path_that_is_not_light_to_one_that_is_runs_every_part(self):
        # Git's rename detection would list only the new name, which is light.
        def plant(case):
            case.settle()
            case.git("mv", "test/code_rule/planted_test.gleam", "dev/planted_test.sh")
            case.git("commit", "-q", "-m", "rename into the light set")

        self.assert_every_part(scoped_run("light-renamed", plant), "test/code_rule/planted_test.gleam")

    def test_a_light_path_with_a_space_in_it_is_light(self):
        run = scoped_run("light-with-space", lambda case: plant_light_changes(case, [".claude/skills/writing-tests/extra notes.md"]))
        self.assert_light(run)

    def test_a_path_with_a_space_in_it_that_is_not_light_is_named_whole(self):
        run = scoped_run("other-with-space", lambda case: plant_light_changes(case, ["CLAUDE.md", "src/my file.gleam"]))
        self.assert_every_part(run, "src/my file.gleam")

    def test_without_a_merge_base_every_part_runs(self):
        def plant(case):
            plant_light_changes(case, ["CLAUDE.md"])
            case.git("branch", "-q", "-m", "main", "trunk")

        self.assert_every_part(scoped_run("light-no-main", plant), "merge base")

    def test_a_shallow_repository_runs_every_part_since_its_merge_base_cannot_be_established(self):
        def plant(case):
            plant_light_changes(case, ["CLAUDE.md"])
            make_the_repository_shallow(case)

        self.assert_every_part(scoped_run("light-shallow", plant), "shallow")

    def test_the_machine_of_ci_runs_every_part_on_a_light_branch(self):
        # GENESIS_NO_CLIENT=1 is what CI sets; GITHUB_ACTIONS is what its runner sets.
        for key, run in (
            ("light-no-client", shared_run("light-no-client", prepare=plant_light_changes)),
            ("light-github-actions", scoped_run("light-github-actions", plant_light_changes, GITHUB_ACTIONS="true")),
        ):
            with self.subTest(key=key):
                self.assert_every_part(run, "CI")

    def test_the_merge_base_is_with_origin_main_when_there_is_one(self):
        # origin/main is at the first commit, while the local main has moved on with a
        # change that is not light, and the branch adds a light file after it: against
        # origin/main the branch changes src, against main it would change CLAUDE.md alone.
        def plant(case):
            case.settle()
            case.git("checkout", "-q", "main")
            commit_new_file(case, "src/planted.gleam")
            set_origin_main(case, "main~1")
            case.git("checkout", "-q", "feature")
            case.git("reset", "-q", "--hard", "main")
            commit_new_file(case, "CLAUDE.md")

        self.assert_every_part(scoped_run("light-origin-main", plant), "src/planted.gleam")

    def test_a_git_diff_that_fails_runs_every_part_and_says_so(self):
        # What git diff would have listed is src/planted.gleam; ls-files alone lists a light file.
        def plant(case):
            plant_failing_git(case)
            commit_new_file(case, "src/planted.gleam")
            (case.repository / "CLAUDE.md").write_text("# not committed\n")

        run = scoped_run("light-diff-fails", plant, PLANT_GIT_FAILS="diff")
        self.assert_every_part(run, "git diff")

    def test_a_git_ls_files_that_fails_runs_every_part_and_says_so(self):
        # What git ls-files would have listed is src/planted.gleam; diff alone lists a light file.
        def plant(case):
            plant_failing_git(case)
            commit_new_file(case, "CLAUDE.md")
            (case.repository / "src" / "planted.gleam").write_text("// not committed\n")

        run = scoped_run("light-ls-files-fails", plant, PLANT_GIT_FAILS="ls-files")
        self.assert_every_part(run, "git ls-files")


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
        self.assertEqual(runs[0], "gleam test -- --workers %s GENESIS_TEST_SKIP_SERIAL=1 GENESIS_TEST_SKIP_WORLD_DATA=1" % TEST_WORKERS)
        self.assertEqual(runs[1], "gleam test -- --tag serial GENESIS_TEST_SKIP_SERIAL= GENESIS_TEST_SKIP_WORLD_DATA=")

    def test_a_failure_in_the_serial_run_fails_the_gleam_test_part(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'if [ "$*" = "test -- --tag serial" ]; then exit 1; fi\nif [ "$1" = test ] &&'))

        run = shared_run("serial-fails", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")

    def test_the_fast_check_runs_no_serial_run(self):
        self.assertFalse([c for c in shared_run("fast", "fast").commands if "--tag serial" in c])


REGION = 1024 * 1024 * 1024


def literal_limit_percent() -> int:
    """The share of the literal region the check allows, as the check states it."""
    found = re.findall(r"(?m)^literal_limit_percent=(\d+)$", CHECK.read_text())
    assert len(found) == 1, found
    return int(found[0])


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class LiteralAreaTest(unittest.TestCase):
    """The persistent terms of a test run live in a literal region of 1 GiB, and a
    run that fills it dies partway (`literal_alloc: Cannot allocate`). The full
    check reads the highest carriers size the run recorded and fails over a share
    of the region, so the margin cannot vanish unnoticed again.

    The planted `gleam test` writes PLANT_LITERAL_PEAK bytes into the file it is
    given, as the real test run does."""

    def at(self, peak: int, **settings: str) -> Run:
        return shared_run("literal-%s-%s" % (peak, sorted(settings.items())), PLANT_LITERAL_PEAK=str(peak), **settings)

    def limit(self) -> int:
        return REGION * literal_limit_percent() // 100

    def test_a_run_whose_peak_is_under_the_limit_passes_and_prints_its_share(self):
        peak = self.limit() // 2
        run = self.at(peak)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.done.stdout, r"(?m)^  literal-area +ok\b")
        tenths = peak * 1000 // REGION
        self.assertRegex(
            run.done.stdout,
            r"(?m)^  literal area: peak %d MiB of 1024 MiB \(%d\.%d%%\), limit %d%%$"
            % (peak // 2**20, tenths // 10, tenths % 10, literal_limit_percent()),
        )

    def test_a_run_whose_peak_is_exactly_the_limit_passes(self):
        run = self.at(self.limit())
        self.assertEqual(run.done.returncode, 0, run.output)

    def test_a_run_whose_peak_is_one_byte_over_the_limit_fails_the_check_naming_the_part(self):
        run = self.at(self.limit() + 1)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bliteral-area\b")
        self.assertIn("over the limit of %d%%" % literal_limit_percent(), run.output)

    def test_a_run_that_fills_the_region_fails_the_check_with_the_part_and_the_other_parts_still_pass(self):
        run = self.at(REGION * 99 // 100)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: literal-area$")

    def test_a_run_that_wrote_no_peak_fails_the_check_naming_the_part(self):
        run = shared_run("literal-no-file", PLANT_LITERAL_PEAK="none")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bliteral-area\b")
        self.assertIn("wrote no literal area peak", run.output)

    def test_a_larger_region_set_through_any_erlang_flags_variable_fails_the_check_since_the_limit_is_a_share_of_the_default(self):
        for variable in ("ERL_FLAGS", "ERL_AFLAGS", "ERL_ZFLAGS", "ELIXIR_ERL_OPTIONS"):
            with self.subTest(variable=variable):
                run = shared_run("literal-miscs-" + variable, **{variable: "+MIscs 4096"})
                self.assertRegex(failed_line(self, run.output), r"\bliteral-area\b")
                self.assertIn("+MIscs", run.output)

    def test_only_the_first_test_run_is_given_the_file(self):
        run = self.at(1)
        peak_log = [line for line in run.peak.splitlines() if line.startswith("gleam test")]
        self.assertEqual(
            peak_log,
            ["gleam test -- --workers %s peak_file=given" % TEST_WORKERS, "gleam test -- --tag serial peak_file="],
        )

    def world_data_at(self, test_run_peak: int, world_data_peak) -> Run:
        return shared_run(
            "literal-world-%s-%s" % (test_run_peak, world_data_peak), client=True,
            PLANT_LITERAL_PEAK=str(test_run_peak), PLANT_WORLD_DATA_LITERAL_PEAK=str(world_data_peak), **WORLD_DATA)

    def test_the_world_data_runs_peak_is_measured_in_its_own_region_and_printed_beside_the_first_runs(self):
        first, world = self.limit() // 2, self.limit() // 3
        run = self.world_data_at(first, world)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("literal area: peak %d MiB of 1024 MiB" % (first // 2**20), run.done.stdout)
        self.assertIn("literal area of the world-data run: peak %d MiB of 1024 MiB" % (world // 2**20), run.done.stdout)

    def test_a_world_data_run_over_the_limit_fails_the_part_though_the_first_run_is_under_it(self):
        run = self.world_data_at(self.limit() // 2, self.limit() + 1)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: literal-area$")
        self.assertIn("over the limit of %d%%" % literal_limit_percent(), run.output)

    def test_a_first_run_over_the_limit_fails_the_part_though_the_world_data_run_is_under_it(self):
        run = self.world_data_at(self.limit() + 1, self.limit() // 2)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: literal-area$")

    def test_a_world_data_run_that_wrote_no_peak_fails_the_part_naming_the_run(self):
        run = self.world_data_at(self.limit() // 2, "none")
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: literal-area$")
        self.assertIn("the world-data run wrote no literal area peak", run.output)

    def test_the_first_run_and_the_world_data_run_are_given_the_file_and_the_serial_run_is_not(self):
        run = shared_run("world-data-on", client=True, **WORLD_DATA)
        peak_log = sorted(line for line in run.peak.splitlines() if line.startswith("gleam test"))
        self.assertEqual(peak_log, sorted([
            "gleam test -- --workers %s peak_file=given" % TEST_WORKERS,
            "gleam test -- --tag serial peak_file=",
            "gleam test -- --tag world_data peak_file=given"]))

    def test_the_part_is_skipped_when_the_build_it_needs_failed(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))

        run = shared_run("literal-build-fails", prepare=plant)
        self.assertRegex(run.done.stdout, r"(?m)^  literal-area +skipped \(a part it needs failed: gleam-build\)")

    def test_the_fast_check_does_not_measure_the_area(self):
        self.assertNotIn("literal-area", shared_run("fast", "fast").output)


# The worker count the check gives `gleam test` when GENESIS_TEST_WORKERS is not set: 2, from the
# runs posted on the step's issue (full check wall time and literal area peak with 1 and with 2).
# A change of it is a change here with the measurement that justifies it.
TEST_WORKERS = "2"


WORLD_DATA = {"GENESIS_WORLD_DATA": "/planted/world-data"}


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ParallelPartsTest(unittest.TestCase):
    """After gleam-build, the parts that read the build run beside the test run: glinter,
    generated-tables, squirrel and the world-data run start while `gleam test` is still
    running, and in the fast check glinter runs beside the code-rule tests. The planted
    `gleam test` (PLANT_RENDEZVOUS) waits for each of them to have started and fails
    when one has not, so what is tested is the order of the parts, not their times. The
    planted gleam ends the wait on an event, never on a clock, but gives up after 30
    seconds so a part run after the tests fails the run instead of hanging it."""

    def test_the_full_check_starts_glinter_generated_tables_squirrel_and_the_world_data_run_while_the_test_run_is_running(self):
        run = shared_run("rendezvous-full", client=True, PLANT_RENDEZVOUS="1", **WORLD_DATA)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^  gleam-test +ok\b")
        self.assertNotIn("had not started", run.output)

    def test_the_fast_check_starts_glinter_while_the_code_rule_tests_are_running(self):
        run = shared_run("rendezvous-fast", "fast", PLANT_RENDEZVOUS="1")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^  code-rules +ok\b")

    def test_a_test_run_that_has_a_part_it_should_run_beside_unstarted_fails_the_planted_check(self):
        # The planted tool's own control: with the world-data run never started (no
        # GENESIS_WORLD_DATA here), the rendezvous cannot be met, and the test run fails
        # naming it, so a pass above means every part had started.
        run = shared_run("rendezvous-unmet", client=True, timeout=60, PLANT_RENDEZVOUS="1")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")
        self.assertIn("world_data had not started", run.output)

    def test_the_part_list_has_no_message_codec_part_and_runs_no_generate_messages(self):
        run = shared_run("full")
        self.assertNotIn("message-codec", run.output)
        self.assertFalse([c for c in run.commands if "generate_messages" in c], run.commands)

    def test_the_full_check_lists_every_part_once_in_order(self):
        run = shared_run("full")
        self.assertEqual(
            [part for part in parts_reported(run.output) if part != "branch-current"], EVERY_PART)

    def test_the_parts_that_read_the_build_are_skipped_when_the_build_fails(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))

        run = shared_run("build-fails-all", prepare=plant)
        self.assertNotIn("gleam run -m squirrel check", run.commands)
        for part in ("glinter", "generated-tables", "gleam-test", "world-data", "literal-area", "squirrel"):
            with self.subTest(part=part):
                self.assertRegex(run.output, r"(?m)^  %s +skipped \(a part it needs failed: gleam-build\)" % part)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class WorldDataPartTest(unittest.TestCase):
    """The world-data test (tagged world_data, about a minute alone) is a part of its own:
    one run of `gleam test -- --tag world_data` where the test can run, the test run
    that has the other tests skips it, and a failure fails the world-data part and
    no other."""

    def test_where_it_can_run_the_part_runs_the_tagged_test_alone_and_the_other_run_skips_it(self):
        run = shared_run("world-data-on", client=True, **WORLD_DATA)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^  world-data +ok\b")
        runs = {line.split(" GENESIS_TEST_SKIP_SERIAL")[0]: line for line in run.environment.splitlines() if line.startswith("gleam test")}
        self.assertEqual(sorted(runs), sorted([
            "gleam test -- --workers %s" % TEST_WORKERS, "gleam test -- --tag serial", "gleam test -- --tag world_data"]))
        self.assertIn("GENESIS_TEST_SKIP_WORLD_DATA=1", runs["gleam test -- --workers %s" % TEST_WORKERS])
        for tagged in ("gleam test -- --tag serial", "gleam test -- --tag world_data"):
            self.assertTrue(runs[tagged].endswith("GENESIS_TEST_SKIP_WORLD_DATA="), runs[tagged])

    def test_without_the_client_the_part_is_skipped_and_its_run_never_starts(self):
        run = shared_run("full")
        self.assertRegex(run.output, r"(?m)^  world-data +skipped \(")
        self.assertFalse([c for c in run.commands if "--tag world_data" in c], run.commands)

    def test_without_the_world_database_variable_the_part_is_skipped(self):
        run = shared_run("world-data-no-variable", client=True)
        self.assertRegex(run.output, r"(?m)^  world-data +skipped \(")
        self.assertFalse([c for c in run.commands if "--tag world_data" in c], run.commands)

    def test_a_failing_world_data_run_fails_that_part_and_no_other(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'if [ "$*" = "test -- --tag world_data" ]; then exit 1; fi\nif [ "$1" = test ] &&'))

        run = shared_run("world-data-fails", client=True, prepare=plant, **WORLD_DATA)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: world-data$")

    def test_a_failure_of_the_other_tests_does_not_fail_the_world_data_part(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'if [ "$*" = "test -- --tag serial" ]; then exit 1; fi\nif [ "$1" = test ] &&'))

        run = shared_run("serial-fails-with-world-data", client=True, prepare=plant, **WORLD_DATA)
        self.assertRegex(run.output, r"(?m)^  world-data +ok\b")
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: gleam-test$")

    def test_the_fast_check_does_not_run_it(self):
        self.assertFalse([c for c in shared_run("fast", "fast").commands if "world_data" in c])



@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class WorkerCountTest(unittest.TestCase):
    """The worker count is one setting of the check."""

    def test_the_setting_is_given_to_the_test_run_as_the_worker_count(self):
        run = shared_run("workers-3", GENESIS_TEST_WORKERS="3")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("gleam test -- --workers 3", run.commands)

    def test_without_the_setting_the_test_run_has_two_workers(self):
        run = shared_run("full")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("gleam test -- --workers 2", run.commands)
        self.assertFalse([c for c in run.commands if re.fullmatch(r"gleam test -- --workers (?!2$)\d+", c)], run.commands)


class FactFileMergeTest(unittest.TestCase):
    """The fact file merges by union (.gitattributes): every step appends its records at
    the end, so two branches' records would otherwise conflict on every merge."""

    FACT_FILE = ".claude/skills/decoding-the-client/references/client-facts.toml"

    def test_the_fact_file_merges_by_union(self):
        result = subprocess.run(
            ["git", "check-attr", "merge", "--", self.FACT_FILE],
            cwd=REPOSITORY, capture_output=True, text=True, check=True,
        )
        self.assertEqual(result.stdout.strip(), f"{self.FACT_FILE}: merge: union")

    def test_two_branches_appending_records_merge_without_a_conflict(self):
        base = '["a"]\nstatement = "a"\n'
        ours = base + '\n["b"]\nstatement = "b"\n'
        theirs = base + '\n["c"]\nstatement = "c"\n'
        with tempfile.TemporaryDirectory() as folder:
            files = {}
            for name, text in (("base", base), ("ours", ours), ("theirs", theirs)):
                files[name] = Path(folder) / name
                files[name].write_text(text)
            plain = subprocess.run(
                ["git", "merge-file", "-p", str(files["ours"]), str(files["base"]), str(files["theirs"])],
                capture_output=True, text=True,
            )
            self.assertEqual(plain.returncode, 1, "without union the two appends conflict")
            union = subprocess.run(
                ["git", "merge-file", "-p", "--union", str(files["ours"]), str(files["base"]), str(files["theirs"])],
                capture_output=True, text=True, check=True,
            )
        self.assertEqual(set(tomllib.loads(union.stdout)), {"a", "b", "c"})


if __name__ == "__main__":
    unittest.main()
