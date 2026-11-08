//// A forced move on the player's own unit on the game connection: the go lists the
//// effect and the client moves itself, so the connection takes the client's report of
//// the move as any other 0x637. Expected values come from these places.
//// - `Spell4Effects.effectType.3.player`: the server sends only the go listing the effect
////   on the unit; the client works out the destination, moves its unit and reports it in
////   its next 0x637, which starts with a kind 0 time and then holds, for an instant move
////   (kinds 0, 1, 2, 7 and 8), kind 1, kind 2 (the landing), kind 8 and kind 11 at zero
////   and kind 14. The row is Gate's own 67776 (`table_rows -- Spell4Effects spellId=34355`:
////   kind 0 in dataBits00, 20 m in dataBits01 and dataBits02, delay 200, aimed at the
////   caster), cast by the Spellslinger on the fixture's rows.
//// - `opcode.0x637`: the position kept is the last kind 2 sent while kind 1 is 0; the
////   server relays kinds 1, 2, 8, 11, 14, 24 and 27 to the players who see the unit
////   (`opcode.0x638`).
//// - The tests' character stands at `game_connection_support.entry_place` facing -z (the
////   place of WorldLocation2 row 51596), so 20 m ahead is 20 less in z.

import cast_support
import game_client
import game_connection_support as support
import genesis_prime/client_connection.{type Request, Moving, TellMoved}
import genesis_prime/game/connection as game_connection
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
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test

/// A Spellslinger on the fixture's rows, whose Gate 34355 is at bag index 2 (class 7's
/// level-1 SpellLevel rows 1011, 1036 and 1236: 43468, 34718 and 34355, in that order).
fn spellslinger_entering() -> game_connection.State {
  support.entered_with(
    settings: support.settings(),
    class_id: 7,
    saved_health: None,
  ).0
}

const gate = 2

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
  let state =
    support.watched_by(state: spellslinger_entering(), viewers: [3, 2])
  let #(state, pressed) =
    support.read(
      state,
      support.world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id: 1,
          bag_index: gate,
          target: 0,
          press: 1,
        ),
      ),
    )
  assert list.map(listed_in_go(taken: pressed), list.sort(_, int.compare))
    == [[67_776, 67_777]]
    as "the go lists on the caster Gate's forced move 67776 and its property modifier 67777 (its two Proxy rows start other spells), and the client moves its own unit"
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
