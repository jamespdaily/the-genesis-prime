"""dev/merge_when_green.sh: each path of the merge of one pull request, on a planted `git`, `gh`
and `pr_wait.sh`, and the safety properties again on a real git with a local bare origin.

The script is copied into a temporary `dev/` beside a planted pr_wait.sh, and runs with a PATH
whose `git` and `gh` are planted. Every call is kept in PLANT_DIR/calls as one line. The merge
worktree (MERGE_WHEN_GREEN_WORKTREE) is a folder of the test's own.

- git: `worktree add --detach DIR REF` makes DIR with a planted `check` in it; `worktree remove`
  removes it; `rev-parse HEAD` prints PLANT_DIR/head (the pull request's head, a new one after
  each merge of main); `rev-parse --git-common-dir` prints one fixed folder; `merge-base
  --is-ancestor origin/main HEAD` answers yes or no from the next line of PLANT_DIR/ancestry (the
  last again when they run out), so a test states how main moves as a list; `merge --no-edit
  origin/main` conflicts in PLANT_CONFLICT_FILES when that is set, else makes the next head;
  `diff --name-only --diff-filter=U` prints the conflicted files.
- gh: `pr view` answers with the pull request (OPEN, main, the branch, the head); `pr merge` is
  only kept.
- pr_wait.sh: ends with PLANT_WAIT_STATUS (default 0), after printing PLANT_WAIT_STDERR.
- check (in the worktree): ends with PLANT_CHECK_STATUS (default 0).

The real-git tests plant only `gh` (answering from the local origin), pr_wait.sh and a small
`check` committed on the branch; git is the machine's.

The tests merge nothing: gh never reaches GitHub.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_merge_when_green.py'
"""

import os
import re
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

SCRIPT = HERE.parent / "dev" / "merge_when_green.sh"

RUNNABLE = shutil.which("bash") is not None and shutil.which("git") is not None

BRANCH = "jimd/1-the-step"
FIRST_HEAD = "head0"

GIT_STUB = """#!/bin/bash
echo "git $*" >> "$PLANT_DIR/calls"
if [ "$1" = -C ]; then shift 2; fi
command=$1
shift
""" + NEXT_LINE + """case "$command" in
  fetch|reset|clean) ;;
  worktree)
    case "$1" in
      prune) ;;
      add)
        mkdir -p "$3"
        touch "$3/.git"
        printf '#!/bin/bash\\necho "check $*" >> "$PLANT_DIR/calls"\\nexit "${PLANT_CHECK_STATUS:-0}"\\n' > "$3/check"
        chmod +x "$3/check" ;;
      remove) rm -rf "${@: -1}" ;;
    esac ;;
  rev-parse)
    case "$*" in
      *--git-common-dir*) echo /planted/git-common-dir ;;
      *) cat "$PLANT_DIR/head" ;;
    esac ;;
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

CHECK_STUB = """#!/bin/bash
echo "check $*" >> "$PLANT_DIR/calls"
exit "${PLANT_CHECK_STATUS:-0}"
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
        (r"^git .*reset .*--hard .*origin/" + re.escape(BRANCH) + "$", "reset"),
        (r"^git .*merge --no-edit .*origin/main", "merge-main"),
        (r"^git .*merge --abort", "abort"),
        (r"^check fast$", "check"),
        (r"^git .*push ", "push"),
        (r"^pr_wait 7$", "wait"),
        (r"^gh pr merge 7 ", "merge"),
    ]
    return [word for call in calls for pattern, word in named if re.search(pattern, call)]


