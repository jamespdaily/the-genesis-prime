"""dev/pr_wait.sh: how its wait ends, and that a failed GitHub call is an error, not a CI state.

The script runs on a planted `gh`. The planted gh answers
  `gh pr view N --json statusCheckRollup`      with PLANT_VIEW_OUTPUT (default "1") and the
                                                exit status PLANT_VIEW_STATUS (default 0);
  `gh pr checks N --watch`                     with the exit status PLANT_WATCH_STATUS (default 0);
  `gh pr checks N --json name,bucket --jq ...` with the failing job names in PLANT_FAILING (a
                                                comma-separated line) and the exit status
                                                PLANT_JSON_STATUS (default 0).
Every call is kept in PLANT_DIR/calls.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_pr_wait.py'
"""

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "dev" / "pr_wait.sh"

RUNNABLE = shutil.which("bash") is not None

GH_STUB = """#!/bin/bash
echo "$*" >> "$PLANT_DIR/calls"
case "$1 $2" in
  "pr view")
    echo "${PLANT_VIEW_OUTPUT-1}"
    exit "${PLANT_VIEW_STATUS:-0}" ;;
  "pr checks")
    case "$*" in
      *--watch*) exit "${PLANT_WATCH_STATUS:-0}" ;;
      *--json*) echo "${PLANT_FAILING-}"; exit "${PLANT_JSON_STATUS:-0}" ;;
    esac ;;
esac
echo "planted gh: unexpected $*" >&2
exit 9
"""


@unittest.skipUnless(RUNNABLE, "pr_wait.sh needs bash")
class PullRequestWaitTest(unittest.TestCase):
    def wait(self, **plant: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stub = root / "bin" / "gh"
            stub.parent.mkdir()
            stub.write_text(GH_STUB)
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            environment = {"PATH": f"{stub.parent}:{os.environ['PATH']}", "PLANT_DIR": str(root), **plant}
            done = subprocess.run(["bash", str(SCRIPT), "7"], capture_output=True, text=True, env=environment)
            calls = root / "calls"
            done.calls = calls.read_text().splitlines() if calls.exists() else []
            return done

    def test_checks_that_all_pass_end_the_wait_with_success(self):
        done = self.wait()
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_a_failed_check_ends_the_wait_with_status_1_and_names_the_failing_jobs(self):
        done = self.wait(PLANT_WATCH_STATUS="1", PLANT_FAILING="unit-tests, client-parts")
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("pr_wait: failing jobs: unit-tests, client-parts", done.stderr)

    def test_a_failed_call_that_reads_the_checks_is_an_error_not_no_check(self):
        done = self.wait(PLANT_VIEW_STATUS="1", PLANT_VIEW_OUTPUT="")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)
        self.assertFalse([call for call in done.calls if "--watch" in call], done.calls)

    def test_an_answer_that_is_not_a_count_is_an_error_not_no_check(self):
        done = self.wait(PLANT_VIEW_OUTPUT="HTTP 502")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)

    def test_a_watch_that_fails_while_the_failing_jobs_cannot_be_read_is_an_error_not_a_ci_failure(self):
        done = self.wait(PLANT_WATCH_STATUS="1", PLANT_JSON_STATUS="1")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)

    def test_a_watch_that_fails_while_no_check_failed_is_an_error_not_a_ci_failure(self):
        done = self.wait(PLANT_WATCH_STATUS="1", PLANT_FAILING="")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("no check failed", done.stderr)


if __name__ == "__main__":
    unittest.main()
