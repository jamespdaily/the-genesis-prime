"""The state block a session starts with: what runs and where the work stands.

Run through dev/session_state.sh (the SessionStart hook in .claude/settings.json does).
It prints, in about 40 lines: main's commit and whether this checkout is clean, the open
pull requests with their checks, the play server (ports 23115, 6600 and 24000), the newest
sitting, the two watchers, and the newest "Where it stands" comment of the milestone parents.
Each part is capped at 10 s and prints "unreachable" when it fails, so it never fails a
session. For a watcher that is not running it prints the exact command to start as a
background Bash job.
"""
import concurrent.futures
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CAP_SECONDS = 10
PORTS = (23115, 6600, 24000)
DISCORD_CHANNEL = "1567245238521831534"
CHANNELS = Path.home() / ".claude" / "channels" / "discord"
SITTINGS = Path.home() / ".genesis-prime" / "sittings"
ROOT = Path(__file__).resolve().parent.parent
WATCH_SERVER = ROOT / ".claude" / "skills" / "playing-live" / "scripts" / "watch_server.py"
STANDS_LINES = 15
LINE_WIDTH = 170


def run(command, cwd=None):
    """The standard output of a command, within the cap; raises when it fails."""
    done = subprocess.run(
        command, capture_output=True, text=True, timeout=CAP_SECONDS, cwd=cwd, check=True
    )
    return done.stdout


def part(name, function):
    """The lines of one part; a failure or a timeout becomes 'name: unreachable'."""
    try:
        return function()
    except Exception:
        return [f"{name}: unreachable"]


def checkout():
    short = run(["git", "rev-parse", "--short", "main"], cwd=ROOT).strip()
    dirty = run(["git", "status", "--porcelain"], cwd=ROOT).strip()
    branch = run(["git", "branch", "--show-current"], cwd=ROOT).strip() or "(detached)"
    return [f"git: main {short}, checkout {'dirty' if dirty else 'clean'}, branch {branch}"]


def check_state(rollup):
    """failing, pending, passing or none, from a pull request's statusCheckRollup."""
    if not rollup:
        return "no checks"
    results = [(item.get("conclusion") or item.get("state") or "") for item in rollup]
    if any(r in ("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE") for r in results):
        return "failing"
    if any(r in ("", "PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS") for r in results):
        return "pending"
    return "passing"


def open_pull_requests():
    """The open pull requests as (number, title, head branch, check state)."""
    rows = json.loads(
        run(["gh", "pr", "list", "--limit", "200", "--json", "number,title,headRefName,statusCheckRollup"])
    )
    return [(row["number"], row["title"], row["headRefName"], check_state(row["statusCheckRollup"])) for row in rows]


def pull_requests():
    rows = open_pull_requests()
    if not rows:
        return ["pull requests: none open"]
    return ["pull requests:"] + [f"  #{number} {title[:100]} [{state}]" for number, title, _, state in rows]


def listeners():
    """The processes listening on the game ports, as {command: {pid: [ports]}}."""
    listing = subprocess.run(
        ["lsof", "-nP", "-sTCP:LISTEN"] + [f"-iTCP:{port}" for port in PORTS],
        capture_output=True, text=True, timeout=CAP_SECONDS,
    ).stdout
    found = {}
    for line in listing.splitlines()[1:]:
        fields = line.split()
        if len(fields) > 1:
            port = re.search(r":(\d+) \(LISTEN\)", line)
            found.setdefault(fields[0], {}).setdefault(fields[1], []).append(port.group(1) if port else "?")
    return found


def container_line():
    """The line for the genesis-play container when podman shows it running, else None."""
    try:
        rows = run(
            ["podman", "ps", "--filter", "name=^genesis-play$",
             "--format", "{{.Image}}|{{.Status}}|{{.Ports}}"]
        ).strip().splitlines()
        image, status, ports = rows[0].split("|", 2)
    except Exception:
        return None
    return f"play server: running in container genesis-play, image {image}, {status.lower()}, ports {ports}"


