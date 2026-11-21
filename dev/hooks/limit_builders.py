"""PreToolUse hook (Agent): refuses a spawn of an `implementer` agent (a builder) while as many builders
run as the machine has test slots (machine_slots.TEST_SLOTS).

Up to six builders and reviewers ran at once and overloaded the machine (2026-11-20). Claude Code writes,
per subagent, `PROJECT/SESSION/subagents/agent-ID.meta.json` (`agentType`, `description`, `toolUseId`,
`finished: true` once the agent ends) and `agent-ID.jsonl` (its transcript, appended each turn). A builder
runs when its meta has `agentType == "implementer"`, no `finished`, and a transcript written within
LIVE_SECONDS; a builder that died stops counting then. A meta with no transcript yet is a builder
starting, and counts for PENDING_SECONDS from the meta's own last write. After a `/clear` Claude Code
keeps an agent's files under two session folders: an agent id counts once, by the copy written last. PROJECT is
the folder of the hook input's `transcript_path`, so builders of earlier sessions still count. Reviewers,
investigators and other agents are neither counted nor refused.

Two spawns in one message reach the hook before either agent's meta exists. Each allowed start is
written to a ledger (`EPOCH TOOL_USE_ID` lines, under `fcntl.flock`) and counts as a running builder for
PENDING_SECONDS, until a meta whose `toolUseId` equals it exists; a ledger line that is not an epoch and an id is
skipped and rewritten away. This needs `tool_use_id` in the hook
input; a spawn without it is counted but not recorded, so two such spawns in one message can both pass.

Exit 2 with a line naming the running builders refuses the spawn. Any error, unreadable input or missing
folder, and a ledger another hook holds for LOCK_TRIES tries, exit 0. Checked by
setup_check/test_limit_builders.py.
"""

import fcntl
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import machine_slots  # noqa: E402

LIVE_SECONDS = 900
PENDING_SECONDS = 60
LOCK_TRIES = 50
LOCK_PAUSE_SECONDS = 0.05
LEDGER = Path.home() / ".genesis-prime" / "builder-starts"


def running_builders(project: Path, now: float) -> tuple[list[tuple[str, str, float]], set[str]]:
    """The live builders as (agent id, description, seconds since its last write), and every `toolUseId` with a meta.

    An agent kept under several session folders is one builder: the copy written last decides.
    """
    newest = {}
    shown = set()
    for meta_path in sorted(project.glob("*/subagents/agent-*.meta.json")):
        agent_id = meta_path.name.removeprefix("agent-").removesuffix(".meta.json")
        try:
            meta = json.loads(meta_path.read_text())
            shown.add(meta.get("toolUseId"))
            transcript = meta_path.with_name(f"agent-{agent_id}.jsonl")
            if transcript.exists():
                quiet, limit = now - transcript.stat().st_mtime, LIVE_SECONDS
            else:
                quiet, limit = now - meta_path.stat().st_mtime, PENDING_SECONDS
        except (OSError, ValueError):
            continue
        if agent_id not in newest or quiet < newest[agent_id][0]:
            newest[agent_id] = (quiet, limit, meta)
    live = []
    for agent_id, (quiet, limit, meta) in newest.items():
        if meta.get("agentType") == "implementer" and not meta.get("finished") and quiet <= limit:
            live.append((agent_id, meta.get("description", ""), quiet))
    return live, shown


def pending_starts(lines: list[str], shown: set[str], now: float) -> list[tuple[float, str]]:
    """The ledger's starts under PENDING_SECONDS old whose agent has no meta yet."""
    starts = []
    for line in lines:
        try:
            epoch, tool_use_id = line.split()
            started = float(epoch)
        except ValueError:
            continue
        if now - started < PENDING_SECONDS and tool_use_id not in shown:
            starts.append((started, tool_use_id))
    return starts


def locked(ledger: Path, tries: int):
    """The ledger opened for reading and writing under an exclusive lock, or None when it stays held."""
    ledger.parent.mkdir(parents=True, exist_ok=True)
    handle = open(ledger, "a+")
    for attempt in range(tries):
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except BlockingIOError:
            if attempt + 1 < tries:
                time.sleep(LOCK_PAUSE_SECONDS)
    handle.close()
    return None


def refusal(event: dict, ledger: Path, now: float, lock_tries: int = LOCK_TRIES) -> str | None:
    """The line that refuses the spawn, or None. An allowed builder start with a `tool_use_id` is recorded."""
    try:
        if event["tool_input"].get("subagent_type") != "implementer":
            return None
        tool_use_id = event.get("tool_use_id")
        live, shown = running_builders(Path(event["transcript_path"]).parent, now)
        handle = locked(ledger, lock_tries)
        if handle is None:
            return None
        with handle:
            handle.seek(0)
            pending = pending_starts(handle.read().splitlines(), shown, now)
            slots = machine_slots.TEST_SLOTS
            if len(live) + len(pending) >= slots:
                return refusal_line(live, len(pending), slots)
            if tool_use_id:
                pending.append((now, tool_use_id))
                handle.truncate(0)
                handle.write("".join(f"{epoch} {pending_id}\n" for epoch, pending_id in pending))
    except Exception:
        return None
    return None


def refusal_line(live: list[tuple[str, str, float]], starting: int, slots: int) -> str:
    named = [f"{description} (agent {agent_id}, last wrote {int(quiet // 60)} min ago)"
             for agent_id, description, quiet in live]
    if starting:
        named.append(f"{starting} just started")
    return (f"{slots} builders already run: " + ", ".join(named) + ": another overloads the machine and moves main "
            "under every open pull request. Start it when one hands back; a builder that died stops counting "
            f"{LIVE_SECONDS // 60} minutes after its last write.")


def main() -> int:
    try:
        event = json.load(sys.stdin)
        refused = refusal(event, LEDGER, time.time())
    except Exception:
        return 0
    if refused is None:
        return 0
    print(refused, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
