//// Every game table of the client, loaded together: one entry per table file
//// and the load that reads them all.

import genesis_prime/table/loader/store
import gleam/erlang/reference.{type Reference}

/// The entry of every table in the client, in file-name order.
pub fn entries() -> List(store.Entry) {
  todo
}

/// Loads every table from the folder that holds the client's extracted `.tbl`
/// files under `key`, checking each against its generated schema and the rows
/// the server requires.
pub fn load(
  under key: Reference,
  from folder: String,
) -> Result(store.Tables, store.LoadError) {
  todo
}
