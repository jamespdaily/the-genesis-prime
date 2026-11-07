"""Stop hook: blocks a reply to Jim that names an issue or a message by its number, once.

Jim reads chat by names: an issue by its title, a message by its name (never `#523` or
`0x25e`). Claude Code passes the hook's JSON on stdin when the main session ends a turn:

  last_assistant_message   the text of the reply (else the last assistant text of the file
                           at `transcript_path`, a JSON lines file of
                           {"type": "assistant", "message": {"content": [{"type": "text", ...}]}})
  stop_hook_active         true when the turn is already continuing because a stop hook
                           blocked it
  agent_id                 present only in a subagent's own events

The session's own ending is the `Stop` event; a subagent's ending is `SubagentStop`, which
this hook is not registered for. An input that carries `agent_id` is skipped as well, so a
change in how Claude Code routes subagent endings cannot make the hook block a subagent.

The reply is read without its fenced code blocks and its URLs. A bare token is `#` and digits
(not part of a word, an HTML entity or a path), or `0x` and hex digits. When the reply holds
any, and `stop_hook_active` is false, the hook prints
{"decision": "block", "reason": ...} naming the tokens and exits 0, so Claude rewrites the
reply with names. When `stop_hook_active` is true it exits 0 without output: a reply is
blocked once, never twice in a row. Every other case, an unreadable input included, exits 0.
"""

import json
import re
import sys

_FENCED = re.compile(r"^[ \t]*(```|~~~).*?(?:^[ \t]*\1[ \t]*$|\Z)", re.DOTALL | re.MULTILINE)
_URL = re.compile(r"\b[a-z][a-z0-9+.-]*://\S+", re.IGNORECASE)
_ISSUE_NUMBER = re.compile(r"(?<![\w&/#])#\d+\b")
_MESSAGE_CODE = re.compile(r"(?<![\w])0x[0-9A-Fa-f]+\b")


def bare_tokens(reply: str) -> list[str]:
    """The issue numbers and message codes of a reply outside its code blocks and URLs, in
    order of appearance, each once."""
    text = _URL.sub(" ", _FENCED.sub(" ", reply))
    found = [m.group(0) for m in sorted(
        [*_ISSUE_NUMBER.finditer(text), *_MESSAGE_CODE.finditer(text)], key=lambda m: m.start(),
    )]
    return list(dict.fromkeys(found))


def last_reply(event: dict) -> str:
    """The reply the turn ended with: `last_assistant_message`, else the transcript's last
    assistant text; empty when neither is readable."""
    message = event.get("last_assistant_message")
    if isinstance(message, str) and message:
        return message
    path = event.get("transcript_path")
    if not isinstance(path, str):
        return ""
    last = ""
    try:
        with open(path, encoding="utf-8") as lines:
            for line in lines:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                content = (entry.get("message") or {}).get("content")
                if entry.get("type") != "assistant" or not isinstance(content, list):
                    continue
                text = "\n".join(
                    b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"
                )
                if text.strip():
                    last = text
    except OSError:
        return ""
    return last


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("stop_hook_active") or event.get("agent_id"):
            return 0
        tokens = bare_tokens(last_reply(event))
    except Exception:
        return 0
    if not tokens:
        return 0
    reason = (
        f"Your reply names things by number: {', '.join(tokens)}. Jim reads chat by names: an issue "
        "by its title, a message by its name (for example player_character_state, not its code). "
        "Rewrite the reply with names; keep a number only inside a code block or a URL."
    )
    print(json.dumps({"decision": "block", "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
