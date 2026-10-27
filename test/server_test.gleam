//// The server's supervision tree. Expected values come from these places.
//// - The tree in the doc comment of `genesis_prime/server`, as approved on the
////   login processes card: the pool, then the store, then the hand-off, each a
////   permanent child of a one-for-one supervisor that allows 3 restarts in
////   10 seconds.
//// - OTP's supervisor: a child that is a supervisor has no shutdown limit, and
////   a worker's limit is the milliseconds its spec states.
//// - The supervision-setting code rule (`test/code_rule/supervision_setting.
////   gleam`) checks that the code states each setting; this test reads what
////   the running supervisor holds.

import ask_support
import database_support
import genesis_prime/server
import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/otp/static_supervisor
import gleam/otp/supervision.{Permanent}
import owned_test
import pool_started
import supervisor_children.{ChildSettings}
import supervisor_flags.{Flags}

pub fn the_tree_starts_the_pool_the_store_and_the_hand_off_in_that_order_each_with_its_settings_stated_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let pool_name = process.new_name("pool")
  let settings =
    server.Settings(
      pool: database_support.config(
        for: shared.settings,
        database:,
        pool_name:,
        pool_size: 2,
      ),
      store: process.new_name("store"),
      hand_off: process.new_name("hand_off"),
      hand_off_shutdown_ms: 1500,
    )
  let assert Ok(started) = server.start(settings) as "the tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  assert pool_started.await(pool_name, within_ms: 30_000)
    as "the pool opened its connections"
  let assert Ok(pool) = process.named(pool_name) as "the pool is registered"
  let assert Ok(store) = process.named(settings.store)
    as "the store is registered"
  let assert Ok(hand_off) = process.named(settings.hand_off)
    as "the hand-off is registered"
  assert supervisor_children.in_start_order(started.pid)
    == [pool, store, hand_off]
    as "the pool starts first, then the store, then the hand-off"
  assert supervisor_flags.read(started.pid)
    == Flags(static_supervisor.OneForOne, 3, 10)
    as "one-for-one, 3 restarts in 10 seconds"
  assert supervisor_children.settings_in_start_order(started.pid)
    == [
      ChildSettings(restart: Permanent, shutdown_ms: None),
      ChildSettings(restart: Permanent, shutdown_ms: None),
      ChildSettings(restart: Permanent, shutdown_ms: Some(1500)),
    ]
    as "each child is permanent; the pool and the store are supervisors, the hand-off stops within its own time"
  let _reason = ask_support.stop_tree(started.pid)
  Nil
}
