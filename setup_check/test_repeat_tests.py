"""dev/repeat_tests.py: which test files it repeats, how it starts the runs, and how it
reports a failing one, tested on a planted repository.

Each test copies the script into a temporary git repository (a branch `feature` of
`main`) and runs that copy with a PATH whose `erl` is a stub standing in for the VM
that `./check` starts on the built code (run_built). The stub takes the arguments
the real VM takes (`-extra FILE --seed N --no-color`), keeps one line per start in
PLANT_REPEAT/starts.log (its ticket number, seed, file, how many stubs were alive
beside it, and the skip variables it was given), and prints what unitest prints:
the status line, the seed, and for a failing run the "Failures:" section.

- PLANT_AT_ONCE=N: each of the first N stubs to start waits until all N have started
  (none leaves before the others have arrived), and fails when they have not within
  PLANT_RENDEZVOUS_POLLS tenths of a second (a guard against a script that never
  starts them together, not a time bound);
- PLANT_FAILS_ON_START=N: the Nth stub to start fails the way a run with one
  failing test does;
- PLANT_KILLED_ON_START=N: the Nth stub is killed (signal 9) after printing its seed,
  so its output has no "Failures:" section;
- PLANT_HANGS_ON_START=N: the Nth stub never ends (the script's per-run limit kills it);
- a file named *all_skipped* prints "0 passed, no failures, 3 skipped", as unitest does
  for a file whose tests are all skipped.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
SCRIPT = REPOSITORY / "dev" / "repeat_tests.py"

RUNNABLE = shutil.which("git") is not None and shutil.which("sh") is not None

ERL_STUB = """#!/bin/sh
dir=$PLANT_REPEAT
while [ $# -gt 0 ]; do
  case "$1" in
    -extra) shift; break ;;
    *) shift ;;
  esac
done
file=$1
shift
seed=
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) seed=$2; shift 2 ;;
    *) shift ;;
  esac
done
ticket=1
until mkdir "$dir/ticket.$ticket" 2>/dev/null; do ticket=$((ticket + 1)); done
touch "$dir/alive.$$"
alive() { ls "$dir" | grep -c '^alive\\.'; }
printf 'start %s seed %s file %s alive %s skip %s%s%s%s\\n' "$ticket" "$seed" "$file" "$(alive)" \\
  "$GENESIS_TEST_SKIP_SERIAL" "$GENESIS_TEST_SKIP_WORLD_DATA" "$GENESIS_TEST_SKIP_CLIENT_ROWS" \\
  "$GENESIS_TEST_SKIP_DEV_TOOL" >>"$dir/starts.log"
if [ -n "$PLANT_AT_ONCE" ] && [ "$ticket" -le "$PLANT_AT_ONCE" ]; then
  touch "$dir/arrived.$ticket"
  arrived() { ls "$dir" | grep -c '^arrived\\.'; }
  polls=0
  until [ "$(arrived)" -ge "$PLANT_AT_ONCE" ]; do
    sleep 0.1
    polls=$((polls + 1))
    if [ "$polls" -gt "${PLANT_RENDEZVOUS_POLLS:-300}" ]; then
      echo "only $(arrived) of $PLANT_AT_ONCE runs had started together"
      rm -f "$dir/alive.$$"
      exit 1
    fi
  done
fi
rm -f "$dir/alive.$$"
if [ "$ticket" = "$PLANT_FAILS_ON_START" ]; then
  echo "1 passed, 1 failures"
  echo "Finished in 3 milliseconds"
  echo "Seed: $seed"
  echo
  echo "Failures:"
  echo "1) planted_test.the_planted_rule_test (1ms)"
  echo "   $file:12"
  exit 1
fi
if [ "$ticket" = "$PLANT_KILLED_ON_START" ]; then
  echo "Seed: $seed"
  kill -9 $$
fi
if [ "$ticket" = "$PLANT_HANGS_ON_START" ]; then
  exec sleep 60
