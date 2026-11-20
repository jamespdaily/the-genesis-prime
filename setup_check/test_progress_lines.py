"""dev/hooks/progress_lines.py: the lines it posts when a pull request merges through the
merge queue.

`gh pr merge N --merge --auto` adds a pull request to the queue and returns while it is
still OPEN; the queue merges it later, when the group's checks have passed. So the merge
line is posted by the call that sees the pull request MERGED: `dev/pr_wait.sh N`, which
follows the queue to its end (test_pr_wait.py). Each test drives the hook's own functions
(`events_of`, `report`) with a planted GitHub that keeps the comments the hook posted.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "dev" / "hooks"))

import progress_lines  # noqa: E402
from step_issue import REPOSITORY  # noqa: E402

ISSUE = 1153
NUMBER = 1160
HEAD = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
MERGE_COMMIT = "0f9e8d7c6b5a49382716f5e4d3c2b1a009876543"
BRANCH = f"jimd/{ISSUE}-merge-queue"


class PlantedGitHub:
    """What the hook asks GitHub: one pull request in a state, its checks, an issue whose
    comments are the lines the hook posted."""

    def __init__(self, state: str):
        self.state = state
        self.comments_posted: list[str] = []

    def pull_request(self, target, folder) -> dict:
        pull = {
            "number": NUMBER, "state": self.state, "headRefName": BRANCH, "headRefOid": HEAD,
            "mergeCommit": None, "closingIssuesReferences": [],
        }
        if self.state == "MERGED":
            pull["mergeCommit"] = {"oid": MERGE_COMMIT}
        return pull

    def comments(self, issue: int) -> list[str]:
        return list(self.comments_posted)

    def checks(self, number: int) -> list[dict]:
        return [{"bucket": "pass", "link": ""}]

    def run_attempt(self, links) -> int:
        return 1

    def card_status(self, issue: int) -> str:
        return "In progress"


def hook_input(command: str) -> dict:
    return {"tool_name": "Bash", "tool_input": {"command": command}, "tool_response": {"stdout": ""},
            "cwd": "/nowhere"}


class QueuedMergeTest(unittest.TestCase):
    def run_hook(self, github: PlantedGitHub, command: str) -> list[str]:
        """The comments the hook posts on the step's issue for one Bash call; the planted folder
        is this repository's."""
        posted: list[str] = []

        def record(planted, issue, body, dry_run):
            self.assertEqual(issue, ISSUE)
            posted.append(body)
            planted.comments_posted.append(body)

        events = progress_lines.events_of(hook_input(command))
        self.assertTrue(events, f"the hook reads {command!r} as an event")
        with mock.patch.object(progress_lines, "post", record), \
                mock.patch.object(progress_lines, "names_repository", lambda folder, remote: True):
            for event in events:
                progress_lines.report(event, github, True, [])
        return posted

    def merge_lines(self, github: PlantedGitHub) -> list[str]:
        return [c for c in github.comments_posted if c.startswith(f"merged: pull request {NUMBER} (")]

    def test_a_queued_merge_posts_the_merge_line_once(self):
        queue_command = f"gh pr merge {NUMBER} -R {REPOSITORY} --merge --auto"
        wait_command = f"dev/pr_wait.sh {NUMBER}"
        github = PlantedGitHub("OPEN")

        self.assertEqual(self.run_hook(github, queue_command), [], "queued, not yet merged: no line")

        github.state = "MERGED"
        first = self.run_hook(github, wait_command)
        self.assertEqual(self.merge_lines(github), [f"merged: pull request {NUMBER} ({MERGE_COMMIT[:7]})"], first)

        self.run_hook(github, wait_command)
        self.run_hook(github, queue_command)
        self.assertEqual(len(self.merge_lines(github)), 1, github.comments_posted)

    def test_a_wait_that_ends_on_a_pull_request_still_open_posts_no_merge_line(self):
        github = PlantedGitHub("OPEN")
        self.run_hook(github, f"dev/pr_wait.sh {NUMBER}")
        self.assertEqual(self.merge_lines(github), [])
        self.assertEqual(github.comments_posted, [f"CI passed on {HEAD[:7]}, pull request {NUMBER}, attempt 1"])


if __name__ == "__main__":
    unittest.main()
