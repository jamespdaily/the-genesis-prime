# the-genesis-prime
A server for WildStar that the original client connects to and plays on. Gleam on the BEAM (Erlang/OTP); Postgres for saved data.

## Terms
- **Step:** one sub-issue, one branch, one pull request, with a fixed test list. A step changes one client flow or one process design; a larger one is split before its test list is posted.
- **Test list:** a step's planned tests on its issue, behaviours and failure paths, each naming its evidence.
- **Evidence:** the client's code and tables, then recordings; a retail record only where the client lacks the data.
- **Rule:** a pure function: state and input in, new state and effects (actions to carry out) out. Every game and connection decision is a rule.
- **Shell:** the process that carries out its rule's effects in order and turns all it sees into that rule's inputs; it decides nothing.
- **Full check:** `./check`: the setup check, format, warnings as errors, glinter, generated code matching the schema, migrations, squirrel, the tests and the fact checker; CI runs the same.
- **Coverage measure:** what the client's tables require, against what the server handles.

## Authority
- The client and its data files are the only authority on what the server must do; every protocol or game-rule fact in code points to its evidence.
- The client's tables set the scope; each run of the coverage measure is posted on its issue.
- Never copy another WildStar server's code, text or structure; none of it is evidence. Jim's earlier server, the-eldan-experiment, may be read to find questions, client addresses and sources, and to compare designs. A fact it points to is accepted only once the client's own code or data confirms it. A design it shows is chosen only on this project's own evidence. NexusForever is never read.
- Retail records (Jabbithole, Dulfy, wikis) and Jim's world database (wildstar-knowledge world-data) count only for data the client lacks, such as spawns, vendor stock and loot, and each such value is marked with its source. The world database is data to read, never code or structure to copy.
- Read a problem's rows and evidence before calling it a bug, a decision or a fix; a search that found nothing settles nothing.

## Every change
- Handle errors you can act on; let anything else crash the process, and its supervisor rebuilds it from storage.
- Decode client bytes at the connection into typed values. Bytes the client's own reader would refuse end the connection; a whole frame the server does not know yet is logged as unhandled, and the connection goes on.
- Refuse any value the client sends that its own code or tables would not allow.
- Game tables load once at start into named records; a missing row fails the load.
- Every packet layout lives in one schema with its evidence. The generated codec states each field's size and byte order and is never edited by hand; the bit stream's field kinds and the generator are property-tested, and each message with a client vector is checked against it.
- A bug fix starts with a test that fails because of the bug.
- The full check passes before every push, and files are staged by name.
- No shortcut makes a check pass: no stub or hard-coded value in place of the client's behaviour, no test skipped or loosened without its reason in the test, no swallowed error. A gap is stated where it is enforced and reported as missing or a question.
- Every requirement and fact lives in the code, test, config or check that enforces it. No design documents or decision records: the issue keeps the reasoning, and a choice becomes one line in its place. Tools that gate a merge (the check script, the setup check, the table extractor) have tests that CI runs; other tools and guidance are checked by real use.
- A step's working detail goes in Markdown artifacts on its issue, named "Client trace", "Design" or "Review", each edited in place and never deleted. A step moves from `investigation` to `ready` once its trace and design are written and its test list is posted. Once the step merges, its artifacts are history, and nothing enforced lives only there.
- A lesson becomes a test, a shared function or a permission first; a written rule only for a recurring judgement. A new rule replaces an old one or shows what it saved. A change to this file, a skill or an agent lands in its own pull request once Jim approves it; an approved change that waits for a step is written on that step's card.

## A step
The coordinator approves a step's outcome once: its design and test list, posted on its issue. It then runs to merge (the `running-a-step` skill holds how). Agents go on without Jim to add tests, remove duplication, swap in a library call, or fix a failure within the approved behaviour. Jim decides when expected game behaviour changes, an acceptance condition weakens, the evidence cannot settle a question, or authority widens.

1. **Design and test list.** Read the client's evidence, these rules, then the code the step touches. For a change the client sees, trace the client's code from the step's messages to the visible goal: each check on that path becomes a test, and a field with no known meaning needs the client's code to show its value is safe. Weigh at least two options, asking first what most projects use; measure when costs differ, else take the simplest.
2. **Build.** One fresh implementer, from a brief (the `running-a-step` skill).
3. **Check.** The reviews, the fix round and the live session (the `running-a-step` skill); the full check passes.
4. **Merge** on green, then the closing summary (the `running-a-step` skill).

A step that changes processes or supervision adds a shape commit between 1 and 2, reviewed by Codex: the types, signatures and supervision, and a sequence of each message and what happens when a deadline passes or a process dies. When two rules or shells share a flow, the shape names the module that holds the shared part. A design-only step is part 1 alone; a step that only deletes or moves code skips Codex. At most two agents run tests on one machine at once.

Ask Jim only for decisions you cannot make, in one batch of plain yes-or-no questions, each with a recommendation.

## Missing, a bug, or a question
1. **Logged as unhandled?** Missing: the coverage measure lists it, and its area's checklist line gets any new evidence; no issue. Build it in the step only when the step's goal fails without it.
2. **Handled, but the result differs from the evidence, or it crashed?** A bug. Fix it in the step when the step caused it or changes its code; otherwise it is the next step in the milestone's order, run beside the current one when they share no files. A bug the step caused is fixed in its fix round; one found after it becomes the next step. A milestone does not end with a bug open.
3. **Handled, but no evidence says what is right?** Look in the evidence first. Only when it cannot settle it is it a question for Jim, marked Waiting on Jim. A silent wrong result is always a bug.

## Tracking
- All planned work lives in GitHub: one board, a milestone with a parent issue whose sub-issues are its steps in order, and a measured end condition on the parent.
- Before opening an issue, search the code and the issues under several names. File and move it with `dev/card.sh`: milestone, parent, order and status (To do, In progress, Waiting on Jim, Done).
- A step's issue carries its test list, progress, dated measurements and closing summary; a new session resumes from the parent issue and the board.
- A branch is `jimd/<issue>-<topic>`; each commit names its issue and says why; an issue title states the outcome.
- A playable server is set up whenever Jim asks (the `playing-live` skill).
