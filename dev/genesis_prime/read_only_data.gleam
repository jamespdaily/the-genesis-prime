//// Where read-only data lives: persistent terms, ETS, or each owner's state,
//// measured on rows in the shape of the client's three largest game tables
//// (Creature2, Spell4 and Spline2Node), with synthetic values.
////
//// Run it with `gleam run -m genesis_prime/read_only_data` on a machine with
//// nothing else heavy running. It lives in `dev/` because Gleam compiles that
//// directory with the project, so `gleam build` keeps it compiling, while
//// `gleam test` never runs it. It uses only the runtime's own clock and
//// counters.
////
//// It measures, in order: the shape of a persistent term (tuple or map), the
//// load time of the three tables (median of 5), the memory of each variant,
//// the start cost of a process with each variant (median of 5), and the read
//// cost of one row by id from 1 reader and from 12 at once (median of 5 rounds
//// of 1,000,000 reads, the starting variant rotating each round), with a
//// planted variant that reads each row twice. Then the choosing rule, once
//// on the largest reader count (many map processes read at once), printed step
//// by step, with the one-reader read cost printed beside it. One round of reads
//// is run and discarded first so the processes and caches are warm.

import genesis_prime/read_only_data/choosing_rule.{type Standing, Standing}
import genesis_prime/read_only_data/client_table.{type ClientTable}
import genesis_prime/read_only_data/ets_variant
import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/owner_state_variant
import genesis_prime/read_only_data/persistent_term_variant
import genesis_prime/read_only_data/planted_variant
import genesis_prime/read_only_data/read_round
import genesis_prime/read_only_data/start_cost
import genesis_prime/read_only_data/table_data.{type Source}
import genesis_prime/read_only_data/term_shape
import genesis_prime/read_only_data/variant.{
  type Loaded, type Memory, type Variant,
}
import genesis_prime/read_only_data/workload
import genesis_prime/topology/trial
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

/// How many holder processes the owner-state variant starts when memory is
/// measured: the map processes of the comparison.
const holder_count = 4

/// How many times a load is timed; the median counts.
const load_runs = 5

/// How many times a start is timed; the median counts.
const start_runs = 5

/// The planted variant passes the harness check when its read cost over the
/// persistent term's is between these.
const planted_ratio_lowest = 1.5

const planted_ratio_highest = 2.5

/// The load time of the three tables into one variant and what it then holds.
type LoadMeasure {
  LoadMeasure(variant: String, milliseconds: List(Float), memory: Memory)
}

/// The start cost of a process with one variant.
type StartMeasure {
  StartMeasure(variant: String, microseconds: List(Float))
}

/// The read cost of one variant at one reader count: for each round, the mean
/// over the readers of their time per read.
type ReadMeasure {
  ReadMeasure(variant: String, readers: Int, nanoseconds_per_read: List(Float))
}

/// One read round's result for one variant at one reader count.
type ReadRun {
  ReadRun(variant: String, readers: Int, nanoseconds_per_read: Float)
}

/// Runs the benchmark and prints every measure, the harness check and the
/// choosing rule.
pub fn main() -> Nil {
  io.println(
    "schedulers online: "
    <> int.to_string(measurement.schedulers_online())
    <> ", word size "
    <> int.to_string(measurement.word_bytes())
    <> " bytes",
  )
  print_table_shapes()
  let started = measurement.monotonic_nanoseconds()
  let source = table_data.build_source()
  io.println(
    "built the synthetic rows in "
    <> milliseconds(measurement.monotonic_nanoseconds() - started)
    <> " ms",
  )
  print_shape_check(source)

  let variants = [
    persistent_term_variant.variant(),
    ets_variant.variant(),
    owner_state_variant.variant(),
  ]
  io.println(
    "\n== Measures 1 and 2: load time of the three tables, median of "
    <> int.to_string(load_runs)
    <> "; memory with "
    <> int.to_string(holder_count)
    <> " holders for owner state",
  )
  let loads = list.map(variants, fn(variant) { measure_load(variant, source) })
  list.each(loads, print_load)

  io.println(
    "\n== Measure 4: time for a process to start and be ready, median of "
    <> int.to_string(start_runs),
  )
  list.each(variants, fn(variant) {
    print_start(measure_start(variant, source))
  })

  io.println(
    "\n== Measures 3 and 5: nanoseconds per read of one row by id, "
    <> int.to_string(workload.reads_per_round)
    <> " reads per reader, median of "
    <> int.to_string(workload.rounds)
    <> " rounds, mean over the readers of each round",
  )
  let reads =
    measure_reads(list.append(variants, [planted_variant.variant()]), source)
  list.each(reads, print_read)
  print_harness_check(reads)

  let ruled = ruled_readers()
  io.println(
    "\n== Choosing rule on the read cost at "
    <> int.to_string(ruled)
    <> " readers at once",
  )
  list.each(workload.reader_counts, fn(readers) {
    case readers == ruled {
      True -> Nil
      False ->
        io.println(
          "read cost at "
          <> int.to_string(readers)
          <> " reader(s), not ruled on: "
          <> string.join(
            list.map(standings(loads:, reads:, readers:), fn(standing) {
              standing.variant
              <> " "
              <> trial.two_places(standing.read_nanoseconds)
              <> " ns"
            }),
            ", ",
          ),
        )
    }
  })
  choosing_rule.print(
    choosing_rule.choose(standings(loads:, reads:, readers: ruled)),
  )
}

