"""PreToolUse hook for the Bash tool: refuses a command that starts a test run while two run.

The machine has two test slots. Claude Code passes the hook's JSON on stdin (`tool_name`,
`tool_input.command`, `cwd`). The hook reads the command; when it starts a test run it lists
the machine's processes (`ps`) and, when two or more test runs are already going, prints one
stderr line naming each run (pid, worktree, command) and exits 2, which blocks the call and
shows Claude that line. Every other case, a failed `ps` included, exits 0.

  Bash call about to run
    -> starts_test_run(words)     each simple command of the call (shell_command), by its
                                  command word; text that only mentions a test run is no run
    -> running_tests(ps)          the processes that are test runs, minus those started by
                                  another test run, each with its folder (lsof)
    -> two or more: refuse

A test run is:
  gleam test ...                           the test suite
  ./check, bash ./check ...                the check, in any form (`fast` runs tests too), but
                                           not `--help`, `-h` or `help`
  gleam run -m genesis_prime/load_...      a load run
  gleam run -m genesis_prime/wire_replay   a recording replayed through the server

`timeout`, `nice`, `env`, `time`, `nohup` and `caffeinate`, with their options, in front of
the command are read through. A run started
inside `sh -c "..."` or a script is not seen at the start, but is counted once it runs, as
its `gleam` or `check` process. A run is counted once: `./check` and the `gleam test` it starts
are one run (a process whose parent is a test run is not another). Every worktree counts. A run
whose folder `lsof` cannot read in time is still counted, with an unknown folder.
Two commands that start together can both pass; the second one's `ps` sees the first only
once it is running.
"""

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shell_command import simple_commands  # noqa: E402

SLOTS = 2
_INTERPRETERS = {"bash", "sh", "zsh", "dash"}
# Each wrapper's options that take a value as the next word.
_WRAPPERS = {
    "time": {"-f", "-o"}, "nice": {"-n"}, "command": set(), "exec": set(), "nohup": set(),
    "env": {"-u", "-C", "-S"}, "timeout": {"-k", "-s"}, "caffeinate": {"-t", "-w"},
}
_HELP = {"--help", "-h", "help"}
_LOAD_MODULES = ("genesis_prime/load_", "genesis_prime/wire_replay")


def starts_test_run(words: list[str]) -> bool:
    """Whether a program's words (its name first) are a test run, per the module's list."""
    words = _without_wrappers(words)
    if words and os.path.basename(words[0]) in _INTERPRETERS and len(words) > 1:
        words = words[1:]
    if not words:
        return False
    program, arguments = os.path.basename(words[0]), words[1:]
    if program == "check":
        return not _HELP & set(arguments)
    if program != "gleam" or not arguments:
        return False
    if arguments[0] == "test":
        return True
    if arguments[0] == "run" and "-m" in arguments:
        index = arguments.index("-m") + 1
        return index < len(arguments) and arguments[index].startswith(_LOAD_MODULES)
    return False


def _without_wrappers(words: list[str]) -> list[str]:
    """The words after `timeout -k 5 10`, `nice -n 5`, `env A=b`, `caffeinate -i -t 60`, `nohup`,
    `time` and the like."""
    while words and os.path.basename(words[0]) in _WRAPPERS:
        wrapper, words = os.path.basename(words[0]), words[1:]
        while words and (words[0].startswith("-") or (wrapper == "env" and "=" in words[0].split("/")[0])):
            words = words[2:] if words[0] in _WRAPPERS[wrapper] else words[1:]
        if wrapper == "timeout" and words:
            words = words[1:]
    return words


@dataclass(frozen=True)
class Process:
    pid: int
    parent: int
    command: str


def processes() -> list[Process]:
    """Every process of the machine, from `ps`."""
    done = subprocess.run(
        ["ps", "-axwwo", "pid=,ppid=,command="], capture_output=True, text=True, timeout=10, check=True,
    )
    found = []
    for line in done.stdout.splitlines():
        fields = line.split(None, 2)
        if len(fields) == 3 and fields[0].isdigit() and fields[1].isdigit():
            found.append(Process(int(fields[0]), int(fields[1]), fields[2]))
    return found


def running_tests(everything: list[Process]) -> list[Process]:
    """The test runs among the processes: those that are one and have no test run among their
    ancestors."""
    by_pid = {p.pid: p for p in everything}
    runs = {p.pid for p in everything if starts_test_run(p.command.split())}
    found = []
    for pid in sorted(runs):
        ancestor, seen = by_pid[pid].parent, set()
        while ancestor in by_pid and ancestor not in seen:
            if ancestor in runs:
                break
            seen.add(ancestor)
            ancestor = by_pid[ancestor].parent
        else:
            found.append(by_pid[pid])
    return found


def folders(pids: list[int]) -> dict[int, str]:
    """The working folder of each process, from `lsof`; a process it cannot read, or all of them
    when `lsof` fails or runs over 10 s, is missing."""
    if not pids:
        return {}
    try:
        done = subprocess.run(
            ["lsof", "-a", "-d", "cwd", "-Fpn", "-p", ",".join(map(str, pids))],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    result, pid = {}, None
    for line in done.stdout.splitlines():
        if line.startswith("p"):
            pid = int(line[1:])
        elif line.startswith("n") and pid is not None:
            result[pid] = line[1:]
    return result


def worktree_name(folder: str | None) -> str:
    """The worktree a folder is in: its name under `.claude/worktrees/`, else the folder's name."""
    if not folder:
        return "unknown folder"
    parts = Path(folder).parts
    if "worktrees" in parts:
        index = len(parts) - 1 - parts[::-1].index("worktrees")
        if index + 1 < len(parts):
            return parts[index + 1]
    return folder


def refusal(runs: list[Process], folder_of: dict[int, str]) -> str:
    """The line naming each run that holds a slot."""
    named = "; ".join(
        f"pid {p.pid}, worktree {worktree_name(folder_of.get(p.pid))}, `{p.command[:120]}`" for p in runs
    )
    return (
        f"{len(runs)} test runs already run on this machine and it has {SLOTS} test slots: {named}. "
        "Wait for one to end, then start this one (three agents once tested at once and had to be told)."
    )


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("tool_name") != "Bash":
            return 0
        command = event["tool_input"]["command"]
        folder = event.get("cwd") if isinstance(event.get("cwd"), str) else None
        if not any(starts_test_run(s.words) for s in simple_commands(command, folder)):
            return 0
        runs = running_tests(processes())
        if len(runs) < SLOTS:
            return 0
        message = refusal(runs, folders([p.pid for p in runs]))
    except Exception:
        return 0
    print(message, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
