"""PreToolUse hook (Bash): refuses a command that starts a test run while two already run.

A test run is `check` (any mode but --help) or `gleam test`, behind `sh`/`bash`, `nohup`,
`caffeinate`, `timeout`, `env`, `nice` or `time`. A run started by another run is not counted.
"""

import json
import re
import subprocess
import sys

RUN = r"(?:\S*/)?(?:(?:ba|z|da)?sh\s+)?(?:\S*/)?(?:check(?!\S)(?!\s+(?:--help|-h|help)\b)|gleam\s+test\b)"
WRAPPERS = r"(?:(?:nohup|caffeinate|timeout|env|nice|time)\s+(?:(?:-\S+|\d+|\w+=\S*)\s+)*)*"
STARTS = re.compile(r"(?:^|&&|;|\|\||\n)\s*" + WRAPPERS + RUN)
RUNNING = re.compile(WRAPPERS + RUN)


def main() -> int:
    try:
        if not STARTS.search(json.load(sys.stdin)["tool_input"]["command"]):
            return 0
        ps = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True, timeout=10, check=True)
    except Exception:
        return 0
    rows = [row.split(None, 2) for row in ps.stdout.splitlines()]
    runs = {row[0]: row for row in rows if len(row) == 3 and RUNNING.match(row[2])}
    outer = [f"pid {pid} `{command[:120]}`" for pid, parent, command in runs.values() if parent not in runs]
    if len(outer) < 2:
        return 0
    print("Two test runs already run on this machine, which has two test slots: " + "; ".join(outer)
          + ". Wait for one to end.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