/// The reader count the choosing rule uses: the largest of the measure.
fn ruled_readers() -> Int {
  let assert Ok(largest) = list.last(workload.reader_counts)
    as "the read measure has reader counts"
  largest
}

/// Loads the source into the variant five times, timing each, and measures
/// what the first load holds with 4 holder processes.
fn measure_load(variant: Variant, source: Source) -> LoadMeasure {
  io.println("loading " <> variant.name)
  let #(first_milliseconds, first) = timed_load(variant, source)
  let memory = first.memory()
  first.stop()
  let later =
    list.map(workload.indexes(load_runs - 1), fn(_) {
      let #(milliseconds, loaded) = timed_load(variant, source)
      loaded.stop()
      milliseconds
    })
  LoadMeasure(
    variant: variant.name,
    milliseconds: [first_milliseconds, ..later],
    memory:,
  )
}

/// One load of the source, and the milliseconds it took.
fn timed_load(variant: Variant, source: Source) -> #(Float, Loaded) {
  let started = measurement.monotonic_nanoseconds()
  let loaded = variant.load(source, holder_count)
  let elapsed = measurement.monotonic_nanoseconds() - started
  #(int.to_float(elapsed) /. 1_000_000.0, loaded)
}

/// Starts a process with the variant five times and times each start.
fn measure_start(variant: Variant, source: Source) -> StartMeasure {
  let loaded = variant.load(source, 0)
  let microseconds =
    list.map(workload.indexes(start_runs), fn(_) {
      int.to_float(start_cost.time_to_ready(loaded)) /. 1000.0
    })
  loaded.stop()
  StartMeasure(variant: variant.name, microseconds:)
}

