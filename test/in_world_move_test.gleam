//// The server's move of a player inside its world (`genesis_prime/game/in_world_move`):
//// the four frames the client's own code answers with a placement (0x83c, 0x639, 0x638,
//// 0x636), the movement the move leaves, and the fence that drops the client's 0x637 from
//// before it has taken the placement, lifted by the 0x635 that echoes the move's value.

import character_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/in_world_move
import genesis_prime/game/movement
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/world_entry.{ClientLoading, ClientReady, Placed}
import genesis_prime/message/client_control_granted
import genesis_prime/message/client_control_withdrawn
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/relayed_movement.{Position, Rotation}
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/world_loading_screen_shown
import genesis_prime/step.{Now}
import gleam/list
import owned_test
import place_support
import world_entry_support

/// WorldLocation2 51615 (Warfare Woods): the position's float32 bits are the table's
/// position0 to position2, 0xc24a224e, 0xc45759aa and 0x4399e76d.
fn warfare_woods() -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 5967,
    x: -50.53350067138672,
    y: -861.4010009765625,
    z: 307.8080139160156,
  )
}

fn entered() -> world_entry.Entered {
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: world_entry_support.character(class: 4, faction: 167, level: 1),
    )
  entered
}

/// The move at 12 s on the connection's clock, with the echo 7.
fn begun() -> #(world_entry.Entered, List(Frame)) {
  in_world_move.begin(
    entered: entered(),
    place: warfare_woods(),
    echo_value: 7,
    now: Now(monotonic_ms: 12_000, filetime: world_entry_support.filetime),
  )
}

fn only(frames frames: List(Frame), message_id message_id: Int) -> Frame {
  let assert [frame] =
    list.filter(frames, fn(frame) { frame.message_id == message_id })
    as "the move writes the message once"
  frame
}

pub fn a_placement_writes_0x83c_0x639_0x638_then_0x636_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, frames) = begun()
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x083C, 0x0639, 0x0638, 0x0636]
    as "the client's placement is the loading screen, the control withdrawn, the unit's place and the control granted again, in that order"
  assert only(frames:, message_id: world_loading_screen_shown.message_id).body
    == <<>>
    as "0x83c has an empty body"
  assert only(frames:, message_id: client_control_withdrawn.message_id).body
    == <<>>
    as "0x639 has an empty body"
}

pub fn the_placements_0x638_puts_the_player_at_once_and_keeps_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(entered, frames) = begun()
  let assert Ok(moved) =
    unit_movement.decode(
      only(frames:, message_id: unit_movement.message_id).body,
    )
    as "the frame is a 0x638"
  assert moved.unit_id == entered.unit_id as "the player's own unit"
  assert moved.server_time == 12_000 - entered.clock_origin_ms
    as "the map's clock: milliseconds since the origin the join carried"
  assert moved.reset_movement == 1 as "the unit's movement is rebuilt"
  assert moved.kept == 0 as "no movement is kept"
  assert moved.commands
    == [
      Position(UnitPositionCommand(
        x: 0xc24a224e,
        y: 0xc45759aa,
        z: 0x4399e76d,
        blends: 0,
      )),
      Rotation(MovementRotation(yaw: 0, pitch: 0, roll: 0, blends: 0)),
    ]
    as "kind 2 at WorldLocation2 51615's position with its blend clear, then kind 14 at the place's facing: the client places the unit at once"
}

pub fn the_placements_0x636_resets_and_carries_the_echo_test() -> Nil {
  use <- owned_test.run(5000)
  let #(entered, frames) = begun()
  let assert Ok(granted) =
    client_control_granted.decode(
      only(frames:, message_id: client_control_granted.message_id).body,
    )
    as "the frame is a 0x636"
  assert granted.echo_value == 7 as "the value the client's 0x635 gives back"
  assert granted.reset_movement == 1
  assert granted.unit_id == entered.unit_id
}

pub fn a_placement_moves_the_movement_and_fences_the_moves_test() -> Nil {
  use <- owned_test.run(5000)
  let #(entered, _) = begun()
  assert movement.place(state: entered.movement) == warfare_woods()
    as "the movement keeps the landing, so the next save holds it"
  assert entered.readiness == Placed(echo_value: 7)
    as "a 0x637 sent before the client took the placement is dropped"
}

pub fn the_matching_echo_lifts_the_fence_test() -> Nil {
  use <- owned_test.run(5000)
  assert in_world_move.echoed(readiness: Placed(echo_value: 7), echo_value: 7)
    == ClientReady
    as "the 0x635 that echoes the move's own value says the client holds the placement"
}

pub fn an_earlier_echo_keeps_the_fence_test() -> Nil {
  use <- owned_test.run(5000)
  assert in_world_move.echoed(readiness: Placed(echo_value: 7), echo_value: 0)
    == Placed(echo_value: 7)
    as "the entry's 0x635 echoes 0, which is not this move's"
  assert in_world_move.echoed(readiness: ClientLoading, echo_value: 7)
    == ClientLoading
    as "an echo changes only a placed player's readiness"
  assert in_world_move.echoed(readiness: ClientReady, echo_value: 7)
    == ClientReady
}
