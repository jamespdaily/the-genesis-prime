---
name: running-a-step
description: How the coordinator carries a step from its design to merge - the brief, the builder's hand-back, the reviews, the fix round, the live check and the closing summary. Use when starting, building, reviewing or closing a step.
---

# Running a step

The coordinator (the main session) owns a step from design to merge. Builders and reviewers are fresh agents with bounded briefs; the step's issue holds its state.

## Ready

A step is labelled `ready` when an agent can finish it without inventing requirements: its issue states the outcome, the acceptance checks, the evidence, the scope and what is left out, and the steps it depends on.

## The brief

One fresh implementer per step, in its own worktree (the Agent tool's worktree isolation). Its brief holds:
- **Outcome:** what a player or the client sees when it is done.
- **Evidence:** each value with its source, read before it is written: a client fact, or "server choice" with its reason.
- **Acceptance:** the test list, and the scenario a live check runs.
- **Scope:** the modules it may change, and what is left out.
- **Reuse starting points:** the existing functions, test support and packages a gatherer found for each planned function, by name and file. Never an existing module as a template.
- **Failure table,** for a step with processes, locks, timers or remote steps: each step of the flow, and what happens if it is killed there, run twice at once, or times out. Each row becomes a test, and Codex reviews the table with the shape before the build.
- **Escalation:** what comes back to Jim instead of being chosen.
- **Checks:** `gleam build`, the tests the builder touches, `./check fast`, then `./check` once on the commit it hands back, with their whole output kept; CI runs the no-client variant.

## The hand-back

The builder hands back once, with: each function it added, the closest existing function or library call, and why that one is not used; each failure-table row's test; the check results. Skill or script text it writes holds only what an operator runs, when, and what it refuses.

## Reviews

On the fixed commit the builder pushed, side by side:
- **Codex's bug review** (`dev/codex_review.sh code BASE HEAD "..."`): correctness, evidence, failure paths, restarts, concurrency, and OTP fit when the diff touches processes; bug reviewers are also asked whether any new test depends on timing, a session's length, read boundaries or a mailbox's length.
- **One Claude reuse reviewer:** code that repeats an existing function, the standard library or a package, each finding naming its replacement and whether its errors and edge cases match.
- **A card check:** each test the step's list promised is present, and each done-when item is met, with the evidence for each.
- **The main session's own read** against the skills the step used.

Check each finding against the code first. One fix round. After it, a P1 (a break of what the step promises) and new duplication or a reimplemented library function are fixed; any other bug the step caused becomes the next step in the milestone's order, and the rest goes in the closing summary.

## Live check and merge

A live session runs when the client sees or sends something new (the `playing-live` skill): an agent drives what the client driver reaches, and Jim plays the rest. A replay that differs after a change meant to alter what the client receives: the session is recorded again live (the `designing-processes` skill). Merge on green; Jim's global file holds how the pull request body is written.

## Bugs and the closing summary

Before a bug fix, search the closed bugs for the same cause or module. Two bugs with one cause, or three in one module in a milestone, stop the patching: the next step finds the root cause first and states whether a targeted fix, a stronger check or a redesign removes it, and why; the open fixes fold into it. A review's top finding caused by the last round's fix counts as a second bug with one cause.

The closing summary names each throwaway tool or workaround and the issue that owns it; a bug's also names the choice that let it through and the check that now stops it.
