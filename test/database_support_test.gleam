//// `database_support.once`: callers of one key wait for the first caller's
//// load and are woken when it ends, whether it returns or crashes. The load a
//// waiter waits for is not on the waiter's deadline: a key's waiters returned
//// up to seconds after the load ended when they slept between tries.
//// `database_support.sweep`: a run drops the databases of runs that ended.

import database_support
import event_wait
import genesis_prime/step/runtime
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/string
import open_wait
import owned_test

/// Eight waiters that arrive while the first caller loads wait on the key's
/// lock, which wakes each when the load ends, and every caller returns the
/// first caller's value. The game rule: a shared load is paid by one test and
/// costs every other test no more than that load. A waiter that slept between
/// tries would not be among the processes waiting on the lock, so it would
/// never be seen waiting.
pub fn waiters_return_as_soon_as_the_first_load_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let key = "database_support_test waiters return at once"
  let waiters = 8
  let inside = process.new_subject()
  let returned = process.new_subject()
  let _first =
    process.spawn(fn() {
      process.send(
        returned,
        database_support.once(key, fn() {
          let finish = process.new_subject()
          process.send(inside, finish)
          let Nil =
            open_wait.received(
              from: finish,
              what: "the first caller to be told to end its load",
            )
          7
        }),
      )
    })
  let finish =
    open_wait.received(from: inside, what: "the first caller to start its load")
  list.repeat(Nil, waiters)
  |> list.map(fn(_) {
    process.spawn(fn() {
      process.send(
        returned,
        database_support.once(key, fn() { panic as "a waiter loaded" }),
      )
    })
  })
  |> list.each(wait_until_waiting(key, _))
  assert list.length(lock_waiters(key)) == waiters
    as "each waiter waits on the key's lock, which wakes it when the load ends"
  process.send(finish, Nil)
  let values =
    list.repeat(Nil, waiters + 1)
    |> list.map(fn(_) {
      open_wait.received(
        from: returned,
        what: "a caller to return the first caller's value",
      )
    })
  assert values == list.repeat(7, waiters + 1)
}

/// A holder that crashes inside its load frees the key: a waiter then runs its
/// own load and every later caller gets that value.
pub fn a_waiter_loads_for_itself_when_the_holder_crashes_test() -> Nil {
  use <- owned_test.run(10_000)
  let key = "database_support_test holder crashes"
  let inside = process.new_subject()
  let waiter_value = process.new_subject()
  let _holder =
    process.spawn_unlinked(fn() {
      database_support.once(key, fn() {
        let crash = process.new_subject()
        process.send(inside, crash)
        let Nil =
          open_wait.received(
            from: crash,
            what: "the holder to be told to crash",
          )
        panic as "the holder crashed inside its load"
      })
    })
  let crash =
    open_wait.received(from: inside, what: "the holder to start its load")
  let waiter =
    process.spawn(fn() {
      process.send(waiter_value, database_support.once(key, fn() { 42 }))
    })
  wait_until_waiting(key, waiter)
  process.send(crash, Nil)
  let assert 42 =
    open_wait.received(
      from: waiter_value,
      what: "the waiter to load for itself after the holder crashed",
    )
  assert database_support.once(key, fn() { panic as "loaded again" }) == 42
}

/// The processes waiting for the lock on `key`.
@external(erlang, "database_support_ffi", "lock_waiters")
fn lock_waiters(key: String) -> List(Pid)

/// Waits until `waiter` is among the processes waiting for the lock on `key`,
/// so the holder ends while the waiter waits for it. The lock sends the test no
/// event when a process starts to wait for it, so the test reads its waiters
/// every millisecond; the wait has no limit of its own, and the test's deadline
/// only warns while it goes on (`event_wait`).
fn wait_until_waiting(key: String, waiter: Pid) -> Nil {
  event_wait.until("the waiter to wait for the lock on " <> key, fn() {
    list.contains(lock_waiters(key), waiter)
  })
}

/// A run drops the databases of runs that ended and keeps the rest. The game
/// rule: a killed run's watcher dies with it, so its databases stay unless the
/// next run clears them; the pid in a database's name tells whether its run
/// can still be going, and a pid that any program holds is kept, so a run in
/// another worktree is never touched.
pub fn only_the_databases_of_dead_runs_are_swept_test() -> Nil {
  use <- owned_test.run(5000)
  let live = [100, 4242, 99_999]
  assert database_support.abandoned(
      names: [
        "genesis_test_77_1700000000000_template",
        "genesis_test_77_1700000000000_5",
        "genesis_test_100_1700000000000_template",
        "genesis_test_4242_1700000000000_9",
        "genesis_test_5_1_x",
      ],
      live_pids: live,
    )
    == [
      "genesis_test_77_1700000000000_template",
      "genesis_test_77_1700000000000_5",
      "genesis_test_5_1_x",
    ]
    as "a database whose pid no program holds is dropped, one whose pid is alive is kept"
}

/// Names that are not a run's databases are never dropped, whatever pids are
/// alive: another database on the server, a name with no run after the pid,
/// and a pid that is not plain digits.
pub fn names_that_are_not_a_runs_are_never_swept_test() -> Nil {
  use <- owned_test.run(5000)
  assert database_support.abandoned(
      names: [
        "postgres",
        "genesis_play",
        "genesis_test_",
        "genesis_test_77",
        "genesis_test_abc_1_x",
        "genesis_test_-5_1_x",
        "genesis_test_+5_1_x",
        "genesis_test__1_x",
        "other_genesis_test_77_1_x",
      ],
      live_pids: [],
    )
    == []
    as "only genesis_test_<pid>_<rest> names are a run's"
}

/// The sweep against the real server: a database named for a pid no program
/// holds is gone afterwards, and the database of this run, one named for a pid
/// that is alive (pid 1) and one that is not a run's stay.
pub fn the_sweep_drops_a_dead_runs_database_and_keeps_the_rest_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let suffix = int.to_string(runtime.unique_id())
  let dead = "genesis_test_" <> ended_pid() <> "_1_" <> suffix
  let alive = "genesis_test_1_1_" <> suffix
  let foreign = "genesis_swept_elsewhere_" <> suffix
  let own = database_support.new_database(on: shared)
  [dead, alive, foreign]
  |> list.each(database_support.create_database(
    on: shared,
    name: _,
    options: "",
  ))
  database_support.sweep(on: shared)
  let exists = database_support.database_exists(on: shared, name: _)
  let dead_left = exists(dead)
  let kept = [exists(own), exists(alive), exists(foreign)]
  // Dropped before the assertions, so a failure leaves nothing behind.
  [dead, alive, foreign]
  |> list.each(fn(name) {
    let assert Ok(Nil) =
      database_support.execute(
        on: shared,
        sql: "drop database if exists \"" <> name <> "\" with (force)",
      )
      as "a database the test made was not dropped"
  })
  assert dead_left == False
    as "the database of a run that ended was not dropped"
  assert kept == [True, True, True]
    as "a database of this run, of a live pid or of no run was dropped"
}

/// The pid of a program that has ended.
fn ended_pid() -> String {
  let assert Ok(output) =
    database_support.run_command("sh", ["-c", "echo $$"], [])
    as "a program did not run"
  string.trim(output)
}
