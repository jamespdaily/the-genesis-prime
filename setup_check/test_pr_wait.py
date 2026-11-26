"""dev/pr_wait.py: how its wait ends, and that a failed GitHub call is an error, not a CI state.

Three layers, as dev/ci_gate.py's tests:
- `decide(rows)` is pure: the checks' (bucket, name) rows in, a verdict out.
- `wait(...)` is the loop with its fetch, sleep and clock passed in: a fake clock that only a
  fake sleep moves, so the deadline of 1500 s is crossed with no waiting.
- the script (dev/pr_wait.sh) runs on a planted `gh`, with the deadline, the poll and the
  limit of one call set small by environment. The planted gh answers
  `gh pr checks N --json name,bucket` with a JSON list: the names in PLANT_FAILING (a
  comma-separated line, bucket fail) and the one pending check named by PLANT_PENDING (bucket
  pending), the gate job `check` as a passing check unless PLANT_GATE is 0 for that call
  (default 1), and the exit status PLANT_JSON_STATUS (default 0; a failed call prints
  nothing). PLANT_HANG set makes the call sleep for ever. PLANT_NO_CHECKS 1 for a call answers as
  gh 2.105.0 does for a pull request with no check yet: exit 1, "no checks reported on the 'b'
  branch" on stderr. PLANT_JSON_STATUS, PLANT_PENDING, PLANT_GATE and PLANT_NO_CHECKS are
  comma-separated lists with one item per call, the last item repeated
  (plant_support.NEXT_LINE reads them from files). Every call is kept in PLANT_DIR/calls.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_pr_wait.py'
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
for folder in (HERE, HERE.parent / "dev"):
    if str(folder) not in sys.path:
        sys.path.insert(0, str(folder))

import pr_wait  # noqa: E402
from plant_support import NEXT_LINE  # noqa: E402

SCRIPT = HERE.parent / "dev" / "pr_wait.sh"

RUNNABLE = shutil.which("bash") is not None and shutil.which("python3.13") is not None

GH_STUB = """#!/bin/bash
echo "$*" >> "$PLANT_DIR/calls"
""" + NEXT_LINE + """case "$1 $2" in
  "pr checks")
    case "$*" in
      *--json*)
        [ -n "${PLANT_HANG-}" ] && exec sleep 1000
        if [ "$(next_line no_checks no_checks_asked)" = 1 ]; then
          echo "no checks reported on the 'b' branch" >&2
          exit 1
        fi
        status=$(next_line json_status json_status_asked)
        pending=$(next_line pending pending_asked)
        gate=$(next_line gate gate_asked)
        if [ "${status:-0}" = 0 ]; then
          rows=()
          IFS=',' read -ra failing <<< "${PLANT_FAILING-}"
          for name in "${failing[@]}"; do
            [ -n "$name" ] && rows+=("{\\"name\\":\\"${name# }\\",\\"bucket\\":\\"fail\\"}")
          done
          [ -n "$pending" ] && rows+=("{\\"name\\":\\"$pending\\",\\"bucket\\":\\"pending\\"}")
          { [ "${gate:-1}" = 0 ] || [ "$pending" = check ]; } || rows+=("{\\"name\\":\\"check\\",\\"bucket\\":\\"pass\\"}")
          (IFS=,; echo "[${rows[*]}]")
        fi
        exit "${status:-0}" ;;
    esac ;;
esac
echo "planted gh: unexpected $*" >&2
exit 9
"""

# The per-call lists of the planted gh: the variable, its file in PLANT_DIR and its default.
PER_CALL = {
    "PLANT_JSON_STATUS": ("json_status", "0"),
    "PLANT_PENDING": ("pending", ""),
    "PLANT_GATE": ("gate", "1"),
    "PLANT_NO_CHECKS": ("no_checks", "0"),
}

DEADLINE = pr_wait.DEADLINE_SECONDS
POLL = pr_wait.POLL_SECONDS
NO_CHECK = pr_wait.NO_CHECK_SECONDS


def rows_of(*pairs: tuple[str, str]) -> list[tuple[str, str]]:
    return list(pairs)


def answer(*pairs: tuple[str, str]) -> str:
    """What `gh pr checks --json name,bucket` prints for the (bucket, name) pairs."""
    return json.dumps([{"name": name, "bucket": bucket} for bucket, name in pairs])


PASSED = answer(("pass", "build"), ("pass", "check"))
PENDING = answer(("pending", "build"), ("pass", "other"))
NO_ROWS = answer()


class Fake:
    """A clock that only the fake sleep moves, and a fetch that answers from a list, the last
    again when they run out, or `later`'s answer once the clock has reached its seconds; an item
    that is an exception is raised."""

    def __init__(self, answers: list, later: tuple[float, str] | None = None):
        self.answers = answers
        self.later = later
        self.now = 0
        self.fetches = 0
        self.sleeps = 0

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps += 1
        self.now += seconds

    def fetch(self) -> str:
        if self.fetches > 10 * DEADLINE // POLL:
            raise AssertionError("the wait polled for ever: it has no deadline")
        item = self.answers[min(self.fetches, len(self.answers) - 1)]
        if self.later and self.now >= self.later[0]:
            item = self.later[1]
        self.fetches += 1
        if isinstance(item, Exception):
            raise item
        return item


def run_wait(fake: Fake, **limits) -> tuple[int, str]:
    return pr_wait.wait(7, fake.fetch, fake.sleep, fake.clock, **limits)


class DecideTest(unittest.TestCase):
    def test_every_check_passed_with_the_gate_job_is_a_pass(self):
        verdict = pr_wait.decide(rows_of(("pass", "build"), ("pass", "check")))
        self.assertEqual(verdict.kind, pr_wait.Kind.PASS)

    def test_a_failed_or_cancelled_check_is_a_failure_naming_them_in_order_while_others_pend(self):
        verdict = pr_wait.decide(rows_of(("pending", "slow"), ("cancel", "second"), ("pass", "good"), ("fail", "first")))
        self.assertEqual(verdict.kind, pr_wait.Kind.FAIL)
        self.assertEqual(verdict.names, ("second", "first"))

    def test_a_pending_check_with_none_failed_keeps_waiting(self):
        verdict = pr_wait.decide(rows_of(("pass", "check"), ("pending", "slow"), ("pending", "slower")))
        self.assertEqual(verdict.kind, pr_wait.Kind.WAIT)
        self.assertEqual(verdict.names, ("slow", "slower"))

    def test_all_passed_without_the_gate_job_keeps_waiting(self):
        verdict = pr_wait.decide(rows_of(("pass", "build"), ("pass", "tests")))
        self.assertEqual(verdict.kind, pr_wait.Kind.WAIT)
        self.assertEqual(verdict.names, ())

    def test_no_rows_is_no_check_yet(self):
        self.assertEqual(pr_wait.decide([]).kind, pr_wait.Kind.NONE)

    def test_skipped_checks_are_not_pending_and_a_name_with_spaces_is_kept_whole(self):
        rows = [
            ("a skipped check beside the gate job", rows_of(("skipping", "optional"), ("pass", "check")), pr_wait.Kind.PASS, ()),
            ("a failing name with spaces", rows_of(("fail", "CI / unit tests"), ("pass", "check")), pr_wait.Kind.FAIL, ("CI / unit tests",)),
            ("a pending name with spaces", rows_of(("pending", "CI / client parts"), ("pass", "check")), pr_wait.Kind.WAIT, ("CI / client parts",)),
        ]
        for why, given, kind, names in rows:
            with self.subTest(why):
                verdict = pr_wait.decide(given)
                self.assertEqual((verdict.kind, verdict.names), (kind, names))


class WaitTest(unittest.TestCase):
    def test_pending_then_passed_on_the_third_poll_returns_0_after_two_sleeps(self):
        fake = Fake([PENDING, PENDING, PASSED])
        status, message = run_wait(fake)
        self.assertEqual(status, 0, message)
        self.assertEqual(fake.sleeps, 2)
        self.assertEqual(fake.fetches, 3)

    def test_pending_for_ever_ends_at_the_deadline_with_status_4_naming_the_pending_checks(self):
        fake = Fake([PENDING])
        status, message = run_wait(fake)
        self.assertEqual(status, 4, message)
        self.assertEqual(fake.fetches, DEADLINE // POLL + 1)
        self.assertEqual(message, f"pr_wait: deadline of {DEADLINE} s passed on pull request 7; still pending: build")

    def test_no_gate_job_until_the_deadline_ends_with_status_4_saying_so(self):
        fake = Fake([answer(("pass", "build"))])
        status, message = run_wait(fake)
        self.assertEqual(status, 4, message)
        self.assertEqual(message, f"pr_wait: deadline of {DEADLINE} s passed on pull request 7; no check named check appeared")

    def test_no_check_for_300_seconds_is_status_1_and_one_at_120_seconds_starts_waiting(self):
        status, message = run_wait(Fake([NO_ROWS]))
        self.assertEqual(status, 1, message)
        self.assertEqual(message, f"pr_wait: no check on pull request 7 after {NO_CHECK} s")
        late = Fake([NO_ROWS], later=(120, PASSED))
        status, message = run_wait(late)
        self.assertEqual(status, 0, message)
        self.assertEqual(late.now, 120)

    def test_one_failed_fetch_then_answers_waits_on(self):
        fake = Fake([pr_wait.CallFailed("gh pr checks ended with status 1"), PENDING, PASSED])
        status, message = run_wait(fake)
        self.assertEqual(status, 0, message)
        self.assertEqual(fake.fetches, 3)

    def test_three_failed_fetches_in_a_row_are_status_3(self):
        fake = Fake([pr_wait.CallFailed("gh pr checks ended with status 1")])
        status, message = run_wait(fake)
        self.assertEqual(status, 3, message)
        self.assertEqual(fake.fetches, 3)
        self.assertIn("a GitHub call failed", message)

    def test_an_answer_that_is_not_the_json_asked_for_is_status_3(self):
        rows = [
            ("a gateway error page", "HTTP 502"),
            ("JSON that is not a list", '{"name": "check"}'),
            ("a list of something else", "[1, 2]"),
            ("a row without a bucket", '[{"name": "check"}]'),
        ]
        for why, text in rows:
            with self.subTest(why):
                status, message = run_wait(Fake([text]))
                self.assertEqual(status, 3, message)
                self.assertIn("a GitHub call failed", message)

    def test_checks_that_vanish_after_appearing_wait_to_the_deadline_saying_none_is_listed(self):
        fake = Fake([PENDING, NO_ROWS])
        status, message = run_wait(fake)
        self.assertEqual(status, 4, message)
        self.assertEqual(message, f"pr_wait: deadline of {DEADLINE} s passed on pull request 7; no check is listed")

    def test_a_failure_at_the_first_poll_ends_the_wait_with_no_further_poll(self):
        fake = Fake([answer(("fail", "unit tests"), ("pending", "slow"))])
        status, message = run_wait(fake)
        self.assertEqual(status, 1, message)
        self.assertEqual(message, "pr_wait: failing jobs: unit tests")
        self.assertEqual((fake.fetches, fake.sleeps), (1, 0))


@unittest.skipUnless(RUNNABLE, "pr_wait.sh needs bash and python3.13")
class PullRequestWaitScriptTest(unittest.TestCase):
    def wait(self, arguments: tuple[str, ...] = ("7",), timeout: float = 60, **plant: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stub = root / "bin" / "gh"
            stub.parent.mkdir()
            stub.write_text(GH_STUB)
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            for variable, (name, default) in PER_CALL.items():
                (root / name).write_text("\n".join(plant.pop(variable, default).split(",")) + "\n")
            environment = {"PATH": f"{stub.parent}:{os.environ['PATH']}", "PLANT_DIR": str(root), "PR_WAIT_POLL_SECONDS": "0.01",
                           "PR_WAIT_DEADLINE_SECONDS": "1", "PR_WAIT_CALL_SECONDS": "1", **plant}
            done = subprocess.run(["bash", str(SCRIPT), *arguments], capture_output=True, text=True, env=environment, timeout=timeout)
            calls = root / "calls"
            done.calls = calls.read_text().splitlines() if calls.exists() else []
            return done

    def test_a_passing_run_ends_0_and_never_calls_watch(self):
        done = self.wait()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(done.calls)
        self.assertFalse([call for call in done.calls if "--watch" in call], done.calls)

    def test_a_gh_call_that_never_returns_is_cut_at_the_call_limit_and_counted_a_failed_try(self):
        done = self.wait(PLANT_HANG="1", PR_WAIT_DEADLINE_SECONDS="30", timeout=30)
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("a GitHub call failed", done.stderr)
        self.assertEqual(len(done.calls), pr_wait.TRIES, done.calls)

    def test_pending_for_ever_exits_4_with_its_line_end_to_end(self):
        done = self.wait(PLANT_PENDING="build")
        self.assertEqual(done.returncode, 4, done.stderr)
        self.assertIn("pr_wait: deadline of 1 s passed on pull request 7; still pending: build", done.stderr)

    def test_no_checks_reported_three_times_then_a_pass_ends_0_not_as_three_failed_calls(self):
        done = self.wait(PLANT_NO_CHECKS="1,1,1,0")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(done.calls), 4, done.calls)

    def test_only_no_checks_reported_ends_1_after_the_no_check_limit(self):
        done = self.wait(PLANT_NO_CHECKS="1", PR_WAIT_NO_CHECK_SECONDS="0.05")
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("pr_wait: no check on pull request 7 after 0.05 s", done.stderr)

    def test_a_crash_of_the_script_exits_3_with_its_traceback_not_1(self):
        done = self.wait(PR_WAIT_POLL_SECONDS="soon")
        self.assertEqual(done.returncode, 3, done.stderr)
        self.assertIn("ValueError", done.stderr)

    def test_a_missing_or_non_number_argument_exits_2(self):
        for arguments in ((), ("seven",), ("7", "8")):
            with self.subTest(arguments):
                done = self.wait(arguments)
                self.assertEqual(done.returncode, 2, done.stderr)
                self.assertIn("usage: dev/pr_wait.sh N", done.stderr)
                self.assertEqual(done.calls, [])


if __name__ == "__main__":
    unittest.main()
