#!/usr/bin/env python3.13
"""Refuses a git command that breaks one of two project rules, before it runs.

Claude Code runs this before every shell command (a PreToolUse hook on Bash,
set in .claude/settings.json). It reads the event on stdin and looks at each
`git` command in the command line. It refuses:

- staging by anything but a file name (CLAUDE.md: files are staged by name):
  `git add` with `-A`, `--all`, `-u`, `--update`, `.`, a glob, a directory or
  `:/`, and `git commit -a` or `--all`;
- a new branch not named `jimd/<issue>-<topic>` (CLAUDE.md, Tracking): the new
  name of `git checkout -b`, `git switch -c`, `git branch`, `git branch -m` and
  `git worktree add`, where `<issue>` is digits and `<topic>` is lower-case
  words joined by hyphens.

A refused command is answered with a deny decision and the reason; any other
command, and an event it cannot read, passes with no output. Standard library
only.
"""

import json
import os
import re
import shlex
import sys

BRANCH_NAME = re.compile(r"^jimd/[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$")
CONTROL_WORDS = {";", "&&", "||", "|", "&", "(", ")", ";;", "|&"}
GIT_OPTIONS_WITH_A_VALUE = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--super-prefix",
    "--config-env",
    "--exec-path",
}
COMMIT_OPTIONS_WITH_A_VALUE = {
    "-m",
    "-F",
    "-C",
    "-c",
    "-t",
    "--message",
    "--file",
    "--reuse-message",
    "--reedit-message",
    "--author",
    "--date",
    "--template",
    "--cleanup",
    "--fixup",
    "--squash",
}
COMMIT_LETTERS_WITH_A_VALUE = "mFCct"
BRANCH_OPTIONS_THAT_DO_NOT_CREATE = {
    "--delete",
    "--list",
    "--all",
    "--remotes",
    "--show-current",
    "--verbose",
    "--contains",
    "--no-contains",
    "--merged",
    "--no-merged",
    "--points-at",
    "--set-upstream-to",
    "--unset-upstream",
    "--edit-description",
}
BRANCH_LETTERS_THAT_DO_NOT_CREATE = "dDlarvu"
BRANCH_LETTERS_THAT_RENAME_OR_COPY = "mMcC"
STAGE_REASON = (
    "Stage files by name: `git add <file> ...`, never -A, --all, -u, `.`, a glob or a directory, "
    "and never `git commit -a`. Name each file you changed."
)
BRANCH_REASON = (
    "A branch is `jimd/<issue>-<topic>`: the issue number, then lower-case words joined by hyphens "
    "(for example jimd/262-rule-cleanup)."
)