@unittest.skipUnless(RUNNABLE, "merge_when_green.sh needs bash and git")
class MergeWhenGreenTest(unittest.TestCase):
    def merge(
        self, ancestry: list[str], *, existing: bool = False, lock_pid: int | None = None, **plant: str,
    ) -> subprocess.CompletedProcess:
        directory = tempfile.TemporaryDirectory(prefix="genesis-merge-when-green-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name).resolve()
        state, caller, worktree = root / "state", root / "caller", root / "merge-worktree"
        state.mkdir()
        caller.mkdir()
        (state / "ancestry").write_text("\n".join(ancestry) + "\n")
        (state / "head").write_text(FIRST_HEAD + "\n")
        if existing:
            worktree.mkdir()
            (worktree / ".git").touch()
            executable(worktree / "check", CHECK_STUB)
        if lock_pid is not None:
            os.symlink(str(lock_pid), root / "merge-worktree.lock")
        executable(root / "bin" / "git", GIT_STUB)
        executable(root / "bin" / "gh", GH_STUB)
        executable(root / "repository" / "dev" / "pr_wait.sh", PR_WAIT_STUB)
        shutil.copyfile(SCRIPT, root / "repository" / "dev" / "merge_when_green.sh")
        environment = {
            "PATH": f"{root / 'bin'}:{os.environ['PATH']}", "PLANT_DIR": str(state), "PLANT_BRANCH": BRANCH,
            "MERGE_WHEN_GREEN_POLL_SECONDS": "0", "MERGE_WHEN_GREEN_WORKTREE": str(worktree),
            "TMPDIR": str(root), **plant,
        }
        done = subprocess.run(
            ["bash", str(root / "repository" / "dev" / "merge_when_green.sh"), "7"],
            capture_output=True, text=True, env=environment, cwd=caller,
        )
        calls = state / "calls"
        done.calls = calls.read_text().splitlines() if calls.exists() else []
        done.root, done.caller, done.worktree, done.existing = root, caller, worktree, existing
        return done

    def assert_worktree_kept_and_reset(self, done: subprocess.CompletedProcess) -> None:
        """The script worked in the merge worktree, made on first use and reused after, reset to
        the branch before anything else, and left it and its build in place."""
        added = [c for c in done.calls if re.search(r"worktree add --detach \S+ origin/" + BRANCH, c)]
        self.assertEqual(len(added), 0 if done.existing else 1, done.calls)
        self.assertTrue(all(c.split()[-2] == str(done.worktree) for c in added), added)
        self.assertEqual(steps(done.calls)[0], "reset", done.calls)
        self.assertFalse(any("worktree remove" in c for c in done.calls), done.calls)
        self.assertTrue(done.worktree.exists())
        self.assertEqual(list(done.caller.iterdir()), [], "the caller's folder was touched")
        self.assertFalse((done.root / "merge-worktree.lock").is_symlink(), "the lock was left")
        self.assertEqual(sorted(p.name for p in done.root.iterdir() if p.name.startswith("merge-when-green")), [])

    def test_a_branch_that_holds_main_and_has_green_ci_merges_without_a_merge_of_main(self):
        done = self.merge(["yes"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "wait", "merge"])
        self.assertIn(f"gh pr merge 7 --merge --match-head-commit {FIRST_HEAD}", done.calls)
        self.assert_worktree_kept_and_reset(done)

    def test_main_having_moved_it_is_merged_in_checked_pushed_and_waited_on_before_the_merge(self):
        done = self.merge(["no", "yes"], existing=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "merge-main", "check", "push", "wait", "merge"])
        self.assertIn("gh pr merge 7 --merge --match-head-commit head1", done.calls)
        self.assertTrue(any(re.search(rf"push .*origin HEAD:refs/heads/{BRANCH}$", c) for c in done.calls), done.calls)
        self.assert_worktree_kept_and_reset(done)

    def test_main_moving_again_while_ci_runs_repeats_the_merge_of_main_and_the_wait(self):
        done = self.merge(["no", "no", "yes"])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(
            steps(done.calls),
            ["reset", "merge-main", "check", "push", "wait", "merge-main", "check", "push", "wait", "merge"],
        )
        self.assertIn("gh pr merge 7 --merge --match-head-commit head2", done.calls)
        self.assert_worktree_kept_and_reset(done)

    def test_a_main_that_keeps_moving_stops_after_three_rounds_without_a_merge(self):
        done = self.merge(["no"])
        self.assertEqual(done.returncode, 1)
        self.assertIn("3 rounds", done.stderr)
        self.assertEqual(steps(done.calls), ["reset"] + ["merge-main", "check", "push", "wait"] * 3)
        self.assert_worktree_kept_and_reset(done)

    def test_a_conflict_with_main_stops_names_the_files_and_pushes_nothing(self):
        done = self.merge(["no"], PLANT_CONFLICT_FILES="src/spell.gleam src/cast.gleam")
        self.assertEqual(done.returncode, 1)
        self.assertIn("src/spell.gleam", done.stderr)
        self.assertIn("src/cast.gleam", done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "merge-main", "abort"])
        self.assert_worktree_kept_and_reset(done)

    def test_a_check_fast_that_fails_after_the_merge_pushes_nothing(self):
        done = self.merge(["no"], PLANT_CHECK_STATUS="1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("./check fast failed", done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "merge-main", "check"])
        self.assert_worktree_kept_and_reset(done)

    def test_failing_ci_stops_without_a_merge_and_names_the_failing_job(self):
        done = self.merge(
            ["yes"], PLANT_WAIT_STATUS="1", PLANT_WAIT_STDERR="pr_wait: failing jobs: unit-tests, client-parts",
        )
        self.assertEqual(done.returncode, 1)
        self.assertIn("unit-tests, client-parts", done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "wait"])
        self.assert_worktree_kept_and_reset(done)

    def test_a_wait_that_ends_in_a_github_error_stops_and_is_not_reported_as_failing_ci(self):
        done = self.merge(["yes"], PLANT_WAIT_STATUS="3", PLANT_WAIT_STDERR="pr_wait: a GitHub call failed")
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("CI failed", done.stderr)
        self.assertIn("exit 3", done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "wait"])
        self.assert_worktree_kept_and_reset(done)

    def test_a_run_while_another_holds_the_merge_worktree_stops_before_touching_it(self):
        done = self.merge(["yes"], existing=True, lock_pid=os.getpid())
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"pid {os.getpid()}", done.stderr)
        self.assertEqual(steps(done.calls), [])
        self.assertTrue((done.root / "merge-worktree.lock").is_symlink(), "the other run's lock was removed")

    def test_a_lock_left_by_a_run_that_is_gone_is_taken_over(self):
        gone = subprocess.Popen(["true"])
        gone.wait()
        done = self.merge(["yes"], existing=True, lock_pid=gone.pid)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(steps(done.calls), ["reset", "wait", "merge"])
        self.assert_worktree_kept_and_reset(done)


