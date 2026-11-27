"""./check: what the script does with the parts it runs, tested on a planted repository.

Each test copies ./check and setup_check/environment.sh into a temporary
repository and runs that copy with a PATH of planted tools, so no test touches
the real toolchain, the real database or the real client:

- ./setup-check is a stub that succeeds (after PLANT_SETUP_SECONDS, when set), or
  fails when PLANT_SETUP_FAILS is set;
- `gleam` and `psql` are stubs that write their command line to PLANT_LOG and
  succeed (the `psql` that drops the database takes PLANT_PSQL_DROP_SECONDS
  first, when set, and the one that creates it takes PLANT_PSQL_CREATE_SECONDS
  first, when set, and fails when PLANT_PSQL_CREATE_FAILS is set; `gleam format` takes PLANT_FORMAT_SECONDS, or ends its own
  shell without a word when PLANT_FORMAT_KILLS_PARENT is set), except that `gleam format --check` fails when a file under src,
  test or dev holds PLANTED_FORMAT_ERROR, and any `gleam` run of tests (a `test`
  or a `run -m` of a module other than glinter, squirrel and table_generator)
  fails, when it runs the tests tagged code_rule (a run with no `--tag`, or
  `--tag code_rule`), when a file under test/code_rule holds PLANTED_BREACH, and,
  when it runs the tests tagged registry (a run with no `--tag`, or `--tag
  registry`), when a file under test holds PLANTED_REGISTRY_FAILURE; a test run
  takes PLANT_GLEAM_TEST_SECONDS and dies by signal 6 (after it listed its tests) when
  PLANT_GLEAM_TEST_ABORTS is set, and `gleam run -m glinter` takes
  PLANT_GLINTER_SECONDS; with
  PLANT_RENDEZVOUS set, the plain test run (`gleam test -- --workers N`) waits until
  glinter, table_generator, squirrel, the world-data run and the boot-test run have each started, so a part
  that is not run beside the test run makes it fail;
- `erl` is a stub that stands in for the VM the check starts on the built code
  (run_built): it writes its whole command line to PLANT_LOG.erl, turns it into the
  `gleam test -- ARGS` or `gleam run -m MODULE ARGS` the program is, and runs the `gleam`
  stub on that with PLANT_AS=built, so every behaviour above applies to it and the
  commands log shows `built test -- ARGS` for a start of the built code and
  `gleam ...` only for what compiles; a test run given `--reporter table` prints the
  rows planted for it in $PLANT_LOG.table.workers (the run with workers) or
  $PLANT_LOG.table.serial, in unitest's own layout, and then unitest's `N passed` line
  (N is PLANT_PASSED_FIRST for the run with no tag, PLANT_PASSED_SERIAL for the serial run,
  PLANT_PASSED_GAPS for the run of the tag gaps, PLANT_PASSED_CODE_RULE for the tag code_rule);
  a run given GENESIS_TEST_DIRECTORY lists what that folder holds in $PLANT_LOG.shard (a run of
  a tag but gaps and code_rule does not);
- `python3.13` is the real one, except for the run the stub stands in for:
  check_facts.py, which succeeds at once, and fails when the fact file holds
  PLANTED_FACT_ERROR;
- the client query process's scripts are the real check_support.py (with the
  query_client.py and ghidra_env.py it imports) and formulas_by_hand.py with
  one planted test file whose test is gated by
  check_support.integration_only, so the gate is the real one.

- the planted repository is a git repository on a branch `feature` of `main`
  (the planted files are the first commit), because branch-current and the
  scope compare the branch with its merge base with main.

A planted run costs about two seconds, so tests that only read what one run
printed or logged share it (`shared_run`), the whole file stays under a minute,
and tests of what does not depend on the parts' work run `./check fast`, which
has six parts instead of all of them.

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
PYTHON = shutil.which("python3.13")

RUNNABLE = PYTHON is not None and shutil.which("bash") is not None and CHECK.is_file()

# The commands `gleam run -m MODULE` the check makes that are not a run of tests.
NOT_TEST_RUNS = ("glinter", "squirrel", "genesis_prime/table_generator")

GLEAM_STUB = """#!/bin/sh
as=${PLANT_AS:-gleam}
echo "$as $*" >>"$PLANT_LOG"
echo "$as $* GENESIS_TEST_SKIP_SERIAL=$GENESIS_TEST_SKIP_SERIAL GENESIS_TEST_SKIP_WORLD_DATA=$GENESIS_TEST_SKIP_WORLD_DATA GENESIS_TEST_SKIP_REAL_START=$GENESIS_TEST_SKIP_REAL_START GENESIS_TEST_SKIP_CLIENT_ROWS=$GENESIS_TEST_SKIP_CLIENT_ROWS GENESIS_TEST_SKIP_REAL_TABLES=$GENESIS_TEST_SKIP_REAL_TABLES" >>"$PLANT_LOG.environment"
echo "$as $* directory=$GENESIS_TEST_DIRECTORY" >>"$PLANT_LOG.directory"
[ -z "$DATABASE_URL" ] || echo "$as $* url=$DATABASE_URL" >>"$PLANT_LOG.url"
if [ -n "$PLANT_RENDEZVOUS" ]; then
  rendezvous="$PLANT_LOG.rendezvous"
  mkdir -p "$rendezvous"
  await() {
    for name in "$@"; do
      waited=0
      until [ -f "$rendezvous/$name" ]; do
        sleep 0.1
        waited=$((waited + 1))
        if [ "$waited" -gt "${PLANT_RENDEZVOUS_POLLS:-300}" ]; then
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
    "test -- --tag real_start") touch "$rendezvous/real_start" ;;
    "test -- --tag real_tables") touch "$rendezvous/real_tables" ;;
    "test -- --workers "*) await glinter table_generator squirrel world_data real_start real_tables ;;
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
      glinter) [ -n "$PLANT_GLINTER_SECONDS" ] && sleep "$PLANT_GLINTER_SECONDS" ;;
    esac
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
  echo "$as $* peak_file=${GENESIS_LITERAL_PEAK_FILE:+given}" >>"$PLANT_LOG.peak"
  # A run given a shard's folder (GENESIS_TEST_DIRECTORY), and the runs of the tests tagged gaps
  # and code_rule, lists what the folder holds when it starts: `link PATH TARGET` for each symlink to a file that exists, `stray PATH` for
  # anything else, PATH below the folder.
  if [ -n "$GENESIS_TEST_DIRECTORY" ]; then
    case "$*" in
      *"--tag gaps"*) listed=yes ;;
      *"--tag code_rule"*) listed=yes ;;
      *"--tag"*) listed= ;;
      *) listed=yes ;;
    esac
    case "$listed" in
      "") ;;
      *)
        # One write, since the runs of the fast check start together and append to the same file.
        block=$(
          echo "shard $GENESIS_TEST_DIRECTORY"
          [ -d "$GENESIS_TEST_DIRECTORY" ] || echo "missing $GENESIS_TEST_DIRECTORY"
          find "$GENESIS_TEST_DIRECTORY" ! -type d 2>/dev/null | sort | while read -r entry; do
            relative=${entry#"$GENESIS_TEST_DIRECTORY"/}
            if [ -L "$entry" ] && [ -f "$entry" ]; then
              echo "link $relative $(readlink "$entry")"
            else
              echo "stray $relative"
            fi
          done
        )
        printf '%%s\n' "$block" >>"$PLANT_LOG.shard"
        ;;
    esac
  fi
  # unitest's last line: the count of the tests that passed (PLANT_PASSED_FIRST for the run
  # with no tag, PLANT_PASSED_SERIAL for the serial run), and the skipped ones.
  case "$*" in
    *"--tag serial"*) passed=${PLANT_PASSED_SERIAL:-3} ;;
    *"--tag gaps"*) passed=${PLANT_PASSED_GAPS:-1} ;;
    *"--tag code_rule"*) passed=${PLANT_PASSED_CODE_RULE:-1} ;;
    *"--tag"*) passed=1 ;;
    *) passed=${PLANT_PASSED_FIRST:-12} ;;
  esac
  if [ "$passed" = 0 ]; then
    echo "0 passed, no failures, 4 skipped"
  else
    echo "$passed passed, no failures"
  fi
  # A run with the table reporter prints the rows planted for it: the file
  # $PLANT_LOG.table.workers for the run with workers, .table.serial for the serial run,
  # in unitest's own layout (`| PASS | module | test | 67ms |`).
  case "$*" in
    *"--reporter table"*)
      case "$*" in
        *--workers*) rows="$PLANT_LOG.table.workers" ;;
        *) rows="$PLANT_LOG.table.serial" ;;
      esac
      echo "+--------+--------+------+----------+"
      echo "| Status | Module | Test | Duration |"
      echo "+--------+--------+------+----------+"
      [ -f "$rows" ] && cat "$rows"
      echo "+--------+--------+------+----------+"
      ;;
  esac
  # The run keeps the literal allocator's highest carriers size in the file it is
  # given, as test/genesis_prime_test.gleam does; PLANT_LITERAL_PEAK is that many
  # bytes, and "none" writes no file.
  # PLANT_<TAG>_LITERAL_PEAK (PLANT_WORLD_DATA_LITERAL_PEAK) is the same for the run of
  # that tag alone.
  peak="${PLANT_LITERAL_PEAK:-100000000}"
  case "$*" in
    *"--tag "*)
      arguments="$*"
      tag=$(echo "${arguments##*--tag }" | cut -d' ' -f1 | tr a-z A-Z)
      peak=$(printenv "PLANT_${tag}_LITERAL_PEAK" || echo "$peak")
      ;;
  esac
  if [ -n "$GENESIS_LITERAL_PEAK_FILE" ] && [ "$peak" != none ]; then
    echo "$peak" >"$GENESIS_LITERAL_PEAK_FILE"
  fi
fi
if [ "$*" = "test -- --tag client_rows" ] && [ -n "$PLANT_CLIENT_ROWS_FAILS" ]; then
  echo "planted stale client rows"
  exit 1
fi
# PLANT_LISTED_TESTS lists tests as test/test_progress.gleam does, in the file the run is
# given (GENESIS_TEST_PROGRESS_FILE): one that began 7 seconds ago and ended, one that
# began 5 seconds ago and has not ended; with "ended" only the first.
if [ "$1" = test ] && [ -n "$PLANT_LISTED_TESTS" ] && [ -n "$GENESIS_TEST_PROGRESS_FILE" ]; then
  now=$(date +%%s)
  printf 'start 1.1 %%s planted_test:one_that_ended_test\nend 1.1\n' $((now - 7)) >>"$GENESIS_TEST_PROGRESS_FILE"
  [ "$PLANT_LISTED_TESTS" = ended ] || printf 'start 1.2 %%s planted_test:one_that_hung_test\n' $((now - 5)) >>"$GENESIS_TEST_PROGRESS_FILE"
fi
# PLANT_GLEAM_TEST_ABORTS: the run dies by signal 6, as the VM does when it aborts, after it has listed its tests.
if [ "$1" = test ] && [ -n "$PLANT_GLEAM_TEST_ABORTS" ]; then
  kill -ABRT $$
  sleep 5
fi
if [ "$1" = test ] && [ -n "$PLANT_GLEAM_TEST_SECONDS" ]; then
  sleep "$PLANT_GLEAM_TEST_SECONDS"
fi
# A run with no --tag runs every test not skipped; a tagged run runs the tests of its tag.
runs_tag() {
  tag=$1
  shift
  [ "$1" = test ] || return 1
  case "$*" in
    *"--tag $tag"*) return 0 ;;
    *"--tag"*) return 1 ;;
  esac
  return 0
}
if runs_tag registry "$@" && grep -rq PLANTED_REGISTRY_FAILURE test 2>/dev/null; then
  echo "planted registry test failure"
  exit 1
