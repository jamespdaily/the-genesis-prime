"""Stop hook: blocks once a reply that names an issue, a message, a system or a step by number
(`#123`, `0x25e`, `system 3`, `T3b-1`), or whose first word is "Partly" or "Mostly".

Jim reads chat by names, and wants a plain yes or no first. Fenced code blocks and URLs are not
read. A subagent's event (`agent_id`) and a turn a stop hook already continued (`stop_hook_active`) pass.
"""

import json
import re
import sys

IGNORED = re.compile(r"^[ \t]*(```|~~~).*?(?:^[ \t]*\1[ \t]*$|\Z)|\b[a-z][a-z0-9+.-]*://\S+", re.S | re.M | re.I)
BARE = re.compile(r"(?<![\w&/#])#\d+\b|(?<!\w)0x[0-9A-Fa-f]+\b|\b[Ss]ystem \d+\b|\b[Tt]\d[a-z]?(?:-\d+)?\b")
HEDGE = re.compile(r"^\s*(partly|mostly)\b", re.I)


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("stop_hook_active") or event.get("agent_id"):
            return 0
        reply = IGNORED.sub(" ", event.get("last_assistant_message") or "")
        tokens = list(dict.fromkeys(BARE.findall(reply)))
        hedged = bool(HEDGE.match(reply))
    except Exception:
        return 0
    reasons = []
    if tokens:
        reasons.append(
            f"Your reply names things by number: {', '.join(tokens)}. Jim reads chat by names: an issue by "
            "its title, a message by its name, a system by its name, a step by its title. Rewrite it with "
            "names; a number may stay in a code block or URL.")
    if hedged:
        reasons.append("Lead with a plain yes or no, then the one difference.")
    if reasons:
        print(json.dumps({"decision": "block", "reason": " ".join(reasons)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
