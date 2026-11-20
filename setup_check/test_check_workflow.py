"""The check workflow (.github/workflows/check.yml) on a merge group, and the scripts it
reads its base and its tested commit from.

A pull request merges through GitHub's merge queue, which runs the workflow on a
`merge_group` event for the pull request together with the ones ahead of it. The
workflow file is read as text (no YAML library is installed where these tests run):

- the `on:` block, and each job's one-line `if:`, which `job_runs` evaluates for an event
  with the three operators and the two functions the file's conditions use;
- the base the repeat job compares with comes from dev/ci_base.py, run on event payload
  fixtures shaped as GitHub sends them (pull_request: `pull_request.base.ref`;
  merge_group: `merge_group.base_sha`, "the SHA of the merge group's parent commit";
  push: `before` and `after`), because `github.base_ref` "is only available when the
  event that triggers a workflow run is either pull_request or pull_request_target"
  (docs.github.com, contexts reference), so it is empty on a merge group;
- dev/play_service/tested_tree.sh, which the push-to-main skip runs, is run against a
  planted `gh` that answers the check-runs and workflow-runs calls from a table.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
WORKFLOW = REPOSITORY / ".github" / "workflows" / "check.yml"
CI_BASE = REPOSITORY / "dev" / "ci_base.py"
TESTED_TREE = REPOSITORY / "dev" / "play_service" / "tested_tree.sh"

RUNNABLE = shutil.which("sh") is not None and shutil.which("bash") is not None


def workflow_events() -> dict[str, list[str]]:
    """The `on:` block: each event with the activity types listed under it ([] for none)."""
    events: dict[str, list[str]] = {}
    inside, current = False, None
    for line in WORKFLOW.read_text().splitlines():
        if re.match(r"^\S", line):
            inside = line.startswith("on:")
            continue
        if not inside:
            continue
        if found := re.match(r"^  (\w+):", line):
            current = found[1]
            events[current] = []
        elif current and (found := re.match(r"^    types: \[(.*)\]", line)):
            events[current] = [t.strip() for t in found[1].split(",")]
    return events


def job_conditions() -> dict[str, str | None]:
    """Each job's `if:` expression (None when it has none), without `${{ }}`."""
    jobs: dict[str, str | None] = {}
    inside, current = False, None
    for line in WORKFLOW.read_text().splitlines():
        if re.match(r"^\S", line):
            inside = line.startswith("jobs:")
            continue
        if not inside:
            continue
        if found := re.match(r"^  ([a-z][a-z-]*):\s*$", line):
            current = found[1]
            jobs[current] = None
        elif current and (found := re.match(r"^    if: (.*)$", line)):
            jobs[current] = re.sub(r"^\$\{\{\s*(.*?)\s*\}\}$", r"\1", found[1].strip())
    return jobs


def job_runs(condition: str | None, event_name: str, tested: str) -> bool:
    """Whether a job with this `if:` runs for an event when `tested`'s job gave `tested` as its
    output ("" when that job was skipped). The expression is the workflow's own, translated to
    Python: `!` is `not`, `&&` is `and`, `||` is `or`; `cancelled()` is false."""
    if condition is None:
        return True
    expression = condition.replace("!=", "\0").replace("!", " not ").replace("\0", "!=")
    expression = expression.replace("&&", " and ").replace("||", " or ")
    context = {
        "github": SimpleNamespace(event_name=event_name),
        "needs": SimpleNamespace(tested=SimpleNamespace(outputs=SimpleNamespace(tested=tested))),
        "cancelled": lambda: False,
    }
    return bool(eval(expression, {"__builtins__": {}}, context))  # the workflow's own text


# What each job does on each event, where `tested` is the push job's output when it ran.
# Evidence: the workflow's comments (tested is for a push to main; warm-caches replaces check
# and tools when it found them tested; repeat is for a change that is not yet in main).
RUNS = {
    #            tested  tools  check  repeat  warm-caches
    ("pull_request", ""): dict(tested=False, tools=True, check=True, repeat=True, warm_caches=False),
    ("merge_group", ""): dict(tested=False, tools=True, check=True, repeat=True, warm_caches=False),
    ("push", ""): dict(tested=True, tools=True, check=True, repeat=False, warm_caches=False),
    ("push", "true"): dict(tested=True, tools=False, check=False, repeat=False, warm_caches=True),
}


