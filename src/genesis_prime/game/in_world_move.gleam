//// The server's move of a player inside its world: the four messages the client's own code
//// takes as a placement, the movement the move leaves and the fence that drops the
//// client's 0x637 until it has taken the placement. The tutorial's projectors move the
//// player this way (`genesis_prime/game/projector`).
////
//// ```
//// begin ─▶ 0x83c, 0x639, 0x638 (place at once), 0x636 (echo)    readiness Placed(echo_value)
//// the client ─▶ 0x635(echo), 0x637 at the new place, 0x63a       echoed ─▶ ClientReady
//// ```
////
//// - **The frames** are the loading screen's (0x83c, empty), the withdrawal of the control
////   (0x639, empty), the player's unit at the place (0x638 with reset 1, kept 0, a kind 2
////   position and a kind 14 rotation with their blend bits clear, which place the unit at
////   once) and the control given back (0x636, reset 1, carrying `echo`)
////   (`opcode.0x83c`, `opcode.0x639`, `opcode.0x638`, `opcode.0x636`).
//// - **The fence** is `world_entry.Placed(echo_value)`: a 0x637 the client sent from the old
////   place before it took the placement is decoded, checked and dropped, as a ghost's is.
////   The client's 0x635 gives the value of the 0x636 back; the one that gives `echo` back
////   lifts the fence, an earlier one (the entry's, 0) does not.
////
//// Failure table:
////
//// | What goes wrong | What happens | Where |
//// |---|---|---|
//// | A 0x637 arrives while the player is `Placed` | Decoded, checked, dropped; the map is told nothing | `connection/movement` |
//// | A 0x635 of another value arrives while `Placed` | Taken; the fence stays | `echoed` |
//// | A 0x635 arrives when the player is not `Placed` | Taken; nothing changes | `echoed` |

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/movement
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/world_entry.{type Entered, type Readiness}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/client_control_withdrawn
import genesis_prime/message/relayed_movement.{Position, Rotation}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/world_loading_screen_shown
import genesis_prime/step.{type Now}
import genesis_prime/world_map/map
import genesis_prime/world_map/player_unit

/// The player placed at `place` for the 0x636 value `echo`: its movement keeps the place
/// and its readiness is the fence, with the four frames to write, in order. `now` stamps
/// the 0x638 from the map's clock (`map.server_time`).
pub fn begin(
  entered entered: Entered,
  place place: Place,
  echo_value echo_value: Int,
  now now: Now,
) -> #(Entered, List(Frame)) {
  let #(position, rotation) = player_unit.standing(place:)
  let assert Ok(unit_body) =
    unit_movement.encode(
      UnitMovement(
        unit_id: entered.unit_id,
        server_time: map.server_time(
          origin_ms: entered.clock_origin_ms,
          monotonic_ms: now.monotonic_ms,
        ),
        reset_movement: 1,
        kept: 0,
        commands: [Position(position), Rotation(rotation)],
      ),
    )
    as "a unit id and a time of 32 bits and two commands fit the message"
  let assert Ok(granted_body) =
    client_control_granted.encode(ClientControlGranted(
      echo_value:,
      reset_movement: 1,
      unit_id: entered.unit_id,
    ))
    as "an echo and a unit id of 32 bits fit the message"
  let assert Ok(shown_body) =
    world_loading_screen_shown.encode(
      world_loading_screen_shown.WorldLoadingScreenShown,
    )
    as "the body is empty"
  let assert Ok(withdrawn_body) =
    client_control_withdrawn.encode(
      client_control_withdrawn.ClientControlWithdrawn,
    )
    as "the body is empty"
  #(
    world_entry.Entered(
      ..entered,
      movement: movement.placed(state: entered.movement, place:),
      readiness: world_entry.Placed(echo_value:),
    ),
    [
      Frame(message_id: world_loading_screen_shown.message_id, body: shown_body),
      Frame(
        message_id: client_control_withdrawn.message_id,
        body: withdrawn_body,
      ),
      Frame(message_id: unit_movement.message_id, body: unit_body),
      Frame(message_id: client_control_granted.message_id, body: granted_body),
    ],
  )
}

/// The readiness after the client's 0x635 gave back `echo_value`: a placed player whose
/// move had that value holds the placement, so the fence is lifted; anything else stays.
pub fn echoed(
  readiness readiness: Readiness,
  echo_value echo_value: Int,
) -> Readiness {
  case readiness {
    world_entry.Placed(echo_value: placed) if placed == echo_value ->
      world_entry.ClientReady
    world_entry.Placed(..)
    | world_entry.ClientLoading
    | world_entry.InWorldLoading
    | world_entry.ClientReady -> readiness
  }
}
