---
name: running-a-step
description: How the coordinator carries a step from its design to merge - the phases, the brief, the reviews, the fix round, failures met during a step, tracking on GitHub, the live sitting and the closing summary. Use when planning a milestone, filing an issue, or starting, building, reviewing or closing a step.
---

# Running a step

The coordinator (the main session) owns a step from design to merge. Builders and reviewers are fresh agents with bounded briefs. The step's issue holds its state: a new session resumes from the parent issue, the board and the progress lines.

## The phases

A step runs in this order: design and test list, design review, the shape when the step changes processes, one builder, one result review, a fix round when the review finds something, green, merge, a 3-line closing summary. The pull request body is the outcome, the issue, and one line per behaviour. A hook posts the push, pull request, CI and merge lines and moves the card (`dev/hooks/progress_lines.py`). The coordinator posts the approved list as one comment headed "Test list"; a hook refuses a push to the step's branch before it. Once a goal's last step merges, the goal gets its one live sitting (below).

From design to merge the step runs without Jim, except for the four decisions CLAUDE.md gives him. Agents go on alone to add tests, remove duplication, swap in a library call, or fix a failure within the approved behaviour. A design-only step is the first two phases alone.

## Design and test list

A gatherer (a read-only Sonnet `general-purpose` agent) maps the code the step touches first (each function, type and test support with its file, line, signature and callers); one fresh investigator per step then drafts the Design and the test list from that map, the list sized to the change (about one case per ten planned lines of code, plus one whole-server test for what the client sees), and planning a milestone's steps is a run of its own. One design review reads the draft before any code: Codex (`dev/codex_review.sh ask`), or a `reviewer` on Opus with the same brief when Codex cannot run. The coordinator reads the draft against that review, settles the open questions and approves the test list, and the brief it writes is what the builder follows. (One investigator planned 11 steps and a design in one 200-call run; the design drifted from the code in 20 places and its review found 7 must-fix gaps, 2026-11-17.) Read the client's evidence, CLAUDE.md, then the code the step touches. For a change the client sees, trace the client's code from the step's messages to the visible goal: each check on that path becomes a test, and a field with no known meaning needs the client's code to show its value is safe. For a flow Eldan did live, start from what the player saw there and the messages Eldan sent for it; build only the difference, and prefer the client's default commands over values the server works out. A keyword search that finds nothing settles nothing. Write what Eldan sent and why it worked in the Design's "Eldan" paragraph, compared with the options; its facts count only once the client confirms them. (The ground plan searched Eldan for "terrain", found nothing and planned six steps; Eldan's creatures stayed grounded by one 0x638 bit the client reads, 2026-11-18.) Weigh at least two options, asking first what most projects use. An option is rejected only on a measured cost or a client fact, and the Design says which; else take the simplest.

Less work means not building what the client already does; it never means a smaller design that the client shows differently. (The buffs-in-sight design weighed lines over accuracy, 2026-11-18.) A step that only guards against a rare failure (a retry, a reserve, a fallback) first counts how often it happened (`podman logs genesis-play`, `~/.genesis-prime/sittings`) and states "seen N times in M sittings" in its proof; at 0 it goes to Jim before a build. (The final-save retry went through three failed designs, with 0 failed saves in 288 sittings, 2026-11-18.) A design that picks the simpler option because the load is small says so, and adds it, with the measurement that would reopen it, to a list headed "Revisit before opening" in the body of the Run it for others milestone's parent issue. Before approving a design, trace each input the changed process takes in the code, not only those the draft names. (The recordings design needed three Codex rounds because answers carry a time, 2026-11.)

A step's working detail goes in Markdown artifacts on its issue, named "Design" or "Brief", each edited in place and kept; `gh issue artifact list N` shows them, so look there before the issue timeline or the web (a session searched the timeline and claude.ai for a trace that sat in an artifact, 2026-11-02); reviews and hand-backs are comments. Once the step merges they are history, and nothing enforced lives only there.

