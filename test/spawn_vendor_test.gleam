//// Which spawns of the world database are vendors (`genesis_prime/world_map/spawn`
//// `select`): a spawn is a vendor exactly when its creature is in the vendors' creature
//// set, which is what `vendor.is_vendor` answered for the same creature over the
//// `Vendors` the set is made from. Expected values: `vendor.is_vendor`, the rule the set
//// replaced; the vendors here are every third creature of the stored spawns, since the
//// retail vendor stock is a content table and no rule picks creatures.

import client_tables
import content_support
import database_support
import envoy
import genesis_prime/content/creature_faction as content_creature_faction
import genesis_prime/game/vendor.{ItemRow, VendorRow}
import genesis_prime/import_world_data
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/spawn
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import owned_test
import rating_support
import spawn_support
import unitest

pub fn a_spawn_is_a_vendor_exactly_when_its_creature_id_is_in_the_vendors_creature_set_test() -> Nil {
  // deadline: 19 s measured: the world database is imported and every spawn row is checked once
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  let assert Ok(folder) = envoy.get("GENESIS_WORLD_DATA")
    as "the guard saw the variable"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder:,
    )
    as "the world database imports"
  let stored = content_support.stored_spawns(database:)
  let tables = client_tables.with_content_tables()
  let assert Ok(faction_rows) =
    content_creature_faction.rows(db: content_support.connect(database:))
    as "the creature_faction table reads"
  let assert Ok(factions) = creature_faction.select(rows: faction_rows, tables:)
    as "the chosen factions pass the load's own check"
  let creature_ids =
    stored
    |> list.map(fn(row) { row.creature_id })
    |> list.unique
    |> list.sort(int.compare)
  let sellers =
    list.index_map(creature_ids, fn(creature_id, index) {
      #(creature_id, index)
    })
    |> list.filter(fn(entry) { entry.1 % 3 == 0 })
    |> list.map(fn(entry) { entry.0 })
  let assert Ok(vendors) =
    vendor.select(
      vendors: list.map(sellers, fn(creature_id) {
        VendorRow(creature_id, 1.0, 1.0)
      }),
      items: list.map(sellers, fn(creature_id) {
        ItemRow(creature_id, 1, 12_078)
      }),
      tables:,
    )
    as "the creatures and the item are rows of the client's tables"
  let selection =
    spawn.select(
      rows: stored,
      tables:,
      formulas: rating_support.formulas(),
      kinds: spawn_support.turret_kinds(),
      factions:,
      vendor_creatures: set.from_list(vendor.creatures(vendors:)),
    )
  assert selection.refusals == []
    as "the world database's rows pass the load's checks"
  let started =
    selection.worlds
    |> dict.values
    |> list.flat_map(fn(world) { dict.values(world.by_id) })
  assert started != [] as "the world database starts spawns"
  list.each(started, fn(started_spawn) {
    assert started_spawn.vendor
      == vendor.is_vendor(vendors:, creature_id: started_spawn.creature_id)
      as "a spawn is a vendor exactly when its creature is one"
  })
  assert list.any(started, fn(started_spawn) { started_spawn.vendor })
    as "some spawn is a vendor"
  assert list.any(started, fn(started_spawn) { !started_spawn.vendor })
    as "some spawn is not"
}
