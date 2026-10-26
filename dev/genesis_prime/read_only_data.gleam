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
//// for each reader count, printed step by step.

import genesis_prime/read_only_data/choosing_rule.{type Standing}
import genesis_prime/read_only_data/table_data.{type Source}
import genesis_prime/read_only_data/variant.{type Memory, type Variant}

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

/// Runs the benchmark and prints every measure, the harness check and the
/// choosing rule.
pub fn main() -> Nil {
  todo as "body in the build commit"
}

/// Loads the source into the variant five times, timing each, and measures
/// what the first load holds with 4 holder processes.
fn measure_load(variant: Variant, source: Source) -> LoadMeasure {
  todo as "body in the build commit"
}

/// Starts a process with the variant five times and times each start.
fn measure_start(variant: Variant, source: Source) -> StartMeasure {
  todo as "body in the build commit"
}

/// Measures every variant's read cost at each reader count in
/// `workload.reader_counts`, in `workload.rounds` rounds with the starting
/// variant rotating each round. The variants are loaded together once.
fn measure_reads(variants: List(Variant), source: Source) -> List(ReadMeasure) {
  todo as "body in the build commit"
}

/// Prints the shape check and picks the shape.
fn print_shape_check(source: Source) -> Nil {
  todo as "body in the build commit"
}

/// Prints the table shapes: rows, columns by type, and the bytes of a string.
fn print_table_shapes() -> Nil {
  todo as "body in the build commit"
}

/// Prints the planted variant's read cost against the persistent term's, and
/// whether the harness sees about twice.
fn print_harness_check(reads: List(ReadMeasure)) -> Nil {
  todo as "body in the build commit"
}

/// The standings of the three real variants, with the read cost at `readers`
/// readers.
fn standings(
  loads: List(LoadMeasure),
  reads: List(ReadMeasure),
  readers readers: Int,
) -> List(Standing) {
  todo as "body in the build commit"
}
