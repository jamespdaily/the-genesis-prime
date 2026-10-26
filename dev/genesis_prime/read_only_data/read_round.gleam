//// One timed round of reads: readers started together, each opening the
//// loaded tables in its own process, waiting for one signal, then reading its
//// own stream and timing itself.

import genesis_prime/read_only_data/variant.{type Loaded}

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
  loaded: Loaded,
  streams streams: List(BitArray),
) -> List(ReaderReport) {
  todo as "body in the build commit"
}
