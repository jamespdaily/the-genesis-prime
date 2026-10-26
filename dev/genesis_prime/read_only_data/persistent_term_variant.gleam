//// The tables as persistent terms: one term per table, a tuple of rows with
//// the row of id `n` at element `n`, written once and never replaced. The
//// tuple is the shape because an id is a position: reading is one tuple
//// access, with no hashing, and the ids run from 1 with no gap. `term_shape`
//// measures it against a map of rows.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/table_data.{type Source, type Table}
import genesis_prime/read_only_data/variant.{
  type Memory, type Variant, Loaded, Memory, Reader, Variant,
}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/string

/// The persistent terms one load wrote: the key of each table's term, and the
/// bytes persistent terms held before the load.
pub type Stored {
  Stored(keys: PerTable(Reference), bytes_before: Int)
}

/// The variant: each load writes three terms under keys made for it.
pub fn variant() -> Variant {
  Variant(name: "persistent term", load: fn(source, _holders) {
    let stored = store(source)
    Loaded(
      memory: fn() { memory(stored) },
      open_reader: fn() {
        Reader(read_all: fn(stream) { read_all(stored.keys, stream) })
      },
      stop: fn() { erase(stored) },
    )
  })
}

/// Writes one persistent term per table, each under a new key, and returns the
/// keys. The planted variant loads the same way.
pub fn store(source: Source) -> Stored {
  let bytes_before = held_bytes()
  let keys =
    client_table.map(source, fn(rows) {
      let key = reference.new()
      put(key, table_data.table_of(rows))
      key
    })
  Stored(keys:, bytes_before:)
}

/// Erases the terms of one load.
pub fn erase(stored: Stored) -> Nil {
  let _keys = client_table.map(stored.keys, erase_term)
  Nil
}

/// The memory of one load: the bytes the persistent terms hold now over the
/// bytes they held before it (`persistent_term:info()`), and the words of each
/// term (`erts_debug:size`), in the detail.
pub fn memory(stored: Stored) -> Memory {
  let bytes = held_bytes() - stored.bytes_before
  let words =
    client_table.map(stored.keys, fn(key) { measurement.heap_words(get(key)) })
    |> client_table.to_list
  Memory(
    bytes:,
    detail: "persistent_term:info() memory over before the load; erts_debug:size words per table "
      <> string.join(list.map(words, int.to_string), ", ")
      <> " ("
      <> int.to_string(list.fold(words, 0, int.add) * measurement.word_bytes())
      <> " bytes); runtime binary memory "
      <> int.to_string(measurement.binary_memory_bytes())
      <> " bytes, shared by every variant",
  )
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
  read_from(keys:, stream:, checked: 0)
}

fn read_from(
  keys keys: PerTable(Reference),
  stream stream: BitArray,
  checked checked: Int,
) -> Int {
  case stream {
    <<table:8, id:24, rest:bits>> -> {
      let row =
        table_data.row_at(
          get(client_table.at(per_table: keys, index: table)),
          id,
        )
      let assert True = table_data.id_of(row) == id
        as "a row has another id than the one asked for"
      read_from(keys:, stream: rest, checked: checked + 1)
    }
    _ -> checked
  }
}
