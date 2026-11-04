//// The reshape that moved the loadout into the map's unit changes nothing a
//// client reads: for every class and faction a player can make (each Novice
//// CharacterCreation row), the 0x262 the map's unit builds equals the 0x262 the
//// map built before the move and world entry then rewrote with the gear. The old
//// behaviour is kept here as the oracle, the two functions below: the unit with
//// the stand-in health 136 (the client's level-1 creature Base Health,
//// `0x1404585c0`) and the rewrite of its stats and properties by the gear. They
//// are what step B (the loadout step) sent, which its own tests checked
//// against the client's formulas (`player.level1_gear_properties`).
////
//// The oracle's expected values are not read from the unit this change builds,
//// and the rewrite is not shared with it.

import character_support
import character_tables
import client_tables
import genesis_prime/game/item_property.{Shield}
import genesis_prime/game/loadout
import genesis_prime/game/start_place
import genesis_prime/message/float32
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/store.{type Character, Character}
import genesis_prime/table/character_creation
import genesis_prime/table/id.{ClassId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/player_unit
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import place_support
import unitest

/// The Novice start enum of CharacterCreation (`Item2.novice_set`).
const novice_start = 4

/// Step B's unit: the map's record with the stand-in health 136, then the gear
/// applied to it by stats 0 (maximum health), 10 (the level), 20 (the full
/// shield) and the properties 7, 35, 36, 42 and the shield's 41, 175, 176, 178
/// in the order of their ids, each as base and value alike.
fn step_b(
  character character: Character,
  place place: start_place.Place,
  unit_id unit_id: Int,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
) -> UnitCreatePlayer {
  let assert Ok(set) =
    loadout.of(
      tables:,
      class_id: character.class_id,
      faction_id: character.faction_id,
    )
    as "the Novice set of a row a player can make"
  let assert Ok(max_health) =
    loadout.max_health(tables:, loadout: set, level: character.level)
    as "CreatureLevel holds the level"
  let store.CharacterId(character_id) = character.character_id
  let stand_in = 136
  let health = float32.to_bits(int.to_float(stand_in))
  let #(position, rotation) = player_unit.standing(place:)
  let record =
    UnitCreatePlayer(
      unit_id:,
      character_id:,
      realm_id:,
      name: character.name,
      race_id: character.race_id.value,
      class_id: character.class_id.value,
      gender: character.gender,
      group_id: 0,
      owned_unit_ids: [],
      guild_name: "",
      guild_type: 0,
      guild_ids: [],
      bone_values: character.bones,
      pvp_flags: 0,
      premium_tier: 0,
      title_id: 0,
      tail: UnitCreateTail(
        create_flags: 0,
        stats: [
          UnitStat(stat_id: 0, value: stand_in),
          UnitStat(stat_id: 10, value: character.level),
        ],
        server_time_estimate_start: 0,
        movement_commands: [
          start_movement.Position(position),
          start_movement.Rotation(rotation),
        ],
        properties: [
          UnitProperty(property_id: 7, field_2: health, value: health),
        ],
        item_visuals: loadout.item_visuals(loadout: set),
        cast_id: 0,
        faction_id: character.faction_id,
        base_faction_id: character.faction_id,
        tagged_by_unit_id: 0,
        tagged_by_group_id: 0,
        field_14: 0,
        field_16: 0,
        world_socket_id: 0,
        cluster_id: 0,
        field_20: 0,
        minimap_marker_id: 0,
        display_info_id: 0,
        outfit_info_id: 0,
      ),
    )
  let gear = set.properties
  let shield_stats = case gear.shield {
    Some(Shield(capacity_max:, ..)) -> [
      UnitStat(stat_id: 20, value: float.round(capacity_max)),
    ]
    None -> []
  }
  let shield_properties = case gear.shield {
    Some(Shield(capacity_max:, mitigation_max:, regen_percent:, reboot_time_ms:)) -> [
      #(41, capacity_max),
      #(175, mitigation_max),
      #(176, regen_percent),
      #(178, int.to_float(reboot_time_ms)),
    ]
    None -> []
  }
  let properties =
    list.flatten([
      [
        #(7, int.to_float(max_health)),
        #(35, gear.assault_rating),
        #(36, gear.support_rating),
        #(42, gear.armor),
      ],
      shield_properties,
    ])
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.map(fn(pair) {
      let bits = float32.to_bits(pair.1)
      UnitProperty(property_id: pair.0, field_2: bits, value: bits)
    })
  UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..record.tail,
      stats: list.flatten([
        [
          UnitStat(stat_id: 0, value: max_health),
          UnitStat(stat_id: 10, value: character.level),
        ],
        shield_stats,
      ]),
      properties:,
    ),
  )
}