class WorkflowEventsTest(unittest.TestCase):
    def test_the_workflow_is_triggered_by_a_merge_group_as_well_as_a_pull_request_and_a_push_to_main(self):
        events = workflow_events()
        self.assertEqual(sorted(events), ["merge_group", "pull_request", "push"])
        self.assertEqual(events["merge_group"], ["checks_requested"], "the one activity type GitHub sends")

    def test_every_job_that_tests_code_runs_on_a_merge_group_event(self):
        conditions = job_conditions()
        self.assertEqual(sorted(conditions), ["check", "repeat", "tested", "tools", "warm-caches"])
        ran = {name for name, condition in conditions.items() if job_runs(condition, "merge_group", "")}
        self.assertEqual(ran, {"tools", "check", "repeat"},
                         "tested and warm-caches belong to a push to main, where a merge group's commit lands")

    def test_each_job_runs_on_the_events_the_table_says(self):
        conditions = job_conditions()
        for (event, tested), expected in RUNS.items():
            with self.subTest(event=event, tested=tested):
                got = {name.replace("-", "_"): job_runs(c, event, tested) for name, c in conditions.items()}
                self.assertEqual(got, expected)


FIXTURES = {
    "pull_request": {
        "action": "synchronize",
        "pull_request": {"number": 1153, "base": {"ref": "main", "sha": "1" * 40}, "head": {"sha": "2" * 40}},
    },
    "merge_group": {
        "action": "checks_requested",
        "merge_group": {
            "head_sha": "3" * 40,
            "head_ref": "refs/heads/gh-readonly-queue/main/pr-1153-" + "2" * 40,
            "base_ref": "refs/heads/main",
            "base_sha": "4" * 40,
        },
    },
    "push": {"ref": "refs/heads/main", "before": "5" * 40, "after": "6" * 40},
}


def base_of(event_name: str):
    """ci_base.py run for an event fixture, the way a workflow step runs it."""
    with tempfile.TemporaryDirectory() as folder:
        payload = Path(folder) / "event.json"
        payload.write_text(json.dumps(FIXTURES[event_name]))
        environment = {"PATH": os.environ["PATH"], "GITHUB_EVENT_NAME": event_name, "GITHUB_EVENT_PATH": str(payload)}
        return subprocess.run(
            ["python3.13", "-I", str(CI_BASE)], capture_output=True, text=True, env=environment
        )


@unittest.skipUnless(shutil.which("python3.13"), "the workflow runs its scripts with python3.13")
class BaseOfARunTest(unittest.TestCase):
    def test_the_base_of_a_merge_group_is_the_base_sha_the_event_carries(self):
        done = base_of("merge_group")
        self.assertEqual((done.returncode, done.stdout), (0, "4" * 40 + "\n"), done.stderr)

    def test_the_base_of_a_pull_request_is_its_base_branch_on_origin(self):
        done = base_of("pull_request")
        self.assertEqual((done.returncode, done.stdout), (0, "origin/main\n"), done.stderr)

    def test_a_push_has_no_base_and_the_script_says_so(self):
        done = base_of("push")
        self.assertEqual((done.returncode, done.stdout), (2, ""))
        self.assertIn("push", done.stderr)

    def test_the_repeat_job_takes_its_base_from_the_script_and_no_step_reads_the_empty_base_ref(self):
        text = WORKFLOW.read_text()
        self.assertNotIn("github.base_ref", text, "it is empty on a merge group")
        repeat = text[text.index("\n  repeat:"):text.index("\n  warm-caches:")]
        self.assertEqual(repeat.count("dev/ci_base.py"), 2, "the list step and the run step")
        self.assertIn("fetch-depth: 0", repeat, "the merge base with the group's base sha needs the history")



# A `gh api PATH --jq EXPR` that answers from the file in $PLANT_GH named for PATH (every run
# of characters other than letters and digits turned into "_"), through jq; any other call,
# and a path without a file, fails as GitHub's 404 does.
GH_STUB = """#!/bin/sh
[ "$1" = api ] && [ "$3" = --jq ] || { echo "planted gh: unexpected $*" >&2; exit 9; }
name=$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]\\{1,\\}/_/g')
if [ -f "$PLANT_GH/$name" ]; then jq -r "$4" < "$PLANT_GH/$name"; exit 0; fi
echo "HTTP 404: planted gh has no answer for $2" >&2
exit 1
"""

REPO = "owner/repo"
COMMIT = "c" * 40
PARENT = "b" * 40
TREE = "7" * 40
OTHER_TREE = "8" * 40
JOBS = ("check", "tools")


