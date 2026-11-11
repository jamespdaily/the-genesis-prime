//// The rule that takes a character into a world (`genesis_prime/game/world_entry`):
//// how a rejoin after a departures terminal's move takes the player's health and
//// readiness, and where a saved departure enters. Expected values come from these
//// places.
//// - `opcode.0x637`, 0x1403b6de0: the join's 0xAD removes every unit and its control,
////   so a rejoin's client keeps moving the old one until it arrives (`InWorldLoading`).
//// - The client's WorldLocation2 rows 42074 (world 426, zone 648) and 41641 (world
////   990, zone 1417): the landings of the Northern Wilds and Everstar Grove terminals,
////   whose choice objectives are QuestObjective 21328 and 21329 of Quest2 10528.

import character_tables
import genesis_prime/game/player_life
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/world_entry
import genesis_prime/step.{ConnectionId}
import genesis_prime/store.{type Character, type QuestRow, Character}
import genesis_prime/world_map/map
import gleam/dict
import gleam/option.{None, Some}
import map_support
import owned_test
import place_support
import quest_support
import world_entry_support

/// The place the map is asked to take the character at, the one Join among the
/// effects.
fn asked_place(effects effects: List(world_entry.Effect)) -> Place {
  let assert [world_entry.AskMap(message: map_message, ..)] = effects
    as "a join asks the map once"
  let assert map.Join(place:, ..) = map_message as "the ask is a join"
  place
}

/// The character of the tests, saved in the tutorial world's start place.
fn tutorial_character() -> Character {
  world_entry_support.character(class: 2, faction: 166, level: 1)
}

/// A Bon Voyage log (Quest2 10528: the talk 21326, travel 21327, the Northern Wilds
/// choice 21328, the Everstar Grove choice 21329) with these objective indexes done.
fn bon_voyage(done done_mask: Int, progress progress: List(Int)) -> QuestRow {
  quest_support.active(
    quest_id: 10_528,
    state: 2,
    placeholder: 0,
    tracked: False,
    done_mask:,
    progress:,
  )
}

/// Where the store's answer for the character, saved at `place` with this quest row,
/// has the map take it.
fn entry_place(character character: Character, quest quest: QuestRow) -> Place {
  let #(_, loaded) =
    world_entry_support.loaded_holding(
      tables: character_tables.shared(),
      character:,
      items: [],
      saved_experience: None,
      quests: [quest],
    )
  let assert world_entry.Join(effects:, ..) = loaded
    as "the character is taken into the world"
  asked_place(effects:)
}

fn assert_place(
  place place: Place,
  world world: Int,
  zone zone: Int,
  x x: Float,
  y y: Float,
  z z: Float,
  reason reason: String,
) -> Nil {
  assert start_place.world_id(place) == world as reason
  assert start_place.world_zone_id(place) == zone as reason
  assert start_place.x(place) == x as reason
  assert start_place.y(place) == y as reason
  assert start_place.z(place) == z as reason
}

pub fn a_departure_rejoin_keeps_the_players_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let character = tutorial_character()
  let #(_, entered) = world_entry_support.entry(tables:, character:)
  let full = player_life.health(life: entered.life)
  let landing =
    place_support.at(
      world_id: 426,
      world_zone_id: 648,
      x: 4098.16015625,
      y: -665.9780883789062,
      z: -5165.10009765625,
    )
  let rejoin = fn(health) {
    let #(state, effects) =
      world_entry.rejoining(
        entered:,
        place: landing,
        health:,
        connection: ConnectionId(1),
        stay: map_support.stay(count: 2),
        tables:,
        visibility: dict.new(),
      )
    let assert world_entry.InTheWorld(entered: rejoined, ..) =
      world_entry_support.joined_state(
        state:,
        tables:,
        character:,
        place: landing,
        now: world_entry_support.now(),
      )
      as "the map's answer to the rejoin puts the player in the world"
    #(rejoined, effects)
  }
  let #(hurt, effects) = rejoin(Some(1))
  assert player_life.health(life: hurt.life) == 1
    as "a rejoin given a health of 1 enters with 1: the unit's health stays across a departure"
  assert player_life.health(life: hurt.life) < full
    as "1 is below the full health a play enters with"
  let #(whole, _) = rejoin(None)
  assert player_life.health(life: whole.life) == full
    as "a rejoin given none enters with the full health, as the Holocrypt's join does"
  assert_place(
    place: asked_place(effects:),
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "the map of the landing's world is asked to take the player at the landing",
  )
}

