//// The casts a unit create (0x262) lists, so a player that comes into sight
//// of a casting player shows the cast bar the caster holds.
////
//// ```
//// cast state --views--> CastView --entries_of--> UnitCreateCast list
////    (caster's connection)                         (tail.casts of the create)
//// ```
////
//// - The list is a 9-bit count, so 511 entries at most, in cast id order
////   (`opcode.0x262.casts`).
//// - An entry's bit is 1 for a cast whose first go has not gone and 0 after,
////   the client's cast state 2 or 3 (`cast.state`, `RestoreCastFromCreate
////   0x14053da80`).
//// - No entry has cast id 0: the client files such a cast as pending, so
////   `ApplyUnitCreateCasts 0x140458fe0` fails and skips every later entry
////   (`CreateCast 0x140561780`).
//// - An entry lists no target and no position, so the client builds no node
////   and draws no server-placed telegraph row; a cast that is not the unit's
////   current cast has nothing to list and is left out.

import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/table/id.{type Spell4Id}
import gleam/int
import gleam/list

/// The most entries the list's 9-bit count holds.
const most_entries = 511

/// One cast of a unit as the viewer's client is told of it: who casts it, at
/// whom, under which id and spell, and whether its first go has gone. `current`
/// is whether it is the caster's current cast, the one its cast bar shows.
pub type CastView {
  CastView(
    caster_unit_id: Int,
    cast_id: Int,
    spell4_id: Spell4Id,
    primary_target: Int,
    gone: Bool,
    current: Bool,
  )
}

/// The entry of one cast, or `Error(Nil)` for a cast id 0.
pub fn entry_of(view view: CastView) -> Result(UnitCreateCast, Nil) {
  case view.cast_id {
    0 -> Error(Nil)
    cast_id ->
      Ok(
        UnitCreateCast(
          caster_unit_id: view.caster_unit_id,
          primary_target_unit_id: view.primary_target,
          cast_id:,
          spell4_id: view.spell4_id.value,
          started: case view.gone {
            True -> 0
            False -> 1
          },
          targets: [],
          initial_positions: [],
          telegraph_positions: [],
        ),
      )
  }
}

/// The entries a create lists: those of the current casts, in cast id order,
/// at most 511.
pub fn entries_of(views views: List(CastView)) -> List(UnitCreateCast) {
  views
  |> list.filter(fn(view) { view.current })
  |> list.sort(fn(left, right) { int.compare(left.cast_id, right.cast_id) })
  |> list.filter_map(entry_of)
  |> list.take(most_entries)
}