fi
if runs_tag gaps "$@" && grep -rq PLANTED_GAP_FAILURE test 2>/dev/null; then
  echo "planted gap test failure"
  exit 1
fi
if runs_tag code_rule "$@" && grep -rq PLANTED_BREACH test/code_rule 2>/dev/null; then
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

ERL_STUB = """#!/bin/sh
echo "erl $*" >>"$PLANT_LOG.erl"
module=
while [ $# -gt 0 ]; do
  case "$1" in
    -eval) module=$2; shift 2 ;;
    -extra) shift; break ;;
    *) shift ;;
  esac
done
module=${module#*:run(}
module=$(echo "${module%%)*}" | tr @ /)
if [ "$module" = genesis_prime_test ]; then
  if [ $# -gt 0 ]; then set -- test -- "$@"; else set -- test; fi
else
  set -- run -m "$module" "$@"
fi
PLANT_AS=built exec "$(dirname "$0")/gleam" "$@"
"""

PYTHON_STUB = """#!/bin/sh
echo "python3.13 $*" >>"$PLANT_LOG"
case "$*" in
  *check_facts.py*)
    grep -q PLANTED_FACT_ERROR .claude/skills/decoding-the-client/references/client-facts.toml 2>/dev/null && { echo "planted fact-file error"; exit 1; }
    exit 0 ;;
  *client_files.py*) [ -n "$PLANT_TOKENS_STALE" ] && exit 1; exit 0 ;;
esac
exec "$PLANT_REAL_PYTHON" "$@"
"""

