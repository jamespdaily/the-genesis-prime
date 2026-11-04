//// What the server chooses for each kind of creature, as the content load checks
//// it: today how long a creature that died stays dead, and how long a spawn whose
//// creature crashed waits for its next one. A creature has the kind of its
//// Creature2 row when the table has one, and the default row 0 otherwise.
////
//// ```
//// creature_kind rows (genesis_prime/content/creature_kind) ─▶ select(rows, tables)
////   a row of a Creature2 id the client does not hold      ─▶ Refusal
////   a respawn time below the strike deadline              ─▶ Refusal
////   no row 0                                              ─▶ Refusal
////   otherwise ─▶ Kinds ─▶ kind_of(kinds, creature2 id)    a map's and a creature's reading
//// ```
////
//// - **Row 0 is the default** every creature without a row of its own takes; the
////   table has to hold it, so a creature always has a kind, and a start without it
////   stops.
//// - **Who reads it.** A creature starts its corpse timer from its kind's respawn time, and a
////   map waits that long before it starts a spawn's creature again after a crash, so the
////   one number is the only source of both (genesis_prime/world_map/creature,
////   genesis_prime/world_map/map).
//// - **The respawn time** is a server choice: the client holds none
////   (`death.creature_respawn`). A time longer than the idle stop is allowed: a dead
////   creature told to retire stops at its respawn (genesis_prime/world_map/creature).
//// - **Every refusal is collected**, one bad row beside its neighbours, as the
////   other content tables' are (genesis_prime/content).

import genesis_prime/content/refusal.{type Refusal, Refusal}
import genesis_prime/game/strike_tell
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The table's name in a refusal.
const table = "creature_kind"

/// One row of the creature_kind table as the load reads it: the Creature2 id the
/// row is for (0 for the default) and the respawn time in milliseconds.
pub type Row {
  Row(creature_id: Int, respawn_ms: Int)
}

/// What the server chose for a kind of creature.
pub type Kind {
  Kind(respawn_ms: Int)
}

/// The kinds the load put in its term: the default and each creature that has a
/// row of its own.
pub type Kinds {
  Kinds(default: Kind, by_creature: Dict(Int, Kind))
}

/// The kinds of the rows, or every row the load refuses: a Creature2 id that has no
/// row in the client's table, a respawn time below the strike deadline (1000 ms), and a table with no default
/// row.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, List(Refusal)) {
  let default = list.find(rows, fn(row) { row.creature_id == 0 })
  let missing_default = case default {
    Ok(..) -> []
    Error(Nil) -> [
      Refusal(
        table: table,
        id: 0,
        rule: "the table has no default row 0, which every creature without a row of its own takes",
      ),
    ]
  }
  let refused =
    list.filter_map(rows, fn(row) {
      case
        row.creature_id != 0
        && result.is_error(creature2.get(
          tables:,
          id: Creature2Id(row.creature_id),
        ))
      {
        True ->
          Ok(Refusal(
            table: table,
            id: row.creature_id,
            rule: "the client's Creature2 table has no such creature",
          ))
        False ->
          case row.respawn_ms < strike_tell.deadline_ms {
            True ->
              Ok(Refusal(
                table: table,
                id: row.creature_id,
                rule: "a respawn time of "
                  <> int.to_string(row.respawn_ms)
                  <> " ms is below the strike deadline of "
                  <> int.to_string(strike_tell.deadline_ms)
                  <> " ms",
              ))
            False -> Error(Nil)
          }
      }
    })
  case list.append(missing_default, refused), default {
    [], Ok(default) ->
      Ok(Kinds(
        default: Kind(respawn_ms: default.respawn_ms),
        by_creature: list.filter(rows, fn(row) { row.creature_id != 0 })
          |> list.map(fn(row) {
            #(row.creature_id, Kind(respawn_ms: row.respawn_ms))
          })
          |> dict.from_list,
      ))
    refusals, _ -> Error(refusals)
  }
}

/// The kind of a creature: its own row's when it has one, else the default.
pub fn kind_of(kinds kinds: Kinds, creature2_id creature2_id: Int) -> Kind {
  dict.get(kinds.by_creature, creature2_id)
  |> result.unwrap(kinds.default)
}