A step is labelled `ready` when an agent can finish it without inventing requirements: its issue states the outcome, the acceptance checks, the evidence, the scope and what is left out, and the steps it depends on; its design artifact is written and its test list is posted. Until then it is labelled `investigation`.

Steps that change no function in common run at once, each with its own builder, even when they share a file; the second to merge merges main first. (Steps sharing cast and spell_plan waited one after another, 2026-11-15.) At most two test runs share the machine: a hook refuses a third `./check` or `gleam test`; recordings and load runs are counted by hand.

## The shape

A step that changes processes, supervision, or what one process asks or sends another (one new request counts) gets a shape commit and its review before the build. A step that only deletes or moves code skips it.

The shape commit holds the types, signatures and supervision, and a sequence of each message and what happens when a deadline passes or a process dies. When two rules or shells share a flow, it names the module that holds the shared part. Codex reviews it (`dev/codex_review.sh`), or a `reviewer` on Opus with the same brief when Codex cannot run.

## The brief

One fresh implementer per step, in its own worktree (the Agent tool's worktree isolation), run locally, never with `isolation: remote`; a hook refuses it. A build fits in about 2 hours; a step whose build would run longer is split before its brief. (Spell depth's 5-7 hour builds were 40-80% of their steps' tokens, measured 2026-11-16.) A brief names the simplest mechanism and the layer each test runs at, never a line budget or test-to-code ratio for the builder; the test list's sizing above is the investigator's. (A budget made a builder break things to meet it; the process hooks came back at 740 lines for simple rules, 2026-11-06.)

The brief is a "Brief" artifact on the step's issue, and the builder's prompt is one line naming the issue and the artifact's number. It points to the Design and the test list instead of repeating them, and holds these headings, each left out when it has nothing:
- **Goal:** what a player or the client sees when it is done, and the branch with its base.
- **Read:** the view command of each artifact to read (`gh issue artifact view N <number>`), the test list comment, and the `designing-processes` skill for a step with a shape commit (builders do not preload it).
- **Changed since the Design:** each later decision, with who made it and why.
- **Ask back if:** what comes back to the coordinator, or to Jim, instead of being chosen.
- **Change / Leave alone:** the modules it may change, and what is left out with who owns it.
- **Reuse:** a gatherer's map, made before the brief: each existing function, type and test support the build touches or reuses, with its file and line on the base commit, its signature and its call sites. Builders start from the map and search only for what it does not name. (The boot check's builders, briefed with a map, took 75 and 31 turns, against 216 for the procs fix round, 2026-11-17.)
- **Failure table,** for a step with a shape commit, or with locks, timers or remote steps: each step of the flow, and what happens if it is killed there, run twice at once, or times out. Each row is answered in the design. A row gets its own test when it is a new mechanism (a timer, a process death, an ordering) or a bug was found there; a row that repeats a tested mechanism names the test that covers it. The shape review reads the table with the shape.
- **Tests:** the test list, each decision tested at the lowest layer that makes it, and whole-server tests only for what the client sees.
- **Done when:** `dev/test_list_check.py N origin/main HEAD` exits 0 and the last commit is pushed; the coordinator watches CI.
- **Live check:** the scenario a live sitting runs.
- **Scratch:** its own scratch subfolder, `<step>-<role>`.

A decision that changes scope edits the approved "Test list" comment in place (`gh api` PATCH) and the brief, since a builder follows the list over a decision written beside it (three builders did, 2026-11-18). The brief is frozen once the builder starts: a change goes to the builder as a message, and a fix round's findings go on the issue as a comment the builder's prompt names.

The implementer's own file (`.claude/agents/implementer.md`) holds its checks, pushes and hand-back.

