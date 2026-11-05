---
name: running-a-step
description: How the coordinator carries a step from its trace to merge - the checklist of phases, the brief, the reviews, the fix round, failures met during a step, tracking on GitHub, the live sitting and the closing summary. Use when planning a milestone, filing an issue, or starting, building, reviewing or closing a step.
---

# Running a step

The coordinator (the main session) owns a step from design to merge. Builders and reviewers are fresh agents with bounded briefs. The step's issue holds its state: a new session resumes from the parent issue, the board and the progress lines.

## The checklist

Copy this onto the step's issue. Each phase posts its progress line on the issue, naming the commit. A hook posts the push, pull request, CI and merge lines and moves the card (`dev/hooks/progress_lines.py`); the coordinator writes the others.

```
- [ ] Trace (once per milestone, up front): decoders trace every message the milestone's goals need, in parallel; each trace lands on its step's issue before that step's design starts. Line: "trace posted".
- [ ] Design and test list posted; the step is ready (below). The coordinator approves them once. Line: "design posted".
- [ ] Shape and its review, when the step changes processes (below). Line: "shape pushed".
- [ ] Brief and build: one fresh implementer, or two after a shape that splits the build (below), from the brief. Line: the hook's push line.
- [ ] Reviews (below). Line: "reviews in".
- [ ] Fix round (below). Line: the hook's push line.
- [ ] Green: the full check and CI pass with no rerun. Line: the hook's CI line, attempt 1, with the builder's `./check` in its hand-back.
- [ ] Merge on green; Jim's global file holds how the pull request body is written. Line: the hook's merge line.
- [ ] Closing summary (below). Line: the summary itself.
```

Once a goal's last step merges, the goal gets its one live sitting (below); its line is "live check" on the goal's issue.

From design to merge the step runs without Jim, except for the four decisions CLAUDE.md gives him. Agents go on alone to add tests, remove duplication, swap in a library call, or fix a failure within the approved behaviour. A design-only step is the first two phases alone.

## Design and test list

Read the client's evidence, CLAUDE.md, then the code the step touches. For a change the client sees, trace the client's code from the step's messages to the visible goal: each check on that path becomes a test, and a field with no known meaning needs the client's code to show its value is safe. Weigh at least two options, asking first what most projects use; measure when costs differ, else take the simplest. Read the-eldan-experiment's code for the same flow, and write what it did, or the search that found nothing, in the Design's "Eldan" paragraph; its facts count only once the client confirms them.

A step's working detail goes in Markdown artifacts on its issue, named "Client trace", "Design" or "Review", each edited in place and kept. Once the step merges they are history, and nothing enforced lives only there.

A step is labelled `ready` when an agent can finish it without inventing requirements: its issue states the outcome, the acceptance checks, the evidence, the scope and what is left out, and the steps it depends on; its trace and design artifacts are written and its test list is posted. Until then it is labelled `investigation`.

Steps that share no files run at once, each with its own builder. At most two agents run tests on one machine at once.

## The shape

A step that changes processes, supervision, or what one process asks or sends another (one new request counts) gets a shape commit and every review; any other step gets one Claude reviewer. A step that only deletes or moves code skips the shape review.

The shape commit holds the types, signatures and supervision, and a sequence of each message and what happens when a deadline passes or a process dies. When two rules or shells share a flow, it names the module that holds the shared part. Codex reviews it (`dev/codex_review.sh`), or a Claude Opus reviewer with the same brief when Codex cannot run (out of credits or down).

## The brief

