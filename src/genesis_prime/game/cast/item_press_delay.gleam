//// The cast a use of an item started, moved to a later time: the store saves the spend
//// of the item's charge before the cast is released (genesis_prime/game/item_charge), so
//// the cast the rule decided at the press is carried out when the answer comes.
////
//// ```
//// press at P ─ cast.use_item ─▶ Started(cast', effects)   decided once, on the press's own picture
//// answer at A ─ delayed(before, cast', effects, A - P) ─▶ the stamps the press made, A - P later
//// ```
////
//// - **The stamps a start makes are absolute times of the monotonic clock**: the end of
////   the global cooldown and of the spell's cooldown, a cast's start (`Live.started_ms`
////   and `Lingering.started_ms`, which its time left and a removal's age are counted from)
////   and the times a strike effect carries. The timers a start asks for are relative to
////   the moment the connection starts them, which is the answer.
//// - **Only what the press made moves**: a cast the caster already had, a cooldown it
////   already ran and the global cooldown it already ran keep their times. A cooldown or a
////   global cooldown the press changes is a new one, since a press that is accepted finds
////   the earlier one over (`cast_press`), and a cast is new by its id.
//// - **An item's spell holds Activate rows alone** (`activate.planned_of`), so its first
////   go strikes no unit, starts no tick, node or proc and has no later timer that holds
////   an absolute time; the effects that do carry one are moved all the same.

import genesis_prime/game/cast/state.{
  type Effect, type State, Activated, CancelTimer, CasterChangeEnds,
  CasterChangeStarts, CreatureDespawns, CreatureHoldsUnitStates,
  ForcedMoveStarts, Gain, Lingering, Live, Log, Pay, Send, ShortcutCast,
  StartTimer, State, StealthChanged, Strike, TargetChangeEnds,
  TargetChangeStarts, Tell, TickStrike,
}
import genesis_prime/game/cooldown
import gleam/dict
import gleam/list
import gleam/option

/// `started` and `effects`, the state and effects of a press made on the state `before`,
/// with the times the press made moved `by_ms` later.
pub fn delayed(
  before before: State,
  started started: State,
  effects effects: List(Effect),
  by_ms by_ms: Int,
) -> #(State, List(Effect)) {
  let later = fn(ms) { ms + by_ms }
  #(
    State(
      ..started,
      global_cooldown_ends_ms: case
        started.global_cooldown_ends_ms == before.global_cooldown_ends_ms
      {
        True -> started.global_cooldown_ends_ms
        False -> option.map(started.global_cooldown_ends_ms, later)
      },
      cooldowns: cooldown.delayed(
        book: started.cooldowns,
        since: before.cooldowns,
        by_ms:,
      ),
      casts: dict.map_values(started.casts, fn(cast_id, live) {
        case dict.has_key(before.casts, cast_id) {
          True -> live
          False -> Live(..live, started_ms: later(live.started_ms))
        }
      }),
      lingering: dict.map_values(started.lingering, fn(cast_id, lingering) {
        case dict.has_key(before.lingering, cast_id) {
          True -> lingering
          False ->
            Lingering(..lingering, started_ms: later(lingering.started_ms))
        }
      }),
    ),
    list.map(effects, delayed_effect(effect: _, by_ms:)),
  )
}

/// An effect with the absolute times it carries moved `by_ms` later.
fn delayed_effect(effect effect: Effect, by_ms by_ms: Int) -> Effect {
  case effect {
    TargetChangeStarts(unit_id:, life:, struck_at_ms:, source:, modifier:) ->
      TargetChangeStarts(
        unit_id:,
        life:,
        struck_at_ms: struck_at_ms + by_ms,
        source:,
        modifier:,
      )
    ForcedMoveStarts(unit_id:, life:, struck_at_ms:, move:) ->
      ForcedMoveStarts(
        unit_id:,
        life:,
        struck_at_ms: struck_at_ms + by_ms,
        move:,
      )
    CreatureDespawns(unit_id:, life:, struck_at_ms:, went_at_ms:, delay_ms:) ->
      CreatureDespawns(
        unit_id:,
        life:,
        struck_at_ms: struck_at_ms + by_ms,
        went_at_ms: went_at_ms + by_ms,
        delay_ms:,
      )
    CreatureHoldsUnitStates(unit_id:, life:, struck_at_ms:, went_at_ms:, rows:) ->
      CreatureHoldsUnitStates(
        unit_id:,
        life:,
        struck_at_ms: struck_at_ms + by_ms,
        went_at_ms: went_at_ms + by_ms,
        rows:,
      )
    Send(..)
    | Tell(..)
    | StartTimer(..)
    | CancelTimer(..)
    | Log(..)
    | Strike(..)
    | TickStrike(..)
    | Pay(..)
    | Gain(..)
    | CasterChangeStarts(..)
    | CasterChangeEnds(..)
    | TargetChangeEnds(..)
    | StealthChanged(..)
    | Activated(..)
    | ShortcutCast(..) -> effect
  }
}
