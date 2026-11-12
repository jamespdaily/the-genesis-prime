//// The top zone of each WorldZone: the zone whose chat a player under a zone
//// shares. The client reports the most specific zone its terrain names and
//// names a zone channel after exactly the zone it is given, never walking to a
//// parent (`opcode.0xf2`, `opcode.0x63a`, `0x140403670`), so the server rolls
//// the reported zone up itself (`chat.zone_reach`, Jim 2026-11-03).
////
//// ```
//// the WorldZone table loads ─▶ derivation: for each row, walk parentZoneId
////                              until a row whose parent is 0 ─▶ TopZones
//// a reported zone id         ─▶ of(top_zones, id) ─▶ the top zone's id, or no row
//// ```
////
//// - **The walk** follows `parentZoneId` until it reaches a row whose parent is
////   0. A parent id with no row stops the walk at the last row that exists (122
////   rows end so, such as the ones that name zone 1132): the client never walks
////   the chain, so where it stops is the server's choice.
//// - **The chain** of a zone is the zone and its parents up to the top zone, the walk's
////   steps (`chain`).
//// - **A cycle** in the parent chain fails the load, since a walk would never
////   end.
//// - **Built once**, when the tables load (genesis_prime/table/loader/derivation),
////   as one record from zone id to top zone id.

import genesis_prime/table/id.{WorldZoneId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/world_zone
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}

/// Each WorldZone id with its top zone's id.
pub opaque type TopZones {
  TopZones(top_of: Dict(Int, Int))
}

/// Why the top zones cannot be built.
pub type TopZoneError {
  /// The parent chain of this zone leads back to itself.
  ParentCycle(zone_id: Int)
}

/// The top zones of the zones given as pairs of a zone's id and its
/// `parentZoneId`, or the first zone, in the order given, whose parent chain is a
/// cycle.
pub fn from_parents(
  parents parents: List(#(Int, Int)),
) -> Result(TopZones, TopZoneError) {
  let parent_of = dict.from_list(parents)
  list.try_map(parents, fn(pair) {
    chain_over(
      parent_of: dict.get(parent_of, _),
      start: pair.0,
      zone: pair.0,
      seen: set.new(),
    )
    |> result.map(fn(zones) {
      let assert Ok(top) = list.last(zones) as "a chain holds its own zone"
      #(pair.0, top)
    })
  })
  |> result.map(fn(tops) { TopZones(top_of: dict.from_list(tops)) })
}

/// The chain of the walk from `start`, which is at `zone`: the zone, then the chain of
/// its parent when the parent is not 0 and has a row. A zone met twice is the cycle.
fn chain_over(
  parent_of parent_of: fn(Int) -> Result(Int, Nil),
  start start: Int,
  zone zone: Int,
  seen seen: Set(Int),
) -> Result(List(Int), TopZoneError) {
  use <- bool.guard(
    when: set.contains(seen, zone),
    return: Error(ParentCycle(zone_id: start)),
  )
  case parent_of(zone) {
    Ok(parent) if parent != 0 ->
      case parent_of(parent) {
        Ok(_) ->
          chain_over(
            parent_of:,
            start:,
            zone: parent,
            seen: set.insert(seen, zone),
          )
          |> result.map(list.prepend(_, zone))
        Error(Nil) -> Ok([zone])
      }
    Ok(_) | Error(Nil) -> Ok([zone])
  }
}

/// The zone, then its parents up to its top zone, or none when the table holds no
/// row for the zone. The tables' load refuses a cycle before any caller holds the
/// tables (`derivation`).
pub fn chain(
  tables tables: table_store.Tables,
  world_zone_id world_zone_id: Int,
) -> List(Int) {
  let parent_of = fn(id) {
    world_zone.get(tables:, id: WorldZoneId(id))
    |> result.map(fn(row) { row.parent_zone_id })
  }
  case parent_of(world_zone_id) {
    Error(Nil) -> []
    Ok(_) -> {
      let assert Ok(zones) =
        chain_over(
          parent_of:,
          start: world_zone_id,
          zone: world_zone_id,
          seen: set.new(),
        )
        as "the tables' load refused every parentZoneId cycle"
      zones
    }
  }
}

/// The zone, then its parents up to its top zone, as the walk the client's zone check
/// makes (0x1403c92e0, `Prerequisite.prerequisiteTypeId.26`): a zone with no row has no
/// parent to walk to, so it is the one zone it is in.
pub fn chain_or_zone(
  tables tables: table_store.Tables,
  world_zone_id world_zone_id: Int,
) -> List(Int) {
  case chain(tables:, world_zone_id:) {
    [] -> [world_zone_id]
    zones -> zones
  }
}

/// The top zone of the zone, or `Error(Nil)` when the table holds no row for
/// it. Zone 0 is no zone and has no row.
pub fn of(
  top_zones top_zones: TopZones,
  world_zone_id world_zone_id: Int,
) -> Result(Int, Nil) {
  let TopZones(top_of:) = top_zones
  dict.get(top_of, world_zone_id)
}

/// The top zones as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`); a cycle fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: top_zones_key, build: fn(tables) {
    world_zone.all(tables)
    |> list.map(fn(row) { #(row.id, row.parent_zone_id) })
    |> from_parents
    |> result.map_error(fn(error) {
      let ParentCycle(zone_id:) = error
      "the parent chain of WorldZone "
      <> int.to_string(zone_id)
      <> " is a cycle"
    })
  })
}

/// The key of the top zones in the tables' store.
const top_zones_key: table_store.DerivedKey(TopZones) =
  table_store.DerivedKey("TopZones")

/// The top zones the tables' load built.
pub fn top_zones(tables tables: table_store.Tables) -> TopZones {
  table_store.derived(tables:, key: top_zones_key)
}
