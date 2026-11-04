//// What the server chooses for each kind of creature, as the content load checks
//// it: today how long a creature that died stays dead, and how long a spawn whose
//// creature crashed waits for its next one. A creature has the kind of its
//// Creature2 row when the table has one, and the default row 0 otherwise.
////
//// ```
//// creature_kind rows (genesis_prime/content/creature_kind) ─▶ select(rows, tables)
////   a row of a Creature2 id the client does not hold      ─▶ Refusal
////   a respawn time that is not positive                   ─▶ Refusal
////   no row 0                                              ─▶ Refusal
////   otherwise ─▶ Kinds ─▶ kind_of(kinds, creature2 id)    a map's and a creature's reading
//// ```
////
//// - **Row 0 is the default** every creature without a row of its own takes; the
////   table has to hold it, so a creature always has a kind, and a start without it
////   stops.
//// - **The respawn time** is a server choice: the client holds none
////   (`death.creature_respawn`). A time longer than the idle stop is allowed: a dead
////   creature told to retire stops at its respawn (genesis_prime/world_map/creature).
//// - **Every refusal is collected**, one bad row beside its neighbours, as the
////   other content tables' are (genesis_prime/content).

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}

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
/// row in the client's table, a respawn time below 1, and a table with no default
/// row.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Kinds, List(Refusal)) {
  unbuilt(inputs: #(rows, tables))
}

/// The kind of a creature: its own row's when it has one, else the default.
pub fn kind_of(kinds kinds: Kinds, creature2_id creature2_id: Int) -> Kind {
  unbuilt(inputs: #(kinds, creature2_id))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
