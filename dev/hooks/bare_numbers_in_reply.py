"""Stop hook: blocks once a reply that names an issue or a message by number (`#123`, `0x25e`).

Jim reads chat by names. Fenced code blocks and URLs are not read. A subagent's event
(`agent_id`) and a turn a stop hook already continued (`stop_hook_active`) pass.
"""

import json
import re
import sys

IGNORED = re.compile(r"^[ \t]*(```|~~~).*?(?:^[ \t]*\1[ \t]*$|\Z)|\b[a-z][a-z0-9+.-]*://\S+", re.S | re.M | re.I)
BARE = re.compile(r"(?<![\w&/#])#\d+\b|(?<!\w)0x[0-9A-Fa-f]+\b")


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("stop_hook_active") or event.get("agent_id"):
            return 0
        tokens = list(dict.fromkeys(BARE.findall(IGNORED.sub(" ", event.get("last_assistant_message") or ""))))
    except Exception:
        return 0
    if tokens:
        print(json.dumps({"decision": "block", "reason": (
            f"Your reply names things by number: {', '.join(tokens)}. Jim reads chat by names: an issue by "
            "its title, a message by its name. Rewrite it with names; a number may stay in a code block or URL.")}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
