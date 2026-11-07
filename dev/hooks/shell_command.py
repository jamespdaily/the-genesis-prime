"""Reads a shell command line the way the hooks need: its simple commands and `git push`es.

Shared by the Bash hooks in this folder (progress_lines, limit_test_runs, not_planned_owner,
push_needs_test_list). A hook script puts this folder on `sys.path` first, because
`python3 -I` leaves the script's folder off it.

  simple_commands(command, folder)   each simple command's words and the folder it runs in
  git_pushes(simple)                 the branches a `git push` command sends

Rules:
  - A command counts only at the start of a simple command (the first word, or after `&&`,
    `||`, `;`, `|`, `(`, a newline, a `VAR=x` prefix or a shell keyword). Heredoc bodies are
    cut first, so text that mentions `git push` is not a push.
  - A `cd X` sets the folder of the commands after it, and `-C X` sets it for one git call;
    `~` is expanded. A path that is a variable, a substitution or `-` gives folder None.
  - `git push -d`, `--delete`, `-n`, `--dry-run`, `--all`, `--mirror` and `--tags` send no
    named branch, so they give no push. Neither does a refspec with an empty source
    (`:branch` deletes it) or a tag (`tag <name>`, `refs/tags/...`).
"""

import os
import re
import shlex
from dataclasses import dataclass

_HEREDOC = re.compile(r"(?<!<)<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
_ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
_KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "{", "!", "time"}

_GIT_OPTIONS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
_PUSH_OPTIONS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
_PUSH_SKIPPED = {"-d", "--delete", "-n", "--dry-run", "--all", "--mirror", "--tags"}


def without_heredocs(command: str) -> str:
    """The command with each heredoc's body cut, so its text is not read as commands."""
    kept: list[str] = []
    waiting: list[tuple[str, bool]] = []
    for line in command.split("\n"):
        if waiting:
            delimiter, dashed = waiting[0]
            if (line.strip() if dashed else line) == delimiter:
                waiting.pop(0)
            continue
        kept.append(line)
        waiting += [(m[3], bool(m[1])) for m in _HEREDOC.finditer(line)]
    return "\n".join(kept)


def _tokens(command: str) -> list[str]:
    """The words of a shell command, with `&&`, `||`, `;`, `|`, parentheses, redirections and
    newlines as words of their own."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lexer.whitespace_split = True
    lexer.commenters = ""
    lexer.whitespace = " \t\r"
    try:
        words = list(lexer)
    except ValueError:
        words = command.replace("\n", " ; ").split()
    # `2>&1` comes out as "2", ">&", "1": the file descriptor is not an argument.
    return [
        w for i, w in enumerate(words)
        if not (w in {"0", "1", "2"} and i + 1 < len(words) and words[i + 1][:1] in "<>")
    ]


def _is_operator(word: str) -> bool:
    """Whether a word ends a command's arguments: a separator, a newline or a redirection."""
    return bool(word) and (
        all(c in "();<>|&\n" for c in word) or re.match(r"\d*[<>]", word) is not None
    )


def in_folder(path: str, folder: str | None) -> str | None:
    """The folder a `cd path` or `-C path` leads to from `folder`; None when the path is a
    variable, a substitution or `-`, or is relative to an unknown folder."""
    if re.search(r"[$`]", path) or path == "-":
        return None
    path = os.path.expanduser(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(folder, path)) if folder else None


@dataclass(frozen=True)
class Simple:
    """One simple command: its words, from its command word on, and the folder it runs in."""

    words: list[str]
    folder: str | None


def simple_commands(command: str, folder: str | None) -> list[Simple]:
    """The commands of a command line, each with the folder the line's `cd`s lead it to."""
    found: list[Simple] = []
    current: list[str] = []

    def finish() -> None:
        nonlocal folder, current
        words = current
        current = []
        while words and (_ASSIGNMENT.match(words[0]) or words[0] in _KEYWORDS):
            words = words[1:]
        if not words:
            return
        if words[0] == "cd":
            paths = [w for w in words[1:] if w not in {"-P", "-L", "-e", "-@"}]
            folder = in_folder(paths[0] if paths else "~", folder)
        else:
            found.append(Simple(words, folder))

    for word in _tokens(without_heredocs(command)):
        if _is_operator(word):
            finish()
        else:
            current.append(word)
    finish()
    return found


@dataclass(frozen=True)
class PushTarget:
    """A remote branch a `git push` sends. `branch` is "HEAD" for the current branch of
    `folder`, which is None when the command's folder is a variable."""

    branch: str
    folder: str | None
    remote: str = "origin"


def git_pushes(simple: Simple) -> list[PushTarget]:
    """The pushes `git [options] push [options] remote refspec...` a simple command makes."""
    words, where = simple.words, simple.folder
    i = 1
    while i < len(words) and words[i].startswith("-"):
        if words[i] == "-C" and i + 1 < len(words):
            where = in_folder(words[i + 1], where)
        i += 2 if words[i] in _GIT_OPTIONS_WITH_VALUE else 1
    if i >= len(words) or words[i] != "push":
        return []
    rest, skip = [], False
    for word in words[i + 1 :]:
        if skip:
            skip = False
        elif word in _PUSH_OPTIONS_WITH_VALUE:
            skip = True
        else:
            rest.append(word)
    if {w for w in rest if w.startswith("-")} & _PUSH_SKIPPED:
        return []
    positional = [w for w in rest if not w.startswith("-")]
    remote = positional[0] if positional else "origin"
    refspecs = positional[1:] or ["HEAD"]
    if refspecs[0] == "tag":
        return []
    pushes = []
    for refspec in refspecs:
        source, colon, destination = refspec.lstrip("+").partition(":")
        if colon and not source:
            continue
        destination = (destination if colon else source).removeprefix("refs/heads/")
        if destination and not destination.startswith("refs/tags/"):
            pushes.append(PushTarget(destination, where, remote))
    return pushes
