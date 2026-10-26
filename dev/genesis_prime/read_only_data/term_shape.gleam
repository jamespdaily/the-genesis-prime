//// Which shape a persistent term holds a table in: a tuple of rows indexed by
//// id, or a map from id to row. Both are read from one process on the same
//// stream, and the faster lookup is the shape the persistent-term variant
//// uses.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/persistent_term_variant
import genesis_prime/read_only_data/table_data.{
  type RowMap, type Source, type Table,
}
import genesis_prime/read_only_data/workload
import genesis_prime/topology/trial
import gleam/erlang/reference.{type Reference}
import gleam/float
import gleam/int
import gleam/list

/// A way to hold a table in one term.
pub type Shape {
  /// A tuple of rows; the row of id `n` is element `n`.
  TupleByRow
  /// A map from id to row.
  MapById
}

/// What reading from one shape cost.
pub type ShapeCost {
  ShapeCost(shape: Shape, nanoseconds_per_read: Float)
}

/// Reads one round of the stream from each shape, from one process, and
/// returns each shape's median over the rounds, in the order tuple, map.
pub fn measure(
  source source: Source,
  stream stream: BitArray,
) -> List(ShapeCost) {
  let tuple_keys =
    client_table.map(source, fn(rows) {
      let key = reference.new()
      put_tuple(key, table_data.table_of(rows))
      key
    })
  let map_keys =
    client_table.map(source, fn(rows) {
      let key = reference.new()
      put_map(key, table_data.map_of(rows))
      key
    })
  let rounds = workload.indexes(workload.rounds)
  // One round to warm up, discarded, then the measured rounds with the shape
  // that starts alternating.
  let _warm_up = time_tuple(tuple_keys, stream)
  let _warm_up = time_map(map_keys, stream)
  let timings =
    list.map(rounds, fn(round) {
      case round % 2 {
        0 -> {
          let tuple = time_tuple(tuple_keys, stream)
          #(tuple, time_map(map_keys, stream))
        }
        _ -> {
          let map = time_map(map_keys, stream)
          #(time_tuple(tuple_keys, stream), map)
        }
      }
    })
  let _erased = client_table.map(tuple_keys, erase)
  let _erased = client_table.map(map_keys, erase)
  [
    ShapeCost(TupleByRow, trial.median(list.map(timings, fn(pair) { pair.0 }))),
    ShapeCost(MapById, trial.median(list.map(timings, fn(pair) { pair.1 }))),
  ]
}

/// The shape with the lower cost. `costs` is not empty.
pub fn faster(costs: List(ShapeCost)) -> Shape {
  let assert Ok(lowest) =
    list.reduce(costs, fn(best, cost) {
      case cost.nanoseconds_per_read <. best.nanoseconds_per_read {
        True -> cost
        False -> best
      }
    })
    as "a shape check has costs"
  lowest.shape
}

/// The shape's name as printed.
pub fn name(shape: Shape) -> String {
  case shape {
    TupleByRow -> "tuple of rows by id"
    MapById -> "map from id to row"
  }
}

fn time_tuple(keys: PerTable(Reference), stream: BitArray) -> Float {
  let started = measurement.monotonic_nanoseconds()
  let checked = read_tuples(keys:, stream:, checked: 0)
  nanoseconds_per_read(measurement.monotonic_nanoseconds() - started, checked)
}

fn time_map(keys: PerTable(Reference), stream: BitArray) -> Float {
  let started = measurement.monotonic_nanoseconds()
  let checked = read_maps(keys:, stream:, checked: 0)
  nanoseconds_per_read(measurement.monotonic_nanoseconds() - started, checked)
}

fn nanoseconds_per_read(elapsed: Int, reads: Int) -> Float {
  int.to_float(elapsed) /. int.to_float(reads)
  |> float.max(0.0)
}

fn read_tuples(
  keys keys: PerTable(Reference),
  stream stream: BitArray,
  checked checked: Int,
) -> Int {
  case stream {
    <<table:8, id:24, rest:bits>> -> {
      let row =
        table_data.row_at(
          persistent_term_variant.get(client_table.at(
            per_table: keys,
            index: table,
          )),
          id,
        )
      let assert True = table_data.id_of(row) == id
        as "a row has another id than the one asked for"
      read_tuples(keys:, stream: rest, checked: checked + 1)
    }
    _ -> checked
  }
}

fn read_maps(
  keys keys: PerTable(Reference),
  stream stream: BitArray,
  checked checked: Int,
) -> Int {
  case stream {
    <<table:8, id:24, rest:bits>> -> {
      let row =
        table_data.row_in(
          get_map(client_table.at(per_table: keys, index: table)),
          id,
        )
      let assert True = table_data.id_of(row) == id
        as "a row has another id than the one asked for"
      read_maps(keys:, stream: rest, checked: checked + 1)
    }
    _ -> checked
  }
}

@external(erlang, "read_only_data_ffi", "persistent_term_put")
fn put_tuple(key: Reference, table: Table) -> Nil

@external(erlang, "read_only_data_ffi", "persistent_term_put")
fn put_map(key: Reference, map: RowMap) -> Nil

@external(erlang, "persistent_term", "get")
fn get_map(key: Reference) -> RowMap

@external(erlang, "read_only_data_ffi", "persistent_term_erase")
fn erase(key: Reference) -> Nil
