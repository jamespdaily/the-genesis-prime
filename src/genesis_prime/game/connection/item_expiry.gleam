//// The timer of the held timed items on the game connection (genesis_prime/game/connection):
//// one timer, `item_expiry_timer`, set for the earliest moment a held item runs out
//// (genesis_prime/game/item_expiry `next_deadline`), started when the player enters the world
//// and moved by every change of the held items. The rules are genesis_prime/game/item_expiry's;
//// this module turns the items before and after a change into the timer's effects.
////
//// ```
//// an answer that changed items ─▶ rearmed: the timer follows the earliest moment
//// the timer fired, an item due ─▶ the delete asked as the player's is (MovingItem), 0x148 reason 26,
////                                 then restarted: the timer for the next moment
//// the delete refused           ─▶ retried: the timer again after `movement.save_period_ms`
//// ```

import genesis_prime/client_connection.{type Handled, Asking, Continue, Done}
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/item_expiry
import genesis_prime/game/movement
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/store.{type HeldItem}
import gleam/list
import gleam/option.{None, Some}

/// What a change of the held items from `before` to the items of the player now in the
/// world leaves of the timer: the effects that move it follow those `handled` carries. A
/// `before` of no items is a timer that is not running. A step that does not leave the player
/// in the world has no timer to move.
pub fn rearmed(
  handled handled: Handled(Session),
  before before: List(HeldItem),
  now now: Now,
) -> Handled(Session) {
  following(handled:, effects_of: fn(entered) {
    list.map(
      item_expiry.timer_moved(
        before:,
        after: entered.items,
        now_unix_ms: step.unix_milliseconds(now:),
      ),
      connection_state.deadline_timer_move(
        connection_state.item_expiry_timer,
        _,
      ),
    )
  })
}

/// The timer for the earliest moment of the items the player in the world holds, started
/// again by a firing: the timer that fired is not running, but a change made while the firing
/// was held may have started it, so the timer is cancelled first (starting a timer that runs
/// ends the connection).
pub fn restarted(
  handled handled: Handled(Session),
  now now: Now,
) -> Handled(Session) {
  following(handled:, effects_of: fn(entered) {
    [
      step.OwnEffect(step.CancelTimer(timer: connection_state.item_expiry_timer)),
      ..list.map(
        item_expiry.timer_moved(
          before: [],
          after: entered.items,
          now_unix_ms: step.unix_milliseconds(now:),
        ),
        connection_state.deadline_timer_move(
          connection_state.item_expiry_timer,
          _,
        ),
      )
    ]
  })
}

/// The timer again, after `movement.save_period_ms`, for the player in the world whose
/// removal of an item that ran out the store refused: the item is still held and still due,
/// so the timer for its moment would fire at once and ask again without end.
pub fn retried(handled handled: Handled(Session)) -> Handled(Session) {
  following(handled:, effects_of: fn(_) {
    [
      step.OwnEffect(step.StartTimer(
        timer: connection_state.item_expiry_timer,
        after_ms: movement.save_period_ms,
      )),
    ]
  })
}

/// What `handled` does, then the effects `effects_of` makes of the player it leaves in the
/// world; a step that ends the connection, or leaves no player in the world, gets none.
fn following(
  handled handled: Handled(Session),
  effects_of effects_of: fn(world_entry.Entered) ->
    List(Effect(ConnectionEffect(client_connection.Request))),
) -> Handled(Session) {
  case handled {
    Continue(session:, effects:) ->
      Continue(session, list.append(effects, after(session:, effects_of:)))
    Asking(session:, effects:, ask:) ->
      Asking(
        session:,
        effects: list.append(effects, after(session:, effects_of:)),
        ask:,
      )
    Done(..) -> handled
  }
}

fn after(
  session session: Session,
  effects_of effects_of: fn(world_entry.Entered) ->
    List(Effect(ConnectionEffect(client_connection.Request))),
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  case connection_state.entered_of(session.status) {
    Some(entered) -> effects_of(entered)
    None -> []
  }
}
