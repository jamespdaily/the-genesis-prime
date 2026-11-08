---
name: writing-tests
description: How to write tests - layers, evidence for expected values, isolation, waiting for events, names. Use when writing or fixing tests.
---

# Writing tests

A test proves the game, not the code. Four layers, most tests at the bottom:

1. **Pure rules:** state and input in, effects out. No database, no process.
2. **Whole tables:** every row of a client table through its engine, checking one fact each; property tests for invariants and round-trips.
3. **Processes:** started under a supervisor inside the test, covering failure paths: a service away or restarting, a failed save, a second login.
4. **The edge:** the client's bytes in and out; recorded sessions replayed through the whole server; the server's messages read by the client's own reader.

- A test's expected value names its source (a client address, a table row, a recording, a retail record, the world database) or states the game rule it checks. It is never computed by the code under test: that would pass a check by construction. An expected value that seems wrong is checked against its source: a value its source settles is corrected with the source named, and any other is reported.
- Test at the boundary where you can, through public functions: a process's messages, the client's bytes, a recording. Assert on the effect that matters, found by a helper; build test data from defaults with record update.
- Test each decision at the lowest layer that makes it. A higher layer tests only its own job, one test per path through it, and does not repeat the decisions below. Apply it to each test file a change touches. (The cast and connection tests were 2.4 to 2.6 times their code; a stealth blow was tested in both, and seven character-select outcomes again over the wire, 2026-11-07.)
- Property tests check invariants of pure rules and every codec round-trip.
- Tests share nothing: no fixed names, nodes or ports. A database test runs in its own database, made from the template `test/database_support.gleam` migrates once per run, so database tests are for processes and saves; rules and engines stay pure.
- CI has no client. A test of logic reads the client's rows from the committed fixture, so it runs in CI; a test that reads a whole table is guarded by `client_tables.present()`. A planted table is only for the table format itself; an edge case no client row holds edits a real row with `fixture_tables.changed` or `added`, and the test says why.
- Wait for an event rather than a fixed time, and do not rely on the order of messages from two senders: Erlang orders signals only per sender. Each test body runs in its own process, inside `owned_test.run` (`test/code_rule/test_body.gleam` checks it). When a test fails, stop and name its cause before changing anything; a test that fails once is unexplained until then.
- A test asserts behaviour, not timing, a count that depends on a session's length, or how bytes were split into reads: those change from run to run. A value from a recording is checked by what it means, not by how many there are.
- A test is named as the rule it checks: `a_full_inventory_refuses_a_new_item_test`.
- Prove a reshape changes nothing by running every table row through old and new code, and prove the harness can fail.
