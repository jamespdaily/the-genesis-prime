"""dev/pr_wait.sh: how its wait ends, and that a failed GitHub call is an error, not a CI state.

The script runs on a planted `gh`. The planted gh answers
  `gh pr view N --json statusCheckRollup`      with PLANT_VIEW_OUTPUT (default "1") and the
                                                exit status PLANT_VIEW_STATUS (default 0);
  `gh pr checks N --watch`                     with the exit status PLANT_WATCH_STATUS (default 0);
  `gh pr checks N --json name,bucket --jq ...` with one line `bucket name` per check: the
                                                names in PLANT_FAILING (a comma-separated line,
                                                bucket fail) and the one pending check named
                                                by PLANT_PENDING (bucket pending), the gate job
                                                `check` as a passing check unless PLANT_GATE is 0
                                                for that call (default 1), and the exit status
                                                PLANT_JSON_STATUS (default 0).
PLANT_VIEW_OUTPUT, PLANT_VIEW_STATUS, PLANT_WATCH_STATUS, PLANT_PENDING, PLANT_GATE and
PLANT_JSON_STATUS are comma-separated lists with one item per call, the last item repeated (plant_support.NEXT_LINE
reads them from files); a call that fails prints nothing. Every call is kept in PLANT_DIR/calls.
Every test sets PR_WAIT_RETRY_SECONDS, PR_WAIT_POLL_SECONDS and PR_WAIT_GATE_POLL_SECONDS to 0, so
none sleeps.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_pr_wait.py'
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from plant_support import NEXT_LINE  # noqa: E402

SCRIPT = HERE.parent / "dev" / "pr_wait.sh"

RUNNABLE = shutil.which("bash") is not None

GH_STUB = """#!/bin/bash
echo "$*" >> "$PLANT_DIR/calls"
""" + NEXT_LINE + """case "$1 $2" in
  "pr view")
    answer=$(next_line view_output view_output_asked)
    status=$(next_line view_status view_status_asked)
    [ "${status:-0}" = 0 ] && echo "$answer"
    exit "${status:-0}" ;;
  "pr checks")
    case "$*" in
      *--watch*)
        status=$(next_line watch_status watch_status_asked)
        exit "${status:-0}" ;;
      *--json*)
        status=$(next_line json_status json_status_asked)
        pending=$(next_line pending pending_asked)
        gate=$(next_line gate gate_asked)
        if [ "${status:-0}" = 0 ]; then
          IFS=',' read -ra failing <<< "${PLANT_FAILING-}"
          for name in "${failing[@]}"; do echo "fail ${name# }"; done
          [ -n "$pending" ] && echo "pending $pending"
          [ "${gate:-1}" = 0 ] || [ "$pending" = check ] || echo "pass check"
        fi
        exit "${status:-0}" ;;
    esac ;;
