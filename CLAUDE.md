# The Genesis Prime

A WildStar server in Gleam on the BEAM, built from the client (WildStar64.exe, build 16042). Gleam package `genesis_prime`. Each kind of work has a skill in `.claude/skills/`; load it before starting.

## Evidence and scope

- The client's tables set what the server must do. The coverage measure counts it; post each run on its issue.
- Evidence ranks: the client's code and tables, then recordings, then retail records. Another server's code is never evidence. Retail records are saved in `~/Projects/reference/` (`jabbithole/`, `dulfy/`, `catalog/`, `wikis/`): cite them, never commit or publish them.
- Read a problem's rows and evidence before calling it a bug, a decision or a fix. A search that found nothing settles nothing.
- A package under a licence that would bind this project, such as AGPL, needs Jim's yes. Code from such a project is never copied.

## Design

- An engine decodes its type, decides what it does and applies it. A feature calls the engine; it never re-implements a check or an effect.
- Scripted content is data, or a pure script module looked up by id. No creature, quest or spell id is written into a rule.
- A game master command checks the account's permission in its rule before it acts, and each use is logged. A new account has no permissions.
- Game tables load once at start into named records; a missing row fails the load.
- Every packet layout lives in one schema, with its evidence. The codec is generated, never edited by hand, and every layout round-trips in a property test.
- Postgres with plain SQL in `.sql` files, typed by squirrel. A row held whole is decoded into its own record where it is read.
- Rust only with four numbers on the issue: a deadline a player can feel, the cheaper fixes tried, Rust closing the gap, and a test comparing the two.

## Checks

- Erlang is not on the Bash tool's path: start each command with `export PATH="$HOME/.local/otp/29.1.2-gc210/bin:$PATH"`. The setup check runs first and names each missing part and its fix.
- `./check` passes before a step is done: formatting, warnings as errors, glinter, generated code matching the schema, the tests, squirrel, rustfmt and Clippy. It stays under 2 minutes. A suppression needs a written reason.
- While iterating, run the named tests only (`./check <test module>...`). The full check runs once, at the end of a step.
- A load run takes the machine alone. Test runs need no queue, because tests share nothing.
- A live login with the real client, played by an agent, ends each step that changes what the client sees or sends.

## Workflow

One approval per step: Jim approves its test list, and the step runs to merge on its own, with no separate stops for push or merge. It stops early only for a question the evidence cannot settle, or for a change to the approved list.

1. **Test list on the issue:** the behaviours and the failure paths, each test naming its evidence.
2. **Shape first:** the first commit holds the new types, signatures and supervision changes, reviewed before any bodies.
3. **Tests first:** a fresh implementer writes them, each expected value is checked against its evidence, and they go in as their own commit. Changing a committed expected value is a change to the list.
4. **Build:** the implementer writes the code, running only the named tests.
5. **Review, check and play:** review the diff while the full check runs; play a live login when the client would see a change.
6. **Merge on green.** The pull request body describes the change as it stands. The closing summary is the issue's last comment.

- A step is one sub-issue, one branch (`jimd/<issue>-<topic>`) and one pull request, with a fixed test list. Each commit names its issue, and an issue title states the outcome.
- The share of tests that name their evidence is measured. A separate test-writing agent is added only if it stays low.
- A rule lives where it is enforced or read: a test or lint, this file, a skill, or a skill's reference file. It stands on an outside source, a measurement or Jim's choice, and an experiment's issue keeps its numbers; there are no decision records. Rule and skill changes are collected on one issue and merged at a milestone's end, when each skill is reviewed once, unless one blocks current work.

## Planning

All planned work lives in `jamespdaily/the-genesis-prime`. `gh` runs as Jim's work account, so prefix it with `GH_TOKEN=$(gh auth token -u jamespdaily)`.

- Each phase is a milestone with one parent issue, which states its measured end condition. Its areas are sub-issues, each a checklist until its work starts, then split into sub-issues.
- Every new issue gets its milestone and its place on the board (https://github.com/users/jamespdaily/projects/2). Its Status moves through To do, In progress, Waiting on Jim and Done.
- A step's issue carries its test list, progress and results; measurements are dated comments. A new session resumes from the issue alone.
- Before opening an issue, search the code and the issues under several names. A playable server is set up whenever Jim asks.

Sort a problem by what the server did. A silent wrong result is always a bug.
1. **Logged as unhandled: missing.** Its area owns it, so open no issue; add new evidence to the area's checklist line. Build it in the step only when the step's goal fails without it.
2. **Handled, but the result differs from the evidence, or it crashed: a bug.** Fix it in the step when the step caused it or changes that code. Otherwise open a bug issue in the current milestone, with the evidence.
3. **Handled, but no evidence says what is right:** look first in the client's code, the tables, the recordings and the retail records. Only what they cannot settle is a question for Jim, marked Waiting on Jim.

**Terms. Step:** one sub-issue's work, from approved test list to merge. **Rule:** a pure function; state and input in, new state and effects out. **Effect:** what a rule asks its process to carry out. **Engine:** the module that owns one kind of client type (prerequisites, quest objectives, spell effects, unit types) for every feature. **Coverage measure:** the report of which client types the engines handle, weighted by their rows. **Fact file:** the one file of client facts, kept with the decoding-the-client skill.
