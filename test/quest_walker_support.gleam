//// A shown Dorian Walker (Creature2 74812), the creature of the tutorial that gives quest
//// 10528 and receives quest 10520, for the quest tests that need a creature in reach.

import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, CreatureAppeared,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/step.{type ConnectionEvent, type Event}
import genesis_prime/store
import genesis_prime/table/id
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{Attackable, Hostile}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/creature_unit_type.{NonPlayer}
import genesis_prime/world_map/spawn.{Spawn}
import gleam/dict
import gleam/option
import spawn_support

/// Dorian Walker (Creature2 74812) as unit 40 in a picture, `gap` from the player's edge,
pub fn walker(
  gap gap: Float,
  alive alive: Bool,
  hostile hostile: Bool,
) -> shown.Picture {
  let entry = connection_support.entry_place()
  // The gap is between the two edges: the player's hit radius 1.2 (Race.hitRadius) and
  // Dorian Walker's 1.1 (Creature2DisplayInfo 25510) lie in between (`0x1403ad690`).
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry) -. { gap +. 1.2 +. 1.1 },
    )
  dict.from_list([
    #(
      40,
      shown.ShownCreature(
        creature_id: id.Creature2Id(74_812),
        faction_id: 0,
        checklist_index: 0,
        path: creature_path.Standing(at: place),
        life: 4,
        alive:,
        hit_radius: 1.1,
        attackable: creature_life.Attackable(exile: True, dominion: True),
        hostile_to: creature_life.Hostile(exile: hostile, dominion: hostile),
      ),
    ),
  ])
}

/// The connection of the tests' character in the world with these quest rows saved and
/// these tables, Dorian Walker shown to it as unit 40.
pub fn in_world_with_walker(
  tables tables: table_store.Tables,
  quests quests: List(store.QuestRow),
) -> game_connection.State {
  connection_support.feed(
    state: in_world(tables:, quests:),
    event: walker_appears(),
  ).0
}

/// The same connection with no creature shown to it.
pub fn in_world(
  tables tables: table_store.Tables,
  quests quests: List(store.QuestRow),
) -> game_connection.State {
  in_world_as(tables:, quests:, character: connection_support.world_character())
}

/// The same for a character of the test's choosing, for a quest whose rule reads the faction.
pub fn in_world_as(
  tables tables: table_store.Tables,
  quests quests: List(store.QuestRow),
  character character: store.Character,
) -> game_connection.State {
  let #(accepted, _) =
    connection_support.accepted(
      Settings(..connection_support.settings(), tables:),
    )
  let #(state, taken) =
    connection_support.joining_holding(
      in_character_select: connection_support.in_select_from(accepted),
      character:,
      saved_health: option.None,
      saved_experience: option.None,
      quests:,
    )
  connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(
      client_connection.FromMap(connection_support.map_answer(taken)),
    ),
  ).0
}

/// The 0x262 news of Dorian Walker as unit 40, as his process sends it, standing 1.0 from the
/// player's edge as `walker` does.
pub fn walker_appears() -> Event(ConnectionEvent(Message, Answer)) {
  let assert Ok(shown_walker) =
    dict.get(walker(gap: 1.0, alive: True, hostile: False), 40)
    as "the picture holds unit 40"
  let assert shown.ShownCreature(path: creature_path.Standing(at: place), ..) =
    shown_walker
    as "the walker stands"
  let beast = spawn_support.beast_at(number: 1, place:)
  let spawned =
    Spawn(
      ..beast,
      creature_id: id.Creature2Id(74_812),
      combat: creature_life.Combat(
        ..beast.combat,
        hit_radius: 1.1,
        attackable: Attackable(exile: True, dominion: True),
        hostile_to: Hostile(exile: False, dominion: False),
      ),
    )
  connection_support.sent_by_a_peer(connection_support.news_of(
    unit_id: 40,
    news: CreatureAppeared(
      unit_type: NonPlayer,
      unit: creature_unit.create(
        spawn: spawned,
        unit_id: 40,
        health: 52,
        interrupt_armor: option.None,
        server_time_estimate_start: 0,
      ),
      life: 4,
      place:,
      hit_radius: 1.1,
      attackable: spawned.combat.attackable,
      hostile_to: spawned.combat.hostile_to,
    ),
  ))
}
