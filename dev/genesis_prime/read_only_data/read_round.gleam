//// One timed round of reads: readers started together, each opening the
//// loaded tables in its own process, waiting for one signal, then reading its
//// own stream and timing itself.

import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/variant.{type Loaded}
import gleam/erlang/process
import gleam/int
import gleam/list

/// What one reader found in one round.
pub type ReaderReport {
  ReaderReport(
    /// The reader's own time for the stream, over the stream's reads.
    nanoseconds_per_read: Float,
    /// The reads it made and checked; the stream's length when nothing went
    /// wrong.
    checked_reads: Int,
  )
}

/// Starts one reader process for each stream, waits until all have opened the
/// tables, lets them all read at once and returns their reports, in stream
/// order. A reader that does not report within the deadline stops the
/// benchmark with a message.
pub fn run(
  loaded loaded: Loaded,
  streams streams: List(BitArray),
) -> List(ReaderReport) {
  let ready = process.new_subject()
  let reports = process.new_subject()
  list.index_map(streams, fn(stream, index) {
    process.spawn_unlinked(fn() {
      let reader = loaded.open_reader()
      let go = process.new_subject()
      process.send(ready, go)
      process.receive_forever(go)
      let started = measurement.monotonic_nanoseconds()
      let checked = reader.read_all(stream)
      let elapsed = measurement.monotonic_nanoseconds() - started
      process.send(reports, #(
        index,
        ReaderReport(
          nanoseconds_per_read: int.to_float(elapsed) /. int.to_float(checked),
          checked_reads: checked,
        ),
      ))
    })
  })
  let go_subjects =
    list.map(streams, fn(_) {
      let assert Ok(go) = process.receive(ready, 600_000)
        as "a reader did not open the tables in time"
      go
    })
  list.each(go_subjects, fn(go) { process.send(go, Nil) })
  list.map(streams, fn(_) {
    let assert Ok(report) = process.receive(reports, 600_000)
      as "a reader did not report in time"
    report
  })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.map(fn(indexed) { indexed.1 })
}
