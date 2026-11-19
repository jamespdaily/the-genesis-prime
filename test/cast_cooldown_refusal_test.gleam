//// The result a press is refused with for the cooldowns it meets
//// (`genesis_prime/game/cast/cost.cooldown_refusal`). Expected values come from
//// `0x1403b14c0`, the client's press check: it records the kinds that run in the order
//// global (14), own (15), group (16) and returns the last it recorded once the longest
//// time left is past the queue window of 500 ms (`cast_state.queue_window_ms`); the time
//// left of each kind decides only whether the press is refused, never which result.

import genesis_prime/game/cast/cost.{CooldownsLeft}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/message/cast_result
import gleam/list
import gleam/option.{None, Some}
import owned_test

pub fn a_press_is_refused_with_the_last_kind_of_cooldown_that_runs_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_state.queue_window_ms == 500
    as "the table's rows are written against the client's 500 ms window"
  list.each(
    [
      #(
        "the global cooldown alone gives 14",
        CooldownsLeft(global_ms: 1000, own_ms: 0, group_ms: 0),
        Some(cast_result.SpellGlobalCooldown),
      ),
      #(
        "the global and own cooldowns give 15",
        CooldownsLeft(global_ms: 1000, own_ms: 2000, group_ms: 0),
        Some(cast_result.SpellCooldown),
      ),
      #(
        "the own and group cooldowns give 16",
        CooldownsLeft(global_ms: 0, own_ms: 2000, group_ms: 3000),
        Some(cast_result.SpellGroupCooldown),
      ),
      #(
        "a group cooldown alone gives 16",
        CooldownsLeft(global_ms: 0, own_ms: 0, group_ms: 3000),
        Some(cast_result.SpellGroupCooldown),
      ),
      #(
        "a long global cooldown with a short group one gives 16: the group is the last kind that runs, not the one with the most left",
        CooldownsLeft(global_ms: 1000, own_ms: 0, group_ms: 300),
        Some(cast_result.SpellGroupCooldown),
      ),
      #(
        "a long own cooldown with a short group one gives 16 too",
        CooldownsLeft(global_ms: 0, own_ms: 5000, group_ms: 300),
        Some(cast_result.SpellGroupCooldown),
      ),
      #(
        "no cooldown runs: not refused",
        CooldownsLeft(global_ms: 0, own_ms: 0, group_ms: 0),
        None,
      ),
      #(
        "every time at the 500 ms window: not refused, the press is held",
        CooldownsLeft(global_ms: 500, own_ms: 500, group_ms: 500),
        None,
      ),
      #(
        "the longest time one over the window: refused",
        CooldownsLeft(global_ms: 100, own_ms: 501, group_ms: 0),
        Some(cast_result.SpellCooldown),
      ),
    ],
    fn(row) {
      assert cost.cooldown_refusal(left: row.1, window_ms: 500) == row.2
        as row.0
    },
  )
}
