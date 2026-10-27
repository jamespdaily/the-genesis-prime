"""One step's agent work, measured from this project's Claude Code transcripts.

Claude Code saves each session as JSON lines under ~/.claude/projects/, one folder per
checkout, and each subagent run in its own file beside a .meta.json that names its
agent type. This script reads the folders of every checkout of this repository and
prints, for one step, a Markdown table of the runs, minutes, tokens and dollars of the
main session and of each agent type, and the Codex review runs. It reads files on this
machine only.

A step is named by its branch, jimd/<n>-..., or its worktree, worktrees/<n>-..., in the
text of a tool call. A number counts only when a jimd/<n>- branch is named somewhere,
so a milestone's parent issue never takes a step's work.

  main session  a step starts in a fresh session, so a session that names one step
                belongs to it whole. A session that names several is shared: each of
                its replies goes to the branch it was written on, else to the step last
                mentioned in a tool call (a branch, a worktree, `gh issue <verb> <n>` or
                `dev/card.sh <verb> <n>`), and the step's table marks it rough.
  subagent      the first step its brief names, else the branch it runs on, else the
                step of the reply that started it.

A transcript writes one reply on several lines, each with the same usage; each reply
is counted once. A subagent's minutes run from its first line to its last. The main
session's minutes add the time from each line to the next while it works, each gap
capped at five minutes, and leave out the wait for Jim's next message. Codex runs in
the background and its tokens are not in these transcripts, so it shows runs only.

Prices are dollars per million tokens from Anthropic's pricing page,
platform.claude.com/docs/en/about-claude/pricing. --check-prices prices each session
Claude Code recorded a cost for and prints both, so a stale rate shows as a gap. A
session whose work stays in one transcript matches to the cent. A session with
subagents records more than its transcripts hold: calls that read context but write
almost nothing, and compaction, are not saved. The step's table names that share for
the sessions the step ran in.

Usage:
  python3 -I dev/step_measure.py 143
  python3 -I dev/step_measure.py --check-prices
"""

import argparse
import collections
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
IDLE_CAP_SECONDS = 300


@dataclass(frozen=True)
class Price:
    """Dollars per million tokens of one model."""

    input: float
    write_5m: float
    write_1h: float
    read: float
    output: float


# Cache writes cost 1.25x input for five minutes and 2x for an hour. Cache reads cost
# 0.05x input on Opus 5.5 and Sonnet 5.5, and 0.1x on Haiku 5.5.
PRICES = {
    "claude-opus-5-5": Price(4.00, 5.00, 8.00, 0.20, 20.00),
    "claude-sonnet-5-5": Price(2.00, 2.50, 4.00, 0.10, 10.00),
    "claude-haiku-5-5": Price(0.10, 0.125, 0.20, 0.01, 0.50),
}
# Haiku 5.5 charges five times its rates for a prompt over 100,000 tokens.
LONG_PROMPT = {"claude-haiku-5-5": (100_000, 5.0)}

_BRANCH = re.compile(r"jimd/(\d+)-")
_NAMES_STEP = re.compile(r"jimd/(\d+)-|worktrees/(\d+)-")
_MENTIONS_STEP = re.compile(
    r"jimd/(\d+)-|worktrees/(\d+)-"
    r"|\bgh issue (?:view|edit|comment|close|reopen)\s+(\d+)\b"
    r"|\bcard\.sh (?:status|move|order)\s+(\d+)\b"
)
_CODEX = re.compile(r"codex_review\.sh|\bcodex (?:review|exec)\b")


def numbers(pattern: re.Pattern, text: str) -> list[int]:
    """The step numbers a pattern finds, in the order they are written."""
    return [int(next(g for g in m.groups() if g)) for m in pattern.finditer(text)]


@dataclass
class Reply:
    """One model reply, counted once however many transcript lines carry it."""

    time: datetime
    model: str
    usage: dict
    active: float = 0.0
    names: list[int] = field(default_factory=list)
    mentions: list[int] = field(default_factory=list)
    branch: int | None = None
    starts: list[str] = field(default_factory=list)
    codex: int = 0
    step: int | None = None


@dataclass
class Run:
    """One transcript: a main session or a subagent run."""

    path: Path
    session: str
    agent: str
    started_by: str | None
    brief: str = ""
    replies: list[Reply] = field(default_factory=list)
    times: list[datetime] = field(default_factory=list)
    recorded: dict | None = None
    branches: set[int] = field(default_factory=set)
    shared: bool = False
    step: int | None = None


