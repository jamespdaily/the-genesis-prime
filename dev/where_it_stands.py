"""Prints the draft of a milestone parent's "Where it stands" comment from GitHub's state.

    python3 -I dev/where_it_stands.py PARENT

PARENT is the milestone parent's issue number. The script reads GitHub through `gh` and prints
Markdown; it posts nothing, so the coordinator adds the notes and posts it. Sections: the pull
requests merged since the parent's newest "Where it stands" comment (the last 24 hours when it
has none, and the line says so), the open pull requests with their checks, the pushed `jimd/*`
branches with no pull request (work that is not a board issue: those with a commit since the
earlier of that window's start and 24 hours ago), then the milestone's open issues on the board (project 2) that are in progress, waiting on Jim, or next in order
(to do, with those that have no open blocker first, in the parent's sub-issue order). It exits
non-zero when a `gh` call fails.
"""
import concurrent.futures
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import session_state  # noqa: E402

PROJECT = "2"
OWNER = "jamespdaily"
WITHOUT_COMMENT = timedelta(hours=24)


def gh_json(*arguments):
    """The parsed JSON a `gh` call prints; raises when the call fails."""
    return json.loads(session_state.run(["gh", *arguments]))


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def merged_since(since):
    """The pull requests merged after `since`, oldest first, as (number, title)."""
    rows = gh_json(
        "pr", "list", "--state", "merged", "--limit", "200",
        "--search", f"merged:>={since.strftime('%Y-%m-%dT%H:%M:%SZ')}",
        "--json", "number,title,mergedAt",
    )
    fresh = [row for row in rows if parse_time(row["mergedAt"]) > since]
    return [(row["number"], row["title"]) for row in sorted(fresh, key=lambda row: row["mergedAt"])]


def board_items(milestone_title, parent):
    """The milestone's board issues other than the parent, as (number, title, status)."""
    items = gh_json("project", "item-list", PROJECT, "--owner", OWNER, "--format", "json", "--limit", "1000")["items"]
    return [
        (item["content"]["number"], item["title"], item.get("status", ""))
        for item in items
        if (item.get("milestone") or {}).get("title") == milestone_title
        and item["content"].get("type") == "Issue"
        and item["content"]["number"] != parent
    ]


def open_blockers(number):
    """None when the issue is closed, otherwise the numbers of its open blockers."""
    data = gh_json("issue", "view", str(number), "--json", "state,blockedBy")
    if data["state"] != "OPEN":
        return None
    return [node["number"] for node in data["blockedBy"]["nodes"] if node["state"] == "OPEN"]


def pushed_branches(cutoff):
    """The remote `jimd/*` branches with commits beyond main, no open pull request and a commit after `cutoff`."""
    root = session_state.ROOT
    session_state.run(["git", "fetch", "--prune", "origin"], cwd=root)
    listing = session_state.run(
        ["git", "for-each-ref", "--format=%(refname:short)|%(objectname:short)|%(committerdate:iso-strict)|%(contents:subject)",
         "refs/remotes/origin/jimd"],
        cwd=root,
    )
    with_pull_request = {row["headRefName"] for row in gh_json("pr", "list", "--json", "headRefName")}
    found = []
    for row in listing.splitlines():
        ref, short, date, subject = row.split("|", 3)
        branch = ref.removeprefix("origin/")
        committed = parse_time(date).astimezone(timezone.utc)
        if branch in with_pull_request or committed <= cutoff:
            continue
        if int(session_state.run(["git", "rev-list", "--count", f"origin/main..{ref}"], cwd=root)) > 0:
            found.append((committed, f"- {branch} ({short}, {committed.strftime('%Y-%m-%d %H:%M')} UTC, {subject})"))
    return [line for _, line in sorted(found)] or ["- none"]


def issue_lines(items, status):
    return [f"- #{number} {title}" for number, title, item_status in items if item_status == status] or ["- none"]


def next_in_order(items, blockers, order):
    """The open to-do issues: no open blocker first, each group in the parent's sub-issue order."""
    todo = [item for item in items if item[2] == "To do"]
    todo.sort(key=lambda item: (bool(blockers[item[0]]), order.get(item[0], len(order))))
    return [
        f"- #{number} {title}" + (f" (blocked by {', '.join(f'#{b}' for b in blockers[number])})" if blockers[number] else "")
        for number, title, _ in todo
    ] or ["- none"]


def draft(parent):
    parent_data = gh_json("issue", "view", str(parent), "--json", "milestone,subIssues")
    milestone_title = parent_data["milestone"]["title"]
    order = {node["number"]: index for index, node in enumerate(parent_data["subIssues"]["nodes"])}
    now = datetime.now(timezone.utc)
    newest = session_state.milestone_comment(parent)
    if newest:
        since = parse_time(newest[0])
        window = f"since the last line ({newest[0][:16].replace('T', ' ')} UTC)"
    else:
        since = now - WITHOUT_COMMENT
        window = "in the last 24 hours (the parent has no \"Where it stands\" comment yet)"

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        merged_job = pool.submit(merged_since, since)
        pulls_job = pool.submit(session_state.pull_requests)
        pushed_job = pool.submit(pushed_branches, min(since, now - WITHOUT_COMMENT))
        items = board_items(milestone_title, parent)
        found = dict(zip((item[0] for item in items), pool.map(open_blockers, (item[0] for item in items))))
        merged = merged_job.result()
        pulls = pulls_job.result()
        pushed = pushed_job.result()
    open_items = [item for item in items if found[item[0]] is not None]

    pull_lines = [line.strip().replace("#", "- #", 1) for line in pulls[1:]] or ["- none"]
    lines = [f"**Where it stands ({now.strftime('%Y-%m-%d')}, {milestone_title})**"]
    lines.append(f"- Merged {window}:")
    lines += [f"  - #{number} {title}" for number, title in merged] or ["  - none"]
    sections = (
        ("Open pull requests", pull_lines),
        ("Pushed, no pull request", pushed),
        ("In progress", issue_lines(open_items, "In progress")),
        ("Waiting on Jim", issue_lines(open_items, "Waiting on Jim")),
        ("Next in order", next_in_order(open_items, found, order)),
    )
    for heading, body in sections:
        lines.append(f"- {heading}:")
        lines += [f"  {line}" for line in body]
    lines.append("- Notes:")
    return "\n".join(lines)


def main():
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        sys.exit(__doc__)
    print(draft(int(sys.argv[1])))


if __name__ == "__main__":
    main()