fi
case "$file" in
  *all_skipped*)
    echo "0 passed, no failures, 3 skipped"
    echo "Finished in 0 nanoseconds"
    echo "Seed: $seed"
    exit 0 ;;
esac
echo "2 passed, no failures"
echo "Finished in 3 milliseconds"
echo "Seed: $seed"
exit 0
"""


def executable(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@unittest.skipUnless(RUNNABLE, "the repeat script's tests need git and sh here")
class PlantedRepeatCase(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="genesis-repeat-tests-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.repository = self.root / "repository"
        self.state = self.root / "state"
        self.state.mkdir()
        self.repository.mkdir()
        (self.repository / "dev").mkdir()
        shutil.copyfile(SCRIPT, self.repository / "dev" / "repeat_tests.py")
        for package in ("alpha", "beta"):
            (self.repository / "build" / "dev" / "erlang" / package / "ebin").mkdir(parents=True)
        (self.repository / "test" / "nested").mkdir(parents=True)
        (self.repository / "src").mkdir()
        for path in (
            "test/unchanged_test.gleam",
            "test/changed_test.gleam",
            "test/support.gleam",
            "test/removed_test.gleam",
            "test/nested/deep_test.gleam",
            "src/server.gleam",
        ):
            (self.repository / path).write_text("// planted\n")
        executable(self.root / "tools" / "erl", ERL_STUB)
        self.git("init", "-q", "-b", "main")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "planted repository")
        self.git("checkout", "-q", "-b", "feature")

    def git(self, *arguments: str) -> str:
        done = subprocess.run(
            ["git", "-c", "user.name=Planted", "-c", "user.email=planted@example.invalid", *arguments],
            cwd=self.repository, capture_output=True, text=True, check=True,
        )
        return done.stdout.strip()

    def commit(self, message: str, *, change=(), add=(), remove=(), rename=()) -> None:
        for path in change:
            with open(self.repository / path, "a") as changed:
                changed.write("// changed on the branch\n")
        for path in add:
            (self.repository / path).parent.mkdir(parents=True, exist_ok=True)
            (self.repository / path).write_text("// added on the branch\n")
        for path in remove:
            (self.repository / path).unlink()
        for old, new in rename:
            (self.repository / old).rename(self.repository / new)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def commit_on_main(self, message: str, *, change) -> None:
        """A commit on main after the branch point, as another merged pull request makes."""
        self.git("checkout", "-q", "main")
        self.commit(message, change=change)
        self.git("checkout", "-q", "feature")

    def run_script(self, *arguments: str, **settings: str) -> subprocess.CompletedProcess:
        env = {
            "PATH": "%s:/usr/bin:/bin" % (self.root / "tools"),
            "HOME": str(self.root),
            "PLANT_REPEAT": str(self.state),
        }
        env.update(settings)
        return subprocess.run(
            [sys.executable, "-I", "dev/repeat_tests.py", *(arguments or ("main",))],
            cwd=self.repository, env=env, capture_output=True, text=True, timeout=120,
        )

    def starts(self) -> list[dict[str, str]]:
        log = self.state / "starts.log"
        if not log.exists():
            return []
        rows = []
        for line in log.read_text().splitlines():
            fields = line.split()
            rows.append({key: value for key, value in zip(fields[0::2], fields[1::2])})
        return rows


class RepeatTestsTest(PlantedRepeatCase):
    def test_it_runs_each_added_or_changed_test_file_and_no_other(self):
        self.commit(
            "change, add and rename test files",
            change=["test/changed_test.gleam", "test/support.gleam", "src/server.gleam"],
            add=[
                "test/added_test.gleam",
                "test/nested/another_test.gleam",
                "test/helper.gleam",
                "test/all_skipped_test.gleam",
            ],
            remove=["test/removed_test.gleam"],
            rename=[("test/nested/deep_test.gleam", "test/nested/moved_test.gleam")],
        )
        # Another pull request changes a test file on main after this branch began.
        self.commit_on_main("change a test file on main", change=["test/unchanged_test.gleam"])
        listed = [
            "test/added_test.gleam",
            "test/all_skipped_test.gleam",
            "test/changed_test.gleam",
            "test/nested/another_test.gleam",
            "test/nested/moved_test.gleam",
        ]
        self.assertEqual(self.run_script("--list", "main").stdout.splitlines(), listed)
        self.assertEqual(self.starts(), [], "--list starts no VM")
        # Eight starts in all over five files is under two each, so each gets two.
        done = self.run_script(GENESIS_REPEAT_RUNS="8", GENESIS_REPEAT_AT_ONCE="1")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        files = [row["file"] for row in self.starts()]
        self.assertEqual(set(files), set(listed), "a renamed file runs at its new path; no other file runs")
        for file in listed:
            if file != "test/all_skipped_test.gleam":
                self.assertEqual(files.count(file), 2, file)
        self.assertEqual(
            files.count("test/all_skipped_test.gleam"), 1, "a file that ran 0 tests is not started again"
        )
        self.assertIn("not repeated: test/all_skipped_test.gleam", done.stdout)
        self.assertIn("all 8 runs passed", done.stdout, "a run of 0 tests is not counted as passed")

    def test_no_changed_test_file_passes_without_a_run(self):
        self.commit(
            "change a support module, the server and delete a test",
            change=["test/support.gleam", "src/server.gleam"],
            remove=["test/removed_test.gleam"],
        )
        done = self.run_script()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.starts(), [], "no VM is started")
        self.assertIn("no added or changed test file", done.stdout)

    def test_each_run_has_its_own_seed_and_runs_start_at_once(self):
        self.commit("change a test file", change=["test/changed_test.gleam"])
        done = self.run_script(GENESIS_REPEAT_RUNS="6", GENESIS_REPEAT_AT_ONCE="3", PLANT_AT_ONCE="3")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        rows = self.starts()
        self.assertEqual(len(rows), 6)
        seeds = [row["seed"] for row in rows]
        self.assertTrue(all(re.fullmatch(r"\d+", seed) for seed in seeds), seeds)
        self.assertEqual(len(set(seeds)), 6, "every run has its own seed")
        # Each of the first three stubs waited until three were alive, so three started
        # together; no stub ever saw more than three beside it.
        self.assertEqual(max(int(row["alive"]) for row in rows), 3)
        # The tests that need the whole machine are skipped as ./check's test run skips them.
        self.assertEqual({row["skip"] for row in rows}, {"1111"})

    def test_one_failing_run_fails_it_naming_the_seed_and_test(self):
        self.commit("change two test files", change=["test/changed_test.gleam"], add=["test/added_test.gleam"])
        done = self.run_script(
            GENESIS_REPEAT_AT_ONCE="4",
            GENESIS_REPEAT_RUN_SECONDS="1",
            PLANT_FAILS_ON_START="7",
            PLANT_KILLED_ON_START="11",
            PLANT_HANGS_ON_START="15",
        )
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        rows = self.starts()
        self.assertEqual(len(rows), 40, "forty starts in all by default, split over the two files")
        self.assertEqual({row["file"] for row in rows}, {"test/changed_test.gleam", "test/added_test.gleam"})
        failing = {number: next(row for row in rows if row["start"] == number) for number in ("7", "11", "15")}
        output = done.stdout + done.stderr
        for row in failing.values():
            self.assertIn("seed %s" % row["seed"], output)
            self.assertIn(row["file"], output)
        self.assertIn("planted_test.the_planted_rule_test", output)
        self.assertIn("killed by signal 9", output, "a run with no Failures section is still reported")
        self.assertIn("check WARNING:", output, "a run over its limit is a warning, not a failure")
        self.assertIn("still going after 1 seconds", output)
        for row in rows:
            if row not in failing.values():
                self.assertNotIn(row["seed"], output, "a passing run's seed is not named")
        self.assertIn("2 of 39 runs failed", output)


if __name__ == "__main__":
    unittest.main()
