//// What the ability points tests share: the 0x0169 frames among a step's frames,
//// decoded to what the client reads (the points to spend, then the total,
//// `opcode.0x169`), and a level rise on tables a test chooses. Expected totals are
//// in the tests, each from `XpPerLevel.abilityPointsPerLevel`.

import ability_book_support
import experience_support
import game_connection_support as support
import genesis_prime/client_connection.{type Request, FromMap}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/map/message as map_message
import genesis_prime/message/ability_points
import genesis_prime/shared/loadout
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store
import genesis_prime/table/id.{ClassId}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{Some}
import map_support

/// Every 0x0169 among the frames, in order, as (points to spend, total).
pub fn points_in(frames frames: List(Frame)) -> List(#(Int, Int)) {
  support.decoded(frames, ability_points.message_id, ability_points.decode)
  |> list.map(fn(message) {
    #(message.ability_points, message.total_ability_points)
  })
}

/// A player of the class at `from` in the world on these tables, whose saved experience is
/// one short of the level `to`, credited a kill: every level between in one rise
/// (`ability_book_support.level_up`, on the tables the connection is given).
pub fn level_up_on(
  tables tables: table_store.Tables,
  class_id class_id: Int,
  from from: Int,
  to to: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(accepted, _) = support.accepted(Settings(..support.settings(), tables:))
  let #(state, taken) =
    support.joining_holding(
      in_character_select: support.in_select_from(accepted),
      character: store.Character(
        ..support.world_character(),
        class_id: ClassId(class_id),
        faction_id: 166,
        level: from,
      ),
      saved_health: option.None,
      saved_experience: Some(ability_book_support.experience_of(level: to) - 1),
      quests: [],
    )
  // The tests' map holds the committed rows, whose loadout lacks the class's later
  // abilities; the map of a server on these tables answers with the class's loadout on them.
  let assert map_message.Joined(unit:, incarnation:, clock_origin_ms:, ..) =
    support.map_answer(taken)
    as "the map takes the player"
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(class_id), faction_id: 166)
    as "the tables hold a loadout for the class and faction"
  let #(state, _) =
    support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(map_message.Joined(
          unit:,
          loadout:,
          address: map_support.address(number: 1),
          incarnation:,
          clock_origin_ms:,
        )),
      ),
    )
  experience_support.credited(
    state:,
    creature_id: ability_book_support.killed_creature,
    level: from,
  )
}
