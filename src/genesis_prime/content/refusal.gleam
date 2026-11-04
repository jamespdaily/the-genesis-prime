//// A row of a content table that the load refuses, named by its table, its key
//// and the rule it breaks. The load collects every refusal of every table, logs
//// them all and then stops the start, so one bad row shows its neighbours
//// (genesis_prime/content).

import gleam/int

/// One refused row: the table's name, the row's key and the rule it breaks, in
/// words.
pub type Refusal {
  Refusal(table: String, row: Row, rule: String)
}

/// The key a content table names its rows by: a number (a spawn, a creature
/// kind) or a name (a game number).
pub type Row {
  RowId(id: Int)
  RowName(name: String)
}

/// The refusal as one line of the log and of the message the start stops with.
pub fn describe(refusal refusal: Refusal) -> String {
  "the table "
  <> refusal.table
  <> " row "
  <> case refusal.row {
    RowId(id:) -> int.to_string(id)
    RowName(name:) -> name
  }
  <> " is refused: "
  <> refusal.rule
}
