"""dev/pr_wait.sh: how its wait ends, and that a failed GitHub call is an error, not a CI state.

The script runs on a planted `gh`. The planted gh answers
  `gh pr view N --json statusCheckRollup`      with PLANT_VIEW_OUTPUT (default "1") and the
                                                exit status PLANT_VIEW_STATUS (default 0);
  `gh pr checks N --watch`                     with the exit status PLANT_WATCH_STATUS (default 0);
  `gh pr checks N --json name,bucket --jq ...` with one line `bucket name` per check: the
                                                names in PLANT_FAILING (a comma-separated line,
                                                bucket fail) and the one pending check named
                                                by PLANT_PENDING (bucket pending), and the exit
                                                status PLANT_JSON_STATUS (default 0).
PLANT_VIEW_OUTPUT, PLANT_VIEW_STATUS, PLANT_WATCH_STATUS, PLANT_PENDING and PLANT_JSON_STATUS
are comma-separated lists with one item per call, the last item repeated. Every call is kept in
PLANT_DIR/calls. Every test sets PR_WAIT_RETRY_SECONDS to 0, so none sleeps.

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
# The item of the comma-separated list in variable $1 that this call gets.
answer() {
  local items count=0
  IFS=',' read -ra items <<< "${!1}"
  [[ -f "$PLANT_DIR/count-$1" ]] && count=$(<"$PLANT_DIR/count-$1")
  echo $((count + 1)) > "$PLANT_DIR/count-$1"
  [[ ${#items[@]} -eq 0 ]] && return
  [[ $count -ge ${#items[@]} ]] && count=$((${#items[@]} - 1))
  echo "${items[$count]}"
}
case "$1 $2" in
  "pr view")
    PLANT_VIEW_OUTPUT=${PLANT_VIEW_OUTPUT-1}
    answer PLANT_VIEW_OUTPUT
    PLANT_VIEW_STATUS=${PLANT_VIEW_STATUS:-0}
    exit "$(answer PLANT_VIEW_STATUS)" ;;
  "pr checks")
    case "$*" in
      *--watch*)
        PLANT_WATCH_STATUS=${PLANT_WATCH_STATUS:-0}
        exit "$(answer PLANT_WATCH_STATUS)" ;;
      *--json*)
        IFS=',' read -ra failing <<< "${PLANT_FAILING-}"
        for name in "${failing[@]}"; do echo "fail ${name# }"; done
        pending=$(answer PLANT_PENDING)
        [[ -n $pending ]] && echo "pending $pending"
        PLANT_JSON_STATUS=${PLANT_JSON_STATUS:-0}
        exit "$(answer PLANT_JSON_STATUS)" ;;
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
            environment = {"PATH": f"{stub.parent}:{os.environ['PATH']}", "PLANT_DIR": str(root), "PR_WAIT_RETRY_SECONDS": "0", **plant}
            done = subprocess.run(["bash", str(SCRIPT), "7"], capture_output=True, text=True, env=environment)
            calls = root / "calls"
            done.calls = calls.read_text().splitlines() if calls.exists() else []
            return done

    def watches(self, done: subprocess.CompletedProcess) -> list[str]:
        return [call for call in done.calls if "--watch" in call]

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
        self.assertFalse(self.watches(done), done.calls)
        self.assertEqual(len([call for call in done.calls if call.startswith("pr view")]), 3, done.calls)

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
        done = self.wait(PLANT_WATCH_STATUS="1,0", PLANT_PENDING="check")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.watches(done)), 2, done.calls)

    def test_a_github_call_that_fails_once_is_asked_again_and_the_wait_goes_on(self):
        done = self.wait(PLANT_VIEW_STATUS="1,0", PLANT_VIEW_OUTPUT=",1")
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_a_github_call_that_fails_on_every_try_ends_the_wait_as_an_error_after_three_tries(self):
        done = self.wait(PLANT_VIEW_STATUS="1", PLANT_VIEW_OUTPUT="")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)
        self.assertEqual(len([call for call in done.calls if call.startswith("pr view")]), 3, done.calls)
        self.assertFalse(self.watches(done), done.calls)

    def test_a_watch_that_keeps_ending_with_a_check_pending_ends_as_an_error_after_three_tries(self):
        done = self.wait(PLANT_WATCH_STATUS="1", PLANT_PENDING="check")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("check", done.stderr)
        self.assertEqual(len(self.watches(done)), 3, done.calls)


if __name__ == "__main__":
    unittest.main()
