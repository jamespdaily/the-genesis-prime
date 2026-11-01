//// A rule's table of the client messages it takes: each entry is a message id
//// and what the message is to the rule. A rule keeps one such table, finds
//// what a frame's id is in it with `of`, and lists its ids with `ids`, so what
//// the rule takes and what it names cannot differ. The coverage measure reads
//// the ids each rule names.

import gleam/list
import gleam/result

/// What the message with this id is in the table, or `otherwise` when the rule
/// takes no such message.
pub fn of(
  table table: List(#(Int, message)),
  message_id message_id: Int,
  otherwise otherwise: message,
) -> message {
  list.key_find(table, message_id)
  |> result.unwrap(otherwise)
}

/// The ids the table names.
pub fn ids(table table: List(#(Int, message))) -> List(Int) {
  list.map(table, fn(taken) { taken.0 })
}
