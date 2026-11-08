//// `database_support.once`: callers of one key wait for the first caller's
//// load and are woken when it ends, whether it returns or crashes. The load a
//// waiter waits for is not on the waiter's deadline: a key's waiters returned
//// up to seconds after the load ended when they slept between tries.

import database_support
import gleam/bool
import gleam/erlang/process.{type Pid}
import gleam/list
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
          let assert Ok(Nil) = process.receive(finish, within: 5000)
            as "the first caller was never told to end its load"
          7
        }),
      )
    })
  let assert Ok(finish) = process.receive(inside, within: 5000)
    as "the first caller did not start its load"
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
      let assert Ok(value) = process.receive(returned, within: 5000)
        as "a caller did not return the first caller's value"
      value
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
        let assert Ok(Nil) = process.receive(crash, within: 5000)
          as "the holder was never told to crash"
        panic as "the holder crashed inside its load"
      })
    })
  let assert Ok(crash) = process.receive(inside, within: 5000)
    as "the holder did not start its load"
  let waiter =
    process.spawn(fn() {
      process.send(waiter_value, database_support.once(key, fn() { 42 }))
    })
  wait_until_waiting(key, waiter)
  process.send(crash, Nil)
  let assert Ok(42) = process.receive(waiter_value, within: 5000)
    as "the waiter did not load for itself after the holder crashed"
  assert database_support.once(key, fn() { panic as "loaded again" }) == 42
}

/// The processes waiting for the lock on `key`.
@external(erlang, "database_support_ffi", "lock_waiters")
fn lock_waiters(key: String) -> List(Pid)

/// Waits until `waiter` is among the processes waiting for the lock on `key`,
/// so the holder ends while the waiter waits for it.
fn wait_until_waiting(key: String, waiter: Pid) -> Nil {
  use <- bool.guard(when: list.contains(lock_waiters(key), waiter), return: Nil)
  process.sleep(1)
  wait_until_waiting(key, waiter)
}
