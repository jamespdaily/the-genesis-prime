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
- [ ] Design and test list: the step is ready (below), and the coordinator approves both once. Line: one comment headed "Test list", holding the approval and the whole list; a hook refuses a push to the step's branch before it.
- [ ] Shape and its review, when the step changes processes (below). Line: "shape pushed".
- [ ] Brief and build: one fresh implementer, or two after a shape that splits the build (below), from the brief. Line: the hook's push line.
- [ ] Reviews (below). Line: "reviews in".
- [ ] Fix round (below). Line: the hook's push line.
- [ ] Green: the full check and CI pass with no rerun. Line: the hook's CI line, attempt 1, with the builder's `./check` in its hand-back.
- [ ] Merge on green. The pull request body is the outcome, the issue, and one line per behaviour. Line: the hook's merge line, which also posts the step's measures.
- [ ] Closing summary (below): the coordinator's notes only. Line: the summary itself.
```

Once a goal's last step merges, the goal gets its one live sitting (below); its line is "live check" on the goal's issue.

From design to merge the step runs without Jim, except for the four decisions CLAUDE.md gives him. Agents go on alone to add tests, remove duplication, swap in a library call, or fix a failure within the approved behaviour. A design-only step is the first two phases alone.

## Design and test list

Read the client's evidence, CLAUDE.md, then the code the step touches. For a change the client sees, trace the client's code from the step's messages to the visible goal: each check on that path becomes a test, and a field with no known meaning needs the client's code to show its value is safe. Weigh at least two options, asking first what most projects use; measure when costs differ, else take the simplest. Read the-eldan-experiment's code for the same flow, and write what it did, or the search that found nothing, in the Design's "Eldan" paragraph; its facts count only once the client confirms them.

A step's working detail goes in Markdown artifacts on its issue, named "Client trace", "Design" or "Review", each edited in place and kept. Once the step merges they are history, and nothing enforced lives only there.

A step is labelled `ready` when an agent can finish it without inventing requirements: its issue states the outcome, the acceptance checks, the evidence, the scope and what is left out, and the steps it depends on; its trace and design artifacts are written and its test list is posted. Until then it is labelled `investigation`.

Steps that share no files run at once, each with its own builder. At most two test runs share the machine: full checks, targeted tests, recordings and load runs all count, and a hook refuses a third.

## The shape

A step that changes processes, supervision, or what one process asks or sends another (one new request counts) gets a shape commit and both reviews (below); any other step gets one Claude reviewer. A step that only deletes or moves code skips the shape review.

The shape commit holds the types, signatures and supervision, and a sequence of each message and what happens when a deadline passes or a process dies. When two rules or shells share a flow, it names the module that holds the shared part. Codex reviews it (`dev/codex_review.sh`), or a Claude Opus reviewer with the same brief when Codex cannot run (out of credits or down).

## The brief

One fresh implementer per step, in its own worktree (the Agent tool's worktree isolation). After a shape commit, the build may go to two implementers at once when the shape splits it into parts that share no files: each builds its part on its own branch from the shape, with its own brief, and the second to finish merges the other's branch into the step's branch before the reviews. Step G's single builder took 51 minutes over 32 files (2026-11-04).

The brief is a "Brief" artifact on the step's issue, and the builder's prompt is one line naming the issue and the artifact's number. It points to the Design and the test list instead of repeating them, and holds these headings, each left out when it has nothing:
- **Goal:** what a player or the client sees when it is done, and the branch with its base.
- **Read:** the view command of each artifact to read (`gh issue artifact view N <number>`), and the test list comment.
- **Changed since the Design:** each later decision, with who made it and why.
- **Ask back if:** what comes back to the coordinator, or to Jim, instead of being chosen.
- **Change / Leave alone:** the modules it may change, and what is left out with who owns it.
- **Reuse:** the existing functions, test support and packages a gatherer found for each planned function, by name and file. Reuse what a module shares by importing it or moving it to a shared module; copying a module's glue and tests is what to avoid.
- **Failure table,** for a step with a shape commit, or with locks, timers or remote steps: each step of the flow, and what happens if it is killed there, run twice at once, or times out. Each row becomes a test, and the shape review reads the table with the shape.
- **Tests:** the test list, each decision tested at the lowest layer that makes it, and whole-server tests only for what the client sees.
- **Done when:** `dev/test_list_check.py N origin/main HEAD` exits 0 and `./check` passes.
- **Live check:** the scenario a live sitting runs.
- **Scratch:** its own scratch subfolder, `<step>-<role>`.

The brief is frozen once the builder starts: a change goes to the builder as a message, and a fix round's findings go on the issue as a comment the builder's prompt names.

The implementer's own file (`.claude/agents/implementer.md`) holds its checks, pushes and hand-back.

## Reviews

Every step's reviews start from `dev/test_list_check.py N BASE HEAD`, which lists each test named in the issue's "Test list" comment that the diff does not define. A missing test goes to the fix round without a reviewer.

A step with a shape commit gets two reviews, on the fixed commit the builder pushed, side by side:
- **Codex's bug review** (`dev/codex_review.sh code BASE HEAD "..."`), or a Claude Opus reviewer when Codex cannot run: correctness, evidence, failure paths, restarts, concurrency, and OTP fit when the diff touches processes. Bug reviewers are also asked whether any new test depends on timing, a session's length, read boundaries or a mailbox's length.
- **One Claude reviewer** for bugs, reuse and the issue check: code that repeats an existing function, the standard library or a package, each finding naming its replacement and whether its errors and edge cases match; and each done-when item met, with its evidence.

Any other step gets the Claude reviewer alone. The main session reads every diff against the skills the step used. (Fight's shape steps ran four reviews each; two cover the same ground, 2026-11-07.)

## The fix round

Check each finding against the code first, then fix what holds in one round. A bug the step caused is fixed before it merges, in this round or another. A review's top finding caused by the last round's fix counts as a second failure with one cause (below). Anything else follows "Failures" below. Notes that change nothing the step promises go in the closing summary.

## Failures, gaps and questions

**Done** means the full check and CI pass with no rerun. A failure met during a step is fixed before the step merges: inside the step when the step caused it; otherwise in its own small pull request, merged first. A fix that touches one area and changes nothing the server does (a test, a typo, a stale line) needs no design or trace: one builder, one reviewer. An issue is filed only for a wrong result found outside any step's work, such as live play or a nightly bot run.

- **Logged as unhandled** is missing, not a bug: the coverage measure lists it, and its area's checklist line gets any new evidence; no issue. Build it in the step only when the step's goal fails without it.
- **Handled, but the result differs from the evidence, or it crashed:** a bug.
- **Handled, but no evidence says what is right:** look in the evidence first. Only when it cannot settle it is it a question for Jim, marked Waiting on Jim. A silent wrong result is a bug.
- **A report from live play** is sorted first. A wrong result from a system already built is a bug and the next step. A behaviour not built yet is a dated line on the issue of the system whose planned work builds it, and no new issue. A milestone does not end with a bug open. (Creature facing was filed as its own step, #432, though the creature's fight behaviour was already planned work, 2026-11-05.)
- **The scope cut:** when a milestone's goal steps are nearly merged and live reports keep coming, the coordinator proposes a cut to Jim as one question: the steps left, and where everything else moves. After the cut, a live report is fixed in the milestone only if it breaks the milestone's goal; anything else is a dated line on its system's issue. (Fight's small live fixes kept extending it, 2026-11-06.)
- **A gap** stated in code, a test or a summary names the open issue whose planned work closes it, and that issue holds a dated line for it. Closing an issue as not planned names the issue that takes its open items; a hook refuses it otherwise. (Volatility's gain and the killing-blast gap sat only on closed issues, 2026-11-06.)

Before any fix, inside a step or not, search the closed issues and the step's own fixes for the same cause or module. Two failures with one cause, or three in one module in a milestone, stop the patching: the next step finds the root cause first and states whether a targeted fix, a stronger check or a redesign removes it, and why; the open fixes fold into it.

## The live sitting

A sitting runs when the client sees or sends something new (the `playing-live` skill): an agent drives what the client driver reaches, and Jim plays the rest. The steps of one goal share one sitting: each merges on green, and the sitting runs once the goal's last step merges. A failure in it is sorted as a report from live play (above); the goal stays open until the sitting passes. A replay that differs after a change meant to alter what the client receives is recorded again live (the `designing-processes` skill). A playable server is set up whenever Jim asks.

## Tracking

- Planned work lives in GitHub: one board, and a milestone with a parent issue whose sub-issues are its steps, with a measured end condition on the parent. A playable goal's done-when includes "a bot can do it".
- **Choosing the next step:** biggest impact first, by two rankings: the types the system's content reaches that the coverage measure (`gleam run -m genesis_prime/coverage`) shows unhandled (spell effects, prerequisites; whole-game weight breaks ties), and the unhandled messages the recorded sittings send most (`gleam run -m genesis_prime/unhandled_ranking -- ~/.genesis-prime/sittings/*`). A step handles a type for every row that uses it, never for one ability. (Fight's per-ability steps #403, #418 and #419 drifted from this, 2026-11-05.)
- **At a milestone's close** the coordinator posts on its parent the coverage measure, the ranking and each step's cost per type or message, against the milestone before; `dev/step_measure.py --milestone TITLE --types N` gives the cost per type. When the cost per type did not fall, the rule goes to Jim before the next milestone starts.
- Step order is set by blocked-by links (`dev/card.sh block N --by S`), not by the sub-issue list's order. Cleanups and dev tools sit after the milestone's goal steps, unless the parent's order, with Jim's yes, places one earlier.
- Before opening an issue, search the code and the issues under several names. A new issue states its proof the problem is real (a failing test, a measurement, a client fact or Jim's request), else it is a line on the parent. Its title states the outcome. File and move it with `dev/card.sh`: milestone, parent, blockers and status (To do, In progress, Waiting on Jim, Done).
- A step's issue carries its test list, progress lines, dated measurements and closing summary.
- A change to guidance (CLAUDE.md, a skill, an agent) needs no issue: its pull request names the milestone's parent issue.
- The coordinator's session compacts at 200k tokens (`CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000`, set at launch), since a builder is nearly always running and the session cannot be cleared mid-work. Builders post their hand-backs on the step's issue, so a compaction loses none. The session-start state block (`dev/session_state.sh`) shows what runs, so a hand-off is the parent's newest "Where it stands" comment and one line naming the milestone. That comment is posted after each merge from the draft `dev/where_it_stands.py PARENT` prints, with the coordinator's notes added.

## The closing summary

The merge line already holds the step's measures: its cost (`dev/step_measure.py N`), the coverage measure's handled counts and the ranking's top five. The summary is one comment of notes only:
- The cost per type or message handled, from those measures, and the fix rounds.
- Each throwaway tool or workaround, and each gap, with the open issue that owns it. For a bug fix: the choice that let the bug through and the check that now stops it.
- Its other notes, sorted: a missing tool or feature gets its own issue when it has its proof, else a line on the parent; a small repeat or a stale line goes on the milestone's standing cleanups issue's checklist, and a step that touches its file fixes it; anything else stays in the summary.
