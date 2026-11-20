"""dev/pr_wait.sh: what it waits for and how it ends, on a planted `gh`.

The planted gh answers `gh pr view N --json statusCheckRollup` with one check, ends
`gh pr checks N --watch` with the status in PLANT_CHECKS_STATUS (default 0), and answers
the GraphQL question about the pull request ("STATE IN_QUEUE AUTO", e.g. "OPEN true false")
with the next line of $PLANT_STATES, the last line again when they run out, so a test
states the queue's course as a list. PR_WAIT_QUEUE_POLL_SECONDS=0 keeps a poll from sleeping.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
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
  "pr view") echo 1 ;;
  "pr checks") exit "${PLANT_CHECKS_STATUS:-0}" ;;
  "api graphql")
    n=$(cat "$PLANT_DIR/asked" 2>/dev/null || echo 0)
    n=$((n + 1)); echo "$n" > "$PLANT_DIR/asked"
    line=$(sed -n "${n}p" "$PLANT_DIR/states")
    [ -n "$line" ] || line=$(tail -n 1 "$PLANT_DIR/states")
    echo "$line" ;;
  *) echo "planted gh: unexpected $*" >&2; exit 9 ;;
esac
"""


@unittest.skipUnless(RUNNABLE, "pr_wait.sh needs bash")
class PullRequestWaitTest(unittest.TestCase):
    def wait(self, states: list[str], checks_status: int = 0) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stub = root / "bin" / "gh"
            stub.parent.mkdir()
            stub.write_text(GH_STUB)
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            (root / "states").write_text("\n".join(states) + "\n")
            environment = {
                "PATH": f"{stub.parent}:{os.environ['PATH']}", "PLANT_DIR": str(root),
                "PLANT_CHECKS_STATUS": str(checks_status), "PR_WAIT_QUEUE_POLL_SECONDS": "0",
            }
            done = subprocess.run(["bash", str(SCRIPT), "7"], capture_output=True, text=True, env=environment)
            done.asked = int((root / "asked").read_text()) if (root / "asked").exists() else 0
            return done

    def test_a_pull_request_that_is_not_queued_when_its_checks_end_ends_the_wait_there(self):
        done = self.wait(["OPEN false false"])
        self.assertEqual((done.returncode, done.asked), (0, 1), done.stderr)

    def test_a_queued_pull_request_is_followed_until_the_queue_merges_it(self):
        done = self.wait(["OPEN true false", "OPEN true false", "MERGED false false"])
        self.assertEqual((done.returncode, done.asked), (0, 3), done.stderr)
        self.assertIn("merged", done.stdout)

    def test_a_pull_request_with_auto_merge_set_is_followed_until_it_merges(self):
        done = self.wait(["OPEN false true", "MERGED false false"])
        self.assertEqual((done.returncode, done.asked), (0, 2), done.stderr)

    def test_a_pull_request_the_queue_drops_fails_the_wait(self):
        done = self.wait(["OPEN true false", "OPEN false false"])
        self.assertEqual(done.returncode, 1)
        self.assertIn("left the merge queue", done.stderr)

    def test_a_pull_request_closed_without_merging_fails_the_wait(self):
        done = self.wait(["OPEN true false", "CLOSED false false"])
        self.assertEqual(done.returncode, 1)
        self.assertIn("closed", done.stderr)

    def test_failed_checks_end_the_wait_with_their_status_and_ask_nothing_of_the_queue(self):
        done = self.wait(["OPEN true false"], checks_status=1)
        self.assertEqual((done.returncode, done.asked), (1, 0), done.stderr)


if __name__ == "__main__":
    unittest.main()