SETUP_CHECK_STUB = """#!/bin/sh
[ -n "$PLANT_SETUP_SECONDS" ] && sleep "$PLANT_SETUP_SECONDS"
if [ -n "$PLANT_SETUP_FAILS" ]; then
  echo "planted setup check failure"
  exit 1
fi
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
        (repository / "test" / "code_rule" / "planted_test.gleam").write_text('// a code-rule test, which names the tags "gaps" and "code_rule"\n')
        scripts = repository / SCRIPTS
        scripts.mkdir(parents=True)
        for name in ("check_support.py", "query_client.py", "ghidra_env.py", "formulas_by_hand.py"):
            shutil.copyfile(REPOSITORY / SCRIPTS / name, scripts / name)
        self.plant_integration_test(fails=False)
        tools = self.root / "tools"
        executable(tools / "gleam", GLEAM_STUB)
        executable(tools / "erl", ERL_STUB)
        for package in ("alpha", "beta"):
            (repository / "build" / "dev" / "erlang" / package / "ebin").mkdir(parents=True)
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

    def side_log(self, suffix: str) -> str:
        """A stub's side log, empty when it wrote none: `environment` holds the gleam
        commands with the value of GENESIS_TEST_SKIP_SERIAL each saw, `peak` the test
        commands with whether each was given the literal peak file, `erl` the
        command line of each start of the built code, as the erl stub saw it, `directory`
        the shard folder each was given, `shard` the listing of that folder, and `url`
        the DATABASE_URL of each command that had one."""
        path = Path(str(self.log) + "." + suffix)
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
    erl: str
    took: float
    marker_ran: bool
    hang: str
    left_running: list[str]
    directory: str
    shard: str
    url: str

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
        run = Run(
            done, case.commands(), case.side_log("environment"), case.side_log("peak"), case.side_log("erl"), took,
            case.marker.exists(), seconds, left,
            case.side_log("directory"), case.side_log("shard"), case.side_log("url"),
        )
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
        for arguments in (("everything",), ("part",)):
            with self.subTest(arguments=arguments):
                run = shared_run("usage-" + "-".join(arguments), *arguments)
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
        for part in ("gleam-build", "glinter", "fact-checker"):
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
    is the margin a loaded machine needs. The budgets the check has when none is set
    are the measured ones, below."""

    # The slowest of 3 full checks on the idle development Mac, with the parts beside
    # each other and 2 test workers, was 125 s, times 1.25, rounded up; the fast
    # check's slowest of 3 warm runs was 35 s, rounded up to 5 s.
    FULL_BUDGET = 157
    FAST_BUDGET = 35

    def test_the_budgets_the_check_has_when_none_is_set_are_the_measured_ones(self):
        for name, args, budget in (("full", (), self.FULL_BUDGET), ("fast", ("fast",), self.FAST_BUDGET)):
            with self.subTest(check=name):
                run = shared_run(name, *args)
                self.assertRegex(run.output, r"(?m)^check passed.*, budget %ds$" % budget)

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
        self.assertIn("built run -m squirrel check", run.commands)
        self.assertRegex(run.output, r"(?m)^  squirrel +ok\b")

    def test_squirrel_is_skipped_when_the_migrations_part_fails(self):
        run = shared_run("failing-migrations", prepare=self.quick_polls, PLANT_PSQL_CREATE_FAILS="1")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bmigrations\b")
        self.assertNotIn("built run -m squirrel check", run.commands)
        self.assertRegex(run.output, r"(?m)^  squirrel +skipped \(a part it needs failed: migrations\)")

    def test_a_part_run_over_its_budget_passes_with_the_warning(self):
        run = shared_run("slow-part-run", "part", "format", GENESIS_CHECK_BUDGET_SECONDS="3", PLANT_FORMAT_SECONDS="4")
        self.assert_passed_with_the_warning(run, budget=3)

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
    check fails naming it.

    A hang is a planted `sleep` of 600 seconds and a fraction unique to the run. The
    budget is 2 seconds, so the hang is ended at 6."""

    BUDGET = 2

    def assert_stopped_as_hung(self, run: Run, part: str | None, budget: int = BUDGET) -> None:
        output = run.output
        self.assertNotEqual(run.done.returncode, 0, output)
        # That the hang was stopped is shown by the run having ended inside shared_run's
        # timeout, far below the planted 600 s sleep (run_check fails the test naming the
        # check that had not ended), by the failure naming the hang, and by nothing of
        # the sleep left running. There is no upper bound on the run's time: run.took
        # also counts the harness planting the repository before the check starts, and
        # the check stopping and cleaning up after its deadline (the 1 s grace, the
        # drop's 30 polls of `sleep 0.1`), which a loaded machine lengthens, so an upper
        # bound would measure the machine.
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
        wall = re.search(r"wall time (\d+)s, budget %ds" % budget, output)
        self.assertTrue(wall, "the check prints its wall time and budget")
        # The check's own clock: the watchdog fires no earlier than three times the budget.
        self.assertGreaterEqual(int(wall.group(1)), 3 * budget, "the check was stopped before three times its budget")
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

    def test_a_gleam_run_that_hangs_is_stopped_with_what_it_started(self):
        # The sleep is a grandchild of the check: its subshell runs `gleam`, which runs it.
        run = shared_run(
            "hung-gleam", "fast", hang=lambda seconds: dict(PLANT_GLINTER_SECONDS=seconds), timeout=40,
            GENESIS_CHECK_FAST_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_as_hung(run, "glinter")

    def hung_test_run(self, listed: str | None) -> Run:
        """The first test run hangs after listing tests (`listed`: "ended" lists one that
        ended and one that did not, "ended" alone one that ended, none lists nothing)."""
        settings = dict(GENESIS_CHECK_BUDGET_SECONDS=str(self.BUDGET))
        if listed:
            settings["PLANT_LISTED_TESTS"] = listed
        return shared_run(
            "hung-test-run-%s" % listed, hang=lambda seconds: dict(PLANT_GLEAM_TEST_SECONDS=seconds),
            timeout=40, **settings,
        )

    def assert_test_run_hung(self, run: Run) -> None:
        """The check failed, and the gleam-test part's line says it hung. (The summary
        line also names the literal-area part, which never started: it follows the tests.)"""
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"gleam-test hung, still running at three times its budget of %ds" % self.BUDGET)
        part_line = next(line for line in run.output.splitlines() if line.strip().startswith("gleam-test "))
        self.assertRegex(part_line, r"FAILED\s+hung")
        self.assertEqual(run.left_running, [], "the planted sleep is still running")

    def still_running_lines(self, run: Run) -> list[str]:
        return [line.strip() for line in run.output.splitlines() if "still running:" in line]

    def test_a_test_run_that_hangs_names_the_tests_that_began_and_did_not_end(self):
        run = self.hung_test_run("hung")
        self.assert_test_run_hung(run)
        lines = self.still_running_lines(run)
        self.assertEqual(len(lines), 1, "only the unfinished test is named:\n" + run.output)
        # The planted test began 5 seconds before the run's own list was read, and the
        # check reads it when the hang stops it, 6 seconds into the run or later.
        self.assertRegex(lines[0], r"^still running: planted_test:one_that_hung_test \((\d+) s\)$")
        self.assertGreaterEqual(int(re.search(r"\((\d+) s\)", lines[0]).group(1)), 5)
        part_line_index = run.output.splitlines().index(next(l for l in run.output.splitlines() if l.strip().startswith("gleam-test ")))
        self.assertIn("still running:", run.output.splitlines()[part_line_index + 1], "the names follow the part's line")

    def test_a_test_run_that_hangs_with_every_listed_test_ended_says_it_hung_outside_a_test(self):
        run = self.hung_test_run("ended")
        self.assert_test_run_hung(run)
        self.assertEqual(self.still_running_lines(run), ["still running: no test was running: the run hung outside a test"])

    def test_a_test_run_that_hangs_before_listing_a_test_says_none_had_started(self):
        run = self.hung_test_run(None)
        self.assert_test_run_hung(run)
        self.assertEqual(self.still_running_lines(run), ["still running: no test had started"])

    def test_a_part_that_is_not_a_test_run_is_named_without_tests(self):
        self.assertEqual(self.still_running_lines(self.part_and_drop()), [])

    def test_a_part_run_whose_part_hangs_is_stopped_at_three_times_the_budget_and_named(self):
        run = shared_run(
            "hung-part-run-glinter", "part", "glinter", hang=lambda seconds: dict(PLANT_GLINTER_SECONDS=seconds), timeout=40,
            GENESIS_CHECK_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_as_hung(run, "glinter")
        self.assertEqual(self.still_running_lines(run), [])
        # A shard's hang names the tests that had started and not ended, as the full check's does.
        run = shared_run(
            "hung-part-run-shard", "part", "gleam-test", "1/3", timeout=40,
            hang=lambda seconds: dict(PLANT_GLEAM_TEST_SECONDS=seconds, PLANT_LISTED_TESTS="hung"),
            GENESIS_CHECK_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_as_hung(run, "gleam-test")
        self.assertRegex(self.still_running_lines(run)[0], r"^still running: planted_test:one_that_hung_test \(\d+ s\)$")

    def test_a_setup_check_that_hangs_is_stopped_at_three_times_the_budget(self):
        run = shared_run(
            "hung-setup", "fast", hang=lambda seconds: dict(PLANT_SETUP_SECONDS=seconds), timeout=40,
            GENESIS_CHECK_FAST_BUDGET_SECONDS=str(self.BUDGET),
        )
        self.assert_stopped_as_hung(run, None)
        self.assertEqual(run.commands, [], "no part ran after a setup check that did not end")

    def test_a_database_drop_that_hangs_does_not_hold_a_check_that_ended_in_time(self):
        run = shared_run(
            "hung-drop-in-time", hang=lambda seconds: dict(PLANT_PSQL_DROP_SECONDS=seconds), timeout=30,
        )
        self.assertEqual(run.done.returncode, 0, run.output)
        # Ending inside the 30 s timeout, against a planted drop of 600 s and a default
        # budget far above 30 s, shows the check did not wait for the drop. A bound
        # tighter than the timeout would measure the machine's speed.
        self.assertEqual(run.left_running, [], "the planted sleep is still running")


class AbortedTestRunTest(unittest.TestCase):
    def test_a_run_the_vm_aborts_names_the_tests_it_had_started(self):
        run = shared_run(
            "aborted-test-run", timeout=40,
            PLANT_LISTED_TESTS="hung", PLANT_GLEAM_TEST_ABORTS="1",
        )
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"gleam-test")
        lines = [line.strip() for line in run.output.splitlines() if "still running:" in line]
        self.assertEqual(len(lines), 1, "only the unfinished test is named:\n" + run.output)
        self.assertRegex(lines[0], r"^still running: planted_test:one_that_hung_test \(\d+ s\)$")
        self.assertIn("signal 6", run.output, "the abort is named by its signal")


def plant_failing_gated_test(case: PlantedCheckCase) -> None:
    case.plant_integration_test(fails=True)


def part_line(output: str, part: str) -> str:
    """The line of the summary that names the part, or an empty string."""
    return next((line for line in output.splitlines() if part in line), "")


def set_origin_main(case: PlantedCheckCase, revision: str) -> None:
    """Makes `origin/main` the planted repository's commit at `revision`, as a fetch would."""
    case.git("update-ref", "refs/remotes/origin/main", case.git("rev-parse", revision))


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ClientSuiteTest(unittest.TestCase):
    """The client-suite part runs the client scripts' tests that need no Ghidra with
    GENESIS_INTEGRATION=0, whatever the caller exported: an exported GENESIS_INTEGRATION=1
    would open the gate of check_support.integration_only and run the Ghidra tests inside
    the client-suite part, in the usual budget."""

    def gate_holds(self, key: str, client: bool) -> Run:
        return shared_run(key, client=client, prepare=plant_failing_gated_test, GENESIS_INTEGRATION="1")

    def assert_gate_held(self, run: Run) -> None:
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertFalse(run.marker_ran, "an integration test ran inside the client-suite part")
        self.assertRegex(run.output, r"(?m)^  client-suite +ok\b")

    def test_an_exported_genesis_integration_does_not_open_the_gate_of_the_unit_suite(self):
        self.assert_gate_held(self.gate_holds("gate-no-client", client=False))

    def test_with_the_client_the_part_also_checks_the_committed_token_list(self):
        run = shared_run("tokens-on", client=True)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("python3.13 -I .claude/skills/decoding-the-client/scripts/client_files.py tokens --check", run.commands)

    def test_without_the_client_the_token_list_is_not_checked(self):
        run = shared_run("full")
        self.assertFalse([c for c in run.commands if "client_files.py" in c], run.commands)

    def test_with_the_client_the_part_runs_the_client_rows_test_and_the_first_test_run_skips_it(self):
        run = shared_run("tokens-on", client=True)
        self.assertEqual(run.done.returncode, 0, run.output)
        runs = [line for line in run.environment.splitlines() if line.startswith("built test")]
        self.assertIn("built test -- --tag client_rows GENESIS_TEST_SKIP_SERIAL= GENESIS_TEST_SKIP_WORLD_DATA= GENESIS_TEST_SKIP_REAL_START= GENESIS_TEST_SKIP_CLIENT_ROWS= GENESIS_TEST_SKIP_REAL_TABLES=", runs)
        self.assertIn("GENESIS_TEST_SKIP_CLIENT_ROWS=1", next(line for line in runs if "--workers" in line))

    def test_without_the_client_the_client_rows_test_never_starts(self):
        run = shared_run("full")
        self.assertFalse([c for c in run.commands if "--tag client_rows" in c], run.commands)

    def test_a_failing_client_rows_test_fails_the_client_suite_part_and_no_other(self):
        run = shared_run("client-rows-fails", client=True, PLANT_CLIENT_ROWS_FAILS="1")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: client-suite$")

    def test_a_stale_token_list_fails_the_client_suite_part_and_no_other(self):
        run = shared_run("tokens-stale", client=True, PLANT_TOKENS_STALE="1")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: client-suite$")


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
    warnings as errors, glinter, the runs of the tests tagged gaps and code_rule and
    the fact checker, and nothing else: no other run of tests, so none of the tests
    tagged registry that are not also tagged gaps.

    The planted `gleam` stands for the tools: it fails the format check on a
    planted format error, the gap tests on a planted gap-test failure, the code-rule
    tests on a planted breach and the fact checker on a planted fact-file error.
    What these tests hold is that the fast check runs each of those six and fails,
    naming the part, when one fails."""

    def test_a_planted_format_error_fails_the_fast_check_naming_the_format_part(self):
        run = shared_run("fast-format-error", "fast", prepare=lambda case: (case.repository / "src" / "planted.gleam").write_text("// PLANTED_FORMAT_ERROR\n"))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bformat\b")

    def test_a_planted_fact_file_error_fails_the_fast_check_naming_the_fact_checker_part(self):
        run = shared_run("fast-fact-error", "fast", prepare=lambda case: plant_fact_file_error(case))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bfact-checker\b")

    def test_a_planted_gap_test_failure_fails_the_fast_check_naming_the_gap_tests_part(self):
        def plant(case):
            (case.repository / "test").mkdir(exist_ok=True)
            (case.repository / "test" / "planted_gaps_test.gleam").write_text("// PLANTED_GAP_FAILURE\n")

        run = shared_run("fast-gap-failure", "fast", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgap-tests\b")
        self.assertNotRegex(failed_line(self, run.output), r"\b(format|glinter|fact-checker)\b")

    def test_a_fast_check_whose_gap_run_counts_no_passed_test_fails_naming_the_gap_tests_part(self):
        run = shared_run("fast-gap-ran-nothing", "fast", PLANT_PASSED_GAPS="0")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgap-tests\b")
        self.assertNotRegex(failed_line(self, run.output), r"\b(format|glinter|fact-checker)\b")
        self.assertIn("no test tagged gaps ran", run.output)

    def test_a_fast_check_in_which_no_test_file_names_the_gaps_tag_fails_naming_the_gap_tests_part(self):
        run = shared_run("fast-no-gap-file", "fast", prepare=lambda case: (case.repository / "test" / "code_rule" / "planted_test.gleam").write_text('// tagged "code_rule" only\n'))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgap-tests\b")
        self.assertNotRegex(failed_line(self, run.output), r"\b(format|glinter|fact-checker|code-rule-tests)\b")
        self.assertIn("no test file names the tag gaps", run.output)

    def test_a_planted_code_rule_breach_fails_the_fast_check_naming_the_code_rule_tests_part(self):
        run = shared_run("fast-breach", "fast", prepare=lambda case: (case.repository / "test" / "code_rule" / "planted_test.gleam").write_text('// PLANTED_BREACH, which names the tags "gaps" and "code_rule"\n'))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bcode-rule-tests\b")
        self.assertNotRegex(failed_line(self, run.output), r"\b(format|glinter|fact-checker|gap-tests)\b")

    def test_a_fast_check_whose_code_rule_run_counts_no_passed_test_fails_naming_the_code_rule_tests_part(self):
        run = shared_run("fast-code-rule-ran-nothing", "fast", PLANT_PASSED_CODE_RULE="0")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bcode-rule-tests\b")
        self.assertNotRegex(failed_line(self, run.output), r"\b(format|glinter|fact-checker|gap-tests)\b")
        self.assertIn("no test tagged code_rule ran", run.output)

    def test_a_fast_check_in_which_no_test_file_names_the_code_rule_tag_fails_naming_the_code_rule_tests_part(self):
        run = shared_run("fast-no-code-rule-file", "fast", prepare=lambda case: (case.repository / "test" / "code_rule" / "planted_test.gleam").write_text('// tagged "gaps" only\n'))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bcode-rule-tests\b")
        self.assertIn("no test file names the tag code_rule", run.output)

    def test_the_code_rule_tests_read_a_folder_holding_the_files_that_name_the_tag_and_no_other(self):
        def plant(case):
            for name, text in (("code_rule/named_test", '// tagged "code_rule"\n'), ("spells/also_named_test", '// "code_rule"\n'), ("other_test", "// a test\n")):
                file = case.repository / "test" / (name + ".gleam")
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text)

        run = shared_run("fast-code-rule-folder", "fast", prepare=plant)
        self.assertEqual(run.done.returncode, 0, run.output)
        held = sorted(path for path, _ in shard_listing(run, "code-rule-tests"))
        self.assertEqual(held, ["code_rule/named_test.gleam", "code_rule/planted_test.gleam", "spells/also_named_test.gleam"])
        for path, target in shard_listing(run, "code-rule-tests"):
            self.assertRegex(target, r"^/.*/test/%s$" % re.escape(path), "each link goes to the file at its own path below test")
        self.assertIn("build/chosen_tests/code-rule-tests/test", set(directories_given(run).values()))

    def test_the_gap_tests_read_a_folder_holding_the_files_that_name_the_tag_and_no_other(self):
        def plant(case):
            for name, text in (("named_test", '// tagged "gaps"\n'), ("spells/also_named_test", '// "gaps"\n'), ("other_test", "// a test\n")):
                file = case.repository / "test" / (name + ".gleam")
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text)

        run = shared_run("fast-gap-folder", "fast", prepare=plant)
        self.assertEqual(run.done.returncode, 0, run.output)
        held = sorted(path for path, _ in shard_listing(run, "gap-tests"))
        self.assertEqual(held, ["code_rule/planted_test.gleam", "named_test.gleam", "spells/also_named_test.gleam"])
        for path, target in shard_listing(run, "gap-tests"):
            self.assertRegex(target, r"^/.*/test/%s$" % re.escape(path), "each link goes to the file at its own path below test")
        self.assertIn("build/chosen_tests/gap-tests/test", set(directories_given(run).values()))

    def test_the_fast_check_runs_the_six_parts_and_no_other(self):
        run = shared_run("fast", "fast")
        self.assertEqual(run.done.returncode, 0, run.output)
        listed = re.findall(r"^\s*([a-z-]+)\s+(?:ok|FAILED)\b", run.output, re.MULTILINE)
        self.assertEqual(sorted(listed), ["code-rule-tests", "fact-checker", "format", "gap-tests", "gleam-build", "glinter"])
        commands = run.commands
        self.assertTrue(any(c.startswith("gleam format --check") for c in commands), commands)
        self.assertIn("gleam build --warnings-as-errors", commands)
        self.assertLess(
            commands.index("gleam build --warnings-as-errors"), commands.index("built run -m glinter"),
            "glinter runs on the built code, after gleam-build")
        self.assertFalse(foreign_commands(commands), commands)
        self.assertIn(FACT_CHECKER_COMMAND, commands)
        for module in NOT_TEST_RUNS:
            if module != "glinter":
                self.assertFalse([c for c in commands if module in c], commands)

    def test_the_fast_check_runs_the_tests_tagged_gaps_and_code_rule_and_no_other_test(self):
        run = shared_run("fast", "fast")
        tests = [c for c in run.commands if c.startswith("built test")]
        self.assertEqual(sorted(tests), ["built test -- --tag code_rule --no-color", "built test -- --tag gaps --no-color"], "the other tests run in the full check")
        for command in tests:
            self.assertLess(
                run.commands.index("gleam build --warnings-as-errors"), run.commands.index(command),
                "the tests run on the built code, after gleam-build")

    def test_a_failing_build_fails_the_fast_check_naming_it(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))

        run = shared_run("fast-build-fails", "fast", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"gleam-build")
        self.assertRegex(
            run.output, r"(?m)^  glinter +skipped \(a part it needs failed: gleam-build\)")
        self.assertFalse([c for c in run.commands if c.startswith("built ")], run.commands)


FACT_FILE = ".claude/skills/decoding-the-client/references/client-facts.toml"
FACT_CHECKER_COMMAND = "python3.13 -I .claude/skills/decoding-the-client/scripts/check_facts.py"


def plant_fact_file_error(case: PlantedCheckCase) -> None:
    fact_file = case.repository / FACT_FILE
    fact_file.parent.mkdir(parents=True, exist_ok=True)
    fact_file.write_text("# PLANTED_FACT_ERROR\n")


def foreign_commands(commands: list[str]) -> list[str]:
    """The psql and python3.13 commands that are not the fact checker's call (its own script,
    and on a machine with the client the `-c` lookup of the client's path before it)."""
    return [
        c for c in commands
        if c.startswith(("psql", "python3.13")) and c not in (FACT_CHECKER_COMMAND, "python3.13 -I -c ")
    ]


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
    "format", "gleam-build", "glinter", "generated-tables", "gleam-test", "real-start", "real-tables", "world-data", "literal-area",
    "migrations", "squirrel", "client-suite", "fact-checker",
]
QUICK_PARTS = ["format", "gleam-build", "glinter", "fact-checker"]

