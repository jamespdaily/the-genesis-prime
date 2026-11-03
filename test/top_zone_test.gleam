//// The top zone of each WorldZone (genesis_prime/game/top_zone): the walk up
//// `parentZoneId` to the row whose parent is 0, from the planted rows, which are
//// the client's own rows (`character_tables.world_zones`), and from the real
//// table where the client is present.

import character_tables
import client_tables
import genesis_prime/game/top_zone
import genesis_prime/table/id.{WorldZoneId}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/world_zone
import gleam/erlang/reference
import gleam/list
import gleam/result
import owned_test
import planted_table
import unitest

fn planted() -> top_zone.TopZones {
  let assert Ok(zones) = top_zone.from_parents(character_tables.world_zones())
    as "the planted rows have no cycle"
  zones
}

pub fn a_zone_with_parent_0_is_its_own_top_test() -> Nil {
  use <- owned_test.run(5000)
  assert top_zone.of(planted(), 248) == Ok(248)
    as "WorldZone row 248 has parentZoneId 0 (chat.zone_reach: the walk ends at a row whose parent is 0)"
  assert top_zone.of(planted(), 35) == Ok(35)
    as "WorldZone row 35 has parentZoneId 0"
}

pub fn a_zone_7_parents_below_its_top_maps_to_the_top_test() -> Nil {
  use <- owned_test.run(5000)
  assert top_zone.of(planted(), 1755) == Ok(248)
    as "WorldZone 1755 -> 378 -> 1777 -> 382 -> 1778 -> 1738 -> 1580 -> 248, whose parent is 0"
  assert top_zone.of(planted(), 1411) == Ok(1304)
    as "WorldZone 1411 -> 1305 -> 1304"
  assert top_zone.of(planted(), 1305) == Ok(1304)
    as "WorldZone 1305 -> 1304: the zones of one top zone share it"
}

pub fn a_broken_chain_stops_at_the_last_row_that_exists_test() -> Nil {
  use <- owned_test.run(5000)
  assert top_zone.of(planted(), 147) == Ok(147)
    as "WorldZone 147's parent 1132 has no row, so the walk stops at 147 (the coordinator's choice: the client never walks the chain)"
  let assert Ok(zones) =
    top_zone.from_parents([#(20, 10), #(10, 1132), #(30, 20)])
    as "no cycle"
  assert top_zone.of(zones, 30) == Ok(10)
    as "a chain 30 -> 20 -> 10 -> 1132 stops at 10, the last row above 30 that exists"
}

pub fn a_zone_with_no_row_has_no_top_zone_test() -> Nil {
  use <- owned_test.run(5000)
  assert top_zone.of(planted(), 1132) == Error(Nil)
    as "WorldZone 1132 has no row"
  assert top_zone.of(planted(), 0) == Error(Nil)
    as "zone 0 is no zone and has no row"
}

pub fn a_cycle_in_the_parent_chain_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert top_zone.from_parents([#(1, 2), #(2, 1)])
    |> result.is_error
    as "a walk of two zones that name each other never ends"
  assert top_zone.from_parents([#(5, 5)]) |> result.is_error
    as "a zone that is its own parent is a cycle"
  assert top_zone.from_parents([#(7, 8), #(8, 9), #(9, 7), #(3, 7)])
    == Error(top_zone.ParentCycle(zone_id: 7))
    as "the first zone in the table's order whose walk finds a cycle is named, here 7"
}

pub fn a_load_with_a_cycle_in_the_parent_chain_fails_test() -> Nil {
  use <- owned_test.run(10_000)
  use folder <- planted_table.in_folder(
    character_tables.files_with_zones(zones: [#(1, 2), #(2, 1)]),
  )
  let key = reference.new()
  let assert Error(store.DerivationFailed(name: "TopZones", ..)) =
    server_table.load_under(under: key, from: folder)
    as "CLAUDE.md: a table the server cannot read fails the load; a cycle has no top zone"
  assert planted_table.persistent_terms_under(key) == 0
    as "the failed load erased what it wrote"
}

pub fn the_planted_load_builds_the_top_zones_once_test() -> Nil {
  use <- owned_test.run(10_000)
  assert top_zone.of(top_zone.top_zones(character_tables.shared()), 1755)
    == Ok(248)
    as "the tables' load built the top zones from the planted rows"
}

pub fn the_planted_zone_rows_are_the_clients_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  list.each(character_tables.world_zones(), fn(zone) {
    let #(id, parent) = zone
    let assert Ok(row) = world_zone.get(tables: real, id: WorldZoneId(id))
      as "the planted zone has a row in the client's table"
    assert row.parent_zone_id == parent
      as "WorldZone: the planted parentZoneId is the real one"
  })
  assert world_zone.get(tables: real, id: WorldZoneId(1132)) == Error(Nil)
    as "WorldZone has no row 1132, the parent of 147"
}

pub fn against_the_real_table_111_rows_are_their_own_top_and_every_row_has_a_top_that_exists_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  let zones = top_zone.top_zones(real)
  let rows = world_zone.all(real)
  assert list.length(rows) == 3436
    as "chat.zone_reach: the WorldZone table has 3,436 rows"
  assert list.count(rows, fn(row) { row.parent_zone_id == 0 }) == 111
    as "chat.zone_reach: 3,325 of the 3,436 rows have a parent, so 111 have none"
  list.each(rows, fn(row) {
    let assert Ok(top) = top_zone.of(zones, row.id)
      as "every row of the table has a top zone"
    assert result.is_ok(world_zone.get(tables: real, id: WorldZoneId(top)))
      as "the top zone is a row of the table"
    assert row.parent_zone_id != 0 || top == row.id
      as "a row with parent 0 is its own top"
  })
}
