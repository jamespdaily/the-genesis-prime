"""dev/merge_when_green.sh: each path of the merge of one pull request, on a planted `git`, `gh`
and `pr_wait.sh`.

The script is copied into a temporary `dev/` beside a planted pr_wait.sh, and runs with a PATH
whose `git` and `gh` are planted. Every call is kept in PLANT_DIR/calls as one line.

- git: `worktree add --detach DIR REF` makes DIR with a planted `check` in it; `worktree remove`
  removes it; `rev-parse HEAD` prints PLANT_DIR/head (the pull request's head, a new one after
  each merge of main); `merge-base --is-ancestor origin/main HEAD` answers yes or no from the
  next line of PLANT_DIR/ancestry (the last again when they run out), so a test states how main
  moves as a list; `merge --no-edit origin/main` conflicts in PLANT_CONFLICT_FILES when that is
  set, else makes the next head; `diff --name-only --diff-filter=U` prints the conflicted files.
- gh: `pr view` answers with the pull request (OPEN, main, the branch, the head); `pr merge` is
  only kept.
- pr_wait.sh: ends with PLANT_WAIT_STATUS (default 0), after printing PLANT_WAIT_STDERR.
- check (in the worktree): ends with PLANT_CHECK_STATUS (default 0).

The tests merge nothing: gh never reaches GitHub.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_merge_when_green.py'
"""

import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "dev" / "merge_when_green.sh"

RUNNABLE = shutil.which("bash") is not None

BRANCH = "jimd/1-the-step"
FIRST_HEAD = "head0"

GIT_STUB = """#!/bin/bash
echo "git $*" >> "$PLANT_DIR/calls"
if [ "$1" = -C ]; then shift 2; fi
command=$1
shift
next_line() {  # next_line FILE COUNTER: the counter's next line of FILE, the last when it runs out
  n=$(cat "$PLANT_DIR/$2" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$PLANT_DIR/$2"
  line=$(sed -n "${n}p" "$PLANT_DIR/$1")
  [ -n "$line" ] || line=$(tail -n 1 "$PLANT_DIR/$1")
  echo "$line"
}
case "$command" in
  fetch) ;;
  worktree)
    case "$1" in
      add)
        mkdir -p "$3"
        printf '#!/bin/bash\\necho "check $*" >> "$PLANT_DIR/calls"\\nexit "${PLANT_CHECK_STATUS:-0}"\\n' > "$3/check"
        chmod +x "$3/check" ;;
      remove) rm -rf "${@: -1}" ;;
    esac ;;
  rev-parse) cat "$PLANT_DIR/head" ;;
  merge-base) [ "$(next_line ancestry ancestry_asked)" = yes ] ;;
  merge)
    [ "$1" = --abort ] && exit 0
    if [ -n "$PLANT_CONFLICT_FILES" ]; then echo "CONFLICT (content)"; exit 1; fi
    n=$(cat "$PLANT_DIR/merges" 2>/dev/null || echo 0)
    n=$((n + 1)); echo "$n" > "$PLANT_DIR/merges"
    echo "head$n" > "$PLANT_DIR/head" ;;
  diff) printf '%s\\n' $PLANT_CONFLICT_FILES ;;
  push) ;;
  *) echo "planted git: unexpected $command $*" >&2; exit 9 ;;
esac
"""

GH_STUB = """#!/bin/bash
echo "gh $*" >> "$PLANT_DIR/calls"
case "$1 $2" in
  "pr view")
    case "$*" in
      *baseRefName*) echo "OPEN main $PLANT_BRANCH $(cat "$PLANT_DIR/head")" ;;
      *) cat "$PLANT_DIR/head" ;;
    esac ;;
  "pr merge") ;;
  *) echo "planted gh: unexpected $*" >&2; exit 9 ;;
esac
"""

PR_WAIT_STUB = """#!/bin/bash
echo "pr_wait $*" >> "$PLANT_DIR/calls"
[ -n "$PLANT_WAIT_STDERR" ] && echo "$PLANT_WAIT_STDERR" >&2
exit "${PLANT_WAIT_STATUS:-0}"
"""