def play_server():
    found = listeners()
    lines = []
    for pid, ports in found.get("beam.smp", {}).items():
        elapsed = run(["ps", "-o", "etime=", "-p", pid]).strip()
        lines.append(f"play server: running, pid {pid}, up {elapsed}, ports {','.join(sorted(ports))}")
    container = container_line()
    if container:
        lines.append(container)
    if not lines:
        others = [
            f"{command} pid {pid} on {','.join(sorted(ports))}"
            for command, pids in found.items() for pid, ports in pids.items()
        ]
        if others:
            lines = [f"play server: not running (something else listens: {'; '.join(others)})"]
        else:
            lines = [f"play server: not running (nothing listens on {', '.join(map(str, PORTS))})"]
    folders = sorted((p for p in SITTINGS.iterdir() if p.is_dir()), key=lambda p: p.stat().st_mtime)
    lines.append(f"newest sitting: {folders[-1].name if folders else 'none'}")
    return lines


def running_scripts():
    """The script names of the python processes running, by their command lines."""
    table = run(["ps", "-axo", "args="])
    names = []
    for command in table.splitlines():
        words = command.split()
        if words and "python" in os.path.basename(words[0]).lower():
            names.extend(os.path.basename(word) for word in words[1:] if word.endswith(".py"))
    return names


def server_pane():
    """The pane id of the herdr tab labelled `server`, or None."""
    workspace = os.environ.get("HERDR_WORKSPACE_ID")
    if not workspace:
        return None
    tabs = json.loads(run(["herdr", "tab", "list", "--workspace", workspace]))["result"]["tabs"]
    tab = next((t for t in tabs if t["label"] == "server"), None)
    if tab is None:
        return None
    panes = json.loads(run(["herdr", "pane", "list", "--workspace", workspace]))["result"]["panes"]
    return next((p["pane_id"] for p in panes if p["tab_id"] == tab["tab_id"]), None)


def watchers():
    names = running_scripts()
    lines = []
    if "watch.py" in names:
        lines.append("watcher discord: running")
    else:
        lines.append("watcher discord: NOT running; start as a background Bash job:")
        lines.append(
            f"  python3 -I {CHANNELS}/watch.py {DISCORD_CHANNEL} {CHANNELS}/watch.state --once 2>/dev/null"
        )
    if "watch_server.py" in names:
        lines.append("watcher server: running")
    else:
        try:
            pane = server_pane()
        except Exception:
            pane = None
        if pane:
            lines.append("watcher server: NOT running; start as a background Bash job:")
            lines.append(f"  python3 -I {WATCH_SERVER} {pane} --once")
        else:
            lines.append("watcher server: not running (no herdr tab labelled server)")
    return lines


def milestone_comment(number):
    """The newest 'Where it stands' comment of one issue as (created, number, body), or None."""
    data = json.loads(run(["gh", "issue", "view", str(number), "--json", "comments"]))
    stands = [c for c in data["comments"] if c["body"].startswith("**Where it stands")]
    if not stands:
        return None
    newest = max(stands, key=lambda c: c["createdAt"])
    return (newest["createdAt"], number, newest["body"])


def where_it_stands():
    issues = json.loads(
        run(["gh", "issue", "list", "--state", "open", "--search", "Milestone in:title",
             "--json", "number,title", "--limit", "50"])
    )
    parents = [i["number"] for i in issues if re.match(r"Milestone \d+:", i["title"])]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        found = [c for c in pool.map(lambda n: part_safe(milestone_comment, n), parents) if c]
    if not found:
        return ["where it stands: no comment on a milestone parent"]
    created, number, body = max(found)
    lines = [f"where it stands: milestone parent #{number}, {created[:10]}"]
    lines += [line[:LINE_WIDTH] for line in body.splitlines()[:STANDS_LINES]]
    return lines


def part_safe(function, argument):
    """One issue's failure must not hide the others'."""
    try:
        return function(argument)
    except Exception:
        return None


def main():
    for name, function in (
        ("git", checkout),
        ("pull requests", pull_requests),
        ("play server", play_server),
        ("watchers", watchers),
        ("where it stands", where_it_stands),
    ):
        print("\n".join(part(name, function)))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
