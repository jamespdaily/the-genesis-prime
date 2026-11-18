//// The client's 0x07A5 on the game connection (`genesis_prime/game/connection`): the cast of
//// the Level Up spell that answers it, and what ends the connection. The rule is
//// `level_up_test`'s and the cast's is `cast_level_up_test`'s; this tests the connection's
//// own job, one case per path. Expected values come from these places:
//// - `opcode.0x7a5` and `lua.LevelUpUnlocks.ReplayLevelUp`: the client sends its unit's level
////   or an earlier one (the Replay button), never a level above its unit's, and a body of
////   exactly 32 bits.
//// - `Spell4.tierIndex.level_up`: the Spell4 of a level (`level_up_support.tiers`).
//// - `opcode.0x7ff` and `opcode.0x7f4`: the answer is a start and a go at once, and the cast
////   lingers on a timer of the connection's own.

import cast_support
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{AskStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/step
import genesis_prime/store.{CharacterId, Move, SavePlace}
import gleam/int
import gleam/list
import level_up_support
import owned_test

/// A player of level 4 in the world: the character of the tests' connection, at level 4.
fn in_world_at_level_4() -> game_connection.State {
  connection_support.entered_as(
    store.Character(..connection_support.world_character(), level: 4),
  ).0
}

/// A 0x07A5 with this body, inside 0x038C.
fn asked(body body: BitArray) -> BitArray {
  connection_support.world_message(message_id: 0x07A5, body:)
}

pub fn a_0x07a5_in_the_world_is_answered_with_the_cast_and_a_level_above_the_players_ends_the_connection_test() -> Nil {
  use <- owned_test.run(120_000)
  let state = in_world_at_level_4()
  // The cast rule's timer ids begin at 1000.
  list.each([#(4, 77_409), #(3, 77_407)], fn(case_) {
    let #(level, spell4_id) = case_
    let #(_, taken) =
      connection_support.read(
        state:,
        bytes: asked(body: level_up_support.replay_body(level:)),
      )
    let frames = connection_support.written(taken:)
    assert cast_support.ids(frames:) == [0x07FF, 0x07F4]
      as {
        "level "
        <> int.to_string(level)
        <> ": the start and the go at once, no 0x7fd"
      }
    assert connection_support.started_spells(frames:) == [spell4_id]
      as "Spell4.tierIndex.level_up: the tier of the level"
    let assert [_] =
      list.filter(support.timers_started(taken), fn(timer) {
        let step.TimerId(number) = timer
        number >= 1000
      })
      as "one cast timer: the 5000 ms of the effect's life"
  })
  let #(_, taken) =
    connection_support.read(
      state:,
      bytes: asked(body: level_up_support.replay_body(level: 1)),
    )
  assert support.writes(taken) == []
    as "level 1 has no fanfare: nothing is written"
  assert list.length(support.logs_of(step: taken, level: step.LogDebug)) == 1
    as "one debug line says so"
  assert support.logs_of(step: taken, level: step.LogError) == []
  assert !support.stops(taken)
  list.each(
    [
      #(level_up_support.replay_body(level: 5), "a level above the player's"),
      #(<<4, 0, 0>>, "a body the client's writer would not write"),
    ],
    fn(case_) {
      let #(body, why) = case_
      let #(_, taken) = connection_support.read(state:, bytes: asked(body:))
      let assert [line] = support.logs_of(step: taken, level: step.LogError)
        as why
      assert support.says(line, "0x07A5")
      assert support.writes(taken) == []
      let assert AskStore(Move(SavePlace(character_id: CharacterId(42), ..))) =
        connection_support.ask_request(taken)
        as "the place is saved as for any refused message, then the connection ends"
    },
  )
}
