"""PreToolUse hook for the Bash tool: refuses to close an issue as not planned with no owner.

An issue closed as not planned with open items and no owner loses them (the Volatility gain
was lost that way). Claude Code passes the hook's JSON on stdin (`tool_name`, `tool_input.command`,
`cwd`). For each `gh issue close <issue> ... ` in the command whose reason is "not planned"
(`--reason`, `-r`, with a space or `=`; case, `_` and `-` for the space are accepted), the
`--comment` / `-c` text must either name another issue (the one that takes the open items) as
`#N`, `owner/repo#N` or an issue URL (`https://github.com/.../issues/N`), or say "no open
items". Otherwise the hook prints one stderr line and exits 2, which blocks the call and shows
Claude that line. Every other case exits 0.

  - A reference to the issue being closed does not count as its owner.
  - A comment that is not literal (`$(...)`, a variable, backticks, a heredoc) cannot be read
    here, so the whole command text is searched instead.
  - `gh api` calls that set `state_reason` are not read.
"""

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shell_command import simple_commands  # noqa: E402
from step_issue import REPOSITORY  # noqa: E402

# An issue URL (groups 1, 2: repository, number) or `#N` / `owner/repo#N` (groups 3, 4).
_REFERENCE = re.compile(
    r"https?://github\.com/([\w.-]+/[\w.-]+)/issues/(\d+)\b"
    r"|(?<![\w&/])(?:([\w.-]+/[\w.-]+))?#(\d+)\b"
)
_NO_OPEN_ITEMS = re.compile(r"\bno\s+open\s+items\b", re.IGNORECASE)


def _option(words: list[str], long: str, short: str) -> str | None:
    """The value of `--long v`, `--long=v`, `-s v` or `-sv` among a command's words; the last
    one wins. None when the option is absent."""
    value = None
    for i, word in enumerate(words):
        if word == long or word == short:
            value = words[i + 1] if i + 1 < len(words) else ""
        elif word.startswith(long + "="):
            value = word[len(long) + 1 :]
        elif word.startswith(short) and not word.startswith("--") and len(word) > 2:
            value = word[2:]
    return value


def _issue_number(words: list[str]) -> int | None:
    """The issue a `gh issue close` names, when it is a number or a URL ending in one."""
    for word in words[3:]:
        found = re.fullmatch(r"#?(\d+)", word) or re.search(r"/issues/(\d+)$", word)
        if found:
            return int(found.group(1))
    return None


def is_not_planned(reason: str | None) -> bool:
    return reason is not None and re.sub(r"[\s_-]+", " ", reason.strip().lower()) == "not planned"


def names_owner(text: str, own_issue: int | None) -> bool:
    """Whether a close comment names the issue that takes the open items (an issue other than
    the closed one, in this repository or another) or says there are none."""
    for found in _REFERENCE.finditer(text):
        repository = (found.group(1) or found.group(3) or REPOSITORY).lower()
        number = int(found.group(2) or found.group(4))
        if number != own_issue or repository != REPOSITORY:
            return True
    return _NO_OPEN_ITEMS.search(text) is not None


def refusal_for(command: str, folder: str | None) -> str | None:
    """The refusal line for the first `gh issue close` of the command that closes as not planned
    with no owner, or None."""
    for simple in simple_commands(command, folder):
        words = simple.words
        if os.path.basename(words[0]) != "gh" or words[1:3] != ["issue", "close"]:
            continue
        if not is_not_planned(_option(words, "--reason", "-r")):
            continue
        comment = _option(words, "--comment", "-c")
        number = _issue_number(words)
        if comment is not None:
            text = command if re.search(r"[$`]", comment) else comment
            if names_owner(text, number):
                continue
        label = f"issue {number}" if number else "the issue"
        return (
            f"Closing {label} as not planned needs its --comment to name the issue that takes its "
            "open items (an #N reference to another issue) or to say \"no open items\" "
            "(the Volatility gain was lost when an issue closed not planned with open items and no owner)."
        )
    return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("tool_name") != "Bash":
            return 0
        folder = event.get("cwd") if isinstance(event.get("cwd"), str) else None
        message = refusal_for(event["tool_input"]["command"], folder)
    except Exception:
        return 0
    if message is None:
        return 0
    print(message, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
