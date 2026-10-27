//// The server's supervision tree. Expected values come from these places.
//// - The tree in the doc comment of `genesis_prime/server`, as approved on the
////   login processes card: the pool, then the store, then the hand-off, each a
////   permanent child of a one-for-one supervisor that allows 3 restarts in
////   10 seconds.
//// - The login's two listeners, the STS listener and then the auth listener,
////   each a permanent child that is a supervisor (Ranch's), as the doc comment
////   of `genesis_prime/server` draws them.
//// - OTP's supervisor: a child that is a supervisor has no shutdown limit, and
////   a worker's limit is the milliseconds its spec states.
//// - The supervision-setting code rule (`test/code_rule/supervision_setting.
////   gleam`) checks that the code states each setting; this test reads what
////   the running supervisor holds.

import ask_support
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor
import gleam/otp/supervision.{Permanent}
import login_support
import owned_test
import supervisor_children.{ChildSettings}
import supervisor_flags.{Flags}

pub fn the_tree_starts_the_pool_the_store_the_hand_off_and_the_two_listeners_in_that_order_each_with_its_settings_stated_test() -> Nil {
  use <- owned_test.run(60_000)
  let started = login_support.start()
  let settings = started.settings
  let pool_name = settings.pool.pool_name
  let assert Ok(pool) = process.named(pool_name) as "the pool is registered"
  let assert Ok(store) = process.named(settings.store)
    as "the store is registered"
  let assert Ok(hand_off) = process.named(settings.hand_off)
    as "the hand-off is registered"
  let children = supervisor_children.in_start_order(started.tree)
  assert list.take(children, 3) == [pool, store, hand_off]
    as "the pool starts first, then the store, then the hand-off"
  assert list.length(children) == 5
    as "the STS listener and the auth listener follow the hand-off"
  assert supervisor_flags.read(started.tree)
    == Flags(static_supervisor.OneForOne, 3, 10)
    as "one-for-one, 3 restarts in 10 seconds"
  assert supervisor_children.settings_in_start_order(started.tree)
    == [
      ChildSettings(restart: Permanent, shutdown_ms: None),
      ChildSettings(restart: Permanent, shutdown_ms: None),
      ChildSettings(restart: Permanent, shutdown_ms: Some(1500)),
      ChildSettings(restart: Permanent, shutdown_ms: None),
      ChildSettings(restart: Permanent, shutdown_ms: None),
    ]
    as "each child is permanent; the pool, the store and the two listeners are supervisors, the hand-off stops within its own time"
  let _reason = ask_support.stop_tree(started.tree)
  Nil
}
