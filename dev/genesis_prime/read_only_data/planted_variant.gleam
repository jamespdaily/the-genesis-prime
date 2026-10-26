//// The planted variant that proves the harness can see a difference: the
//// persistent-term variant reading each row twice. Its read cost must be
//// about twice the persistent term's.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/variant.{type Variant}
import gleam/erlang/reference.{type Reference}

/// The variant: loaded as persistent terms, read twice per entry.
pub fn variant() -> Variant {
  todo as "body in the build commit"
}

/// Reads each entry of the stream twice from its table's term and checks both
/// rows.
fn read_all(keys: PerTable(Reference), stream: BitArray) -> Int {
  todo as "body in the build commit"
}