/// Measures every variant's read cost at each reader count in
/// `workload.reader_counts`, in `workload.rounds` rounds with the starting
/// variant rotating each round. The variants are loaded together once.
fn measure_reads(variants: List(Variant), source: Source) -> List(ReadMeasure) {
  let loaded =
    list.map(variants, fn(variant) { #(variant.name, variant.load(source, 0)) })
  let streams =
    workload.indexes(ruled_readers()) |> list.map(workload.read_stream)
  io.println("round 0 (discarded, warms up)")
  let _warm_up = read_one_round(loaded:, streams:, round: 0)
  let runs =
    list.flat_map(workload.indexes(workload.rounds), fn(round) {
      read_one_round(loaded: rotate(loaded, round), streams:, round: round + 1)
    })
  list.each(loaded, fn(named) { { named.1 }.stop() })
  list.flat_map(variants, fn(variant) {
    list.map(workload.reader_counts, fn(readers) {
      ReadMeasure(
        variant: variant.name,
        readers:,
        nanoseconds_per_read: runs
          |> list.filter(fn(run) {
            run.variant == variant.name && run.readers == readers
          })
          |> list.map(fn(run) { run.nanoseconds_per_read }),
      )
    })
  })
}

/// Every loaded variant once at each reader count, in the order given, each
/// run printed as it finishes. Every reader must have checked every read.
fn read_one_round(
  loaded loaded: List(#(String, Loaded)),
  streams streams: List(BitArray),
  round round: Int,
) -> List(ReadRun) {
  list.flat_map(loaded, fn(named) {
    list.map(workload.reader_counts, fn(readers) {
      let reports =
        read_round.run(loaded: named.1, streams: list.take(streams, readers))
      let assert True =
        list.all(reports, fn(report) {
          report.checked_reads == workload.reads_per_round
        })
        as "a reader did not check every read"
      let mean =
        float.sum(list.map(reports, fn(report) { report.nanoseconds_per_read }))
        /. int.to_float(readers)
      io.println(
        "round "
        <> int.to_string(round)
        <> "  "
        <> string.pad_end(named.0, 38, " ")
        <> trial.pad_start(int.to_string(readers), 3)
        <> " reader(s)  "
        <> trial.two_places(mean)
        <> " ns/read",
      )
      ReadRun(variant: named.0, readers:, nanoseconds_per_read: mean)
    })
  })
}

/// The list with its first `by` items moved to the end, so each round starts
/// with another variant.
fn rotate(items: List(a), by: Int) -> List(a) {
  let by = by % list.length(items)
  list.append(list.drop(items, by), list.take(items, by))
}

/// Prints the shape check and picks the shape.
fn print_shape_check(source: Source) -> Nil {
  io.println(
    "\n== Persistent-term shape: one reader, "
    <> int.to_string(workload.reads_per_round)
    <> " reads, median of "
    <> int.to_string(workload.rounds)
    <> " rounds",
  )
  let costs = term_shape.measure(source:, stream: workload.read_stream(0))
  list.each(costs, fn(cost) {
    io.println(
      string.pad_end(term_shape.name(cost.shape), 24, " ")
      <> trial.two_places(cost.nanoseconds_per_read)
      <> " ns/read",
    )
  })
  case term_shape.faster(costs) {
    term_shape.TupleByRow ->
      io.println("the tuple is the faster shape, as the variant uses")
    term_shape.MapById ->
      io.println(
        "WARNING: the map is the faster shape, but the persistent-term variant uses the tuple",
      )
  }
}

/// Prints the table shapes: rows, columns by type, and the bytes of a string.
fn print_table_shapes() -> Nil {
  io.println("\n== Shapes of the measured tables")
  list.each(client_table.to_list(client_table.measured()), print_table_shape)
}

fn print_table_shape(table: ClientTable) -> Nil {
  let kinds = client_table.kinds(table)
  let count = fn(kind) { int.to_string(list.count(kinds, fn(k) { k == kind })) }
  io.println(
    string.pad_end(table.name, 12, " ")
    <> int.to_string(table.rows)
    <> " rows, "
    <> int.to_string(list.length(kinds))
    <> " columns ("
    <> count(client_table.Integer32)
    <> " 32-bit integer, "
    <> count(client_table.Float32)
    <> " float, "
    <> count(client_table.Boolean32)
    <> " boolean, "
    <> count(client_table.Integer64)
    <> " 64-bit integer, "
    <> count(client_table.Utf16Text)
    <> " string), "
    <> int.to_string(client_table.average_text_bytes(table))
    <> " bytes per string",
  )
}

fn print_load(measure: LoadMeasure) -> Nil {
  let sorted = list.sort(measure.milliseconds, float.compare)
  io.println(
    string.pad_end(measure.variant, 16, " ")
    <> "load median "
    <> trial.two_places(trial.median(measure.milliseconds))
    <> " ms (runs "
    <> string.join(list.map(measure.milliseconds, trial.two_places), ", ")
    <> "; smallest "
    <> trial.two_places(first_of(sorted))
    <> ")  memory "
    <> trial.two_places(int.to_float(measure.memory.bytes) /. 1_000_000.0)
    <> " MB",
  )
  io.println("                " <> measure.memory.detail)
}

fn print_start(measure: StartMeasure) -> Nil {
  io.println(
    string.pad_end(measure.variant, 16, " ")
    <> "start median "
    <> trial.two_places(trial.median(measure.microseconds))
    <> " us (runs "
    <> string.join(list.map(measure.microseconds, trial.two_places), ", ")
    <> ")",
  )
}

fn print_read(measure: ReadMeasure) -> Nil {
  let sorted = list.sort(measure.nanoseconds_per_read, float.compare)
  io.println(
    string.pad_end(measure.variant, 38, " ")
    <> trial.pad_start(int.to_string(measure.readers), 3)
    <> " reader(s)  median "
    <> trial.two_places(trial.median(measure.nanoseconds_per_read))
    <> " ns/read  min "
    <> trial.two_places(first_of(sorted))
    <> "  max "
    <> trial.two_places(first_of(list.reverse(sorted))),
  )
}

fn first_of(values: List(Float)) -> Float {
  let assert [first, ..] = values as "no values"
  first
}

/// Prints the planted variant's read cost against the persistent term's, and
/// whether the harness sees about twice.
fn print_harness_check(reads: List(ReadMeasure)) -> Nil {
  io.println("\n== Harness check: the planted variant reads each row twice")
  let base_name = persistent_term_variant.variant().name
  let planted_name = planted_variant.variant().name
  list.each(workload.reader_counts, fn(readers) {
    let cost = fn(name) {
      let assert Ok(measure) =
        list.find(reads, fn(measure) {
          measure.variant == name && measure.readers == readers
        })
        as "a read measure is missing"
      trial.median(measure.nanoseconds_per_read)
    }
    let ratio = cost(planted_name) /. cost(base_name)
    io.println(
      int.to_string(readers)
      <> " reader(s): planted / persistent term = "
      <> trial.two_places(ratio)
      <> " (about twice is "
      <> trial.two_places(planted_ratio_lowest)
      <> " to "
      <> trial.two_places(planted_ratio_highest)
      <> "): the harness "
      <> case
        ratio >=. planted_ratio_lowest && ratio <=. planted_ratio_highest
      {
        True -> "sees the difference"
        False -> "does NOT see about twice"
      },
    )
  })
}

/// The standings of the three real variants, with the read cost at `readers`
/// readers.
fn standings(
  loads loads: List(LoadMeasure),
  reads reads: List(ReadMeasure),
  readers readers: Int,
) -> List(Standing) {
  list.map(loads, fn(load) {
    let assert Ok(read) =
      list.find(reads, fn(read) {
        read.variant == load.variant && read.readers == readers
      })
      as "a read measure is missing"
    Standing(
      variant: load.variant,
      memory_bytes: load.memory.bytes,
      load_milliseconds: trial.median(load.milliseconds),
      read_nanoseconds: trial.median(read.nanoseconds_per_read),
    )
  })
}

/// Milliseconds from nanoseconds, as text to two places.
fn milliseconds(nanoseconds: Int) -> String {
  trial.two_places(int.to_float(nanoseconds) /. 1_000_000.0)
}
