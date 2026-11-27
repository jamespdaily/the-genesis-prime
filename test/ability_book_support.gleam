//// What the ability book tests share: the loadout of a class on the committed rows,
//// a character of a class that rises from one level to another on the game
//// connection, and what the 0x0111 and 0x01A0 frames a step writes hold.
//// The expected values are in the tests, each from the client's rows.

import cast_support
import experience_support
import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{type Request, FromMap}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/ability_tier.{type AbilityTier}
import genesis_prime/message/ability_tiers
import genesis_prime/message/item_added
import genesis_prime/shared/loadout.{type Loadout}
import genesis_prime/step.{type ConnectionStep, OwnEvent}
import genesis_prime/store
import genesis_prime/table/id.{ClassId, XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/list
import gleam/option.{None, Some}
import world_entry_support

/// The Creature2 and its level a kill is credited for: a creature of Creature2Difficulty 1
/// (`experience_test`), which gives experience at the levels the tests rise from.
pub const killed_creature = 73_464

/// The faction of the tests' characters (Dominion).
const faction = 166

/// The loadout of a class on the committed rows.
pub fn loadout_of(
  tables tables: table_store.Tables,
  class_id class_id: Int,
) -> Loadout {
  let assert Ok(set) =
    loadout.of(tables:, class_id: ClassId(class_id), faction_id: faction)
    as "the committed rows give every class and faction a loadout"
  set
}

/// An ability item of the ability location (4) a step writes: its bag index, the item (a
/// Spell4Base id), the reason and the guid.
pub type Added {
  Added(bag_index: Int, base: Int, reason: Int, item_guid: Int)
}

/// The 0x0111 of location 4 among the frames, in order.
pub fn added_in(frames frames: List(Frame)) -> List(Added) {
  support.decoded(frames, item_added.message_id, item_added.decode)
  |> list.filter_map(fn(added) {
    let item = added.held_item.item
    case item.location {
      4 ->
        Ok(Added(
          bag_index: item.bag_index,
          base: item.item_id,
          reason: added.held_item.reason,
          item_guid: item.item_guid,
        ))
      _ -> Error(Nil)
    }
  })
}

/// The tiers of every 0x01A0 among the frames, in order.
pub fn tiers_in(frames frames: List(Frame)) -> List(AbilityTier) {
  support.decoded(frames, ability_tiers.message_id, ability_tiers.decode)
  |> list.flat_map(fn(message) { message.tiers })
}

/// The tiers of a book that holds these bases at tier 1 in each of the four action sets.
pub fn tiers_of(bases bases: List(Int)) -> List(AbilityTier) {
  list.flat_map(bases, fn(base) {
    list.map([0, 1, 2, 3], fn(action_set_index) {
      ability_tier.AbilityTier(spell4_base_id: base, tier: 1, action_set_index:)
    })
  })
}

/// A player of the class and level in the world holding the experience its last save kept.
pub fn entered_at(
  class_id class_id: Int,
  level level: Int,
  saved_experience saved_experience: Int,
) -> game_connection.State {
  support.entered_holding(
    in_character_select: support.in_select(),
    character: store.Character(
      ..support.world_character(),
      class_id: ClassId(class_id),
      faction_id: faction,
      level:,
    ),
    saved_experience: Some(saved_experience),
  ).0
}

/// The tests' character of this class and level in the world after the store gave it these
/// action sets and the map took it.
pub fn entered_holding_action_sets(
  class_id class_id: Int,
  level level: Int,
  action_sets action_sets: store.ActionSets,
) -> game_connection.State {
  let character =
    store.Character(
      ..support.world_character(),
      class_id: ClassId(class_id),
      faction_id: faction,
      level:,
    )
  let #(state, taken) =
    support.joining_holding_currencies(
      in_character_select: support.in_select(),
      character:,
      saved_health: None,
      saved_experience: Some(experience_of(level:)),
      quests: [],
      items: world_entry_support.novice_items(character:),
      currencies: [],
      action_sets:,
    )
  support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(support.map_answer(taken))),
  ).0
}

/// The experience a level starts at (`XpPerLevel.minXpForLevel`).
pub fn experience_of(level level: Int) -> Int {
  let assert Ok(row) =
    xp_per_level.get(tables: fixture_tables.shared(), id: XpPerLevelId(level))
    as "the committed rows hold XpPerLevel for every level"
  row.min_xp_for_level
}

/// A player of the class at `from` whose saved experience is one short of the level `to`,
/// credited a kill: the experience crosses into `to`, which is every level between in
/// one rise.
pub fn level_up(
  class_id class_id: Int,
  from from: Int,
  to to: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  experience_support.credited(
    state: entered_at(
      class_id:,
      level: from,
      saved_experience: experience_of(level: to) - 1,
    ),
    creature_id: killed_creature,
    level: from,
  )
}

/// The same player credited a second kill at its new level.
pub fn another_kill(
  state state: game_connection.State,
  level level: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  experience_support.credited(state:, creature_id: killed_creature, level:)
}

/// The frames a step writes to the player's client.
pub fn written(taken taken: ConnectionStep(Request)) -> List(Frame) {
  support.heard(taken, support.keyed())
}

/// The press of the bag index at `ms`, taken by the connection: the step.
pub fn pressed(
  state state: game_connection.State,
  bag_index bag_index: Int,
  ms ms: Int,
) -> ConnectionStep(Request) {
  support.at(
    state:,
    ms:,
    event: OwnEvent(
      step.Read(support.world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id: 1,
          bag_index:,
          target: 0,
          press: 1,
        ),
      )),
    ),
  ).1
}
