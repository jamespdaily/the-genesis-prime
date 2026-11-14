//// The player a prerequisite check reads, made from what the game connection keeps
//// of the entered character (`genesis_prime/game/connection/prerequisite_player`).
//// Expected values come from these places.
//// - `0x1403b5030` (`GetUnitFormulaLevel`): the level the client's formulas read
////   is the unit's stat 11 when it is not 0, else its stat 10; a unit created
////   with neither is level 1 (`0x1404543c1`). `opcode.0x6bc` is the message that
////   changes a unit's stat, which is how a unit's stat 11 comes to hold a value.
//// - `0x1403c92e0` (type 26): the zone the player is in, then each parent through
////   the WorldZone table's parentZoneId, stopping at a zone with no row.
//// - The character's own row: its race, class, path, gender, and the World it
////   entered.
//// - `0x1403bb170` (type 214) and `0x1403ac590` (types 13, 14 and 246): the checker's
////   ability book is its abilities in bar order, then its innate; its held items are the
////   ones the store saved. `0x140c3a004` (0xF1): the world difficulty the client is told.
//// - The client's WorldZone rows: 1411 under 1305 under 1304; 147 under 1132,
////   which has no row; no row for 99999.

import character_tables
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/loadout
import genesis_prime/game/movement
import genesis_prime/game/world_entry
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/store.{HeldItem}
import genesis_prime/table/id.{Item2Id, Spell4BaseId}
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{None}
import owned_test
import place_support
import world_entry_support

/// The entered character: race 1, class 4, a male on path 3 in World 3460 (the
/// character `world_entry_support.character` makes).
fn entered() -> world_entry.Entered {
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: world_entry_support.character(
        class: 4,
        faction: 166,
        level: 12,
      ),
    )
  entered
}

/// The entered character whose unit holds exactly these stats.
fn with_stats(
  entered entered: world_entry.Entered,
  stats stats: List(#(Int, Int)),
) -> world_entry.Entered {
  world_entry.Entered(
    ..entered,
    unit: UnitCreatePlayer(
      ..entered.unit,
      tail: UnitCreateTail(
        ..entered.unit.tail,
        stats: list.map(stats, fn(stat) {
          unit_fields.integer_stat(stat_id: stat.0, value: stat.1)
        }),
      ),
    ),
  )
}

/// The entered character standing in this zone.
fn standing_in(
  entered entered: world_entry.Entered,
  zone zone: Int,
) -> world_entry.Entered {
  world_entry.Entered(
    ..entered,
    movement: movement.placed(
      state: entered.movement,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: zone,
        x: 1.0,
        y: 2.0,
        z: 3.0,
      ),
    ),
  )
}

pub fn a_players_facts_come_from_its_character_and_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let player = prerequisite_player.of(tables:, entered: entered())
  assert player.race_id == 1 && player.class_id == 4
    as "the character's race and class"
  assert player.path == 3 && player.gender == 0
    as "the character's path and gender"
  assert player.world_id == 3460 as "the World the character entered"
  let level = fn(stats) {
    prerequisite_player.of(
      tables:,
      entered: with_stats(entered: entered(), stats:),
    ).level
  }
  assert level([#(10, 12)]) == 12
    as "stat 10 is the level when there is no stat 11 (0x1403b5030)"
  assert level([#(10, 12), #(11, 0)]) == 12
    as "a stat 11 of 0 is no override (0x1403b5030)"
  assert level([#(10, 12), #(11, 35)]) == 35
    as "a stat 11 that is not 0 is the level the formulas read (0x1403b5030)"
  assert level([]) == 1
    as "a unit created with neither stat is level 1 (0x1404543c1)"
}

pub fn the_players_zones_stop_at_a_parent_with_no_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let zones = fn(zone) {
    prerequisite_player.of(
      tables:,
      entered: standing_in(entered: entered(), zone:),
    ).zones
  }
  assert zones(1411) == [1411, 1305, 1304]
    as "the zone, then each parent up to the top zone (0x1403c92e0)"
  assert zones(147) == [147]
    as "zone 147's parent 1132 has no row: the walk ends at 147"
  assert zones(99_999) == [99_999]
    as "a zone with no row is the one zone the player is in, which a condition on it still matches"
}

pub fn the_checker_comes_from_the_entered_player_test() -> Nil {
  use <- owned_test.run(60_000)
  let held =
    HeldItem(
      item_guid: 41,
      item2_id: Item2Id(84_957),
      location: 1,
      bag_index: 3,
      stack_count: 1,
      random_stats: 0,
    )
  let entered =
    world_entry.Entered(
      ..entered(),
      items: [held],
      loadout: loadout.Loadout(
        ..entered().loadout,
        abilities: [Spell4BaseId(8740), Spell4BaseId(2823)],
        innate: None,
      ),
    )
  let checker = prerequisite_player.checker_of(entered:)
  assert checker.items == [held]
    as "the items the character holds, as the store saved them"
  assert checker.book == [Spell4BaseId(8740), Spell4BaseId(2823)]
    as "the ability book is the abilities in bar order (0x1403bb170)"
  assert checker.world_difficulty == world_entry.world_difficulty
    as "the world difficulty is the one 0xF1 tells the client"
}
