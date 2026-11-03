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
//// - **A cycle** in the parent chain fails the load, since a walk would never
////   end.
//// - **Built once**, when the tables load (genesis_prime/table/loader/derivation),
////   as one record from zone id to top zone id.

import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}

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
/// `parentZoneId`, or the zone whose parent chain is a cycle.
pub fn from_parents(
  parents _parents: List(#(Int, Int)),
) -> Result(TopZones, TopZoneError) {
  panic as "built in the top zone step"
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
  panic as "built in the top zone step"
}

/// The top zones the tables' load built.
pub fn top_zones(tables _tables: table_store.Tables) -> TopZones {
  panic as "built in the top zone step"
}
