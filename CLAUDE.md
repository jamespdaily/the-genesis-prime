# the-genesis-prime
A server for WildStar that the original client connects to and plays on. Gleam on the BEAM (Erlang/OTP); Postgres for saved data.

## Terms
- **Step:** one sub-issue, one branch, one pull request, with a fixed test list. A step changes one client flow or one process design; a larger one is split before its test list is posted.
- **Test list:** a step's planned tests on its issue, behaviours and failure paths, each naming its evidence.
- **Evidence:** the client's code and tables, then recordings; a retail record only where the client lacks the data.
- **Rule:** a pure function: state and input in, new state and effects (actions to carry out) out. Every game and connection decision is a rule.
- **Shell:** the process that carries out its rule's effects in order and turns all it sees into that rule's inputs; it decides nothing.
- **Engine:** the one module that owns a kind of game data: it decodes, decides and applies it.
- **Full check:** `./check`: the setup check, format, warnings as errors, glinter, generated code matching the schema, migrations, squirrel, the tests and the fact checker; CI runs the same.
- **Coverage measure:** what the client's tables require, counted against what the server handles.

## Authority
- The client and its data files are the only authority on what the server must do. Every protocol or game-rule fact in code points to its evidence.
- The client's tables set the scope; each run of the coverage measure is posted on its issue.
- Never read or copy another WildStar server's code, text or structure; it is never evidence.
- Retail records (Jabbithole, Dulfy, wikis) count only for data the client lacks, such as spawns, vendor stock and loot, and each such value is marked.
- Read a problem's rows and evidence before calling it a bug, a decision or a fix; a search that found nothing settles nothing.

## Every change
- Handle errors you can act on; let anything else crash the process, and its supervisor rebuilds it from storage.
- Decode client bytes at the connection into typed values. Bytes the client's own reader would refuse end the connection; a whole frame the server does not know yet is logged as unhandled, and the connection goes on.
- Game tables load once at start into named records; a missing row fails the load.
- Every packet layout lives in one schema with its evidence. The generated codec states each field's size and byte order, is never edited by hand, and round-trips in a property test.
- A bug fix starts with a test that fails because of the bug.
- No shortcut makes a check pass: no stub or hard-coded value in place of the client's behaviour, no test skipped or loosened without its reason in the test, no swallowed error. A gap is stated where it is enforced and reported as missing or a question.
- Every requirement and fact lives in the code, test, config or check that enforces it. No design documents or decision records: the issue keeps the reasoning, and a choice becomes one line in its place.
- A new rule replaces an old one or shows what it saved. A change to this file, a skill or an agent lands in its own pull request once Jim approves it; the guidance issue lists only approved changes not yet merged.

## A step
Four parts. Jim's go on the design and test list is the step's one stop; it then runs to merge, stopping early only for a question the evidence cannot settle or a change to the test list. State the estimate in rounds first; past twice it, ask Jim to cut or continue.

1. **Design and test list.** Read the client's evidence, these rules, then the code the step touches. For a change the client sees, trace the client's code from the step's messages to the visible goal: each check on that path becomes a test, and a field with no known meaning needs the client's code to show its value is safe. Weigh at least two options, asking first what most projects use; measure when costs differ, else take the simplest. Codex names the failure paths the list is missing; they become tests.
2. **Build.** One fresh implementer writes the tests, then the code, and hands back once. The main session checks each expected value against its evidence; changing one is a change to the test list.
3. **Check.** `./check fast` first, then side by side: the main session's diff review, one Codex review (`dev/codex_review.sh`) and the full check, which passes in under 2 minutes. A live login with the real client, played by an agent, runs when the client sees or sends something new. Check each finding against the code first. One fix round, then one Codex re-check of the fix commits; after that only a P1 (a break of what the step promises) is fixed, and the rest goes in the closing summary.
4. **Merge** on green. The pull request body describes the change as it stands, rewritten, never appended to; then the closing summary.

A step that changes processes or supervision adds a shape commit between 1 and 2, reviewed by Codex: the types, signatures and supervision, and a sequence of each message and what happens when a deadline passes or a process dies. A design-only step is part 1 alone; a step that only deletes or moves code skips Codex. At most two agents run tests on one machine at once.

Ask Jim only for decisions you cannot make, in one batch, each with a recommendation.

## Missing, a bug, or a question
1. **Logged as unhandled?** Missing: the coverage measure lists it, and its area's checklist line gets any new evidence; no issue. Build it in the step only when the step's goal fails without it.
2. **Handled, but the result differs from the evidence, or it crashed?** A bug. Fix it in the step when the step caused it or changes its code; otherwise it is the next step in the milestone's order, run beside the current one when they share no files. A milestone does not end with a bug open.
3. **Handled, but no evidence says what is right?** Look in the evidence first. Only when it cannot settle it is it a question for Jim, marked Waiting on Jim. A silent wrong result is always a bug.

Before a bug fix, search the closed bugs for the same cause or module. Two bugs with one cause, or three in one module in a milestone, stop the patching: the next step redesigns that part and the open fixes fold into it. A review's top finding caused by the last round's fix counts as a second bug with one cause.

A closing summary names each throwaway tool or workaround and the issue that owns it; a bug's also names the choice that let it through and the check that now stops it.

## Tracking
- All planned work lives in GitHub: one board, a milestone with a parent issue whose sub-issues are its steps in order, and a measured end condition on the parent.
- Before opening an issue, search the code and the issues under several names. File and move it with `dev/card.sh`: milestone, parent, order and status (To do, In progress, Waiting on Jim, Done).
- A step's issue carries its test list, progress, dated measurements and closing summary; a new session resumes from the parent issue and the board.
- A branch is `jimd/<issue>-<topic>`; each commit names its issue and says why; an issue title states the outcome.
- A playable server is set up whenever Jim asks; the `playing-live` skill says how.
