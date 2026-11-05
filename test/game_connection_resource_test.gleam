//// The class resource on the game connection (`genesis_prime/game/connection/resource`):
//// a press's cost paid at its accept and written to the player's own client as
//// 0x935, and the refill's timer run by the connection. Expected values come from
//// the client (`opcode.0x935`: a 32-bit unit, a 5-bit stat, a float; stat n + 2
//// is slot n, `opcode.0x262.resource_stats`), the client's row
//// (`table_rows -- Spell4 38779`: Impale costs 35 of type 8, slot 3) and the step's
//// design (issue 403: the Stalker's 100 Suit Power, +7 each second, paid at the
//// accept).

import cast_support
import character_tables
import game_connection_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/class_resource
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/message/float32
import genesis_prime/message/unit_float_stat_changed.{
  type UnitFloatStatChanged, UnitFloatStatChanged,
}
import genesis_prime/step.{OwnEvent, TimerFired}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import gleam/list
import owned_test

/// The 0x935s among the frames, decoded.
fn resource_changes(frames: List(Frame)) -> List(UnitFloatStatChanged) {
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

pub fn a_stalkers_impale_writes_its_suit_power_at_65_as_0x935_and_the_refill_writes_72_a_second_later_test() -> Nil {
  use <- owned_test.run(30_000)
  // The connection reads the starting abilities' trees, Impale's cost among them
  // (`character_tables.shared_with_spell_trees`).
  let fresh =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        tables: character_tables.shared_with_spell_trees(),
      ),
    ).0
  let #(state, entered) =
    game_connection_support.entered_from(
      in_character_select: game_connection_support.in_select_from(fresh),
      character: Character(
        ..game_connection_support.world_character(),
        class_id: ClassId(5),
      ),
    )
  let unit_id = game_connection_support.player_in(entered).unit_id
  let assert Ok(set) =
    loadout.of(
      tables: character_tables.shared(),
      class_id: ClassId(5),
      faction_id: 166,
    )
    as "the tables hold the Stalker's Novice set"
  let assert Ok(bag_index) =
    list.index_map(set.abilities, fn(base, index) { #(base, index) })
    |> list.key_find(Spell4BaseId(23_161))
    as "a level-1 Stalker holds Impale (Spell4Base 23161)"
  let #(state, pressed) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id: 9,
          bag_index:,
          target: 0,
          press: 1,
        ),
      ),
    )
  let frames =
    game_connection_support.heard(pressed, game_connection_support.keyed())
  assert resource_changes(frames)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 5, value: float32.to_bits(65.0)),
    ]
    as "100 less 35, paid at the accept, as 0x935 of stat 5 (slot 3) to the player's own client"
  let #(_, ticked) =
    game_connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.regen_timer)),
    )
  assert resource_changes(game_connection_support.heard(
      ticked,
      game_connection_support.keyed(),
    ))
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 5, value: float32.to_bits(72.0)),
    ]
    as "the refill's tick, a timer of the connection: +7"
}