/// Every Novice class and faction of the tables, once each, at levels 1 and 3,
/// through the old unit and the new one.
fn every_row_is_unchanged(tables tables: table_store.Tables) -> Int {
  let pairs =
    character_creation.all(tables)
    |> list.filter(fn(row) {
      row.character_creation_start_enum == novice_start
      && row.enabled
      && !row.costume_only
    })
    |> list.map(fn(row) { #(row.class_id, row.faction_id) })
    |> set.from_list
    |> set.to_list
  list.each(pairs, fn(pair) {
    list.each([1, 3], fn(level) {
      let character =
        Character(
          ..character_support.character(number: 5),
          class_id: ClassId(pair.0),
          faction_id: pair.1,
          level:,
        )
      let place = place_support.live_character_place()
      let old = step_b(character:, place:, unit_id: 9, realm_id: 4, tables:)
      let assert Ok(set) =
        loadout.of(tables:, class_id: character.class_id, faction_id: pair.1)
        as "the Novice set of a row a player can make"
      let assert Ok(max_health) =
        loadout.max_health(tables:, loadout: set, level:)
        as "CreatureLevel holds the level"
      let new =
        player_unit.create(
          unit: player_unit.new(
            character:,
            place:,
            unit_id: 9,
            body: [],
            loadout: set,
            max_health:,
          ),
          realm_id: 4,
        )
      assert new == old
        as {
          "class "
          <> int.to_string(pair.0)
          <> " faction "
          <> int.to_string(pair.1)
          <> " level "
          <> int.to_string(level)
          <> ": the map's 0x262 is what the map and world entry made before the move"
        }
    })
  })
  list.length(pairs)
}

pub fn the_map_builds_the_0x262_step_b_sent_for_every_novice_class_and_faction_of_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let rows = every_row_is_unchanged(tables: client_tables.shared())
  assert rows >= 12
    as "the client's Novice rows hold six classes in both factions (`player.level1_gear_properties`), so the proof ran over them"
}

pub fn the_map_builds_the_0x262_step_b_sent_for_the_planted_novice_rows_test() -> Nil {
  use <- owned_test.run(20_000)
  let rows = every_row_is_unchanged(tables: character_tables.shared())
  assert rows >= 1 as "the planted tables hold a Novice row, so the proof ran"
}

pub fn the_oracle_differs_from_a_unit_with_another_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  let character = character_support.character(number: 5)
  let place = place_support.live_character_place()
  let old = step_b(character:, place:, unit_id: 9, realm_id: 4, tables:)
  let assert Ok(set) =
    loadout.of(
      tables:,
      class_id: character.class_id,
      faction_id: character.faction_id,
    )
    as "the planted tables hold the Novice set of the tests' character"
  let other =
    player_unit.create(
      unit: player_unit.new(
        character:,
        place:,
        unit_id: 9,
        body: [],
        loadout: set,
        max_health: 1,
      ),
      realm_id: 4,
    )
  assert other != old
    as "the proof can fail: a unit made with another health is not the oracle's"
}