One fresh implementer per step, in its own worktree (the Agent tool's worktree isolation). After a shape commit, the build may go to two implementers at once when the shape splits it into parts that share no files: each builds its part on its own branch from the shape, with this brief for its part, and the second to finish merges the other's branch into the step's branch before the reviews. Step G's single builder took 51 minutes over 32 files (2026-11-04). Its brief holds:
- **Outcome:** what a player or the client sees when it is done.
- **Evidence:** each value with its source, read before it is written: a client fact, or "server choice" with its reason.
- **Acceptance:** the test list, and the scenario a live sitting runs.
- **Scope:** the modules it may change, and what is left out.
- **Reuse starting points:** the existing functions, test support and packages a gatherer found for each planned function, by name and file. Reuse what a module shares by importing it or moving it to a shared module; copying a module's glue and tests is what to avoid.
- **Failure table,** for a step with a shape commit, or with locks, timers or remote steps: each step of the flow, and what happens if it is killed there, run twice at once, or times out. Each row becomes a test, and the shape review reads the table with the shape.
- **Escalation:** what comes back to Jim instead of being chosen.
- **Scratch:** its own scratch subfolder, `<step>-<role>`.

The implementer's own file (`.claude/agents/implementer.md`) holds its checks, pushes and hand-back.

## Reviews

A step with a shape commit gets these, on the fixed commit the builder pushed, side by side:
- **Codex's bug review** (`dev/codex_review.sh code BASE HEAD "..."`), or a Claude Opus reviewer when Codex cannot run: correctness, evidence, failure paths, restarts, concurrency, and OTP fit when the diff touches processes. Bug reviewers are also asked whether any new test depends on timing, a session's length, read boundaries or a mailbox's length.
- **One Claude reuse reviewer:** code that repeats an existing function, the standard library or a package, each finding naming its replacement and whether its errors and edge cases match.
- **An issue check:** each test the step's list promised is present, and each done-when item is met, with the evidence for each.
- **The main session's own read** against the skills the step used.

Any other step gets one Claude reviewer for bugs, reuse and the issue check together, beside the main session's own read.

## The fix round

Check each finding against the code first, then fix what holds in one round. A bug the step caused is fixed before it merges, in this round or another. A review's top finding caused by the last round's fix counts as a second failure with one cause (below). Anything else follows "Failures" below. Notes that change nothing the step promises go in the closing summary.

## Failures, gaps and questions

**Done** means the full check and CI pass with no rerun. A failure met during a step is fixed before the step merges: inside the step when the step caused it; otherwise in its own small pull request, merged first. A fix that touches one area and changes nothing the server does (a test, a typo, a stale line) needs no design or trace: one builder, one reviewer. An issue is filed only for a wrong result found outside any step's work, such as live play or a nightly bot run.

- **Logged as unhandled** is missing, not a bug: the coverage measure lists it, and its area's checklist line gets any new evidence; no issue. Build it in the step only when the step's goal fails without it.
- **Handled, but the result differs from the evidence, or it crashed:** a bug.
- **Handled, but no evidence says what is right:** look in the evidence first. Only when it cannot settle it is it a question for Jim, marked Waiting on Jim. A silent wrong result is a bug.
- **A report from live play** is sorted first. A wrong result from a system already built is a bug and the next step. A behaviour not built yet is a dated line on the issue of the system whose planned work builds it, and no new issue. A milestone does not end with a bug open. (Creature facing was filed as its own step, #432, though the creature's fight behaviour was already planned work, 2026-11-05.)

Before any fix, inside a step or not, search the closed issues and the step's own fixes for the same cause or module. Two failures with one cause, or three in one module in a milestone, stop the patching: the next step finds the root cause first and states whether a targeted fix, a stronger check or a redesign removes it, and why; the open fixes fold into it.

## The live sitting

A sitting runs when the client sees or sends something new (the `playing-live` skill): an agent drives what the client driver reaches, and Jim plays the rest. The steps of one goal share one sitting: each merges on green, and the sitting runs once the goal's last step merges. A failure in it is sorted as a report from live play (above); the goal stays open until the sitting passes. A replay that differs after a change meant to alter what the client receives is recorded again live (the `designing-processes` skill). A playable server is set up whenever Jim asks.

## Tracking

- Planned work lives in GitHub: one board, and a milestone with a parent issue whose sub-issues are its steps, with a measured end condition on the parent. A playable goal's done-when includes "a bot can do it".
- **Choosing the next step:** biggest impact first, by two rankings: the types the system's content reaches that the coverage measure (`gleam run -m genesis_prime/coverage`) shows unhandled (spell effects, prerequisites; whole-game weight breaks ties), and the unhandled messages the recorded sittings send most (`gleam run -m genesis_prime/unhandled_ranking -- ~/.genesis-prime/sittings/*`). A step handles a type for every row that uses it, never for one ability. (Fight's per-ability steps #403, #418 and #419 drifted from this, 2026-11-05.)
- **At a milestone's close** the coordinator posts on its parent the coverage measure, the ranking and each step's cost per type or message, against the milestone before. When the cost per type did not fall, the rule goes to Jim before the next milestone starts.
- Step order is set by blocked-by links (`dev/card.sh block N --by S`), not by the sub-issue list's order. Cleanups and dev tools sit after the milestone's goal steps, unless the parent's order, with Jim's yes, places one earlier.
- Before opening an issue, search the code and the issues under several names. A new issue states its proof the problem is real (a failing test, a measurement, a client fact or Jim's request), else it is a line on the parent. Its title states the outcome. File and move it with `dev/card.sh`: milestone, parent, blockers and status (To do, In progress, Waiting on Jim, Done).
- A step's issue carries its test list, progress lines, dated measurements and closing summary.
- A change to guidance (CLAUDE.md, a skill, an agent) needs no issue: its pull request names the milestone's parent issue.
- The session is cleared at each merge with no builder mid-work. The session-start state block (`dev/session_state.sh`) shows what runs, so a hand-off is the parent's newest "Where it stands" comment and one line naming the milestone.

## The closing summary

- The step's wall time, its agents' tool calls (unique tool_use ids in their transcripts) and its fix rounds, with the measure the merge line posted (`dev/step_measure.py N`) for the cost.
- Each throwaway tool or workaround and the issue that owns it. For a bug fix: the choice that let the bug through and the check that now stops it.
- The coverage measure's handled counts and the ranking's top five, before and after, and the cost per type or message handled.
- Its notes, sorted: a missing tool or feature gets its own issue when it has its proof, else a line on the parent; a small repeat or a stale line goes on the milestone's standing cleanups issue's checklist, and a step that touches its file fixes it; anything else stays in the summary.