pub fn a_rejoin_starts_in_world_loading_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let character = tutorial_character()
  let #(_, played) = world_entry_support.entry(tables:, character:)
  assert played.readiness == world_entry.ClientLoading
    as "a play's client loads the world it was told to"
  let landing =
    place_support.at(
      world_id: 426,
      world_zone_id: 648,
      x: 4098.16015625,
      y: -665.9780883789062,
      z: -5165.10009765625,
    )
  let #(state, _) =
    world_entry.rejoining(
      entered: played,
      place: landing,
      health: None,
      connection: ConnectionId(1),
      stay: map_support.stay(count: 2),
      tables:,
      visibility: dict.new(),
    )
  let assert world_entry.InTheWorld(entered: rejoined, ..) =
    world_entry_support.joined_state(
      state:,
      tables:,
      character:,
      place: landing,
      now: world_entry_support.now(),
    )
    as "the map's answer to the rejoin puts the player in the world"
  assert rejoined.readiness == world_entry.InWorldLoading
    as "opcode.0x637: the client moves the old unit until the join's 0xAD reaches it"
}

pub fn a_saved_choice_in_the_terminals_world_enters_at_its_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Talk (index 0), travel (1) and the Northern Wilds choice (2) done: mask 0b111.
  assert_place(
    place: entry_place(
      character: tutorial_character(),
      quest: bon_voyage(done: 7, progress: [1, 1, 1, 0, 0]),
    ),
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "21328 done in world 3460: the player enters at WorldLocation2 42074, the Northern Wilds landing",
  )
  // The Everstar Grove choice (3) instead: mask 0b1011.
  assert_place(
    place: entry_place(
      character: tutorial_character(),
      quest: bon_voyage(done: 11, progress: [1, 1, 0, 1, 0]),
    ),
    world: 990,
    zone: 1417,
    x: -768.36572265625,
    y: -904.805419921875,
    z: -2275.0791015625,
    reason: "21329 done in world 3460: the player enters at WorldLocation2 41641, the Everstar Grove landing",
  )
  // Travel counted with no choice (mask 0b11) is no departure: the saved place.
  assert_place(
    place: entry_place(
      character: tutorial_character(),
      quest: bon_voyage(done: 3, progress: [1, 1, 0, 0, 0]),
    ),
    world: 3460,
    zone: 6009,
    x: 29.0,
    y: -853.0,
    z: -560.0,
    reason: "no choice objective done: the player enters at its saved place",
  )
  // The quest not held at all: the saved place.
  let #(_, loaded) =
    world_entry_support.loaded_holding(
      tables: character_tables.shared(),
      character: tutorial_character(),
      items: [],
      saved_experience: None,
      quests: [],
    )
  let assert world_entry.Join(effects:, ..) = loaded
    as "the character is taken into the world"
  assert_place(
    place: asked_place(effects:),
    world: 3460,
    zone: 6009,
    x: 29.0,
    y: -853.0,
    z: -560.0,
    reason: "no quest: the player enters at its saved place",
  )
}

pub fn a_saved_choice_outside_the_terminals_world_keeps_the_saved_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let character =
    Character(
      ..tutorial_character(),
      place: Some(place_support.at(
        world_id: 426,
        world_zone_id: 648,
        x: 100.0,
        y: -600.0,
        z: -5000.0,
      )),
    )
  assert_place(
    place: entry_place(
      character:,
      quest: bon_voyage(done: 7, progress: [1, 1, 1, 0, 0]),
    ),
    world: 426,
    zone: 648,
    x: 100.0,
    y: -600.0,
    z: -5000.0,
    reason: "21328 done but the saved place is in world 426, not the tutorial world 3460: the player has moved on and enters where it was saved",
  )
}
