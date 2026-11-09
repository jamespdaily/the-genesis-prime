//// What the experience tests share: a player of a level and experience in the world,
//// the credit of a kill told to it, and what a step writes of the credit. The
//// expected values are in the tests, each from the client's rows.

import game_connection_support as support
import genesis_prime/client_connection.{
  type Request, AskStore, FromMap, SentByKill,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/experience.{Credit}
import genesis_prime/message/experience_gained.{type ExperienceGained}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_level.{UnitStatLevel}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/map.{Left}
import genesis_prime/world_map/stay.{type Stay}
import gleam/list
import gleam/option.{type Option}

/// The unit id of the creature the credits name.
pub const creature_unit_id = 7

/// The tests' player as a character of this level, in the world with the
/// experience its last save kept (`None` for none: the least of its level).
pub fn entered_at(
  level level: Int,
  saved_experience saved_experience: Option(Int),
) -> game_connection.State {
  support.entered_holding(
    in_character_select: support.in_select(),
    character: store.Character(..support.world_character(), level:),
    saved_experience:,
  ).0
}

/// The credit of a kill of a creature of this Creature2 row and level, told to the
/// connection for the stay `stay`.
pub fn credited_in(
  state state: game_connection.State,
  stay stay: Stay,
  creature_id creature_id: Int,
  level level: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.feed(
    state:,
    event: support.for_stay(
      stay:,
      sent: SentByKill(Credit(
        unit_id: creature_unit_id,
        creature_id: Creature2Id(creature_id),
        level:,
      )),
    ),
  )
}

/// The credit told for the player's own first stay.
pub fn credited(
  state state: game_connection.State,
  creature_id creature_id: Int,
  level level: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  credited_in(state:, stay: support.own_stay(), creature_id:, level:)
}

/// The player camping out of the world: the state in character select, and the
/// experience and level the camp's save asks the store to keep.
pub fn camped(
  state state: game_connection.State,
) -> #(game_connection.State, Int, Int) {
  let #(state, _) =
    support.read(state:, bytes: support.camp_request_message(True))
  let #(state, taken) =
    support.read(state:, bytes: support.camp_finished_message())
  let assert AskStore(store.Move(store.SavePlace(experience:, level:, ..))) =
    support.ask_request(taken)
    as "the camp's end asks the store to save the place"
  let #(state, taken) =
    support.answer(state:, taken:, outcome: support.place_saved())
  let #(state, _) =
    support.answer(state:, taken:, outcome: step.Answer(FromMap(Left)))
  #(state, experience, level)
}

/// The 0x1ac messages a step writes to the player's client, in order.
pub fn gains(taken taken: ConnectionStep(Request)) -> List(ExperienceGained) {
  support.decoded(
    support.heard(taken, support.keyed()),
    experience_gained.message_id,
    experience_gained.decode,
  )
}

/// The levels a step writes to the player's client as 0x938 of stat 10, each
/// with the unit it names.
pub fn level_writes(taken taken: ConnectionStep(Request)) -> List(#(Int, Int)) {
  support.decoded(
    support.heard(taken, support.keyed()),
    0x0938,
    unit_stat_changed.decode,
  )
  |> list.filter_map(fn(message: unit_stat_changed.UnitStatChanged) {
    case message.change {
      unit_stat_change.Level(UnitStatLevel(value:)) ->
        Ok(#(message.unit_id, value))
      unit_stat_change.Shield(..)
      | unit_stat_change.InterruptArmor(..)
      | unit_stat_change.Absorption(..) -> Error(Nil)
    }
  })
}