Reviewers and investigators use their own agent files (`reviewer`, `investigator`), which run on Sonnet; a reviewer standing in for Codex runs on Opus. (General-purpose reviewers ran on Opus by default and were 20-35% of a step's tokens, 2026-11-16.) A design or hand-back that cites a recording names where it was captured; one made against another server is not evidence.

## Reviews

Every step's reviews start from `dev/test_list_check.py N BASE HEAD`, which lists each test named in the issue's "Test list" comment that the diff does not define. A missing test goes to the fix round without a reviewer.

Then one result review, on the fixed commit the builder pushed: Codex's bug review (`dev/codex_review.sh code BASE HEAD "..."`), or a `reviewer` on Opus with the same brief when Codex cannot run. It reads correctness, evidence, failure paths, restarts, concurrency, OTP fit when the diff touches processes, any new test that depends on timing, a session's length, read boundaries or a mailbox's length, reuse (the `reviewer` agent's rules), and each done-when item met, with its evidence. The main session reads every diff against the skills the step used. (The first lean step, one review before the code and one after, took about 1 h 40 min from map to merge, against 2 h 40 and 2 h 25 for comparable steps with more reviews, 2026-11-17.)

## The fix round

Check each finding against the code first, then fix what holds in one round. Each fix round goes to a fresh implementer whose prompt names the findings comment; the first builder is not resumed, since its long context is re-read on every turn. A bug the step caused is fixed before it merges, in this round or another. A review's top finding caused by the last round's fix counts as a second failure with one cause (below). Anything else follows "Failures" below. Notes that change nothing the step promises go in the closing summary.

## Failures, gaps and questions

**Done** means CI passes with no rerun, and the coordinator's own `./check` too where CLAUDE.md asks for it; the coordinator waits on CI with `dev/pr_wait.sh P` in the background, which the hook's CI line follows. Before a local `./check`, confirm its folder holds the pull request's head (`git log -1`), since an agent may have moved it. A failure met during a step is fixed before the step merges: inside the step when the step caused it; otherwise in its own small pull request, merged first. A fix that touches one area and changes nothing the server does (a test, a typo, a stale line) needs no design or trace: one builder, one reviewer. An issue is filed only for a wrong result found outside any step's work, such as live play.

