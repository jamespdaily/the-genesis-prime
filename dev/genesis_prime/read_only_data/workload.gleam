//// The reads every variant is timed on: a stream of one table and one id for
//// each read, drawn at random from a fixed seed, the same for every variant.

import genesis_prime/read_only_data/client_table
import gleam/int
import gleam/list

/// Reads one reader makes in one round.
pub const reads_per_round = 1_000_000

/// Rounds each read measure takes the median of.
pub const rounds = 5

/// The reader counts of the read measure: one process alone, and twelve at
/// once.
pub const reader_counts = [1, 12]

/// The seed the read streams are drawn from. Reader `n` uses this seed plus
/// `n`, so the readers differ and every run is the same.
const seed = 26_102_026

/// The stream of one reader: `reads_per_round` entries of 4 bytes each, the
/// table's index (0 Creature2, 1 Spell4, 2 Spline2Node) in the first byte and
/// an id between 1 and that table's row count in the other three. Entry `n`
/// is for table `n` modulo 3, so each table gets a third of the reads.
pub fn read_stream(reader reader: Int) -> BitArray {
  stream(row_counts(), reads_per_round, seed + reader)
}

/// The row counts of the measured tables, in table order, which the stream's
/// ids are drawn from.
fn row_counts() -> List(Int) {
  client_table.measured()
  |> client_table.map(fn(table) { table.rows })
  |> client_table.to_list
}

/// The Erlang helper that draws the stream: `count` entries, entry `n` for the
/// table `n` modulo the number of row counts.
@external(erlang, "read_only_data_ffi", "read_stream")
fn stream(row_counts: List(Int), count: Int, seed: Int) -> BitArray

/// The numbers 0 up to `count`, for numbering rounds and readers.
pub fn indexes(count: Int) -> List(Int) {
  int.range(0, count, [], fn(indexes, index) { [index, ..indexes] })
  |> list.reverse
}
