"""PreToolUse hook (Bash): refuses a command that starts a test run while the machine's test slots
(machine_slots.TEST_SLOTS) are all taken, and a `gleam test` command that writes a unitest option as
`--flag=value`.

A test run is `check` (any mode but --help) or `gleam test`, behind `sh`/`bash`, `nohup`,
`caffeinate`, `timeout`, `env`, `nice` or `time`, or variable assignments. A run started by another
run is not counted.

unitest's options (`--test`, `--tag`, `--seed`, `--module`, `--workers`, `--reporter`, `--sort`) match the
exact word and take the next one; clip's `arg` skips an unknown word that starts with `-`
(build/packages/clip/src/clip/arg.gleam), so `--test=x` ran the whole suite. The hook refuses that
form and names `--test module.fn` with a space.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import machine_slots  # noqa: E402

RUN = r"(?:\S*/)?(?:(?:ba|z|da)?sh\s+)?(?:\S*/)?(?:check(?!\S)(?!\s+(?:--help|-h|help)\b)|gleam\s+test\b)"
WRAPPERS = r"(?:(?:nohup|caffeinate|timeout|env|nice|time)\s+(?:(?:-\S+|\d+|\w+=\S*)\s+)*)*"
ASSIGNMENTS = r"(?:\w+=\S*\s+)*"
SEPARATOR = r"&&|;|\|\||\n"
STARTS = re.compile(r"(?:^|" + SEPARATOR + r")\s*" + ASSIGNMENTS + WRAPPERS + RUN)
RUNNING = re.compile(WRAPPERS + RUN)
GLEAM_TEST = re.compile(ASSIGNMENTS + WRAPPERS + r"(?:\S*/)?gleam\s+test\b")
EQUALS_OPTION = re.compile(r"\s--(?:test|tag|seed|module|workers|reporter|sort)=")


def equals_option(command: str) -> bool:
    """True when a `gleam test` part of the command holds an option written with an equals sign."""
    parts = re.split(SEPARATOR, command)
    return any(GLEAM_TEST.match(part.strip()) and EQUALS_OPTION.search(part) for part in parts)


def refusal(command: str, rows: list[list[str]]) -> str | None:
    """The line that refuses the command, or None. `rows` are the running processes as pid, parent pid, command."""
    if not STARTS.search(command):
        return None
    if equals_option(command):
        return ("Write a gleam test option with a space, not an equals sign: `gleam test -- --test module.fn`, "
                "`--tag serial`, `--seed 7`. unitest ignores `--test=module.fn` and runs the whole suite.")
    runs = {row[0]: row for row in rows if len(row) == 3 and RUNNING.match(row[2])}
    outer = [f"pid {pid} `{running[:120]}`" for pid, parent, running in runs.values() if parent not in runs]
    slots = machine_slots.TEST_SLOTS
    if len(outer) < slots:
        return None
    return (f"{slots} test runs already run on this machine, which has {slots} test slots: "
            + "; ".join(outer) + ". Wait for one to end.")


def main() -> int:
    try:
        command = json.load(sys.stdin)["tool_input"]["command"]
        if not STARTS.search(command):
            return 0
        ps = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True, timeout=10, check=True)
        rows = [row.split(None, 2) for row in ps.stdout.splitlines()]
        refused = refusal(command, rows)
    except Exception:
        return 0
    if refused is None:
        return 0
    print(refused, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