esac
echo "planted gh: unexpected $*" >&2
exit 9
"""

# The per-call lists of the planted gh: the variable, its file in PLANT_DIR and its default.
PER_CALL = {
    "PLANT_VIEW_OUTPUT": ("view_output", "1"),
    "PLANT_VIEW_STATUS": ("view_status", "0"),
    "PLANT_WATCH_STATUS": ("watch_status", "0"),
    "PLANT_JSON_STATUS": ("json_status", "0"),
    "PLANT_PENDING": ("pending", ""),
    "PLANT_GATE": ("gate", "1"),
}


@unittest.skipUnless(RUNNABLE, "pr_wait.sh needs bash")
class PullRequestWaitTest(unittest.TestCase):
    def wait(self, **plant: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stub = root / "bin" / "gh"
            stub.parent.mkdir()
            stub.write_text(GH_STUB)
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            for variable, (name, default) in PER_CALL.items():
                (root / name).write_text("\n".join(plant.pop(variable, default).split(",")) + "\n")
            environment = {"PATH": f"{stub.parent}:{os.environ['PATH']}", "PLANT_DIR": str(root), "PR_WAIT_RETRY_SECONDS": "0",
                           "PR_WAIT_POLL_SECONDS": "0", "PR_WAIT_GATE_POLL_SECONDS": "0", **plant}
            done = subprocess.run(["bash", str(SCRIPT), "7"], capture_output=True, text=True, env=environment)
            calls = root / "calls"
            done.calls = calls.read_text().splitlines() if calls.exists() else []
            return done

    def watches(self, done: subprocess.CompletedProcess) -> list[str]:
        return [call for call in done.calls if "--watch" in call]

    def calls_starting(self, done: subprocess.CompletedProcess, prefix: str) -> list[str]:
        return [call for call in done.calls if call.startswith(prefix)]

    def test_checks_that_all_pass_end_the_wait_with_success(self):
        done = self.wait()
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_a_failed_check_ends_the_wait_with_status_1_and_names_the_failing_jobs(self):
        done = self.wait(PLANT_WATCH_STATUS="1", PLANT_FAILING="CI / unit tests, client parts")
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("pr_wait: failing jobs: CI / unit tests, client parts", done.stderr)

    def test_a_failed_call_that_reads_the_checks_is_an_error_not_no_check(self):
        done = self.wait(PLANT_VIEW_STATUS="1", PLANT_VIEW_OUTPUT="")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)
        self.assertFalse(self.watches(done), done.calls)

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

    def test_a_watch_that_ends_while_a_check_is_still_pending_watches_again_and_ends_with_the_checks_outcome(self):
        rows = [
            ("a check is pending when the first watch ends", dict(PLANT_WATCH_STATUS="1,0", PLANT_PENDING="check,"), 2, 2),
            # The gate job `check` is created about a second after the last part job ends: a watch
            # that ends in that second sees every check passed and none named `check`.
            ("every check passed but none is named `check` yet", dict(PLANT_GATE="0,0,1"), 1, 3),
        ]
        for why, plant, watched, listed in rows:
            with self.subTest(why):
                done = self.wait(**plant)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertEqual(len(self.watches(done)), watched, done.calls)
                self.assertEqual(len(self.calls_starting(done, "pr checks 7 --json")), listed, done.calls)

    def test_a_wait_whose_gate_job_never_appears_ends_as_an_error(self):
        done = self.wait(PLANT_GATE="0")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("no check named check appeared", done.stderr)
        self.assertEqual(len(self.calls_starting(done, "pr checks 7 --json")), 20, done.calls)

    def test_a_github_call_that_fails_once_is_asked_again_and_the_wait_goes_on(self):
        rows = [
            ("the check count", dict(PLANT_VIEW_STATUS="1,0", PLANT_VIEW_OUTPUT=",1"), "pr view", 2, 1),
            (
                "the buckets after a watch that ended while a check is pending",
                dict(PLANT_WATCH_STATUS="1,0", PLANT_JSON_STATUS="1,0", PLANT_PENDING="check,check,"),
                "pr checks 7 --json",
                3,
                2,
            ),
        ]
        for call, plant, prefix, asked, watched in rows:
            with self.subTest(call):
                done = self.wait(**plant)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertEqual(len(self.calls_starting(done, prefix)), asked, done.calls)
                self.assertEqual(len(self.watches(done)), watched, done.calls)

    def test_a_github_call_that_fails_on_every_try_ends_the_wait_as_an_error_after_three_tries(self):
        done = self.wait(PLANT_VIEW_STATUS="1", PLANT_VIEW_OUTPUT="")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)
        self.assertEqual(len(self.calls_starting(done, "pr view")), 3, done.calls)
        self.assertFalse(self.watches(done), done.calls)

    def test_a_watch_that_keeps_ending_with_a_check_pending_ends_as_an_error_after_three_tries(self):
        done = self.wait(PLANT_WATCH_STATUS="1", PLANT_PENDING="check")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("still pending: check", done.stderr)
        self.assertEqual(len(self.watches(done)), 3, done.calls)


if __name__ == "__main__":
    unittest.main()
