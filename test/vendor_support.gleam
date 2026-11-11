//// Vendors for a test to stock a creature with: the content load's own `vendor.select`
//// over the client's committed rows, so a creature and an item a test names are rows the
//// client has.

import character_tables
import game_connection_support as connection_support
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/game/vendor.{type Vendors, ItemRow, VendorRow}
import genesis_prime/table/id
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/creature_path
import gleam/dict
import gleam/list
import spawn_support

/// The Item2 ids a test stocks: the first three of Supplier Ingavak's list, rows of the
/// committed Item2 table.
pub const items = [12_078, 14_838, 20_791]

/// The 22 Item2 ids Supplier Ingavak (Creature2 28739) sells, in the order of his
/// Jabbithole page, all rows of the committed Item2 table.
pub const ingavaks_items = [
  12_078, 14_838, 20_791, 13_176, 13_185, 13_194, 13_188, 12_044, 13_191, 13_179,
  13_151, 13_154, 13_166, 27_874, 27_873, 27_876, 13_157, 13_163, 27_875, 13_169,
  13_148, 13_160,
]

/// The vendors of these creatures, each selling `items` at positions 1, 2 and 3, with
/// the multipliers the content migration gives every vendor, 1.0.
pub fn stocking(creature_ids creature_ids: List(Int)) -> Vendors {
  stocking_items(creature_ids:, items:)
}

/// The vendors of these creatures, each selling `items` from position 1.
pub fn stocking_items(
  creature_ids creature_ids: List(Int),
  items items: List(Int),
) -> Vendors {
  let rows = list.map(creature_ids, fn(id) { VendorRow(id, 1.0, 1.0) })
  let stock =
    list.flat_map(creature_ids, fn(id) {
      list.index_map(items, fn(item, index) { ItemRow(id, index + 1, item) })
    })
  let assert Ok(vendors) =
    vendor.select(
      vendors: rows,
      items: stock,
      tables: character_tables.shared(),
    )
    as "the creatures and items of the support are rows of the client's committed tables"
  vendors
}

/// The player's hit radius (Race.hitRadius, 0x3f99999a, every playable race) and Dorian
/// Walker's (Creature2DisplayInfo 25510's hitRadius, 0x3f8ccccd).
pub const player_radius = 1.2

pub const walker_radius = 1.1

/// The unit Dorian Walker is in `picture_with_walker`.
pub const walker_unit = 40

/// Dorian Walker (Creature2 74812, alive, Hostile to neither faction) as unit 40 in a
/// picture, `gap` from the player's edge straight ahead of the player at the entry place,
/// with another player's unit 9: what a rule that reads the connection's picture sees.
pub fn picture_with_walker(gap gap: Float) -> shown.Picture {
  let entry = connection_support.entry_place()
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry) -. { gap +. player_radius +. walker_radius },
    )
  let walker = spawn_support.dorian_walker(number: 1, place:)
  dict.from_list([
    #(
      walker_unit,
      shown.ShownCreature(
        creature_id: id.Creature2Id(74_812),
        faction_id: 0,
        checklist_index: 0,
        path: creature_path.Standing(at: place),
        life: 4,
        alive: True,
        hit_radius: walker.combat.hit_radius,
        attackable: walker.combat.attackable,
        hostile_to: Hostile(exile: False, dominion: False),
      ),
    ),
    #(9, shown.ShownPlayer),
  ])
}