- **Logged as unhandled** is missing, not a bug: the coverage measure lists it, and its area's checklist line gets any new evidence; no issue. Build it in the step only when the step's goal fails without it.
- **Handled, but the result differs from the evidence, or it crashed:** a bug.
- **Handled, but no evidence says what is right:** look in the evidence first. Only when it cannot settle it is it a question for Jim, marked Waiting on Jim. A silent wrong result is a bug.
- **A report from live play** is sorted first. A wrong result from a system already built is a bug and the next step. A behaviour not built yet is a dated line on the issue of the system whose planned work builds it, and no new issue. A milestone does not end with a bug open. (Creature facing was filed as its own step, #432, though the creature's fight behaviour was already planned work, 2026-11-05.)
- **The scope cut:** when a milestone's goal steps are nearly merged and live reports keep coming, the coordinator proposes a cut to Jim as one question: the steps left, and where everything else moves. After the cut, a live report is fixed in the milestone only if it breaks the milestone's goal; anything else is a dated line on its system's issue. (Fight's small live fixes kept extending it, 2026-11-06.)
- **A gap** stated in code, a test or a summary names the open issue whose planned work closes it, and that issue holds a dated line for it. Closing an issue as not planned names the issue that takes its open items; a hook refuses it otherwise. (Volatility's gain and the killing-blast gap sat only on closed issues, 2026-11-06.)

- **A bug fix covers every type, row or path the same rule applies to**, found from the client's code and tables and fixed by one rule; "no live report" is no reason to leave one out. (A fix for objective type 12 left types 32 and 5 out; Jim finished a type 32 quest by clicking one crate five times, 2026-11-17.)
- **A suspected bug found by reading** goes to a builder for its failing test at once, never a "to confirm" line: if it fails it is a bug step, if it passes the test is the answer. (A creature re-aggroing a dead player's body sat as a "to confirm" line until Jim hit it live, 2026-11-06.)

Before asking Jim a question or calling a gap open, search the closed issues for the topic; a "waits on Jim" line in a goal issue's comment can be stale. (A question already answered and built was re-asked, 2026-11-16.)

Before any fix, inside a step or not, search the closed issues and the step's own fixes for the same cause or module. Two failures with one cause, or three in one module in a milestone, stop the patching: the next step finds the root cause first and states whether a targeted fix, a stronger check or a redesign removes it, and why; the open fixes fold into it.

## The live sitting

A sitting runs when the client sees or sends something new (the `playing-live` skill): an agent drives what the client driver reaches, and Jim plays the rest. The steps of one goal share one sitting: each merges on green, and the sitting runs once the goal's last step merges. A failure in it is sorted as a report from live play (above); the goal stays open until the sitting passes. A replay that differs after a change meant to alter what the client receives is recorded again live (the `designing-processes` skill). Live checks use a Veteran character (`client.sh veteran`), not a Novice, except for the tutorial goal. A playable server is set up whenever Jim asks.

## Tracking

- Planned work lives in GitHub: one board, and a milestone with a parent issue whose sub-issues are its steps, with a measured end condition on the parent. A playable goal's done-when includes "a bot can do it".
- **Choosing the next step:** biggest impact first, by two rankings: the types the system's content reaches that the coverage measure (`gleam run -m genesis_prime/coverage`) shows unhandled (spell effects, prerequisites; whole-game weight breaks ties), and the unhandled messages the recorded sittings send most (`gleam run -m genesis_prime/unhandled_ranking -- ~/.genesis-prime/sittings/*`). A step handles a type for every row that uses it, never for one ability. (Fight's per-ability steps #403, #418 and #419 drifted from this, 2026-11-05.) Within a system, a shared mechanism that most planned steps' rows wait on goes first (measure each step's player reach), then whole-system steps a player sees; correctness sweeps run alongside, and a report leads with what a player now sees. The tutorial goal is last. (Two steps in a row built effects no player could reach, 2026-11-17; Jim called a night of tracing-sweep merges background, 2026-11-18.)
- **At a milestone's close** the coordinator posts on its parent the coverage measure, the ranking and each step's cost per type or message, against the milestone before; `dev/step_measure.py --milestone TITLE --types N` gives the cost per type. When the cost per type did not fall, the rule goes to Jim before the next milestone starts.
- Step order is set by blocked-by links (`dev/card.sh block N --by S`), not by the sub-issue list's order. Cleanups and dev tools sit after the milestone's goal steps, unless the parent's order, with Jim's yes, places one earlier.
- Before opening an issue, search the code and the issues under several names. A new issue states its proof the problem is real (a failing test, a measurement, a client fact or Jim's request), else it is a line on the parent. Its title states the outcome. File and move it with `dev/card.sh`: milestone, parent, blockers and status (To do, In progress, Waiting on Jim, Done).
- An issue's text is written for agents first (precise, structured, complete); a page meant for Jim goes in chat, not on the issue. (Jim, 2026-11-02, when offered a reworded issue line.)
- Housekeeping (stale agent worktrees, merged branches) and no-behaviour tidy-ups (doc comments, names, log wording) go to a cheaper model as a dry-run list or a patch the coordinator checks and applies.
- A step's issue carries its test list, progress lines, dated measurements and closing summary.
- Builders post their hand-backs on the step's issue, so a compaction loses none. The session-start state block (`dev/session_state.sh`) shows what runs, so a hand-off is the parent's newest "Where it stands" comment and one line naming the milestone. That comment holds only what changed (merged since the last line, open pull requests, pushed without a pull request, in progress, waiting on Jim, notes) and is posted after each merge from the draft `dev/where_it_stands.py PARENT` prints, with the coordinator's notes added. The next-in-order list sits in the parent's body between `<!-- next-in-order -->` markers, edited in place by `dev/where_it_stands.py PARENT --body` after each merge.

## The closing summary

The merge line already holds the step's cost (`dev/step_measure.py N`). The summary is one comment of three lines:
- The time and cost against comparable steps, and the fix rounds.
- What the reviews caught, and any bug found after the merge.
- Each throwaway tool, workaround or gap, with the open issue that owns it; for a bug fix, the choice that let the bug through and the check that now stops it. Any other note: a missing tool or feature gets its own issue when it has its proof, else a line on the parent; a small repeat or a stale line goes on the milestone's standing cleanups issue's checklist.
