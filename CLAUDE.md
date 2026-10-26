# the-genesis-prime
A server for WildStar that the original client connects to and plays on. Gleam on the BEAM (Erlang/OTP); Postgres for saved data.

## Terms
- **Step:** one sub-issue, one branch, one pull request, with a fixed test list.
- **Test list:** a step's planned tests on its issue, behaviours and failure paths, each test naming its evidence.
- **Evidence:** the client's code and tables, then recordings; a retail record only where the client lacks the data.
- **Rule:** a pure function: state and input in, new state and effects out. Game logic is rules.
- **Effect:** an action a rule returns, carried out in order by the process that owns the state.
- **Engine:** the one module that owns a kind of game data: it decodes a type, decides what it does and applies it.
- **Full check:** the setup check, then format, warnings as errors, glinter, generated code matching the schema, migrations, squirrel, the tests and the fact checker; `./check` runs it, and CI runs the same.
- **Coverage measure:** the count of what the client's tables require, against what the server handles.

## Authority
- The client and its data files are the only authority on what the server must do. Every protocol or game-rule fact in code points to its evidence.
- The client's tables set the scope. The coverage measure counts what they require, and each run is posted on its issue.
- Never read or copy another WildStar server's code, text or structure; it is never evidence.
- Evidence ranks: the client's code and tables, then recordings. Retail records (Jabbithole, Dulfy, wikis) count only for data the client lacks, such as spawns, vendor stock and loot, and each such value is marked.
- Read a problem's rows and evidence before calling it a bug, a decision or a fix. A search that found nothing settles nothing.

## Every change
- Handle errors you expect and can act on. Let anything else crash the process; its supervisor rebuilds it from storage.
- Decode client bytes at the connection into typed values; reject bad input there. A decode failure ends the connection.
- A game master command checks the account's permission in its rule before it acts, and each use is logged. A new account has no permissions.
- A feature calls the engine for its kind; it never re-implements a check or an effect.
- Scripted content is data, or a pure script module looked up by id. No creature, quest or spell id is written into a rule.
- Game tables load once at start into named records; a missing row fails the load.
- Every packet layout lives in one schema with its evidence. The codec is generated, states the size and byte order of every field, and is never edited by hand. Every layout round-trips in a property test.
- Plain SQL in `.sql` files, typed by squirrel. A row held whole is decoded into its own record where it is read.
- A bug fix starts with a test that fails because of the bug.
- A package under a licence that would bind this project, such as AGPL, needs Jim's yes; code from such a project is never copied. The project's own licence is chosen in Milestone 0.
- Rust only with four numbers on the issue: a deadline a player can feel, cheaper fixes tried, Rust closes the gap, a test compares the two.
- Every requirement and fact lives in the code, test, config or check that enforces it, and nowhere else. No design documents and no decision records: the issue keeps the reasoning, and a new choice becomes one line in its place.

## A step
Jim approves the test list; that is the step's one approval, with no separate stops for push or merge. The step then runs to merge, and stops early only for a question the evidence cannot settle or a change to the test list.

1. **Test list on the issue.** Jim says go on that list.
2. **Shape first.** The first commit holds the new types, signatures and supervision changes; the main session reviews them before any bodies.
3. **Tests first.** A fresh implementer writes the tests from the list; the main session checks each expected value against its evidence; they go in as their own commit. Changing a committed expected value is a change to the list.
4. **Build.** The implementer writes the code, running only the named tests. Anything found outside the list is sorted as below.
5. **Review, check and play.** The main session reviews the diff while the full check runs, once, at the end; it passes in under 2 minutes, independent parts side by side. A live login with the real client, played by an agent, runs when the step changes what the client sees or sends.
6. **Merge on green.** The pull request body describes the whole change as it stands; it is rewritten, never appended to. Jim reads the closing summary after.

Ask only for decisions you cannot make, in one batch, each with a recommendation. Changes to CLAUDE.md, the skills and the agents are collected on one issue and merged at a milestone's end, unless one blocks current work. The share of tests that name their evidence is measured; a separate test-writing agent is added only if it stays low.

## Missing, a bug, or a question
1. **Logged as unhandled?** Missing. Its area owns it and the coverage measure lists it. Open no issue; add new evidence to the area's checklist line. Build it in the step only when the step's goal fails without it.
2. **Handled, but the result differs from the evidence, or it crashed?** A bug. Fix it in the step when the step caused it or it sits in code the step changes; otherwise open a bug issue in the current milestone, with the evidence.
3. **Handled, but no evidence says what is right?** Look first: the client's code, the tables, the recordings, retail records for data the client lacks. Only when the evidence cannot settle it is it a question for Jim, marked Waiting on Jim. A silent wrong result is always a bug.

## Tracking
- All planned work lives in GitHub: one project board, a milestone with one parent issue per phase, areas as sub-issues, each a checklist until its work starts. Each milestone ends on a measured condition written on its parent issue.
- Every new issue gets its milestone and its place on the board; its status moves through To do, In progress, Waiting on Jim and Done.
- A step's issue carries its test list, progress and results; measurements are dated comments; the closing summary is its last comment. A new session resumes from the issue alone.
- Before opening an issue, search the code and the issues under several names.
- A branch is `jimd/<issue>-<topic>`, each commit names its issue and says why, and an issue title states the outcome.
- A playable server is set up whenever Jim asks, at any point.
