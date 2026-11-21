"""dev/hooks/progress_lines.py: the merge line of a pull request that dev/merge_when_green.sh P
merged.

`dev/merge_when_green.sh P` runs `gh pr merge` inside itself, so the hook never sees that
command; it reads the script's own command line as the merge of P. Each test drives the hook's
functions (`events_of`, `report`) with a planted GitHub and the dry run, which prints
"#issue: line" in place of posting and runs no clean-up.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_progress_lines.py'
"""

import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "dev" / "hooks"))

import progress_lines  # noqa: E402

ISSUE = 1160
NUMBER = 1161
HEAD = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
MERGE_COMMIT = "0f9e8d7c6b5a49382716f5e4d3c2b1a009876543"


class PlantedGitHub:
    """One pull request in a state, with passing checks, on an issue with no comments."""

    def __init__(self, state: str):
        self.state = state

    def pull_request(self, target, folder) -> dict:
        merged = self.state == "MERGED"
        return {
            "number": NUMBER, "state": self.state, "headRefName": f"jimd/{ISSUE}-merge-when-green",
            "headRefOid": HEAD, "mergeCommit": {"oid": MERGE_COMMIT} if merged else None,
            "closingIssuesReferences": [],
        }

    def comments(self, issue: int) -> list[str]:
        return []

    def checks(self, number: int) -> list[dict]:
        return [{"bucket": "pass", "link": ""}]

    def run_attempt(self, links) -> int:
        return 1


def hook_input(command: str) -> dict:
    return {"tool_name": "Bash", "tool_input": {"command": command}, "tool_response": {"stdout": ""},
            "cwd": "/nowhere"}


class MergeScriptTest(unittest.TestCase):
    def posted(self, state: str, command: str) -> list[str]:
        """The lines the hook prints for one Bash call, a pull request in `state`."""
        output = io.StringIO()
        with mock.patch.object(progress_lines, "names_repository", return_value=True), \
                contextlib.redirect_stdout(output):
            for event in progress_lines.events_of(hook_input(command)):
                progress_lines.report(event, PlantedGitHub(state), True, [])
        return output.getvalue().splitlines()

    def test_the_merge_script_ending_on_a_merged_pull_request_posts_the_ci_and_merge_lines(self):
        lines = self.posted("MERGED", f"dev/merge_when_green.sh {NUMBER}")
        self.assertEqual(lines, [
            f"#{ISSUE}: CI passed on {HEAD[:7]}, pull request {NUMBER}, attempt 1",
            f"#{ISSUE}: merged: pull request {NUMBER} ({MERGE_COMMIT[:7]})",
        ])

    def test_the_merge_script_ending_on_an_open_pull_request_posts_no_merge_line(self):
        self.assertEqual(self.posted("OPEN", f"dev/merge_when_green.sh {NUMBER}"), [])

    def test_a_path_to_the_merge_script_is_read_as_the_script(self):
        lines = self.posted("MERGED", f"cd /somewhere && /abs/dev/merge_when_green.sh {NUMBER}")
        self.assertEqual(len(lines), 2, lines)


if __name__ == "__main__":
    unittest.main()