GIT_ENVIRONMENT = {
    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
}

REAL_GH_STUB = """#!/bin/bash
echo "gh $*" >> "$PLANT_DIR/calls"
head=$(git --git-dir="$PLANT_ORIGIN" rev-parse "refs/heads/$PLANT_BRANCH")
case "$1 $2" in
  "pr view")
    case "$*" in
      *baseRefName*) echo "OPEN main $PLANT_BRANCH $head" ;;
      *) echo "$head" ;;
    esac ;;
  "pr merge") ;;
  *) echo "planted gh: unexpected $*" >&2; exit 9 ;;
esac
"""

REAL_CHECK = """#!/bin/bash
[ "$1" = fast ] || exit 2
if [ -e build/marker ]; then echo "check warm" >> "$PLANT_DIR/calls"; else echo "check cold" >> "$PLANT_DIR/calls"; fi
mkdir -p build
touch build/marker
"""

KEPT_CALLS = ("check", "pr_wait", "gh pr merge")


@unittest.skipUnless(RUNNABLE, "merge_when_green.sh needs bash and git")
class MergeWhenGreenOnRealGitTest(unittest.TestCase):
    """The script on the machine's git, a local bare origin and a clone of it as the caller's
    repository: a pull request branch (BRANCH) one commit ahead of main."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="genesis-merge-when-green-real-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.origin = self.root / "origin.git"
        self.clone = self.root / "repository"
        self.worktree = self.root / "merge-worktree"
        self.state = self.root / "state"
        self.caller = self.root / "caller"
        for folder in (self.state, self.caller):
            folder.mkdir()
        self.git("init", "-q", "--bare", "-b", "main", str(self.origin), cwd=self.root)
        self.git("init", "-q", "-b", "main", str(self.clone), cwd=self.root)
        self.git("remote", "add", "origin", str(self.origin), cwd=self.clone)
        executable(self.clone / "check", REAL_CHECK)
        (self.clone / ".gitignore").write_text("build/\n")
        (self.clone / "shared.txt").write_text("base\n")
        self.commit("base", "check", ".gitignore", "shared.txt")
        self.git("push", "-q", "origin", "main", cwd=self.clone)
        self.git("switch", "-q", "-c", BRANCH, cwd=self.clone)
        (self.clone / "feature.txt").write_text("feature\n")
        self.commit("feature", "feature.txt")
        self.git("push", "-q", "origin", BRANCH, cwd=self.clone)
        self.git("switch", "-q", "main", cwd=self.clone)
        executable(self.root / "bin" / "gh", REAL_GH_STUB)
        executable(self.clone / "dev" / "pr_wait.sh", PR_WAIT_STUB)
        shutil.copyfile(SCRIPT, self.clone / "dev" / "merge_when_green.sh")

    def git(self, *args: str, cwd: Path) -> str:
        done = subprocess.run(
            ["git", *args], cwd=cwd, capture_output=True, text=True, env={**os.environ, **GIT_ENVIRONMENT},
        )
        self.assertEqual(done.returncode, 0, f"git {' '.join(args)}: {done.stderr}")
        return done.stdout.strip()

    def commit(self, message: str, *files: str) -> None:
        self.git("add", *files, cwd=self.clone)
        self.git("commit", "-q", "-m", message, cwd=self.clone)

    def move_main(self, file: str, text: str) -> None:
        """A new commit on origin's main that changes `file`."""
        self.git("switch", "-q", "main", cwd=self.clone)
        (self.clone / file).write_text(text)
        self.commit(f"main changes {file}", file)
        self.git("push", "-q", "origin", "main", cwd=self.clone)

    def run_script(self) -> subprocess.CompletedProcess:
        environment = {
            **os.environ, **GIT_ENVIRONMENT, "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "PLANT_DIR": str(self.state), "PLANT_ORIGIN": str(self.origin), "PLANT_BRANCH": BRANCH,
            "MERGE_WHEN_GREEN_POLL_SECONDS": "0", "MERGE_WHEN_GREEN_WORKTREE": str(self.worktree),
            "TMPDIR": str(self.root),
        }
        (self.state / "calls").unlink(missing_ok=True)
        done = subprocess.run(
            ["bash", str(self.clone / "dev" / "merge_when_green.sh"), "7"],
            capture_output=True, text=True, env=environment, cwd=self.caller,
        )
        calls = self.state / "calls"
        done.calls = calls.read_text().splitlines() if calls.exists() else []
        return done

    def origin_branch(self) -> str:
        return self.git("rev-parse", f"refs/heads/{BRANCH}", cwd=self.origin)

    def assert_origin_branch_holds_main(self) -> None:
        self.git("merge-base", "--is-ancestor", "refs/heads/main", f"refs/heads/{BRANCH}", cwd=self.origin)

    def test_main_moving_is_merged_into_the_branch_and_the_next_run_reuses_the_warm_worktree(self):
        self.move_main("main_only.txt", "one\n")
        first = self.run_script()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assert_origin_branch_holds_main()
        pushed = self.origin_branch()
        self.assertEqual(len(self.git("rev-list", "--parents", "-n", "1", pushed, cwd=self.origin).split()), 3)
        self.assertEqual(
            [c for c in first.calls if c.startswith(KEPT_CALLS)],
            ["check cold", "pr_wait 7", f"gh pr merge 7 --merge --match-head-commit {pushed}"],
        )
        self.assertTrue((self.worktree / "build" / "marker").exists(), "the worktree's build was not kept")

        self.move_main("main_only.txt", "two\n")
        (self.worktree / "feature.txt").write_text("uncommitted\n")
        (self.worktree / "junk.txt").write_text("untracked\n")
        second = self.run_script()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assert_origin_branch_holds_main()
        self.assertEqual(
            [c for c in second.calls if c.startswith(KEPT_CALLS)],
            ["check warm", "pr_wait 7", f"gh pr merge 7 --merge --match-head-commit {self.origin_branch()}"],
        )
        self.assertEqual(self.git("status", "--porcelain", cwd=self.worktree), "")
        self.assertEqual((self.worktree / "feature.txt").read_text(), "feature\n")
        self.assertFalse((self.worktree / "junk.txt").exists())
        listed = self.git("worktree", "list", "--porcelain", cwd=self.clone).count("worktree ")
        self.assertEqual(listed, 2, "the run made a second worktree instead of reusing the first")
        self.assertEqual(list(self.caller.iterdir()), [])
        self.assertEqual(self.git("branch", "--show-current", cwd=self.clone), "main")

    def test_a_conflict_with_main_pushes_nothing_and_leaves_the_worktree_clean(self):
        self.git("switch", "-q", BRANCH, cwd=self.clone)
        (self.clone / "shared.txt").write_text("branch\n")
        self.commit("branch changes shared", "shared.txt")
        self.git("push", "-q", "origin", BRANCH, cwd=self.clone)
        self.move_main("shared.txt", "main\n")
        before = self.origin_branch()
        done = self.run_script()
        self.assertEqual(done.returncode, 1)
        self.assertIn("shared.txt", done.stderr)
        self.assertEqual(self.origin_branch(), before)
        self.assertFalse(any(c.startswith(KEPT_CALLS) for c in done.calls), done.calls)
        self.assertEqual(self.git("status", "--porcelain", cwd=self.worktree), "")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=self.worktree), before)

    def test_a_folder_at_the_worktree_path_that_belongs_to_another_repository_is_refused(self):
        self.worktree.mkdir()
        self.git("init", "-q", cwd=self.worktree)
        done = self.run_script()
        self.assertEqual(done.returncode, 1)
        self.assertIn("not a worktree of", done.stderr)
        self.assertFalse(any(c.startswith(KEPT_CALLS) for c in done.calls), done.calls)
        self.assertFalse((self.worktree / "build").exists())


if __name__ == "__main__":
    unittest.main()
