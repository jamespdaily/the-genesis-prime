//// `database_support.once`: callers of one key wait for the first caller's
//// load and are woken when it ends, whether it returns or crashes. The load a
//// waiter waits for is not on the waiter's deadline: a key's waiters returned
//// up to seconds after the load ended when they slept between tries.

import database_support
import genesis_prime/step/runtime
import gleam/bool
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import owned_test

/// How long the first caller's load runs, long enough that a waiter that
/// sleeps between tries has backed off to seconds.
const load_ms = 2000

/// The most a waiter may take to return after the first caller has returned.
const wake_within_ms = 500

/// Eight waiters that arrive while the first caller loads return as soon as it
/// has returned. The game rule: a shared load is paid by one test and costs
/// every other test no more than that load.
pub fn waiters_return_as_soon_as_the_first_load_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let key = "database_support_test waiters return at once"
  let inside = process.new_subject()
  let loaded_at = process.new_subject()
  let returned_at = process.new_subject()
  let _first =
    process.spawn(fn() {
      let value =
        database_support.once(key, fn() {
          process.send(inside, Nil)
          process.sleep(load_ms)
          7
        })
      process.send(loaded_at, #(value, runtime.monotonic_ms()))
    })
  let assert Ok(Nil) = process.receive(inside, within: 5000)
    as "the first caller did not start its load"
  list.repeat(Nil, 8)
  |> list.each(fn(_) {
    process.spawn(fn() {
      let value = database_support.once(key, fn() { panic as "a waiter loaded" })
      process.send(returned_at, #(value, runtime.monotonic_ms()))
    })
  })
  let assert Ok(#(7, first_returned_ms)) =
    process.receive(loaded_at, within: 5000)
    as "the first caller did not return its load"
  let late_ms =
    list.repeat(Nil, 8)
    |> list.map(fn(_) {
      let assert Ok(#(7, waiter_returned_ms)) =
        process.receive(returned_at, within: 5000)
        as "a waiter did not return the first caller's value"
      waiter_returned_ms - first_returned_ms
    })
  let slowest_ms = list.fold(late_ms, 0, int.max)
  assert slowest_ms <= wake_within_ms
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
