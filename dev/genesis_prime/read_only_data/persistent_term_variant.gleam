//// The tables as persistent terms: one term per table, a tuple of rows with
//// the row of id `n` at element `n`, written once and never replaced. The
//// tuple is the shape because an id is a position: reading is one tuple
//// access, with no hashing, and the ids run from 1 with no gap. `term_shape`
//// measures it against a map of rows.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/table_data.{type Source, type Table}
import genesis_prime/read_only_data/variant.{type Variant}
import gleam/erlang/reference.{type Reference}

/// The persistent terms one load wrote: the key of each table's term, and the
/// bytes persistent terms held before the load.
pub type Stored {
  Stored(keys: PerTable(Reference), bytes_before: Int)
}

/// The variant: each load writes three terms under keys made for it.
pub fn variant() -> Variant {
  todo as "body in the build commit"
}

/// Writes one persistent term per table, each under a new key, and returns the
/// keys. The planted variant loads the same way.
pub fn store(source: Source) -> Stored {
  todo as "body in the build commit"
}

/// Erases the terms of one load.
pub fn erase(stored: Stored) -> Nil {
  todo as "body in the build commit"
}

/// The memory of one load: the bytes the persistent terms hold now over the
/// bytes they held before it (`persistent_term:info()`), and the words of each
/// term (`erts_debug:size`), in the detail.
pub fn memory(stored: Stored) -> variant.Memory {
  todo as "body in the build commit"
}

/// Gets a table's term. The key is looked up on every call, as a process
/// reading the table would.
@external(erlang, "persistent_term", "get")
pub fn get(key: Reference) -> Table

/// Writes a persistent term.
@external(erlang, "read_only_data_ffi", "persistent_term_put")
fn put(key: Reference, table: Table) -> Nil

/// Erases a persistent term.
@external(erlang, "read_only_data_ffi", "persistent_term_erase")
fn erase_term(key: Reference) -> Nil

/// The bytes persistent terms hold, from `persistent_term:info()`.
@external(erlang, "read_only_data_ffi", "persistent_term_bytes")
fn held_bytes() -> Int

/// Reads each entry of the stream from its table's term and checks the row.
fn read_all(keys: PerTable(Reference), stream: BitArray) -> Int {
  todo as "body in the build commit"
}