def executable(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def steps(calls: list[str]) -> list[str]:
    """The calls that matter to the order of a merge, each as one word."""
    named = [
        (r"^git .*merge --no-edit .*origin/main", "merge-main"),
        (r"^git .*merge --abort", "abort"),
        (r"^check fast$", "check"),
        (r"^git .*push ", "push"),
        (r"^pr_wait 7$", "wait"),
        (r"^gh pr merge 7 ", "merge"),
    ]
    return [word for call in calls for pattern, word in named if re.search(pattern, call)]


@unittest.skipUnless(RUNNABLE, "merge_when_green.sh needs bash")
class MergeWhenGreenTest(unittest.TestCase):
    def merge(self, ancestry: list[str], **plant: str) -> subprocess.CompletedProcess:
        directory = tempfile.TemporaryDirectory(prefix="genesis-merge-when-green-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name).resolve()
        state, caller = root / "state", root / "caller"
        state.mkdir()
        caller.mkdir()
        (state / "ancestry").write_text("\n".join(ancestry) + "\n")
        (state / "head").write_text(FIRST_HEAD + "\n")
        executable(root / "bin" / "git", GIT_STUB)
        executable(root / "bin" / "gh", GH_STUB)
        executable(root / "repository" / "dev" / "pr_wait.sh", PR_WAIT_STUB)
        shutil.copyfile(SCRIPT, root / "repository" / "dev" / "merge_when_green.sh")
        environment = {
            "PATH": f"{root / 'bin'}:{os.environ['PATH']}", "PLANT_DIR": str(state), "PLANT_BRANCH": BRANCH,
            "MERGE_WHEN_GREEN_POLL_SECONDS": "0", "TMPDIR": str(root), **plant,
        }
        done = subprocess.run(
            ["bash", str(root / "repository" / "dev" / "merge_when_green.sh"), "7"],
            capture_output=True, text=True, env=environment, cwd=caller,
        )
        calls = state / "calls"
        done.calls = calls.read_text().splitlines() if calls.exists() else []
        done.root, done.caller = root, caller
        return done

    def assert_worktree_made_and_removed(self, done: subprocess.CompletedProcess) -> None:
        """The script worked in a worktree of its own, not the caller's folder, and left none."""
        added = [c for c in done.calls if re.search(r"worktree add --detach \S+ origin/" + BRANCH, c)]
        self.assertEqual(len(added), 1, done.calls)
        folder = added[0].split()[-2]
        self.assertNotEqual(Path(folder).resolve(), done.caller)
        self.assertTrue(any(re.search(r"worktree remove .*" + re.escape(folder), c) for c in done.calls), done.calls)
        self.assertFalse(Path(folder).exists())
        self.assertEqual(list(done.caller.iterdir()), [], "the caller's folder was touched")

    def test_a_branch_that_holds_main_and_has_green_ci_merges_without_a_merge_of_main(self):
        done = self.merge(["yes"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(steps(done.calls), ["wait", "merge"])
        self.assertIn(f"gh pr merge 7 --merge --match-head-commit {FIRST_HEAD}", done.calls)
        self.assert_worktree_made_and_removed(done)

    def test_main_having_moved_it_is_merged_in_checked_pushed_and_waited_on_before_the_merge(self):
        done = self.merge(["no", "yes"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(steps(done.calls), ["merge-main", "check", "push", "wait", "merge"])
        self.assertIn("gh pr merge 7 --merge --match-head-commit head1", done.calls)
        self.assertTrue(any(re.search(rf"push .*origin HEAD:refs/heads/{BRANCH}$", c) for c in done.calls), done.calls)
        self.assert_worktree_made_and_removed(done)

    def test_main_moving_again_while_ci_runs_repeats_the_merge_of_main_and_the_wait(self):
        done = self.merge(["no", "no", "yes"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(
            steps(done.calls),
            ["merge-main", "check", "push", "wait", "merge-main", "check", "push", "wait", "merge"],
        )
        self.assertIn("gh pr merge 7 --merge --match-head-commit head2", done.calls)
        self.assert_worktree_made_and_removed(done)

    def test_a_conflict_with_main_stops_names_the_files_and_pushes_nothing(self):
        done = self.merge(["no"], PLANT_CONFLICT_FILES="src/spell.gleam src/cast.gleam")
        self.assertEqual(done.returncode, 1)
        self.assertIn("src/spell.gleam", done.stderr)
        self.assertIn("src/cast.gleam", done.stderr)
        self.assertEqual(steps(done.calls), ["merge-main", "abort"])
        self.assert_worktree_made_and_removed(done)

    def test_a_check_fast_that_fails_after_the_merge_pushes_nothing(self):
        done = self.merge(["no"], PLANT_CHECK_STATUS="1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("./check fast failed", done.stderr)
        self.assertEqual(steps(done.calls), ["merge-main", "check"])
        self.assert_worktree_made_and_removed(done)

    def test_failing_ci_stops_without_a_merge_and_names_the_failing_job(self):
        done = self.merge(
            ["yes"], PLANT_WAIT_STATUS="1", PLANT_WAIT_STDERR="pr_wait: failing jobs: unit-tests, client-parts",
        )
        self.assertEqual(done.returncode, 1)
        self.assertIn("unit-tests, client-parts", done.stderr)
        self.assertEqual(steps(done.calls), ["wait"])
        self.assert_worktree_made_and_removed(done)

    def test_a_wait_that_ends_in_a_github_error_stops_and_is_not_reported_as_failing_ci(self):
        done = self.merge(["yes"], PLANT_WAIT_STATUS="3", PLANT_WAIT_STDERR="pr_wait: a GitHub call failed")
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("CI failed", done.stderr)
        self.assertIn("exit 3", done.stderr)
        self.assertEqual(steps(done.calls), ["wait"])
        self.assert_worktree_made_and_removed(done)


if __name__ == "__main__":
    unittest.main()
