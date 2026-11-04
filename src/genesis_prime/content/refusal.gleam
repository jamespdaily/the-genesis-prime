//// A row of a content table that the load refuses, named by its table, its id
//// and the rule it breaks. The load collects every refusal of every table, logs
//// them all and then stops the start, so one bad row shows its neighbours
//// (genesis_prime/content).

import gleam/int

/// One refused row: the table's name, the row's id and the rule it breaks, in
/// words.
pub type Refusal {
  Refusal(table: String, id: Int, rule: String)
}

/// The refusal as one line of the log and of the message the start stops with.
pub fn describe(refusal refusal: Refusal) -> String {
  "the table "
  <> refusal.table
  <> " row "
  <> int.to_string(refusal.id)
  <> " is refused: "
  <> refusal.rule
}
