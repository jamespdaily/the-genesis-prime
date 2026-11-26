---
name: running-a-step
description: How the coordinator carries a step from its design to merge - the phases, the brief, the reviews, the fix round, failures met during a step, tracking on GitHub, the live sitting and the closing summary. Use when planning a milestone, filing an issue, or starting, building, reviewing or closing a step.
---

# Running a step

The coordinator (the main session) owns a step from design to merge; investigators, builders and reviewers are fresh agents that follow their own agent files. The step's issue holds its state, so a new session resumes from the parent issue and the board.

## The phases

Test list (with a Design and its review when needed), shape (when processes change), one builder, hand-back check, one result review, fix round if needed, green, merge, closing summary.
- No builder starts until the approved list is posted as one issue comment headed "Test list"; `dev/test_list_check.py --existing BASE N` exits 2 when none is.
- Ask Jim every decision the step needs in one batch while the list is drafted, never after the build.
- Merge with `dev/merge_when_green.sh P`, one at a time; move the card with `dev/card.sh`; the merge line carries `dev/step_measure.py N`.

## Design and test list

- One fresh investigator per step maps the code it touches (file, line, signature, callers) and drafts the list from the map. Planning a milestone is a run of its own.
- One case per decision the step adds, at the lowest layer that makes it; a decision that fits a table test is a row there, marked "row".
- A whole-server test only for a new message, a new order across processes, or a client flow none walks yet.
- A Design, with one review before any code (`dev/codex_review.sh ask`, else a `reviewer`), only for a step that adds or changes a process or plans over about 150 lines.
- For a change the client sees, trace the client's code from the step's messages to the visible goal; each check on that path is a test.
- Weigh at least two options; reject one only on a measured cost or a client fact. Take the one that removes the cause for every case the evidence shows, not the one that ends the case at hand.
- Before approving, settle the review's open questions and trace in the code every input the changed process takes.
- Detail goes in "Design" and "Brief" artifacts on the issue (`gh issue artifact list N`); reviews and hand-backs are comments.
- Steps that share no function run at once; parts that share one are one build. At most two builders and two test runs at once.

## The shape

A step that changes processes, supervision or what one process asks another gets a shape commit before the build: types, signatures, supervision, each message's sequence, and what happens when a deadline passes or a process dies. Codex reviews it (`dev/codex_review.sh`), else a `reviewer`.

## The brief

- One fresh `implementer` per step, local, in its own worktree, never `isolation: remote`. Split a build longer than about 2 hours first.
- The brief is a "Brief" artifact; the prompt is one line naming the issue and artifact. It points to the Design and list, and names the simplest mechanism and each test's layer, never a line budget.
- Write it under the headings in [brief.md](brief.md); read that file when the brief starts.
- A scope change edits the "Test list" comment in place and the brief; once the builder starts, changes go as a message.

## Reviews

- Run `dev/test_list_check.py N BASE HEAD` first; a missing test goes to the fix round without a reviewer.
- Run `dev/affected_tests.py BASE HEAD --run` and compare it with the hand-back's "Affected tests"; a file that fails or is missing there goes to the fix round.
- A hand-back without each listed test's first failure lines, each touched file's last pass line, or a cause for a test fix goes back to the builder.
- One result review per build, by a `reviewer`, on the pushed commit. Codex runs design and shape reviews with the list and design text in its prompt; the coordinator posts its output.
- The coordinator reads every diff against the skills the step used.

## The fix round

- Check each finding against the code, then fix what holds in one round.
- A few-line fix the coordinator makes, tests and pushes; a larger round goes to a fresh implementer naming the findings comment, never the first builder.
- A bug the step caused is fixed before it merges, as is a listed test that cannot fail for its name's reason. Other no-behaviour findings go on the next step in the area.
- A top finding caused by the last fix counts as a second failure with one cause.

## Failures, gaps and questions

- Done is CI green with no rerun (`dev/pr_wait.sh P`, in the background).
- A failure met in a step is fixed before it merges: in the step if it caused it, else in its own pull request merged first.
- A red main stops merging. A failure in a test the pull request did not touch is main's: never rerun or merge around it; name its cause, fix it first, then every open pull request merges main.
- Unhandled is missing, not a bug; build it only when the step's goal fails without it. A wrong, crashed or silently wrong result is a bug. Where the evidence cannot settle it, ask Jim (Waiting on Jim).
- A live report on a built system is a bug and the next step; one on unbuilt work is a dated line on the issue that builds it. A milestone does not end with a bug open.
- When live reports keep extending a nearly done milestone, propose a scope cut to Jim as one question.
- A gap has a dated line on the open issue that closes it; closing an issue as not planned names where its open items go.
- A bug fix covers every type, row or path the same rule applies to.
- A suspected bug found by reading goes to a builder for its failing test at once.
- Before a fix, a question to Jim or a new issue, search the closed issues for the same cause or topic.
- Two failures with one cause, or three in one module in a milestone, stop the patching: the next step finds the root cause and says whether a fix, a check or a redesign removes it.

## The live sitting

When the client sees or sends something new, a goal's steps share one sitting after the last merges (the `playing-live` skill), on a Veteran character except for the tutorial; the goal stays open until it passes.

## Tracking

- A milestone has a parent issue with a measured end condition; its sub-issues are the steps, ordered by blocked-by links (`dev/card.sh block`).
- Next step: biggest impact first, by `gleam run -m genesis_prime/coverage` and `genesis_prime/unhandled_ranking`; a step handles a type for every row that uses it. The tutorial goal is last.
- A new issue states its proof (a failing test, a measurement, a client fact or Jim's ask), else it is a line on the parent.
- After each merge, post "Where it stands" from `dev/where_it_stands.py PARENT`, and run it with `--body`.
- At a milestone's close, post the coverage measure and the cost per type (`dev/step_measure.py --milestone`); a cost that did not fall goes to Jim.
- When a rule is broken twice in a row, or a rule or check catches nothing in ten steps, the coordinator tells Jim, with the counts, and proposes a check or a removal instead of more text.

## The closing summary

One comment of three lines: time and cost against comparable steps, and fix rounds; what the reviews caught, and any bug after the merge; each workaround or gap with the issue that owns it, and for a bug fix the check that now stops it.