def project_folders() -> list[Path]:
    """The transcript folders of every checkout of this repository."""
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    prefix = re.sub(r"[^A-Za-z0-9]", "-", str(Path(common).parent))
    return sorted(p for p in PROJECTS.glob(prefix + "*") if p.is_dir())


def git_steps() -> set[int]:
    """The step numbers of every local and remote jimd/<n>- branch."""
    refs = subprocess.run(
        [
            "git",
            "for-each-ref",
            "--format=%(refname:short)",
            "refs/heads",
            "refs/remotes",
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return {int(n) for n in _BRANCH.findall(refs)}


def when(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    return " ".join(x.get("text", "") for x in content or [] if isinstance(x, dict))


def from_jim(row: dict) -> bool:
    """Whether a line is a message Jim typed, not a tool result or a notice."""
    if row.get("type") != "user" or row.get("isMeta") or row.get("isCompactSummary"):
        return False
    content = (row.get("message") or {}).get("content")
    if isinstance(content, str):
        return True
    return not any(
        isinstance(x, dict) and x.get("type") == "tool_result" for x in content or []
    )


def read_run(path: Path) -> Run:
    """Reads one transcript into its replies, its brief and its recorded cost."""
    if path.parent.name == "subagents":
        meta = path.with_suffix(".meta.json")
        info = json.loads(meta.read_text()) if meta.exists() else {}
        run = Run(
            path,
            path.parent.parent.name,
            info.get("agentType", "unknown agent"),
            info.get("toolUseId"),
        )
    else:
        run = Run(path, path.stem, "main session", None)

    by_id: dict[tuple, Reply] = {}
    current = None
    last_time = None
    for line in path.open():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("type") == "cost-state":
            run.recorded = row
            continue
        stamp = row.get("timestamp")
        time = when(stamp) if stamp else None
        gap = (
            min((time - last_time).total_seconds(), IDLE_CAP_SECONDS)
            if time and last_time
            else 0.0
        )
        if time:
            run.times.append(time)
            last_time = time
        message = row.get("message") or {}
        content = (
            message.get("content") if isinstance(message.get("content"), list) else []
        )

        if row.get("type") == "user" and not run.brief and run.agent != "main session":
            run.brief = text_of(message.get("content"))

        if row.get("type") != "assistant" or message.get("model") in (
            None,
            "<synthetic>",
        ):
            if current is not None and not from_jim(row):
                current.active += max(gap, 0.0)
            continue

        key = (message.get("id"), row.get("requestId"))
        reply = by_id.get(key)
        if reply is None:
            reply = Reply(time, message["model"], message.get("usage") or {})
            by_id[key] = reply
            run.replies.append(reply)
        reply.active += max(gap, 0.0)
        current = reply
        branch = _BRANCH.match(row.get("gitBranch") or "")
        if branch:
            reply.branch = int(branch.group(1))
            run.branches.add(reply.branch)
        for item in content:
            if not isinstance(item, dict) or item.get("type") != "tool_use":
                continue
            text = json.dumps(item.get("input"))
            reply.names += numbers(_NAMES_STEP, text)
            reply.mentions += numbers(_MENTIONS_STEP, text)
            run.branches.update(int(n) for n in _BRANCH.findall(text))
            if item.get("name") == "Agent":
                reply.starts.append(item["id"])
            if item.get("name") == "Bash" and _CODEX.search(
                (item.get("input") or {}).get("command", "")
            ):
                reply.codex += 1
    return run


def assign_steps(runs: list[Run], known: set[int]) -> None:
    """Gives each main-session reply and each subagent run its step."""
    started_step: dict[str, int | None] = {}
    for run in runs:
        if run.agent != "main session":
            continue
        named = list(
            dict.fromkeys(n for r in run.replies for n in r.names if n in known)
        )
        run.shared = len(named) > 1
        mentioned = None
        for reply in run.replies:
            if not run.shared:
                reply.step = named[0] if named else None
            else:
                mentions = [n for n in reply.mentions if n in known]
                mentioned = mentions[-1] if mentions else mentioned
                reply.step = reply.branch if reply.branch in known else mentioned
            for tool_use in reply.starts:
                started_step[tool_use] = reply.step

    for run in runs:
        if run.agent == "main session":
            continue
        from_brief = [n for n in numbers(_NAMES_STEP, run.brief) if n in known]
        branches = collections.Counter(
            r.branch for r in run.replies if r.branch in known
        )
        if from_brief:
            run.step = from_brief[0]
        elif branches:
            run.step = branches.most_common(1)[0][0]
        else:
            run.step = started_step.get(run.started_by)
        for reply in run.replies:
            reply.step = run.step


def cost(reply: Reply) -> float | None:
    """The reply's price in dollars, or None for a model with no price."""
    price = PRICES.get(reply.model)
    if price is None:
        return None
    usage = reply.usage
    written = usage.get("cache_creation") or {}
    write_1h = written.get("ephemeral_1h_input_tokens", 0)
    write_5m = written.get(
        "ephemeral_5m_input_tokens",
        usage.get("cache_creation_input_tokens", 0) - write_1h,
    )
    tokens = [
        usage.get("input_tokens", 0),
        write_5m,
        write_1h,
        usage.get("cache_read_input_tokens", 0),
        usage.get("output_tokens", 0),
    ]
    rates = [price.input, price.write_5m, price.write_1h, price.read, price.output]
    scale = 1.0
    if reply.model in LONG_PROMPT:
        limit, factor = LONG_PROMPT[reply.model]
        if sum(tokens[:4]) > limit:
            scale = factor
    return scale * sum(t * r for t, r in zip(tokens, rates)) / 1e6


def input_tokens(reply: Reply) -> int:
    usage = reply.usage
    return (
        usage.get("input_tokens", 0)
        + usage.get("cache_creation_input_tokens", 0)
        + usage.get("cache_read_input_tokens", 0)
    )


@dataclass
class Tally:
    runs: int = 0
    minutes: float = 0.0
    input: int = 0
    output: int = 0
    dollars: float = 0.0
    unpriced: set = field(default_factory=set)

    def add(self, replies: list[Reply]) -> None:
        for reply in replies:
            self.input += input_tokens(reply)
            self.output += reply.usage.get("output_tokens", 0)
            price = cost(reply)
            if price is None:
                self.unpriced.add(reply.model)
            else:
                self.dollars += price


@dataclass
class SessionCost:
    """A session's cost as Claude Code recorded it, and as priced from its saved replies."""

    recorded: dict | None
    replies: list[Reply]

    @property
    def priced(self) -> float:
        return sum(cost(x) or 0 for x in self.replies)

    @property
    def recorded_dollars(self) -> float:
        return (self.recorded or {}).get("totalCostUSD", 0.0)


def session_costs(runs: list[Run]) -> dict[str, SessionCost]:
    """Each main session with its subagents' replies."""
    sessions = {
        r.session: SessionCost(r.recorded, list(r.replies))
        for r in runs
        if r.agent == "main session"
    }
    for run in runs:
        if run.agent != "main session" and run.session in sessions:
            sessions[run.session].replies += run.replies
    return sessions


def millions(n: int) -> str:
    return f"{n / 1e6:.1f}M"


def thousands(n: int) -> str:
    return f"{n / 1e3:.0f}k"


def plural(n: int, word: str) -> str:
    return f"{n} {word}{'' if n == 1 else 's'}"


def report(step: int, runs: list[Run]) -> int:
    """Prints the step's table; returns the exit status."""
    mains = {r.session: r for r in runs if r.agent == "main session"}
    sub_runs = [r for r in runs if r.agent != "main session" and r.step == step]
    main_replies = {
        s: [x for x in r.replies if x.step == step] for s, r in mains.items()
    }
    main_replies = {s: x for s, x in main_replies.items() if x}
    if not main_replies and not sub_runs:
        print(f"No transcript work matched step #{step}.")
        return 1

    times = [x.time for xs in main_replies.values() for x in xs]
    times += [t for r in sub_runs for t in (min(r.times), max(r.times)) if r.times]
    start, end = min(times), max(times)
    shared = [s for s in main_replies if mains[s].shared]

    rows: dict[str, Tally] = {}
    main = rows.setdefault("main session", Tally(runs=len(main_replies)))
    for replies in main_replies.values():
        main.add(replies)
        main.minutes += sum(x.active for x in replies) / 60
    for run in sorted(sub_runs, key=lambda r: r.agent):
        tally = rows.setdefault(run.agent, Tally())
        tally.runs += 1
        tally.minutes += (
            (max(run.times) - min(run.times)).total_seconds() / 60 if run.times else 0
        )
        tally.add(run.replies)
    codex = sum(x.codex for xs in main_replies.values() for x in xs)

    print(
        f"**Step #{step}: agent work from {start:%Y-%m-%d %H:%M} to {end:%Y-%m-%d %H:%M} UTC**"
    )
    print()
    print("| Who | Runs | Minutes | Input tokens | Output tokens | Cost |")
    print("|---|---:|---:|---:|---:|---:|")
    total = Tally()
    for name, tally in rows.items():
        runs_text = str(tally.runs)
        if name == "main session":
            runs_text = plural(tally.runs, "session") + (
                f", {len(shared)} shared: rough" if shared else ""
            )
        print(
            f"| {name} | {runs_text} | {tally.minutes:.0f} | {millions(tally.input)} "
            f"| {thousands(tally.output)} | ${tally.dollars:.2f} |"
        )
        total.input += tally.input
        total.output += tally.output
        total.dollars += tally.dollars
        total.unpriced |= tally.unpriced
    if codex:
        print(
            f"| Codex review | {codex} | not recorded | not recorded | not recorded | not recorded |"
        )
    print(
        f"| **total** | | | {millions(total.input)} | {thousands(total.output)} | **${total.dollars:.2f}** |"
    )
    print()

    if shared:
        unmatched = Tally()
        for session in shared:
            unmatched.add(
                [
                    x
                    for x in mains[session].replies
                    if x.step is None and start <= x.time <= end
                ]
            )
        print(
            f"Rough: the step shares {plural(len(shared), 'session')} with other steps. Replies there "
            "went to the step last mentioned, which is often wrong. Replies there in the step's span "
            f"that mentioned no step cost ${unmatched.dollars:.2f} and are left out."
        )
    if total.unpriced:
        print(
            f"No price for {', '.join(sorted(total.unpriced))}: those tokens are counted but not priced."
        )

    costs = session_costs(runs)
    ran_in = set(main_replies) | {r.session for r in sub_runs}
    known = [costs[s] for s in ran_in if s in costs and costs[s].recorded]
    recorded = sum(c.recorded_dollars for c in known)
    priced = sum(c.priced for c in known)
    if recorded:
        print(
            f"Claude Code recorded ${recorded:.2f} for the {plural(len(known), 'session')} this step ran in, "
            f"against ${priced:.2f} priced from their saved replies. The other "
            f"{(recorded - priced) / recorded:.0%} is calls the transcripts do not save, so the table may "
            "miss about that share of the step's cost too."
        )
    if len(known) < len(ran_in):
        print(
            f"No recorded cost yet for {plural(len(ran_in) - len(known), 'session')} this step ran in."
        )
    return 0


def check_prices(runs: list[Run]) -> int:
    """Prints recorded against priced cost for each session Claude Code recorded one for."""
    recorded_total = priced_total = 0.0
    by_model = collections.defaultdict(lambda: [0.0, 0.0])
    print("| Session | Recorded | Priced | Gap |")
    print("|---|---:|---:|---:|")
    for session, spent in session_costs(runs).items():
        if not spent.recorded:
            continue
        recorded, priced = spent.recorded_dollars, spent.priced
        gap = (priced - recorded) / recorded if recorded else 0
        print(f"| {session[:8]} | ${recorded:.2f} | ${priced:.2f} | {gap:+.1%} |")
        recorded_total += recorded
        priced_total += priced
        for model, usage in (spent.recorded.get("modelUsage") or {}).items():
            by_model[model][0] += usage.get("costUSD", 0.0)
        for reply in spent.replies:
            by_model[reply.model][1] += cost(reply) or 0
    gap = (priced_total - recorded_total) / recorded_total if recorded_total else 0
    print(f"| **all** | ${recorded_total:.2f} | ${priced_total:.2f} | {gap:+.1%} |")
    print()
    print("| Model | Recorded | Priced |")
    print("|---|---:|---:|")
    for model, (recorded, priced) in sorted(by_model.items()):
        print(f"| {model} | ${recorded:.2f} | ${priced:.2f} |")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("step", nargs="?", type=int, help="the step's issue number")
    parser.add_argument(
        "--check-prices",
        action="store_true",
        help="compare priced and recorded session costs",
    )
    args = parser.parse_args()
    if args.step is None and not args.check_prices:
        parser.error("give a step's issue number, or --check-prices")

    folders = project_folders()
    paths = [p for f in folders for p in f.glob("*.jsonl")]
    paths += [p for f in folders for p in f.glob("*/subagents/*.jsonl")]
    runs = [read_run(p) for p in sorted(paths)]
    known = git_steps().union(*(run.branches for run in runs))
    assign_steps(runs, known)

    if args.check_prices:
        return check_prices(runs)
    return report(args.step, runs)


if __name__ == "__main__":
    sys.exit(main())
