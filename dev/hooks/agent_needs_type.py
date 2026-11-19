"""PreToolUse hook for the Agent tool: refuses an agent started without `subagent_type` or with `name`.

A named agent joins as a teammate, and its hand-back never reaches the agent that started it:
three design drafters and two decoders lost their work so (2026-11-09 and 11-10). Claude Code
passes the hook's JSON on stdin (`tool_input`). When `tool_input.subagent_type` is missing or
empty, or `tool_input.name` is set, it prints a line to stderr and exits 2, which blocks the call
and shows Claude that line. Every other case, unreadable input included, exits 0.
"""
import json
import sys


def main():
    try:
        call = json.load(sys.stdin)["tool_input"]
        typed = bool(call.get("subagent_type"))
        named = bool(call.get("name"))
    except Exception:
        return 0
    if typed and not named:
        return 0
    print(
        "Start every agent with a subagent_type and no name: a named agent joins as a "
        "teammate and its hand-back never reaches you",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
