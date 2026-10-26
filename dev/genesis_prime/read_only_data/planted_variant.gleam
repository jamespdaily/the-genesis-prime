//// The planted variant that proves the harness can see a difference: the
//// persistent-term variant reading each row twice. Its read cost must be
//// about twice the persistent term's.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/persistent_term_variant
import genesis_prime/read_only_data/table_data
import genesis_prime/read_only_data/variant.{Loaded, Reader, Variant}
import gleam/erlang/reference.{type Reference}

/// The variant: loaded as persistent terms, read twice per entry.
pub fn variant() -> variant.Variant {
  Variant(
    name: "planted: persistent term read twice",
    load: fn(source, _holders) {
      let stored = persistent_term_variant.store(source)
      Loaded(
        memory: fn() { persistent_term_variant.memory(stored) },
        open_reader: fn() {
          Reader(read_all: fn(stream) { read_all(stored.keys, stream) })
        },
        stop: fn() { persistent_term_variant.erase(stored) },
      )
    },
  )
}

/// Reads each entry of the stream twice from its table's term and checks both
/// rows.
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
      let key = client_table.at(per_table: keys, index: table)
      let first = table_data.row_at(persistent_term_variant.get(key), id)
      let second = table_data.row_at(persistent_term_variant.get(key), id)
      let assert True = table_data.id_of(first) == id
        as "a row has another id than the one asked for"
      let assert True = table_data.id_of(second) == id
        as "a row has another id than the one asked for"
      read_from(keys:, stream: rest, checked: checked + 1)
    }
    _ -> checked
  }
}
