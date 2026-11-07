//// A forced move on the player's own unit on the game connection: the go lists the
//// effect and the client moves itself, so the connection takes the client's report of
//// the move as any other 0x637. Expected values come from these places.
//// - `Spell4Effects.effectType.3.player`: the server sends only the go listing the effect
////   on the unit; the client works out the destination, moves its unit and reports it in
////   its next 0x637, which starts with a kind 0 time and then holds, for an instant move
////   (kinds 0, 1, 2, 7 and 8), kind 1, kind 2 (the landing), kind 8 and kind 11 at zero
////   and kind 14. The row is Gate's 67776 (kind 0, 20 m, delay 200), planted on Paralytic
////   Surge (`character_tables.shared_with_forced_move`).
//// - `opcode.0x637`: the position kept is the last kind 2 sent while kind 1 is 0; the
////   server relays kinds 1, 2, 8, 11, 14, 24 and 27 to the players who see the unit
////   (`opcode.0x638`).
//// - The tests' character stands at `game_connection_support.entry_place` facing -z (the
////   place of WorldLocation2 row 51596), so 20 m ahead is 20 less in z.

import character_tables
import game_client
import game_connection_support as support
import genesis_prime/client_connection.{type Request, Moving, TellMoved}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/message/float32
import genesis_prime/message/movement_command
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_velocity.{MovementVelocity}
import genesis_prime/message/relayed_movement
import genesis_prime/message/spell_go
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/step.{type ConnectionStep, ConnectionId, Map, OwnEffect}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId}
import gleam/list
import owned_test

fn medic_entering() -> game_connection.State {
  let tables = character_tables.shared_with_forced_move()
  let fresh = support.accepted(Settings(..support.settings(), tables:)).0
  support.entered_from(
    in_character_select: support.in_select_from(fresh),
    character: Character(..support.world_character(), class_id: ClassId(4)),
  ).0
}

/// The effect ids each target info of the go a step writes to the player's client lists.
fn listed_in_go(taken taken: ConnectionStep(Request)) -> List(List(Int)) {
  let assert [go] =
    support.decoded(
      support.heard(taken, support.keyed()),
      0x07F4,
      spell_go.decode,
    )
  list.map(go.targets, fn(info) {
    list.map(info.effects, fn(effect) { effect.spell4_effects_id })
  })
}

pub fn a_blink_the_client_reports_after_the_go_is_taken_and_relayed_as_any_move_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = support.watched_by(state: medic_entering(), viewers: [3, 2])
  let #(state, pressed) =
    support.press_paralytic_surge(state:, client_cast_id: 1)
  assert listed_in_go(taken: pressed) == [[67_776]]
    as "the go lists the forced move on the caster, and the client moves its own unit"
  // The client's instant move: kind 0's time, kind 1 at 0, kind 2 the landing 20 m
  // ahead (z less by 20), kind 8 and kind 11 at zero, kind 14.
  let landing =
    support.standing_at(
      x: 29.128599166870117,
      y: -853.87158203125,
      z: -580.18798828125,
    )
  let #(_, moved) =
    support.read(
      state,
      support.moves_message([
        movement_command.Time(MovementTime(time: 99)),
        movement_command.Platform(MovementPlatform(unit_id: 0)),
        game_client.position_command(
          x: 29.128599166870117,
          y: -853.87158203125,
          z: -580.18798828125,
        ),
        movement_command.Velocity(MovementVelocity(x: 0, y: 0, z: 0, blends: 0)),
        movement_command.MoveAsked(MovementMoveAsked(
          x: 0,
          y: 0,
          z: 0,
          blends: 0,
        )),
        movement_command.Rotation(MovementRotation(
          yaw: 0,
          pitch: 0,
          roll: 0,
          blends: 0,
        )),
      ]),
    )
  assert support.told_the_map(moved)
    == [
      OwnEffect(step.Tell(
        to: Map(support.camp_map(), support.incarnation),
        request: TellMoved(connection: ConnectionId(1), place: landing, seq: 1),
      )),
    ]
    as "the landing 20 m from where the player stood is the place the movement keeps: no forced-move check refuses it"
  let relayed = [
    relayed_movement.Platform(MovementPlatform(unit_id: 0)),
    relayed_movement.Position(UnitPositionCommand(
      x: float32.to_bits(29.128599166870117),
      y: float32.to_bits(-853.87158203125),
      z: float32.to_bits(-580.18798828125),
      blends: 0,
    )),
    relayed_movement.Velocity(MovementVelocity(x: 0, y: 0, z: 0, blends: 0)),
    relayed_movement.MoveAsked(MovementMoveAsked(x: 0, y: 0, z: 0, blends: 0)),
    relayed_movement.Rotation(MovementRotation(
      yaw: 0,
      pitch: 0,
      roll: 0,
      blends: 0,
    )),
  ]
  assert support.peer_tells(moved)
    == [
      #(2, support.told(news: Moving(server_time_ms: 1000, commands: relayed))),
      #(3, support.told(news: Moving(server_time_ms: 1000, commands: relayed))),
    ]
    as "each viewer is sent the move as it is relayed today, without kind 0"
}
