//// What a step of the game connection tells the player's own client of its class
//// resource and Focus, and which of the rule's timers it starts and cancels: the 0x935s
//// a step writes, decoded, and the timers `genesis_prime/game/class_resource` owns.

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/class_resource
import genesis_prime/message/unit_float_stat_changed.{type UnitFloatStatChanged}
import genesis_prime/step.{
  type ConnectionStep, type TimerId, CancelTimer, OwnEffect, StartTimer, Unwatch,
  Watch,
}
import gleam/list

/// The 0x935s among the frames, decoded.
pub fn resource_changes(frames: List(Frame)) -> List(UnitFloatStatChanged) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == unit_float_stat_changed.message_id {
      True -> {
        let assert Ok(changed) = unit_float_stat_changed.decode(frame.body)
          as "0x935 decodes"
        Ok(changed)
      }
      False -> Error(Nil)
    }
  })
}

/// The 0x935s a step writes, decoded.
pub fn changes_written(
  taken: ConnectionStep(Request),
) -> List(UnitFloatStatChanged) {
  resource_changes(game_connection_support.heard(
    taken,
    game_connection_support.keyed(),
  ))
}

/// The timers of the class resource a step starts, as (timer, after_ms).
pub fn resource_timers_started(
  taken: ConnectionStep(Request),
) -> List(#(TimerId, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) ->
        case class_resource.owns(timer:) {
          True -> Ok(#(timer, after_ms))
          False -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The timers of the class resource a step cancels.
pub fn resource_timers_cancelled(
  taken: ConnectionStep(Request),
) -> List(TimerId) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(CancelTimer(timer:)) ->
        case class_resource.owns(timer:) {
          True -> Ok(timer)
          False -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}
