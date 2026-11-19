"""PreToolUse hook for the Agent tool: refuses an agent started without `subagent_type`, with `name`, or with `isolation: remote`.

A named agent joins as a teammate, and its hand-back never reaches the agent that started it:
three design drafters and two decoders lost their work so (2026-11-09 and 11-10). A remote agent
runs off the Mac, where the client's files must not go (Jim, 2026-11-06). Claude Code passes the
hook's JSON on stdin (`tool_input`). When `tool_input.subagent_type` is missing or empty,
`tool_input.name` is set, or `tool_input.isolation` is "remote", it prints a line to stderr and
exits 2, which blocks the call and shows Claude that line. Every other case, unreadable input
included, exits 0.
"""
import json
import sys


def main():
    try:
        call = json.load(sys.stdin)["tool_input"]
        typed = bool(call.get("subagent_type"))
        named = bool(call.get("name"))
        remote = call.get("isolation") == "remote"
    except Exception:
        return 0
    if remote:
        print(
            "Run builders locally: no remote agents (Jim, 2026-11-06: unclear rights and cost; "
            "the client's files must not leave the Mac).",
            file=sys.stderr,
        )
        return 2
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
