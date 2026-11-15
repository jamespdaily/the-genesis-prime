//// The spell whose node on a unit is Spell Surge, read once at the tables' load.
//// IsSpellSurgeActive `0x1405e7d10` tests for a node of GameFormula 913's dataint0 (47439),
//// and SpellslingerSurgedSpell `0x1405e7e50` swaps a press to the ability's alternate
//// while one is held (`genesis_prime/game/cast`). A missing row fails the load.

import genesis_prime/table/game_formula
import genesis_prime/table/id.{type Spell4Id, GameFormulaId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/result

/// The formula the client reads the Surge spell from.
const surge_formula = 913

const surge_key: table_store.DerivedKey(Spell4Id) =
  table_store.DerivedKey("SpellSurge")

/// The Surge spell as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`).
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: surge_key, build: fn(tables) {
    game_formula.get(tables:, id: GameFormulaId(surge_formula))
    |> result.map(fn(row) { Spell4Id(row.dataint0) })
    |> result.replace_error("no GameFormula row 913, the Spell Surge spell")
  })
}

/// The Surge spell the tables' load built.
pub fn spell(tables tables: table_store.Tables) -> Spell4Id {
  table_store.derived(tables:, key: surge_key)
}
