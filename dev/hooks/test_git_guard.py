"""The git guard hook: what it refuses and what it lets through.

Expected values are the two rules it enforces: CLAUDE.md's "files are staged by
name" and its Tracking rule "a branch is `jimd/<issue>-<topic>`". A command is
refused when it stages by anything but a file name (-A, --all, -u, `.`, a glob, a
directory, `commit -a`) or makes a branch with another name; every command in a
compound line is read, and a command that only mentions git (an echo, a commit
message) is not one.

Run: python3.13 -I -m unittest discover -s dev/hooks -p 'test_*.py'
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import git_guard

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "git_guard.py")


class GitGuardTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        os.mkdir(os.path.join(self.folder.name, "src"))
        with open(os.path.join(self.folder.name, "a.txt"), "w") as file:
            file.write("a")

    def refusal(self, command):
        return git_guard.refusal(command, self.folder.name)

    def assertStageRefused(self, command):
        self.assertEqual(self.refusal(command), git_guard.STAGE_REASON, command)

    def assertBranchRefused(self, command):
        self.assertEqual(self.refusal(command), git_guard.BRANCH_REASON, command)

    def assertAllowed(self, command):
        self.assertIsNone(self.refusal(command), command)


class StagingTest(GitGuardTest):
    def test_adding_everything_by_a_flag_is_refused(self):
        for command in [
            "git add -A",
            "git add --all",
            "git add -u",
            "git add --update",
            "git add -Av",
            "git add -fA a.txt",
        ]:
            self.assertStageRefused(command)

    def test_adding_a_dot_a_glob_a_directory_or_the_root_is_refused(self):
        for command in [
            "git add .",
            "git add ./",
            "git add -- .",
            "git add src",
            "git add src/",
            "git add 'src/*.gleam'",
            "git add a.txt src",
            "git add :/",
            "git add ':(glob)**/*.gleam'",
            "git add src/.",
        ]:
            self.assertStageRefused(command)

    def test_committing_with_all_is_refused(self):
        for command in [
            "git commit -a",
            "git commit -am 'message'",
            "git commit --all -m message",
            "git commit -m message -a",
            "git commit -qa",
        ]:
            self.assertStageRefused(command)

    def test_files_added_by_name_are_allowed(self):
        for command in [
            "git add a.txt",
            "git add a.txt src/b.gleam",
            "git add -- a.txt",
            "git add -N a.txt",
            "git add 'a file with spaces.txt'",
            "git add -p a.txt",
            "git commit -m 'message'",
            "git commit --amend --no-edit",
            "git commit -m 'add . and -A and -a'",
            "git commit a.txt -m message",
            "git commit -F message.txt",
            "git commit -ma",
        ]:
            self.assertAllowed(command)

    def test_every_command_of_a_compound_line_is_read(self):
        self.assertStageRefused("cd src && git add -A")
        self.assertStageRefused("git status; git add .")
        self.assertStageRefused("git diff | cat || git add -u")
        self.assertStageRefused("(git add .)")
        self.assertStageRefused("FOO=1 git add .")
        self.assertStageRefused("/usr/bin/git add .")
        self.assertStageRefused("git -c core.quotepath=off add .")
        self.assertStageRefused("git --no-pager add -A")

    def test_git_c_changes_the_folder_a_directory_is_read_in(self):
        self.assertStageRefused(f"git -C {self.folder.name} add src")
        self.assertAllowed(f"git -C {self.folder.name}/src add src")

    def test_text_that_only_mentions_a_git_command_is_allowed(self):
        for command in [
            "echo git add .",
            "grep -rn 'git add -A' .",
            'git commit -m "$(cat <<\'EOF\'\nWhy git add -A is refused\nEOF\n)"',
            "git status",
            "git diff --stat",
            "ls -a",
        ]:
            self.assertAllowed(command)

    def test_a_command_line_that_does_not_parse_passes(self):
        self.assertAllowed("git add 'unclosed")


class BranchTest(GitGuardTest):
    def test_a_new_branch_not_named_jimd_issue_topic_is_refused(self):
        for command in [
            "git checkout -b feature",
            "git checkout -B jimd/rule-cleanup",
            "git checkout -b jimd/262_rule_cleanup",
            "git checkout -b jimd/262-Rule-Cleanup",
            "git checkout -b jimd/262-",
            "git checkout -b other/262-topic origin/main",
            "git switch -c fix",
            "git switch --create fix",
            "git switch -C fix origin/main",
            "git branch topic",
            "git branch topic origin/main",
            "git branch -m new-name",
            "git branch -m old jimd/oops",
            "git branch -c old fresh",
            "git worktree add ../w -b topic",
            "git worktree add -B topic ../w",
            "git worktree add ../topic",
            "git checkout -btopic",
            "git -C ../w checkout -b topic",
            "git fetch && git checkout -b topic",
        ]:
            self.assertBranchRefused(command)

    def test_a_new_branch_named_jimd_issue_topic_is_allowed(self):
        for command in [
            "git checkout -b jimd/262-rule-cleanup origin/main",
            "git checkout -B jimd/9-x",
            "git switch -c jimd/10-a-b-c",
            "git branch jimd/11-topic",
            "git branch -m jimd/12-renamed",
            "git worktree add ../w -b jimd/13-topic",
            "git worktree add ../w jimd/14-topic",
            "git worktree add --detach ../w",
            "git worktree add ../w origin/main",
        ]:
            self.assertAllowed(command)

    def test_commands_that_make_no_branch_are_allowed(self):
        for command in [
            "git checkout main",
            "git checkout -- a.txt",
            "git checkout origin/main -- a.txt",
            "git switch main",
            "git branch",
            "git branch -a",
            "git branch -r",
            "git branch -vv",
            "git branch -d old",
            "git branch -D old",
            "git branch --delete old",
            "git branch --show-current",
            "git branch --list 'jimd/*'",
            "git branch --contains abc123",
            "git branch --merged main",
            "git branch -u origin/main",
            "git branch --set-upstream-to=origin/main",
            "git worktree list",
            "git worktree remove ../w",
            "git push -u origin jimd/262-rule-cleanup",
            "git log --oneline",
        ]:
            self.assertAllowed(command)


class HookProtocolTest(unittest.TestCase):
    def run_hook(self, event_text):
        return subprocess.run(
            [sys.executable, "-I", SCRIPT],
            input=event_text,
            capture_output=True,
            text=True,
            check=True,
        )

    def test_a_refused_command_is_answered_with_a_deny_decision_and_the_reason(self):
        run = self.run_hook(
            json.dumps({"tool_name": "Bash", "tool_input": {"command": "git add -A"}, "cwd": "/tmp"})
        )
        decision = json.loads(run.stdout)["hookSpecificOutput"]
        self.assertEqual(decision["hookEventName"], "PreToolUse")
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertEqual(decision["permissionDecisionReason"], git_guard.STAGE_REASON)

    def test_an_allowed_command_another_tool_and_unreadable_input_print_nothing(self):
        for event_text in [
            json.dumps({"tool_name": "Bash", "tool_input": {"command": "git add a.txt"}, "cwd": "/tmp"}),
            json.dumps({"tool_name": "Edit", "tool_input": {"command": "git add -A"}}),
            json.dumps({"tool_name": "Bash"}),
            "not json",
            "",
        ]:
            run = self.run_hook(event_text)
            self.assertEqual(run.stdout, "", event_text)


if __name__ == "__main__":
    unittest.main()
