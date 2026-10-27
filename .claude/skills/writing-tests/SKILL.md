---
name: writing-tests
description: How to write tests - layers, evidence for expected values, isolation, waiting for events, names. Use when writing or fixing tests.
---

# Writing tests

A test proves the game, not the code. Four layers, most tests at the bottom:

1. **Pure rules:** state and input in, effects out. No database, no process.
2. **Whole tables:** every row of a client table through its engine, checking one fact each; property tests for invariants and round-trips.
3. **Processes:** started under a supervisor inside the test, covering failure paths: a service away or restarting, a failed save, a second login.
4. **The edge:** the client's bytes in and out; recorded sessions replayed through each rule; the server's messages read by the client's own reader.

Apply every rule to each test, and check the diff against each before it is done.

- A test's expected value names its source (a client address, a table row, a recording, a retail record) or states the game rule it checks. It is never computed by the code under test.
- Test at the boundary where you can, through public functions: a process's messages, the client's bytes, a recording. Assert on the effect that matters, found by a helper; build test data from defaults with record update.
- Property tests check invariants of pure rules and every codec round-trip.
- Tests share nothing: no fixed names, nodes or ports. A database test runs in its own database through `template_database.run`, at about 75 ms a test, so database tests are for processes and saves; rules and engines stay pure. Setup is paid once per run.
- Wait for an event, never a fixed time. Each test runs in its own process. A test that fails once is unexplained until its cause is named.
- A test is named as the rule it checks: `a_full_inventory_refuses_a_new_item_test`.
- Prove a reshape changes nothing by running every table row through old and new code, and prove the harness can fail.
