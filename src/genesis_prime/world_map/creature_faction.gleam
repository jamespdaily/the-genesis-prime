//// The faction the server chooses for a creature in place of the one its Creature2
//// row gives, as the content load checks it. A creature with a row stands with that
//// faction as both its faction and its base faction; a creature without one keeps
//// the faction of its own row. The 0x262 sends the unit's faction, and the client
//// reads it for who may attack whom (opcode.0x262, GetUnitDispositionTo
//// `0x14045a950`), so one value serves combat, the left-out rule, the create and
//// the kill credit.
////
//// ```
//// creature_faction rows (genesis_prime/content/creature_faction) ─▶ select(rows, tables)
////   a row of a Creature2 id the client does not hold ─▶ Refusal
////   a row of a Faction2 id the client does not hold  ─▶ Refusal
////   otherwise ─▶ Factions ─▶ faction_of(factions, creature2 id, own faction)
////                            a spawn's start (spawn.select) and a built row (spawn.creature_row)
//// ```
////
//// - **The Creature2 id** is checked against the client's Creature2 table, as every
////   content table keyed by a creature is.
//// - **The faction** is checked against the client's Faction2 table: the 0x262 field
////   is 14 bits, and a faction the client holds no row for has no relationships.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/table/creature2
import genesis_prime/table/faction2
import genesis_prime/table/id.{Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The table's name in a refusal and in the log.
pub const table = "creature_faction"

/// A row of the creature_faction table: a Creature2 id and the Faction2 id the
/// server gives it.
pub type Row {
  Row(creature_id: Int, faction_id: Int)
}

/// The chosen faction of each creature that has one, by Creature2 id.
pub type Factions {
  Factions(by_creature: Dict(Int, Int))
}

/// No creature has a chosen faction.
pub fn none() -> Factions {
  Factions(by_creature: dict.new())
}

/// The factions of the rows, or every row the load refuses: a Creature2 id or a
/// Faction2 id the client's tables do not hold.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Factions, List(Refusal)) {
  let refused =
    list.filter_map(rows, fn(row) {
      refusal_of(row:, tables:)
      |> result.map(fn(rule) {
        Refusal(table:, row: RowId(row.creature_id), rule:)
      })
    })
  case refused {
    [] -> Ok(taken(rows:))
    refusals -> Error(refusals)
  }
}

/// The factions of the rows `select` takes, leaving out the ones it refuses: the
/// content load checks the spawns with these when it refuses a faction row, so the
/// one start names a bad spawn too (genesis_prime/content).
pub fn taken_of(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Factions {
  taken(
    rows: list.filter(rows, fn(row) {
      result.is_error(refusal_of(row:, tables:))
    }),
  )
}

fn taken(rows rows: List(Row)) -> Factions {
  Factions(
    by_creature: dict.from_list(
      list.map(rows, fn(row) { #(row.creature_id, row.faction_id) }),
    ),
  )
}

/// The first rule the row breaks, or `Error(Nil)` for a row the load takes.
fn refusal_of(
  row row: Row,
  tables tables: table_store.Tables,
) -> Result(String, Nil) {
  case
    creature2.get(tables:, id: Creature2Id(row.creature_id)),
    faction2.get(tables:, id: Faction2Id(row.faction_id))
  {
    Error(Nil), _ -> Ok("the client's Creature2 table has no such creature")
    Ok(..), Error(Nil) ->
      Ok(
        "the client's Faction2 table has no faction "
        <> int.to_string(row.faction_id),
      )
    Ok(..), Ok(..) -> Error(Nil)
  }
}

/// The faction a creature stands with: its chosen one when the table has a row for it,
/// else `own`, the faction its Creature2 row or its spawn row gives.
pub fn faction_of(
  factions factions: Factions,
  creature2_id creature2_id: Int,
  own own: Int,
) -> Int {
  dict.get(factions.by_creature, creature2_id) |> result.unwrap(own)
}