# Files that guidance and untested tools are made of (the issue's light set), one per entry.
LIGHT_FILES = [
    "CLAUDE.md",
    ".claude/skills/writing-tests/SKILL.md",
    ".claude/skills/designing-processes/structure.md",
    ".claude/agents/implementer.md",
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
    changed file, or none at all, runs every part. CI's machine always runs every part."""

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
        self.assertFalse(foreign_commands(run.commands), run.commands)
        self.assertEqual([c for c in run.commands if c.startswith("built test")], [], "no test run, the gap tests' and the code-rule tests' either")

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

    def test_the_workflow_that_runs_the_parts_is_not_light_since_only_its_own_run_tests_it(self):
        run = scoped_run("not-light-workflow", lambda case: plant_light_changes(case, ["CLAUDE.md", ".github/workflows/check.yml"]))
        self.assert_every_part(run, ".github/workflows/check.yml")

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


def scope_run(key: str, base: str, prepare, **settings: str) -> Run:
    """A planted `./check scope BASE`, on CI's machine (no client, GITHUB_ACTIONS set)."""
    return shared_run("scope-" + key, "scope", base, prepare=prepare, GITHUB_ACTIONS="true", **settings)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ScopeModeTest(unittest.TestCase):
    """`./check scope BASE` is how CI's pull request run tells a light change from any other: it
    reads the files changed since BASE against the light set, prints the one `scope:` line the
    full check prints, and ends with 0 for a light change and 1 for any other case. It runs
    on CI's machine, which the full check's own scope never reads as light, and starts nothing
    else: no setup check, no part."""

    def test_the_scope_mode_names_a_light_change_by_its_exit_status_and_every_other_case_by_the_reason(self):
        def plant_other(case):
            plant_light_changes(case, ["CLAUDE.md", "src/planted.gleam"])

        def plant_workflow(case):
            plant_light_changes(case, ["CLAUDE.md", ".github/workflows/check.yml"])

        # (key, base, prepare, exit status, the line the output holds, why)
        rows = [
            ("light", "main", plant_light_changes, 0, "scope: light", "every changed file is in the light set"),
            ("other", "main", plant_other, 1, "scope: every part, because the branch changes src/planted.gleam", "one file is not light"),
            ("workflow", "main", plant_workflow, 1, "scope: every part, because the branch changes .github/workflows/check.yml", "the workflow is tested by its own run"),
            ("nothing", "HEAD", plant_light_changes, 1, "scope: every part, because the branch changes no file", "no file changed since BASE"),
            ("bad-base", "no-such-revision", plant_light_changes, 1, "git diff failed", "a base git cannot find: the files are not known"),
        ]
        for key, base, prepare, status, line, why in rows:
            with self.subTest(why):
                run = scope_run(key, base, prepare)
                self.assertEqual(run.done.returncode, status, run.output)
                self.assertIn(line, run.output)
                self.assertEqual(scope_line(run.output).count("\n"), 0, "one scope line")
                self.assertEqual(run.commands, [], "no part and no setup check ran")
                self.assertNotIn("setup check passed", run.output)

    def test_the_scope_mode_without_a_base_is_refused_with_the_usage(self):
        run = shared_run("scope-no-base", "scope")
        self.assertEqual(run.done.returncode, 2, run.output)
        self.assertIn("usage", run.output.lower())
        self.assertEqual(run.commands, [])


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
    runs only them one at a time (the tests started with `--tag serial`)."""

    def test_the_full_check_runs_the_serial_tests_in_a_second_run_one_at_a_time(self):
        suites = [c for c in shared_run("full").commands if c.startswith("built test")]
        self.assertEqual(suites, [FIRST_RUN, SERIAL_RUN])

    def test_the_run_of_the_other_tests_skips_the_serial_ones(self):
        runs = [line for line in shared_run("full").environment.splitlines() if line.startswith("built test")]
        self.assertEqual(runs[0], "%s GENESIS_TEST_SKIP_SERIAL=1 GENESIS_TEST_SKIP_WORLD_DATA=1 GENESIS_TEST_SKIP_REAL_START=1 GENESIS_TEST_SKIP_CLIENT_ROWS=1 GENESIS_TEST_SKIP_REAL_TABLES=1" % FIRST_RUN)
        self.assertEqual(runs[1], "%s GENESIS_TEST_SKIP_SERIAL= GENESIS_TEST_SKIP_WORLD_DATA= GENESIS_TEST_SKIP_REAL_START= GENESIS_TEST_SKIP_CLIENT_ROWS= GENESIS_TEST_SKIP_REAL_TABLES=" % SERIAL_RUN)

    def test_a_failure_in_the_serial_run_fails_the_gleam_test_part(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'case "$*" in "test -- --tag serial"*) exit 1 ;; esac\nif [ "$1" = test ] &&'))

        run = shared_run("serial-fails", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")

    def test_the_fast_check_runs_no_serial_run(self):
        self.assertFalse([c for c in shared_run("fast", "fast").commands if "--tag serial" in c])


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class CodeRuleAndRegistryTestsTest(unittest.TestCase):
    """The tests tagged `code_rule` and `registry` are not a part of their own: the
    full check's gleam-test part runs them, in the run that skips no tag of theirs.
    The planted `gleam` fails a run that runs a tag's tests (no `--tag` at all, or
    that tag) when the planted breach of that tag is present."""

    def test_a_planted_code_rule_breach_fails_the_full_check_naming_the_gleam_test_part(self):
        run = shared_run("full-breach", prepare=lambda case: (case.repository / "test" / "code_rule" / "planted_test.gleam").write_text("// PLANTED_BREACH\n"))
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")

    def test_a_planted_failing_registry_test_fails_the_full_check_naming_the_gleam_test_part(self):
        def plant(case):
            (case.repository / "test").mkdir(exist_ok=True)
            (case.repository / "test" / "planted_registry_test.gleam").write_text("// PLANTED_REGISTRY_FAILURE\n")

        run = shared_run("full-registry-failure", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")

    def test_the_full_check_lists_no_part_of_their_own_for_them(self):
        run = shared_run("full")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertNotRegex(run.output, r"(?m)^  (code-rules|registry-tests)\b")


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
    check reads the highest carriers size the run recorded and warns over a share
    of the region, so the margin cannot vanish unnoticed again. The limit is on the
    harness's own memory, so the part is `ok` and the check passes whatever the
    peak, a missing peak file or +MIscs: only a `check WARNING` line differs.

    The planted `gleam test` writes PLANT_LITERAL_PEAK bytes into the file it is
    given, as the real test run does."""

    def at(self, peak: int, **settings: str) -> Run:
        return shared_run("literal-%s-%s" % (peak, sorted(settings.items())), PLANT_LITERAL_PEAK=str(peak), **settings)

    def limit(self) -> int:
        return REGION * literal_limit_percent() // 100

    def assert_part_ok(self, run: Run) -> None:
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.done.stdout, r"(?m)^  literal-area +ok\b")
        self.assertRegex(run.done.stdout, r"(?m)^check passed\b")

    def warnings(self, run: Run) -> list:
        """The summary's warning lines, the budget's apart."""
        return [line for line in run.done.stdout.splitlines()
                if line.startswith("check WARNING: ") and not WARNING.match(line)]

    def test_a_run_whose_peak_is_under_the_limit_passes_and_prints_its_share(self):
        peak = self.limit() // 2
        run = self.at(peak)
        self.assert_part_ok(run)
        self.assertEqual(self.warnings(run), [])
        tenths = peak * 1000 // REGION
        self.assertRegex(
            run.done.stdout,
            r"(?m)^  literal area: peak %d MiB of 1024 MiB \(%d\.%d%%\), limit %d%%$"
            % (peak // 2**20, tenths // 10, tenths % 10, literal_limit_percent()),
        )

    def test_a_run_whose_peak_is_exactly_the_limit_passes_without_a_warning(self):
        run = self.at(self.limit())
        self.assert_part_ok(run)
        self.assertEqual(self.warnings(run), [])

    def test_a_run_whose_peak_is_over_the_limit_passes_the_check_with_a_warning_and_still_prints_its_share(self):
        for peak in (self.limit() + 1, REGION * 99 // 100):
            with self.subTest(peak=peak):
                run = self.at(peak)
                self.assert_part_ok(run)
                self.assertRegex(run.done.stdout, r"(?m)^  literal area: peak %d MiB of 1024 MiB" % (peak // 2**20))
                (warning,) = self.warnings(run)
                self.assertTrue(warning.startswith("check WARNING: literal area over %d%% of its region: " % literal_limit_percent()), warning)

    def test_a_run_that_wrote_no_peak_passes_the_check_with_a_warning(self):
        run = shared_run("literal-no-file", PLANT_LITERAL_PEAK="none")
        self.assert_part_ok(run)
        (warning,) = self.warnings(run)
        self.assertTrue(warning.startswith("check WARNING: no literal area peak recorded: the test run wrote none"), warning)

    def test_a_larger_region_set_through_any_erlang_flags_variable_passes_the_check_with_a_warning(self):
        for variable in ("ERL_FLAGS", "ERL_AFLAGS", "ERL_ZFLAGS", "ELIXIR_ERL_OPTIONS"):
            with self.subTest(variable=variable):
                run = shared_run("literal-miscs-" + variable, **{variable: "+MIscs 4096"})
                self.assert_part_ok(run)
                (warning,) = self.warnings(run)
                self.assertTrue(warning.startswith("check WARNING: +MIscs set in "), warning)

    def test_only_the_first_test_run_is_given_the_file(self):
        run = self.at(1)
        peak_log = [line for line in run.peak.splitlines() if line.startswith("built test")]
        self.assertEqual(
            peak_log,
            ["%s peak_file=given" % FIRST_RUN, "%s peak_file=" % SERIAL_RUN],
        )

    def part_at(self, part: str, test_run_peak: int, part_peak) -> Run:
        """A run in which the part's run (and only it) peaks at part_peak, the others at the first run's."""
        variable = "PLANT_%s_LITERAL_PEAK" % part.replace("-", "_").upper()
        return shared_run(
            "literal-%s-%s-%s" % (part, test_run_peak, part_peak), client=True,
            PLANT_LITERAL_PEAK=str(test_run_peak), **{variable: str(part_peak)}, **WORLD_DATA)

    def test_the_runs_that_hold_the_whole_client_tables_or_the_world_database_record_a_peak(self):
        # Each such VM holds the persistent terms of the tables and what the tests derive from
        # them, in a literal region the first run's peak does not include.
        self.assertTrue({"real-tables", "world-data"} <= set(parts_with_a_peak()), parts_with_a_peak())

    def test_a_tagged_runs_peak_is_measured_in_its_own_region_and_printed_beside_the_first_runs(self):
        for part in parts_with_a_peak():
            with self.subTest(part=part):
                first, own = self.limit() // 2, self.limit() // 3
                run = self.part_at(part, first, own)
                self.assertEqual(run.done.returncode, 0, run.output)
                self.assertIn("literal area: peak %d MiB of 1024 MiB" % (first // 2**20), run.done.stdout)
                self.assertIn("literal area of the %s run: peak %d MiB of 1024 MiB" % (part, own // 2**20), run.done.stdout)

    def test_a_tagged_run_over_the_limit_warns_naming_the_run_though_the_first_run_is_under_it(self):
        for part in parts_with_a_peak():
            with self.subTest(part=part):
                run = self.part_at(part, self.limit() // 2, self.limit() + 1)
                self.assert_part_ok(run)
                (warning,) = self.warnings(run)
                self.assertTrue(warning.startswith("check WARNING: literal area of the %s run over %d%% of its region" % (part, literal_limit_percent())), warning)

    def test_a_first_run_over_the_limit_warns_though_the_tagged_runs_are_under_it(self):
        under = {"PLANT_%s_LITERAL_PEAK" % tag.upper(): str(self.limit() // 2) for part, tag in tagged_parts() if part in parts_with_a_peak()}
        run = shared_run("literal-first-over", client=True, PLANT_LITERAL_PEAK=str(self.limit() + 1), **under, **WORLD_DATA)
        self.assert_part_ok(run)
        (warning,) = self.warnings(run)
        self.assertTrue(warning.startswith("check WARNING: literal area over %d%% of its region" % literal_limit_percent()), warning)

    def test_a_tagged_run_that_wrote_no_peak_warns_naming_the_run(self):
        for part in parts_with_a_peak():
            with self.subTest(part=part):
                run = self.part_at(part, self.limit() // 2, "none")
                self.assert_part_ok(run)
                (warning,) = self.warnings(run)
                self.assertTrue(warning.startswith("check WARNING: no literal area peak recorded: the %s run wrote none" % part), warning)

    def test_the_first_run_and_the_runs_of_the_parts_with_a_peak_are_given_the_file_and_no_other_run_is(self):
        run = shared_run("world-data-on", client=True, **WORLD_DATA)
        peak_log = sorted(line for line in run.peak.splitlines() if line.startswith("built test"))
        self.assertEqual(peak_log, sorted(
            ["%s peak_file=given" % FIRST_RUN, "%s peak_file=" % SERIAL_RUN, "built test -- --tag client_rows peak_file="]
            + ["built test -- --tag %s peak_file=%s" % (tag, "given" if part in parts_with_a_peak() else "")
               for part, tag in tagged_parts()]))

    def test_the_part_is_skipped_when_the_build_it_needs_failed(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))

        run = shared_run("literal-build-fails", prepare=plant)
        self.assertRegex(run.done.stdout, r"(?m)^  literal-area +skipped \(a part it needs failed: gleam-build\)")

    def test_the_fast_check_does_not_measure_the_area(self):
        self.assertNotIn("literal-area", shared_run("fast", "fast").output)


# The worker count the check gives `gleam test` when GENESIS_TEST_WORKERS is not set: 2, from runs
# of the full check with 1 and with 2 (its wall time and literal area peak). A change of it is a
# change here with the measurement that justifies it.
TEST_WORKERS = "2"

# The two runs of the gleam-test part, as the check starts them: the unitest table reporter
# prints each test's duration, which the summary adds up per module.
FIRST_RUN = "built test -- --workers %s --reporter table --no-color" % TEST_WORKERS
SERIAL_RUN = "built test -- --tag serial --reporter table --no-color"


WORLD_DATA = {"GENESIS_WORLD_DATA": "/planted/world-data"}


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ParallelPartsTest(unittest.TestCase):
    """After gleam-build, the parts that read the build run beside the test run: glinter,
    generated-tables, squirrel, the world-data run and the boot-test run start while `gleam test` is still
    running. The planted
    `gleam test` (PLANT_RENDEZVOUS) waits for each of them to have started and fails
    when one has not, so what is tested is the order of the parts, not their times. The
    planted gleam ends the wait on an event, never on a clock, but gives up after 300
    polls of 0.1 s (PLANT_RENDEZVOUS_POLLS) so a part run after the tests fails the run
    instead of hanging it; the control test, which must reach that, sets 100 polls, a
    sixth of its 60 s run timeout."""

    def test_the_full_check_starts_glinter_generated_tables_squirrel_the_world_data_run_and_the_boot_test_run_while_the_test_run_is_running(self):
        run = shared_run("rendezvous-full", client=True, PLANT_RENDEZVOUS="1", **WORLD_DATA)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^  gleam-test +ok\b")
        self.assertNotIn("had not started", run.output)

    def test_a_test_run_that_has_a_part_it_should_run_beside_unstarted_fails_the_planted_check(self):
        # The planted tool's own control: with the world-data run never started (no
        # GENESIS_WORLD_DATA here), the rendezvous cannot be met, and the test run fails
        # naming it, so a pass above means every part had started.
        run = shared_run("rendezvous-unmet", client=True, timeout=60, PLANT_RENDEZVOUS="1", PLANT_RENDEZVOUS_POLLS="100")
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
        self.assertNotIn("built run -m squirrel check", run.commands)
        for part in ("glinter", "generated-tables", "gleam-test", "real-start", "real-tables", "world-data", "literal-area", "squirrel"):
            with self.subTest(part=part):
                self.assertRegex(run.output, r"(?m)^  %s +skipped \(a part it needs failed: gleam-build\)" % part)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class BuiltCodeTest(unittest.TestCase):
    """After gleam-build no part compiles again. gleam rewrites every package's .app file
    on each `gleam build`, `gleam run` and `gleam test`, even with nothing changed (gleam
    1.19.2), and a test VM that is loading its applications while another gleam rewrites
    them reads an empty file and dies at start (the first gleam-test run of CI run
    42349388041). So each part that follows gleam-build starts the built code itself
    (run_built), the way gleam does: erl with `-pa` for each package's ebin, `-eval
    genesis_prime@@main:run(MODULE)`, `-noshell` and the program's arguments after
    `-extra`, which is where the argv package reads them (seen with a spy erl on PATH
    under `gleam run` and `gleam test`)."""

    COMPILING = re.compile(r"gleam (build|run|test)\b")

    def compiles_after_the_build(self, commands: list[str]) -> list[str]:
        build = commands.index("gleam build --warnings-as-errors")
        return [c for c in commands[build + 1:] if self.COMPILING.match(c)]

    def test_after_gleam_build_the_full_check_starts_every_part_on_the_built_code_and_compiles_nothing(self):
        run = shared_run("world-data-on", client=True, **WORLD_DATA)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertEqual(self.compiles_after_the_build(run.commands), [])
        self.assertEqual(
            sorted(c for c in run.commands if c.startswith("built ")),
            sorted([
                "built run -m glinter",
                "built run -m genesis_prime/table_generator check",
                "built run -m squirrel check",
                FIRST_RUN,
                SERIAL_RUN,
                "built test -- --tag client_rows",
                "built test -- --tag real_start",
                "built test -- --tag real_tables",
                "built test -- --tag world_data",
            ]))

    def test_after_gleam_build_the_fast_check_starts_every_part_on_the_built_code_and_compiles_nothing(self):
        run = shared_run("fast", "fast")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertEqual(self.compiles_after_the_build(run.commands), [])
        self.assertEqual(
            sorted(c for c in run.commands if c.startswith("built ")),
            ["built run -m glinter", "built test -- --tag code_rule --no-color", "built test -- --tag gaps --no-color"])

    def test_a_part_is_started_with_the_packages_built_and_its_arguments_after_extra(self):
        lines = [line for line in shared_run("full").erl.splitlines() if line.endswith("--tag serial --reporter table --no-color")]
        self.assertEqual(len(lines), 1, lines)
        self.assertRegex(
            lines[0],
            r"^erl -pa /\S+/build/dev/erlang/alpha/ebin -pa /\S+/build/dev/erlang/beta/ebin"
            r" -eval genesis_prime@@main:run\(genesis_prime_test\) -noshell -extra --tag serial --reporter table --no-color$")

    def test_a_part_that_takes_no_arguments_is_started_with_none_after_extra(self):
        lines = [line for line in shared_run("full").erl.splitlines() if "run(glinter)" in line]
        self.assertEqual(len(lines), 1, lines)
        self.assertTrue(lines[0].endswith("-noshell -extra"), lines[0])

    def test_a_started_part_that_fails_fails_that_part_and_no_other(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'case "$1" in\n  format)', 'if [ "$*" = "run -m glinter" ]; then exit 3; fi\ncase "$1" in\n  format)'))

        run = shared_run("glinter-fails", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: glinter$")


ERLANG_ENTRY = """-module('genesis_prime@@main').
-export([run/1]).
run(Module) ->
    Arguments = init:get_plain_arguments(),
    io:format("~w ~p~n", [Module, Arguments]),
    halt(case Arguments of ["fail" | _] -> 7; _ -> 0 end).
"""


@unittest.skipUnless(RUNNABLE and shutil.which("erlc") and shutil.which("erl"), "needs bash, erl and erlc here")
class RunBuiltOnRealErlangTest(unittest.TestCase):
    """run_built on the real erl, against a planted entry module `genesis_prime@@main`:
    the module atom and the arguments reach the program as gleam's reach it, and the
    program's exit status is the function's."""

    def run_built(self, *arguments: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory(prefix="genesis-run-built-") as folder:
            root = Path(folder)
            ebin = root / "build" / "dev" / "erlang" / "genesis_prime" / "ebin"
            ebin.mkdir(parents=True)
            source = root / "genesis_prime@@main.erl"
            source.write_text(ERLANG_ENTRY)
            subprocess.run(["erlc", "-o", str(ebin), str(source)], check=True, capture_output=True)
            function = re.search(r"(?ms)^run_built\(\) \{.*?^\}$", CHECK.read_text())
            assert function, "run_built is defined in ./check"
            return subprocess.run(
                ["bash", "-c", function.group(0) + '\nrun_built "$@"', "run_built", *arguments],
                cwd=root, capture_output=True, text=True,
            )

    def test_the_module_path_and_the_arguments_reach_the_program(self):
        done = self.run_built("genesis_prime/table_generator", "check", "--tag", "serial")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, 'genesis_prime@table_generator ["check","--tag","serial"]\n')

    def test_a_module_without_a_folder_and_no_arguments_reach_the_program_as_they_are(self):
        done = self.run_built("glinter")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, "glinter []\n")

    def test_the_exit_status_of_the_program_is_the_functions(self):
        self.assertEqual(self.run_built("glinter", "fail").returncode, 7)


def tagged_parts() -> list[tuple[str, str]]:
    """The parts that run the tests of one tag alone, as (part, tag), as the check lists them."""
    found = re.findall(r'(?m)^tagged_parts="([^"]*)"$', CHECK.read_text())
    assert len(found) == 1, found
    return [(part, part.replace("-", "_")) for part in found[0].split()]


def parts_with_a_peak() -> list[str]:
    """The tagged parts whose VM records a literal area peak, as the check lists them."""
    found = re.findall(r'(?m)^tagged_parts_with_a_peak="([^"]*)"$', CHECK.read_text())
    assert len(found) == 1, found
    return found[0].split()


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class TaggedPartTest(unittest.TestCase):
    """The tests that need a VM of their own or the client's whole tables are parts of the
    full check beside gleam-test, one per tag: one run of the tests started with
    `--tag TAG` where the part can run, the test runs that have the other tests skip that
    tag, a failure fails that part and no other, and the fast check runs none of them.
    Each rule is run over every part the check lists in `tagged_parts`."""

    def check_the_part_runs_its_tag_alone_and_the_other_runs_skip_it(self, part: str, tag: str) -> None:
        run = shared_run("world-data-on", client=True, **WORLD_DATA)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^  %s +ok\b" % part)
        runs = {line.split(" GENESIS_TEST_SKIP_SERIAL")[0]: line for line in run.environment.splitlines() if line.startswith("built test")}
        own_run = "built test -- --tag " + tag
        variable = "GENESIS_TEST_SKIP_" + tag.upper()
        self.assertIn(variable + "=1", runs[FIRST_RUN])
        for tagged in (SERIAL_RUN, own_run):
            self.assertIn(variable + "=", runs[tagged])
            self.assertNotIn(variable + "=1", runs[tagged])

    def check_the_fast_check_does_not_run_the_part(self, part: str, tag: str) -> None:
        self.assertIn("built test -- --tag " + tag, shared_run("world-data-on", client=True, **WORLD_DATA).commands, "the full check runs the part")
        for name, run in (("fast", shared_run("fast", "fast")), ("light", scoped_run("light-only", plant_light_changes))):
            with self.subTest(scope=name):
                self.assertFalse([c for c in run.commands if tag in c], run.commands)
                self.assertNotIn(part, parts_reported(run.output))

    def test_real_tables_part_runs_the_tagged_tests_and_gleam_test_skips_them(self):
        self.check_the_part_runs_its_tag_alone_and_the_other_runs_skip_it("real-tables", "real_tables")

    def test_real_tables_part_is_not_in_the_fast_check(self):
        self.check_the_fast_check_does_not_run_the_part("real-tables", "real_tables")

    def test_every_tagged_part_runs_its_tag_alone_and_the_other_runs_skip_it(self):
        for part, tag in tagged_parts():
            with self.subTest(part=part):
                self.check_the_part_runs_its_tag_alone_and_the_other_runs_skip_it(part, tag)

    def test_the_full_check_runs_the_first_run_the_serial_run_the_client_rows_and_one_run_per_tagged_part(self):
        run = shared_run("world-data-on", client=True, **WORLD_DATA)
        runs = [line.split(" GENESIS_TEST_SKIP_SERIAL")[0] for line in run.environment.splitlines() if line.startswith("built test")]
        self.assertEqual(sorted(runs), sorted(
            [FIRST_RUN, SERIAL_RUN, "built test -- --tag client_rows"] + ["built test -- --tag " + tag for _, tag in tagged_parts()]))
        self.assertEqual(directories_given(run), {}, "no run of the full check is given a shard's folder")

    def test_every_tagged_part_is_a_part_of_the_full_check(self):
        for part, _ in tagged_parts():
            self.assertIn(part, EVERY_PART)

    def test_the_fast_check_does_not_run_a_tagged_part(self):
        for part, tag in tagged_parts():
            with self.subTest(part=part):
                self.check_the_fast_check_does_not_run_the_part(part, tag)

    def test_without_the_client_a_tagged_part_is_skipped_and_its_run_never_starts(self):
        run = shared_run("full")
        for part, tag in tagged_parts():
            with self.subTest(part=part):
                self.assertRegex(run.output, r"(?m)^  %s +skipped \(" % part)
                self.assertFalse([c for c in run.commands if "--tag " + tag in c], run.commands)

    def test_without_the_world_database_only_the_world_data_part_is_skipped(self):
        run = shared_run("tokens-on", client=True)
        for part, tag in tagged_parts():
            with self.subTest(part=part):
                if part == "world-data":
                    self.assertRegex(run.output, r"(?m)^  %s +skipped \(" % part)
                    self.assertFalse([c for c in run.commands if "--tag " + tag in c], run.commands)
                else:
                    self.assertRegex(run.output, r"(?m)^  %s +ok\b" % part)
                    self.assertIn("built test -- --tag " + tag, run.commands)

    def test_a_failing_tagged_run_fails_that_part_and_no_other(self):
        for part, tag in tagged_parts():
            with self.subTest(part=part):
                def plant(case):
                    executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                        'if [ "$1" = test ] &&', 'if [ "$*" = "test -- --tag %s" ]; then exit 1; fi\nif [ "$1" = test ] &&' % tag))

                run = shared_run("%s-fails" % part, client=True, prepare=plant, **WORLD_DATA)
                self.assertNotEqual(run.done.returncode, 0, run.output)
                self.assertRegex(failed_line(self, run.output), r"^check FAILED: %s$" % part)

    def test_a_failure_of_the_other_tests_does_not_fail_a_tagged_part(self):
        def plant(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'case "$*" in "test -- --tag serial"*) exit 1 ;; esac\nif [ "$1" = test ] &&'))

        run = shared_run("serial-fails-with-tagged-parts", client=True, prepare=plant, **WORLD_DATA)
        for part, _ in tagged_parts():
            with self.subTest(part=part):
                self.assertRegex(run.output, r"(?m)^  %s +ok\b" % part)
        self.assertRegex(failed_line(self, run.output), r"^check FAILED: gleam-test$")


def plant_table_rows(case: PlantedCheckCase, run: str, rows: list[tuple[str, str, str, str]]) -> None:
    """Plants the rows the test run `run` ("workers" or "serial") prints in its table:
    (status, module, test, duration as unitest prints it)."""
    text = "".join("| %-6s | %s | %s | %-8s |\n" % row for row in rows)
    Path(str(case.log) + ".table." + run).write_text(text)


# The modules a planted gleam-test part reports: twelve modules of 1 to 12 s in the run with
# workers (m05_test as two tests of 2.0 and 3.5 s, and a skipped test beside them), and the
# serial run adds 15 s to m01_test and 0.5 s to m02_test.
MODULE_ROWS = [("PASS", "m%02d_test" % i, "a_test", "%dms" % (i * 1000)) for i in range(1, 13) if i != 5] + [
    ("PASS", "m05_test", "a_test", "2000ms"),
    ("PASS", "m05_test", "another_test", "3500ms"),
    ("SKIP", "skipped_test", "a_test", "-"),
]
SERIAL_ROWS = [("PASS", "m01_test", "a_serial_test", "15000ms"), ("PASS", "m02_test", "a_serial_test", "500ms")]


def planted_modules(case: PlantedCheckCase) -> None:
    plant_table_rows(case, "workers", MODULE_ROWS)
    plant_table_rows(case, "serial", SERIAL_ROWS)


def slowest_modules(output: str) -> tuple[str, list[tuple[str, str]]]:
    """The list's heading line and its (seconds, module) lines, as the summary prints them."""
    lines = output.splitlines()
    heading = [i for i, line in enumerate(lines) if line.startswith("  slowest test modules")]
    if not heading:
        return "", []
    found = []
    for line in lines[heading[0] + 1:]:
        match = re.fullmatch(r"\s+([\d.]+) s\s+(\S+)", line)
        if not match:
            break
        found.append((match.group(1), match.group(2)))
    return lines[heading[0]], found


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ModuleTimeTest(unittest.TestCase):
    """The gleam-test part's two runs print unitest's table of each test's duration, and the
    summary adds the durations up per test module and lists the ten slowest (a module's
    tests run side by side, so the sum is the module's test time, not the span it took)."""

    def test_the_summary_lists_the_ten_slowest_modules_with_their_tests_added_up_from_both_runs(self):
        run = shared_run("module-times", prepare=planted_modules)
        self.assertEqual(run.done.returncode, 0, run.output)
        heading, found = slowest_modules(run.output)
        self.assertIn("sum of each module's test times", heading)
        self.assertEqual(found, [
            ("16.0", "m01_test"), ("12.0", "m12_test"), ("11.0", "m11_test"), ("10.0", "m10_test"),
            ("9.0", "m09_test"), ("8.0", "m08_test"), ("7.0", "m07_test"), ("6.0", "m06_test"),
            ("5.5", "m05_test"), ("4.0", "m04_test")])
        # The balance of a shard is read from the sum of all its modules, not only the ten printed:
        # 1 to 12 s, m05 as 2.0 + 3.5 s instead of 5, and the serial run's 15.0 + 0.5 s.
        self.assertIn("  total test time: 94.0 s in 12 modules", run.output.splitlines())

    def test_a_skipped_test_adds_no_time_and_its_module_is_not_listed(self):
        def plant(case):
            plant_table_rows(case, "workers", [("PASS", "m01_test", "a_test", "1000ms"), ("SKIP", "skipped_test", "a_test", "-")])

        run = shared_run("module-times-skipped", prepare=plant)
        self.assertEqual(slowest_modules(run.output)[1], [("1.0", "m01_test")])
        self.assertIn("  total test time: 1.0 s in 1 modules", run.output.splitlines())

    def test_the_two_runs_are_started_with_the_table_reporter_and_no_colour(self):
        commands = shared_run("full").commands
        self.assertIn(FIRST_RUN, commands)
        self.assertIn(SERIAL_RUN, commands)

    def test_runs_that_printed_no_rows_leave_the_list_out(self):
        output = shared_run("full").output
        self.assertEqual(slowest_modules(output), ("", []))
        self.assertNotIn("total test time", output)

    def test_a_failing_part_prints_its_failed_rows_and_leaves_out_the_passed_and_skipped_ones(self):
        def plant(case):
            plant_table_rows(case, "workers", MODULE_ROWS + [("FAIL", "m03_test", "a_failing_test", "42ms")])
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] && [ -n "$PLANT_GLEAM_TEST_SECONDS" ]',
                'case "$*" in *"--workers"*) exit 1 ;; esac\nif [ "$1" = test ] && [ -n "$PLANT_GLEAM_TEST_SECONDS" ]'))

        run = shared_run("module-times-fail", prepare=plant)
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertRegex(failed_line(self, run.output), r"\bgleam-test\b")
        self.assertIn("a_failing_test", run.output)
        self.assertNotIn("| PASS", run.output)
        self.assertNotIn("| SKIP", run.output)


def directories_given(run: Run) -> dict[str, str]:
    """The folder each run of the tests was given (GENESIS_TEST_DIRECTORY), by the run's command; runs given none are left out."""
    given = {}
    for line in run.directory.splitlines():
        command, _, directory = line.rpartition(" directory=")
        if directory and command.startswith("built test"):
            given[command] = directory
    return given


def part_run(key: str, *arguments: str, client: bool = False, prepare=None, timeout: float = 120, **settings: str) -> Run:
    """A planted `./check part ARGUMENTS`, shared by every test that asks for the same key."""
    return shared_run("part-" + key, "part", *arguments, client=client, prepare=prepare, timeout=timeout, **settings)


def gleam_commands(commands: list[str]) -> list[str]:
    """The commands the gleam stub saw, sorted: the format and the build, and each start of the built code."""
    return sorted(c for c in commands if c.startswith(("gleam ", "built ")))


def python_commands(commands: list[str]) -> list[str]:
    """The python3.13 commands the check made, sorted, without the fact checker's lookup of the client's path."""
    return sorted(c for c in commands if c.startswith("python3.13 -I") and not c.endswith("-I -c "))


BUILD = "gleam build --warnings-as-errors"
FORMAT = "gleam format --check src test dev"
CLIENT_SUITE_PYTHON = ["python3.13 -I -m unittest discover -s .claude/skills/decoding-the-client/scripts -p test_*.py"]
CLIENT_SUITE_PYTHON_WITH_CLIENT = sorted(
    CLIENT_SUITE_PYTHON + ["python3.13 -I .claude/skills/decoding-the-client/scripts/client_files.py tokens --check"]
)

# Each part of the full check but literal-area, run alone: the arguments, whether the client is
# there, the rows the summary prints (the part and what it needs, in the full check's order), the
# commands of gleam and of the built code, the python commands, and whether a database is made.
# What a part needs is the full check's own order: gleam-build for each part that starts the
# built code (the client-suite part only where the client's rows are read), migrations for squirrel.
PART_RUNS = [
    (("format",), False, ["format"], [FORMAT], [], False),
    (("gleam-build",), False, ["gleam-build"], [BUILD], [], False),
    (("glinter",), False, ["gleam-build", "glinter"], [BUILD, "built run -m glinter"], [], False),
    (
        ("generated-tables",), True, ["gleam-build", "generated-tables"],
        [BUILD, "built run -m genesis_prime/table_generator check"], [], False,
    ),
    (("gleam-test", "1/3"), False, ["gleam-build", "gleam-test"], [BUILD, FIRST_RUN, SERIAL_RUN], [], False),
    (("real-start",), True, ["gleam-build", "real-start"], [BUILD, "built test -- --tag real_start"], [], False),
    (("real-tables",), True, ["gleam-build", "real-tables"], [BUILD, "built test -- --tag real_tables"], [], False),
    (("world-data",), True, ["gleam-build", "world-data"], [BUILD, "built test -- --tag world_data"], [], False),
    (("migrations",), False, ["migrations"], [], [], True),
    (("squirrel",), False, ["gleam-build", "migrations", "squirrel"], [BUILD, "built run -m squirrel check"], [], True),
    (
        ("client-suite",), True, ["gleam-build", "client-suite"], [BUILD, "built test -- --tag client_rows"],
        CLIENT_SUITE_PYTHON_WITH_CLIENT, False,
    ),
    (("client-suite",), False, ["client-suite"], [], CLIENT_SUITE_PYTHON, False),
    (("fact-checker",), False, ["fact-checker"], [], [FACT_CHECKER_COMMAND], False),
]


def part_run_of(arguments: tuple[str, ...], client: bool) -> Run:
    """The shared planted run of one part, with the world database where the part reads it."""
    settings = WORLD_DATA if arguments == ("world-data",) else {}
    key = "%s-%s" % ("-".join(arguments).replace("/", "of"), "client" if client else "none")
    return part_run(key, *arguments, client=client, **settings)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class PartRunTest(unittest.TestCase):
    """`./check part NAME [K/N]` runs one part of the full check alone, with the setup
    check first, the parts it needs, and the full check's budget, hang handling and
    summary. It decides no scope and runs no branch-current."""

    def test_a_part_run_runs_the_part_and_the_parts_it_needs_and_no_other(self):
        for arguments, client, rows, gleam, python, database in PART_RUNS:
            with self.subTest(part=arguments, client=client):
                run = part_run_of(arguments, client)
                self.assertEqual(run.done.returncode, 0, run.output)
                self.assertEqual(parts_reported(run.output), rows, run.output)
                self.assertEqual(gleam_commands(run.commands), sorted(gleam), run.commands)
                self.assertEqual(python_commands(run.commands), sorted(python), run.commands)
                made_a_database = any("create database" in c or "drop database" in c for c in run.commands)
                self.assertEqual(made_a_database, database, run.commands)
                shown = " ".join(arguments)
                self.assertRegex(run.output, r"(?m)^check passed \(part %s\), wall time \d+s, budget \d+s$" % re.escape(shown))
        self.assertRegex(part_run_of(("gleam-test", "1/3"), False).done.stdout, r"(?m)^  gleam-test seeds: 111 222$")

    def test_a_part_run_that_names_no_part_or_a_bad_shard_is_refused_with_the_usage_and_runs_nothing(self):
        for arguments in (
            (), ("nonesuch",), ("literal-area",), ("gap-tests",), ("code-rule-tests",), ("format", "1/3"), ("gleam-test",), ("gleam-test", "0/3"),
            ("gleam-test", "4/3"), ("gleam-test", "a/b"), ("gleam-test", "1/0"), ("gleam-test", "1/3", "x"),
        ):
            with self.subTest(arguments=arguments):
                run = part_run("refused-" + "-".join(arguments).replace("/", "of"), *arguments)
                self.assertEqual(run.done.returncode, 2, run.output)
                self.assertIn("usage", run.output.lower())
                self.assertEqual(run.commands, [])
                self.assertNotIn("setup check passed", run.output)
        # The forms the usage names are not refused.
        for arguments in (("format",), ("gleam-test", "1/3")):
            with self.subTest(arguments=arguments):
                run = part_run_of(arguments, False)
                self.assertEqual(run.done.returncode, 0, run.output)
                self.assertNotIn("usage", run.output.lower())

    def test_a_part_run_starts_with_the_setup_check_and_a_failing_setup_check_runs_no_part(self):
        self.assertIn("setup check passed", part_run_of(("glinter",), False).output)
        run = part_run("setup-fails", "glinter", PLANT_SETUP_FAILS="1")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertIn("check FAILED: the setup check failed", run.output)
        self.assertEqual(run.commands, [], "no part ran")

    def test_a_check_that_ends_while_the_watchdog_is_starting_leaves_no_process_holding_its_output(self):
        # The check's output pipe stays open while any process it started lives on. The
        # setup check fails at once, so the check ends before the watchdog has started its
        # sleep; a slow `date` keeps the watchdog from starting it, and a `ps` that
        # answers late lets it start between the snapshot of what to stop and the kill.
        def plant_slow_date_and_ps(case):
            tools = case.root / "tools"
            executable(tools / "date", '#!/bin/sh\n/bin/sleep 0.3\nexec /bin/date "$@"\n')
            executable(tools / "ps", '#!/bin/sh\n/bin/ps "$@"\n/bin/sleep 0.6\n')

        run = part_run("setup-fails-watchdog-starting", "glinter", prepare=plant_slow_date_and_ps, timeout=30, PLANT_SETUP_FAILS="1")
        self.assertIn("check FAILED: the setup check failed", run.output)

    def test_a_part_run_ignores_the_scope_and_does_not_run_branch_current(self):
        branches = (
            ("guidance-only", plant_light_changes),
            ("behind-origin-main", lambda case: advance_origin_main(case, 2)),
        )
        for name, prepare in branches:
            with self.subTest(branch=name):
                run = part_run("scope-" + name, "glinter", client=True, prepare=prepare)
                self.assertEqual(run.done.returncode, 0, run.output)
                self.assertRegex(scope_line(run.output), r"^scope: part glinter\b")
                self.assertEqual(parts_reported(run.output), ["gleam-build", "glinter"], run.output)
                self.assertIn("built run -m glinter", run.commands)

    def test_a_failed_prerequisite_fails_the_run_naming_it_and_skips_the_part(self):
        def build_fails(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace("build) exit 0", "build) exit 1"))

        run = part_run("build-fails-glinter", "glinter", prepare=build_fails)
        self.assertEqual(failed_line(self, run.output), "check FAILED: gleam-build")
        self.assertRegex(run.output, r"(?m)^  glinter +skipped \(a part it needs failed: gleam-build\)")
        self.assertNotIn("built run -m glinter", run.commands)
        # The client-suite part runs its scripts' tests beside the build, and with the client it fails
        # when the build did, saying the client's rows were not checked.
        run = part_run("build-fails-client-suite-client", "client-suite", client=True, prepare=build_fails)
        self.assertEqual(failed_line(self, run.output), "check FAILED: gleam-build, client-suite")
        self.assertIn("the committed client rows were not checked: gleam-build failed", run.output)
        self.assertEqual(python_commands(run.commands), CLIENT_SUITE_PYTHON_WITH_CLIENT)
        # Without the client it needs no build, so it passes whatever the build does.
        run = part_run("build-fails-client-suite-none", "client-suite", prepare=build_fails)
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertEqual(gleam_commands(run.commands), [])

    def test_a_failed_part_fails_the_run_naming_only_that_part(self):
        run = part_run(
            "format-error", "format",
            prepare=lambda case: (case.repository / "src" / "planted.gleam").write_text("// PLANTED_FORMAT_ERROR\n"))
        self.assertEqual(failed_line(self, run.output), "check FAILED: format")

        def tagged_run_fails(case):
            executable(case.root / "tools" / "gleam", GLEAM_STUB.replace(
                'if [ "$1" = test ] &&', 'if [ "$*" = "test -- --tag real_tables" ]; then exit 1; fi\nif [ "$1" = test ] &&'))

        run = part_run("real-tables-fails", "real-tables", client=True, prepare=tagged_run_fails)
        self.assertEqual(failed_line(self, run.output), "check FAILED: real-tables")

    def test_a_part_run_without_the_client_skips_the_part_the_way_the_full_check_does(self):
        for part in ("generated-tables", "real-start", "real-tables", "world-data"):
            with self.subTest(part=part):
                run = part_run("no-client-" + part, part)
                self.assertEqual(run.done.returncode, 0, run.output)
                self.assertRegex(run.output, r"(?m)^  %s +skipped \(" % part)
                self.assertFalse([c for c in run.commands if "--tag" in c or "table_generator" in c], run.commands)
        run = part_run_of(("client-suite",), False)
        self.assertEqual(python_commands(run.commands), CLIENT_SUITE_PYTHON)
        self.assertFalse([c for c in run.commands if "--tag client_rows" in c], run.commands)

    def test_the_squirrel_part_run_makes_the_migrated_database_first_and_drops_it(self):
        run = part_run_of(("squirrel",), False)
        self.assertEqual(run.done.returncode, 0, run.output)
        commands = run.commands
        created = next(i for i, c in enumerate(commands) if "create database" in c)
        migrated = next(i for i, c in enumerate(commands) if c.startswith("psql") and "schema_migration" in c)
        squirrel = commands.index("built run -m squirrel check")
        dropped = next(i for i, c in enumerate(commands) if "drop database" in c)
        self.assertLess(created, migrated)
        self.assertLess(migrated, squirrel)
        self.assertLess(squirrel, dropped)
        name = re.search(r'create database "([^"]+)"', commands[created]).group(1)
        urls = [line for line in run.url.splitlines() if line.startswith("built run -m squirrel check ")]
        self.assertEqual([line.rpartition("/")[2] for line in urls], [name], "squirrel is given the database that was migrated")
        self.assertIn(name, commands[dropped])

    def test_a_part_run_reports_the_literal_area_of_its_own_runs_only(self):
        expected = {
            ("gleam-test", "1/3"): ["literal area: peak"],
            ("real-tables",): ["literal area of the real-tables run: peak"],
            ("world-data",): ["literal area of the world-data run: peak"],
            ("glinter",): [],
            ("real-start",): [],
        }
        for arguments, lines in expected.items():
            with self.subTest(part=arguments):
                run = part_run_of(arguments, True)
                self.assertEqual(run.done.returncode, 0, run.output)
                printed = [line.strip() for line in run.output.splitlines() if line.strip().startswith("literal area")]
                self.assertEqual(len(printed), len(lines), run.output)
                for line, text in zip(lines, printed):
                    self.assertTrue(text.startswith(line), text)
                self.assertNotIn("check WARNING", run.output, "no warning about a run that was not made")
        limit = REGION * literal_limit_percent() // 100
        run = part_run("literal-over", "gleam-test", "1/3", PLANT_LITERAL_PEAK=str(limit + 1))
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("check WARNING: literal area over %d%% of its region" % literal_limit_percent(), run.output)


# The test files a shard planted repository holds below test/ (the repository's own
# test/code_rule/planted_test.gleam is one more): the heavy modules of ./check, support files that
# do not end in _test.gleam, a sub-folder, and files that are not Gleam. `SHARD_TREE_ADDED` and
# `SHARD_TREE_REMOVED` make the second tree.
SHARD_TREE_FILES = (
    ["alpha_test", "beta_test", "gamma_test", "delta_test", "support_helper", "spells/flow_test", "spells/support"]
    + ["m%02d_test" % i for i in range(30)]
)
SHARD_TREE_NOT_GLEAM = ["fixture/data.json", "notes.md"]
SHARD_TREE_ADDED = ["added_one_test", "spells/added_test"]
SHARD_TREE_REMOVED = ["beta_test", "m07_test"]

# The shard of some modules, from the hash the check documents (h = (31 * h + byte) mod 1000003, the
# shard h mod N + 1), worked out here in Python, so the awk of macOS and the awk of Ubuntu must agree.
PINNED_SHARDS = {
    2: {
        "alpha_test": 1, "beta_test": 1, "gamma_test": 2, "delta_test": 2, "support_helper": 1,
        "spells/flow_test": 1, "spells/support": 2, "m00_test": 2, "m07_test": 1, "m29_test": 2,
        "code_rule/planted_test": 1,
    },
    3: {
        "alpha_test": 2, "beta_test": 3, "gamma_test": 3, "delta_test": 2, "support_helper": 3,
        "spells/flow_test": 3, "spells/support": 3, "m00_test": 1, "m07_test": 3, "m29_test": 1,
        "code_rule/planted_test": 1,
    },
}

# The shard (of 3) of the files the second tree adds, worked out the same way.
PINNED_ADDED_SHARDS = {"added_one_test": 1, "spells/added_test": 1}


# The shard of each heavy module, worked by hand from the seconds ./check keeps (the
# biggest first, each on the least loaded shard): 3 shards load 203.4, 181.6, 224.0 seconds,
# 2 shards 305.6 and 303.4.
PINNED_HEAVY_SHARDS = {
    2: {
        "table_value_test": 1, "account_store_test": 2, "apply_migrations_test": 2, "game_wire_quest_test": 1,
        "objective_test": 2, "migration_start_test": 1, "sigterm_test": 2, "spell_area_test": 1,
        "spell_plan_lasting_test": 2, "limited_action_set_test": 1,
    },
    3: {
        "table_value_test": 1, "account_store_test": 2, "apply_migrations_test": 3, "game_wire_quest_test": 3,
        "objective_test": 2, "migration_start_test": 1, "sigterm_test": 3, "spell_area_test": 2,
        "spell_plan_lasting_test": 1, "limited_action_set_test": 3,
    },
}


def heavy_modules() -> list[tuple[str, float]]:
    """The modules ./check places first, as (module, seconds), in its order."""
    found = re.findall(r'(?m)^heavy_modules="([^"]*)"$', CHECK.read_text())
    assert len(found) == 1, found
    return [(entry.split(":")[0], float(entry.split(":")[1])) for entry in found[0].split()]


def biggest_first(count: int) -> dict[str, int]:
    """The shard of each heavy module: biggest first (equal seconds by name), each on the least loaded shard, ties to the lower."""
    loads = [0.0] * count
    owner = {}
    for module, seconds in sorted(heavy_modules(), key=lambda entry: (-entry[1], entry[0])):
        shard = loads.index(min(loads))
        owner[module] = shard + 1
        loads[shard] += seconds
    return owner


def plant_shard_tree(tree: str):
    """Plants the test folder of the tree ("first", "second" with files added and removed, or
    "reversed": the first with the planted check listing its heavy modules smallest first, so the
    placement cannot rest on the order of that list), and a leftover link in the folder each shard
    of 2 and 3 will build."""

    def plant(case: PlantedCheckCase) -> None:
        names = [name for name, _ in heavy_modules()] + SHARD_TREE_FILES
        if tree == "second":
            names = [name for name in names if name not in SHARD_TREE_REMOVED] + SHARD_TREE_ADDED
        if tree == "reversed":
            planted = case.repository / "check"
            line = re.search(r'(?m)^heavy_modules="([^"]*)"$', planted.read_text())
            reversed_list = " ".join(reversed(line.group(1).split()))
            planted.write_text(planted.read_text().replace(line.group(0), 'heavy_modules="%s"' % reversed_list))
        for name in names:
            file = case.repository / "test" / (name + ".gleam")
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("// a test\n")
        for name in SHARD_TREE_NOT_GLEAM:
            file = case.repository / "test" / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("not a test\n")
        for count in (2, 3):
            for number in range(1, count + 1):
                stale = case.repository / "build" / "chosen_tests" / ("shard-%d-of-%d" % (number, count)) / "test"
                stale.mkdir(parents=True, exist_ok=True)
                (stale / "stale_test.gleam").symlink_to(case.repository / "test" / "no_longer_there_test.gleam")

    return plant


def shard_runs(count: int, tree: str = "first") -> list[Run]:
    return [
        part_run("shard-%s-%dof%d" % (tree, number, count), "gleam-test", "%d/%d" % (number, count), prepare=plant_shard_tree(tree))
        for number in range(1, count + 1)
    ]


def shard_listing(run: Run, part: str | None = None) -> list[tuple[str, str]]:
    """The (path, target) of each symlink the shard's folder held when its first run started; fails on anything else in it.
    With a part (a run of the fast check lists a folder for each of its test runs), the folder of build/chosen_tests/PART."""
    lines = run.shard.splitlines()
    if part is not None:
        header = "shard build/chosen_tests/%s/test" % part
        assert header in lines, run.shard
        lines = lines[lines.index(header):]
        end = [i for i, line in enumerate(lines[1:], start=1) if line.startswith("shard ")]
        lines = lines[:end[0]] if end else lines
    assert lines and lines[0].startswith("shard "), run.shard
    assert not [line for line in lines if line.startswith(("missing", "stray"))], run.shard
    return [tuple(line.split(" ")[1:]) for line in lines if line.startswith("link ")]


def owners(count: int, tree: str = "first") -> dict[str, int]:
    """The shard that held each file, by its path below test, read from the folders the runs of the count were given."""
    held: dict[str, int] = {}
    for number, run in enumerate(shard_runs(count, tree), start=1):
        assert run.done.returncode == 0, run.output
        for path, _ in shard_listing(run):
            assert path not in held, "%s is in two shards" % path
            held[path] = number
    return held


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class ShardTest(unittest.TestCase):
    """`./check part gleam-test K/N` runs the tests of one of N shards: a folder below
    build/chosen_tests of symlinks to the shard's files, given to the first run and the
    serial run (GENESIS_TEST_DIRECTORY). The ten heaviest modules are placed first, by
    the seconds ./check keeps for them; every other file by a hash of its path, so a file
    keeps its shard when others are added."""

    def test_the_shards_of_a_count_together_hold_every_gleam_file_of_the_test_folder_once(self):
        for count in (2, 3):
            with self.subTest(count=count):
                held = owners(count)
                every = sorted(
                    [name + ".gleam" for name, _ in heavy_modules()] + [name + ".gleam" for name in SHARD_TREE_FILES]
                    + ["code_rule/planted_test.gleam"])
                self.assertEqual(sorted(held), every, "each file once: the files that are not Gleam and the leftover link are not held")
                for number, run in enumerate(shard_runs(count), start=1):
                    self.assertEqual(
                        set(directories_given(run).values()), {"build/chosen_tests/shard-%d-of-%d/test" % (number, count)})
                    for path, target in shard_listing(run):
                        self.assertRegex(target, r"^/.*/test/%s$" % re.escape(path), "each link goes to the file at its own path below test")
                for module, shard in PINNED_SHARDS[count].items():
                    self.assertIn(module + ".gleam", held, "a pinned module the planted tree holds")
                    self.assertEqual(held[module + ".gleam"], shard, module)

    def test_a_gleam_file_stays_in_its_shard_when_other_files_are_added(self):
        before = owners(3)
        after = owners(3, "second")
        for added in SHARD_TREE_ADDED:
            self.assertIn(added + ".gleam", after)
            self.assertEqual(after[added + ".gleam"], PINNED_ADDED_SHARDS[added], added)
        for removed in SHARD_TREE_REMOVED:
            self.assertNotIn(removed + ".gleam", after)
        kept = [path for path in before if path in after]
        self.assertGreater(len(kept), 40)
        for path in kept:
            self.assertEqual(before[path], after[path], path)

    def test_the_heaviest_modules_are_spread_over_the_shards_biggest_first(self):
        for count in (2, 3):
            with self.subTest(count=count):
                held = owners(count, "reversed")
                for module, shard in biggest_first(count).items():
                    self.assertEqual(held[module + ".gleam"], shard, module)
                    self.assertEqual(PINNED_HEAVY_SHARDS[count][module], shard, module)

    def test_a_shard_run_gives_its_folder_to_the_first_run_and_the_serial_run_and_no_other_run(self):
        run = part_run_of(("gleam-test", "2/3"), False)
        self.assertEqual(run.done.returncode, 0, run.output)
        folder = "build/chosen_tests/shard-2-of-3/test"
        self.assertEqual(directories_given(run), {FIRST_RUN: folder, SERIAL_RUN: folder})
        skips = {line.split(" GENESIS_TEST_SKIP_SERIAL")[0]: line for line in run.environment.splitlines() if line.startswith("built test")}
        self.assertIn(
            "GENESIS_TEST_SKIP_SERIAL=1 GENESIS_TEST_SKIP_WORLD_DATA=1 GENESIS_TEST_SKIP_REAL_START=1 GENESIS_TEST_SKIP_CLIENT_ROWS=1 GENESIS_TEST_SKIP_REAL_TABLES=1",
            skips[FIRST_RUN])
        self.assertIn(
            "GENESIS_TEST_SKIP_SERIAL= GENESIS_TEST_SKIP_WORLD_DATA= GENESIS_TEST_SKIP_REAL_START= GENESIS_TEST_SKIP_CLIENT_ROWS= GENESIS_TEST_SKIP_REAL_TABLES=",
            skips[SERIAL_RUN])
        for arguments in (("real-start",), ("real-tables",), ("world-data",), ("client-suite",)):
            with self.subTest(part=arguments):
                other = part_run_of(arguments, True)
                self.assertEqual(other.done.returncode, 0, other.output)
                self.assertEqual(directories_given(other), {})

    def test_a_shard_whose_first_run_ran_no_test_fails_the_part(self):
        run = part_run("shard-first-ran-nothing", "gleam-test", "2/3", PLANT_PASSED_FIRST="0")
        self.assertNotEqual(run.done.returncode, 0, run.output)
        self.assertEqual(failed_line(self, run.output), "check FAILED: gleam-test")
        self.assertIn("no test ran in shard 2/3", run.output)

    def test_a_shard_whose_serial_run_ran_no_test_passes(self):
        run = part_run("shard-serial-ran-nothing", "gleam-test", "2/3", PLANT_PASSED_SERIAL="0")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertRegex(run.output, r"(?m)^  gleam-test +ok\b")

    def test_every_heavy_module_named_in_check_is_a_gleam_file_of_the_test_folder(self):
        heavy = heavy_modules()
        self.assertTrue(heavy, "check names the modules it places first")
        for module, seconds in heavy:
            with self.subTest(module=module):
                self.assertTrue((REPOSITORY / "test" / (module + ".gleam")).is_file())
                self.assertGreater(seconds, 0)


@unittest.skipUnless(RUNNABLE, "the check needs bash, python3.13 and ./check here")
class WorkerCountTest(unittest.TestCase):
    """The worker count is one setting of the check."""

    def test_the_setting_is_given_to_the_test_run_as_the_worker_count(self):
        run = shared_run("workers-3", GENESIS_TEST_WORKERS="3")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn("built test -- --workers 3 --reporter table --no-color", run.commands)

    def test_without_the_setting_the_test_run_has_two_workers(self):
        run = shared_run("full")
        self.assertEqual(run.done.returncode, 0, run.output)
        self.assertIn(FIRST_RUN, run.commands)
        self.assertFalse([c for c in run.commands if re.match(r"built test -- --workers (?!2 )\d+", c)], run.commands)


class FactFileMergeTest(unittest.TestCase):
    """The fact file merges by union (.gitattributes): every step appends its records at
    the end, so two branches' records would otherwise conflict on every merge."""

    FACT_FILE = FACT_FILE

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