def file_name(path: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", path)


@unittest.skipUnless(RUNNABLE and shutil.which("jq"), "the planted gh needs sh, bash and jq")
class TestedTreeTest(unittest.TestCase):
    """The push-to-main skip: tested_tree.sh finds a commit whose files a passed run of check and
    tools tested, on the commit itself (a merge group's run) or on a parent (a pull request's)."""

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        (self.root / "answers").mkdir()
        stub = self.root / "bin" / "gh"
        stub.parent.mkdir()
        stub.write_text(GH_STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
        self.answer(f"repos/{REPO}/commits/{COMMIT}",
                    {"commit": {"tree": {"sha": TREE}}, "parents": [{"sha": PARENT}]})
        self.merge_group_runs([])
        self.answer(f"repos/{REPO}/commits/{PARENT}/check-runs?per_page=100", {"check_runs": []})

    def answer(self, path: str, body) -> None:
        (self.root / "answers" / file_name(path)).write_text(json.dumps(body))

    def merge_group_runs(self, run_ids: list[int]) -> None:
        self.answer(f"repos/{REPO}/actions/runs?head_sha={COMMIT}&event=merge_group&per_page=100",
                    {"workflow_runs": [{"id": i} for i in run_ids]})

    def merge_group_run(self, run_id: int, conclusions: dict[str, str], tree: str = TREE) -> None:
        """A merge group run of the commit whose jobs ended as `conclusions` ("" for a job still
        running) and noted `tree`."""
        jobs = []
        for number, (name, conclusion) in enumerate(conclusions.items()):
            job_id = run_id * 10 + number
            status = "completed" if conclusion else "in_progress"
            jobs.append({"id": job_id, "name": name, "status": status, "conclusion": conclusion or None})
            self.answer(f"repos/{REPO}/check-runs/{job_id}/annotations?per_page=100",
                        [{"message": f"tested tree {tree}"}])
        self.answer(f"repos/{REPO}/actions/runs/{run_id}/jobs?per_page=100", {"jobs": jobs})

    def parent_runs(self, conclusions: dict[str, str], tree: str = TREE) -> None:
        runs = []
        for number, (name, conclusion) in enumerate(conclusions.items()):
            run_id = 900 + number
            runs.append({"id": run_id, "name": name, "status": "completed", "conclusion": conclusion})
            self.answer(f"repos/{REPO}/check-runs/{run_id}/annotations?per_page=100",
                        [{"message": f"tested tree {tree}"}])
        self.answer(f"repos/{REPO}/commits/{PARENT}/check-runs?per_page=100", {"check_runs": runs})

    def run_script(self):
        environment = {"PATH": f"{self.root / 'bin'}:{os.environ['PATH']}", "PLANT_GH": str(self.root / "answers")}
        return subprocess.run(["bash", str(TESTED_TREE), REPO, COMMIT, *JOBS],
                              capture_output=True, text=True, env=environment)

    def test_a_commit_a_passed_merge_group_run_tested_is_found_on_the_commit_itself(self):
        self.merge_group_runs([11])
        self.merge_group_run(11, {"check": "success", "tools": "success"})
        done = self.run_script()
        self.assertEqual((done.returncode, done.stdout.strip()), (0, COMMIT), done.stderr)

    def test_a_merge_group_run_with_a_failed_job_does_not_make_the_commit_tested(self):
        self.merge_group_runs([11])
        self.merge_group_run(11, {"check": "success", "tools": "failure"})
        self.assertEqual(self.run_script().returncode, 1)

    def test_a_merge_group_run_of_another_tree_does_not_make_the_commit_tested(self):
        self.merge_group_runs([11])
        self.merge_group_run(11, {"check": "success", "tools": "success"}, tree=OTHER_TREE)
        self.assertEqual(self.run_script().returncode, 1)

    def test_a_merge_group_run_that_has_not_ended_does_not_make_the_commit_tested(self):
        self.merge_group_runs([11])
        self.merge_group_run(11, {"check": "success", "tools": ""})
        self.assertEqual(self.run_script().returncode, 1)

    def test_a_parent_whose_pull_request_run_tested_the_same_tree_is_still_found(self):
        self.parent_runs({"check": "success", "tools": "success"})
        done = self.run_script()
        self.assertEqual((done.returncode, done.stdout.strip()), (0, PARENT), done.stderr)

    def test_a_commit_no_run_tested_is_not_found(self):
        self.assertEqual(self.run_script().returncode, 1)

    def test_a_commit_github_cannot_be_asked_about_is_status_2(self):
        (self.root / "answers" / file_name(f"repos/{REPO}/commits/{COMMIT}")).unlink()
        self.assertEqual(self.run_script().returncode, 2)


if __name__ == "__main__":
    unittest.main()