def simple_commands(command: str) -> list[list[str]]:
    """The words of each simple command in a command line; none when it does not parse."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        words = list(lexer)
    except ValueError:
        return []
    commands: list[list[str]] = [[]]
    for word in words:
        if word in CONTROL_WORDS:
            commands.append([])
        else:
            commands[-1].append(word)
    return [words for words in commands if words]


def git_call(words: list[str], directory: str) -> tuple[str, list[str], str] | None:
    """The subcommand, its arguments and the directory a simple command runs git in.

    None when the command does not run git. Leading variable assignments and
    git's own options (`-C <path>`, `-c <name=value>`, `--no-pager`) are skipped.
    """
    index = 0
    while index < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[index]):
        index += 1
    if index >= len(words) or os.path.basename(words[index]) != "git":
        return None
    index += 1
    while index < len(words) and words[index].startswith("-"):
        option = words[index]
        if option == "-C" and index + 1 < len(words):
            directory = os.path.join(directory, words[index + 1])
        takes_a_value = option in GIT_OPTIONS_WITH_A_VALUE
        index += 2 if takes_a_value else 1
    if index >= len(words):
        return None
    return words[index], words[index + 1 :], directory


def stages_by_name(arguments: list[str], directory: str) -> bool:
    """Whether a `git add` names each file it stages."""
    paths: list[str] = []
    for position, argument in enumerate(arguments):
        if argument == "--":
            paths.extend(arguments[position + 1 :])
            break
        if argument.startswith("--"):
            if argument in ("--all", "--update", "--no-ignore-removal"):
                return False
        elif argument.startswith("-") and len(argument) > 1:
            if "A" in argument[1:] or "u" in argument[1:]:
                return False
        else:
            paths.append(argument)
    for path in paths:
        if path in (".", "./", ":/") or path.endswith("/.") or any(mark in path for mark in "*?["):
            return False
        if path.startswith(":(") or os.path.isdir(os.path.join(directory, path)):
            return False
    return True


def commits_all(arguments: list[str]) -> bool:
    """Whether a `git commit` stages every changed file with -a or --all."""
    skip_next = False
    for argument in arguments:
        if skip_next:
            skip_next = False
        elif argument == "--":
            return False
        elif argument == "--all":
            return True
        elif argument in COMMIT_OPTIONS_WITH_A_VALUE:
            skip_next = True
        elif argument.startswith("-") and not argument.startswith("--"):
            for position, letter in enumerate(argument[1:], start=1):
                if letter == "a":
                    return True
                if letter in COMMIT_LETTERS_WITH_A_VALUE:
                    skip_next = position == len(argument) - 1
                    break
    return False


def new_branch_names(subcommand: str, arguments: list[str]) -> list[str]:
    """The names a git command gives to a branch it makes, renames or copies."""
    if subcommand == "checkout":
        return names_after(arguments, ("-b", "-B", "--orphan"))
    if subcommand == "switch":
        return names_after(arguments, ("-c", "-C", "--create", "--force-create", "--orphan"))
    if subcommand == "branch":
        return branch_names(arguments)
    if subcommand == "worktree" and arguments[:1] == ["add"]:
        return worktree_names(arguments[1:])
    return []


def names_after(arguments: list[str], options: tuple[str, ...]) -> list[str]:
    names = []
    for position, argument in enumerate(arguments):
        if argument in options and position + 1 < len(arguments):
            names.append(arguments[position + 1])
        elif argument.startswith(("-b", "-B", "-c", "-C")) and len(argument) > 2 and not argument.startswith("--"):
            if argument[:2] in options:
                names.append(argument[2:])
    return names


def branch_names(arguments: list[str]) -> list[str]:
    positionals = []
    renames = False
    for argument in arguments:
        if argument.startswith("--"):
            if argument.split("=")[0] in BRANCH_OPTIONS_THAT_DO_NOT_CREATE:
                return []
        elif argument.startswith("-") and len(argument) > 1:
            letters = argument[1:]
            if any(letter in BRANCH_LETTERS_THAT_DO_NOT_CREATE for letter in letters):
                return []
            renames = renames or any(letter in BRANCH_LETTERS_THAT_RENAME_OR_COPY for letter in letters)
        else:
            positionals.append(argument)
    if not positionals:
        return []
    return [positionals[-1]] if renames else [positionals[0]]


def worktree_names(arguments: list[str]) -> list[str]:
    """The branch `git worktree add` makes: the -b name, or the folder's name when it names no commit."""
    positionals = []
    detached = False
    skip_next = False
    for position, argument in enumerate(arguments):
        if skip_next:
            skip_next = False
        elif argument in ("-b", "-B") and position + 1 < len(arguments):
            return [arguments[position + 1]]
        elif argument in ("--reason", "--orphan"):
            skip_next = argument == "--reason"
            detached = detached or argument == "--orphan"
        elif argument == "--detach" or argument == "-d":
            detached = True
        elif not argument.startswith("-"):
            positionals.append(argument)
    if len(positionals) == 1 and not detached:
        return [os.path.basename(positionals[0].rstrip("/"))]
    return []


def refusal(command: str, directory: str) -> str | None:
    """The reason to refuse a command line, or None."""
    for words in simple_commands(command):
        call = git_call(words, directory)
        if call is None:
            continue
        subcommand, arguments, where = call
        if subcommand == "add" and not stages_by_name(arguments, where):
            return STAGE_REASON
        if subcommand == "commit" and commits_all(arguments):
            return STAGE_REASON
        if any(not BRANCH_NAME.match(name) for name in new_branch_names(subcommand, arguments)):
            return BRANCH_REASON
    return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    if event.get("tool_name") != "Bash":
        return 0
    command = str((event.get("tool_input") or {}).get("command", ""))
    reason = refusal(command, str(event.get("cwd") or os.getcwd()))
    if reason is not None:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                }
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
