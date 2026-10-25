---
name: writing-tests
description: How to write and fix tests in the-genesis-prime - the four layers, where each expected value comes from, testing at the boundary, property tests, whole-table tests, differential tests for a reshape, isolation, waiting for events instead of sleeping, failure paths, naming a test as the rule it checks, and the unitest runner, with the traps of the test database. Use when writing a step's test list, writing or fixing any test, or when a test fails only sometimes, even if the request only says "add a test".
---

# Writing tests

A test proves the game, not the code.

## Four layers, most tests at the bottom

1. **Pure rules:** state and input in, effects out. No database, no process.
2. **Whole tables:** every row of a client table through its engine, checking one fact each; property tests for invariants and round-trips.
3. **Processes:** started under a supervisor inside the test, covering failure paths: a service away or restarting, a failed save, a second login.
4. **The edge:** the client's bytes in and out, and recordings replayed.

## The test list

A step's test list is its plan, and Jim approves it on the issue. Each line is one test:

- **Named as the rule it checks:** `a_full_inventory_refuses_a_new_item_test`. The approved list then reads as the spec.
- **With its evidence:** the client address, the table and row, the recording, or the retail record that gives the expected value; or the game rule it states.
- **With the failure paths** beside the normal one: a service that is away or restarting, a save that fails, a player on another map, a second login, an unknown id.

Once the tests are committed, an expected value changes only as a change to the approved list, which stops the step for Jim.

## Rules

- **A test's expected value names its source** (a client address, a table row, a recording, a retail record) **or states the game rule it checks.** 34% of sampled earlier tests only checked what the code happened to do.
- **Test at the boundary where you can:** a process's messages, the client's bytes, a recording. Assert on the effect that matters, found by a helper, never on a whole effect list. One new effect once broke 10 effect lists in 5 files.
- **Build test data from defaults with record update,** such as `Player(..default_player(), level: 9)`, so a new field changes one place.
- **Property tests check invariants of pure rules and every codec round-trip.** Example tests miss the inputs nobody thought of.
- **Prove a reshape changes nothing by running every table row through old and new code,** and prove the harness can fail. Copy the old module into `test/` with `git show <commit>:<path>`, drive old and new with one seeded `prng` sequence, and compare after every call with Erlang's `=:=`, since the two modules' types differ by name. Then break the new code by one small step and check the harness stops on it. Delete the harness afterwards. Earlier reshapes were proved over 32,131 and 72,130 rows this way.
- **Tests share nothing:** no fixed names, nodes or ports. Each database test is isolated, by the method the database-isolation trial on its Milestone 0 issue chose. Setup is paid once per run. A shared database once forced a test queue and random failures, and setup cost about 16 s per run.
- **Wait for an event, never a fixed time.** A `process.sleep` pays its whole length when the event came at once, and fails on a busy machine when it comes late. Wait with `process.receive` and a timeout for a message; a monitor and its down message for a process that ends; a `process.call` for "it has handled what I sent". A fixed wait is right only to prove that something does not happen, and even then a call to the process afterwards usually proves it sooner. Waiting for the right event once took a test from 25 s to 5.6 s.
- **Wait for a message the reader has not read yet.** A wait for one an earlier read already took runs out its whole timeout, and swallows everything sent meanwhile.
- **Each test runs in its own process,** so every pool and server it starts stops with it. Never pass a pool or a server from one test to another. With every test in one process, nothing closed until the run ended, and the suite peaked at 297 of Postgres's 300 connections; with a process each it peaked at 12.
- **A test that fails once is unexplained until its cause is named.** Record its log lines and how many runs it failed in, and name an experiment that would tell the causes apart. It is never "flaky".

## Running tests

Tests run on unitest: plain test functions with `assert`, a seeded random order, runs by file, line, name or tag, parallel workers, and a per-test timeout in its own process. Its docs are in `~/Projects/reference/gleam-1.19/text/packages/unitest-1.6.1/`. An earlier trial ran a whole suite at the same speed as before, ran one test by name, and its random order found a real order dependence.

- While iterating, name the tests: `./check <test module>...` runs every other check but only those tests. Name each test module the change touches, and each that imports a changed `src` module.
- A failure in random order reruns in the same order with `gleam test -- --seed <seed>`, using the seed the failed run printed. Put the seed in the issue comment that reports the failure.

## Traps of the test database

- **`pg_stat_activity` does not change inside a transaction.** Postgres copies it at its first read in a transaction, so a poll for a backend waiting on a lock must run outside the transaction that holds the lock.
- **A temporary table lives on one connection.** With a pool of more than one, a `create temporary table` and the next query can land on different connections. Do it in one statement, or use a single-connection pool.
- **The Postgres VM's clock can fall behind after the Mac sleeps,** and tests that compare a database time with the Mac's then fail. The setup check compares the two clocks.
- **The world data folder is shared, outside every repo.** When another session rewrites it, tests that count its rows fail with no change to the code. Check the folder's modification times before suspecting a diff.
