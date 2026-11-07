"""PreToolUse hook (Bash): refuses `gh issue close` as not planned with no owner for the open items.

The command must name the issue that takes them (`#N`, `owner/repo#N`, an issue URL) or say
"no open items"; a close as not planned with open items and no owner lost them.
"""

import json
import re
import sys

NOT_PLANNED = re.compile(r"\bgh\s+issue\s+close\b[^\n]*?(?:--reason|-r)[ =]+['\"]?not[ _-]planned", re.I)
OWNER = re.compile(r"#\d+|/issues/\d+|no open items", re.I)


def main() -> int:
    try:
        command = json.load(sys.stdin)["tool_input"]["command"]
    except Exception:
        return 0
    if NOT_PLANNED.search(command) and not OWNER.search(command):
        print("Closing as not planned needs a --comment naming the issue that takes the open items "
              "(#N, owner/repo#N or an issue URL) or saying \"no open items\".", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
