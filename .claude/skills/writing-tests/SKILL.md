---
name: writing-tests
description: Sets how this project's tests are written - layers, evidence for expected values, table tests, isolation, waiting for events, names. Use when writing, fixing or reviewing tests.
---

# Writing tests

A test proves the game, not the code. Four layers, most tests at the bottom:

1. **Pure rules:** state and input in, effects out. No database, no process.
2. **Whole tables:** every row of a client table through its engine, checking one fact each; property tests for invariants and round-trips.
3. **Processes:** started under a supervisor inside the test, covering failure paths: a service away or restarting, a failed save, a second login.
4. **The edge:** the client's bytes in and out; recorded sessions replayed through the whole server; the server's messages read by the client's own reader.

## Expected values

- An expected value names its source (a client address, a table row, a recording, a retail record, the world database) or states the game rule it checks. Never compute it with the code under test or take it from the support that builds the input.
- An expected value that seems wrong is checked against its source: correct it with the source named if the source settles it, else report it.
- An inventory (tables, message modules, opcodes, world ids) is checked against a second source (the table files present, the schema, the rule's doc comment), never a literal list.
- A count of what the server handles lives in the coverage run posted on the issue (`gleam run -m genesis_prime/coverage`), never in a literal: test the property (every row is planned or names its reason), and counts that come from the client alone.

## Shape

- Test at the boundary through public functions: a process's messages, the client's bytes, a recording. Assert on the effect that matters, found by a helper; build test data from defaults with record update.
- Test each decision at the lowest layer that makes it. A higher layer tests only its own job, one test per path, and never repeats the decisions below. Apply this to each test file a change touches.
- A rule with several cases is one table test (input, expected, reason) through one check, with scenes from shared helpers in the test support files so each row states only what differs. A test list names its cases as rows.
- A game rule with an invariant is checked by a qcheck property first; every codec round-trip has one. A table holds the cases tied to real client rows.
- A test is named as the rule it checks: `a_full_inventory_refuses_a_new_item_test`.
- Prove a reshape changes nothing by running every table row through old and new code, and prove the harness can fail.

## Data and isolation

- Tests share nothing: no fixed names, nodes or ports. A database test runs in its own database, made from the template `test/database_support.gleam` migrates once per run; database tests are for processes and saves, and rules and engines stay pure.
- A logic test reads client rows from the committed fixture, so it runs without the client's files; a test that reads a whole table is guarded by `client_tables.present()`. A planted table is only for the table format itself; an edge case no client row holds edits a real row with `fixture_tables.changed` or `added`, and says why.
- A whole-world data read (every spawn, every table row) belongs in the check's real-data part, not in a plain test.

## Time and order

- Wait for an event, never a fixed time, and never rely on the order of messages from two senders: Erlang orders signals only per sender. Drive timers and the clock; time bounds belong in load runs.
- Each test body runs in its own process inside `owned_test.run` (`test/code_rule/test_body.gleam`). Its deadline warns and does not end the test, so every wait ends by its own condition: a frame seen, an answer, a driven-clock step.
- A test never runs under a production time limit (a shutdown, send or ask deadline, a database client's default query timeout): it passes settings that cannot expire.
- Assert behaviour, never timing, a count that depends on a session's length, or how bytes were split into reads. A recorded value is checked by what it means, not how many there are.

## A failing test

- Stop and name its cause before changing anything; a test that fails once is unexplained until then.
- A fix names its cause with the evidence (the failing lines and the code that makes them) in the commit and the hand-back. A slower step, a longer wait or a rerun is not a cause. A test that fails in one run of many rolled a die (`GENESIS_TEST_SEED_SALT`, `test/fixed_seed.gleam`).
