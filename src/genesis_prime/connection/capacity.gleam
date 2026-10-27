//// How much memory a connection may hold and how many connections the server
//// accepts: the heap ceiling of one socket owner and the connection cap, which
//// together keep the connections under 1 GB.

import gleam/bool
import gleam/int

/// The memory all connections together may be allowed to hold, in bytes: 1 GB.
pub const memory_limit_bytes = 1_000_000_000

/// Bytes in a word of the runtime's heap on the machines the server runs on.
const bytes_per_word = 8

/// The heap ceiling for a socket owner whose measured peak is `peak_words`
/// words: four times the peak, rounded up to a power of two words. The peak is
/// a reading of the heap every 100 ms, and the runtime counts toward the limit
/// the memory a collection needs while the old and the new heap exist
/// together, which took 2.15 times a sampled peak in an earlier measurement;
/// four times leaves room for that and for the load to grow, and a power of
/// two is the size the runtime grows a heap in.
pub fn heap_ceiling_for_peak(peak_words peak_words: Int) -> Int {
  assert peak_words >= 1 as "a peak is at least 1 word"
  power_of_two_from(1, at_least: 4 * peak_words)
}

fn power_of_two_from(candidate: Int, at_least target: Int) -> Int {
  use <- bool.guard(when: candidate >= target, return: candidate)
  power_of_two_from(candidate * 2, at_least: target)
}

/// The most connections whose heap ceilings of `ceiling_words` words each
/// stay under `memory_limit_bytes` together.
pub fn connection_cap_for(ceiling_words ceiling_words: Int) -> Int {
  { memory_limit_bytes - 1 } / { ceiling_words * bytes_per_word }
}

/// The most words an owner's heap reached in the dash load, shared binaries
/// counted: 800 connections each sending 120 frames a second, read every 100
/// ms over 5 rounds, 4,583 words at the most (a load run of the socket owner).
const dash_load_peak_words = 4583

/// The words the runtime itself needs for an owner to hold a frame of the
/// largest size the client sends, 131,070 bytes: owners under 61,440 words were
/// all killed and every owner at 63,488 words survived, 5 runs of each
/// (a run that sent the largest frame to owners of each ceiling). The frame arrives in about a millisecond, so no
/// reading of the heap can catch it.
const largest_frame_need_words = 63_488

/// A reading of the heap, every 100 ms, is 100 of every 215 words the runtime
/// counts toward the limit: a collection needed 2.15 times a sampled peak.
const sampled_percent_of_counted = 100

const counted_percent_of_sampled = 215

/// The largest heap an owner reaches, shared binaries counted, in the unit of a
/// sampled reading: the dash load's, or the largest frame's need scaled down
/// to a sampled reading, whichever is larger.
pub fn peak_heap_words() -> Int {
  int.max(
    dash_load_peak_words,
    largest_frame_need_words
      * sampled_percent_of_counted
      / counted_percent_of_sampled,
  )
}

/// The most words a socket owner's heap may need, shared binaries counted,
/// before the runtime kills it. A word is 8 bytes.
pub fn heap_ceiling_words() -> Int {
  heap_ceiling_for_peak(peak_words: peak_heap_words())
}

/// The most connections one listener serves at once: the cap for the heap
/// ceiling, so that all of them together stay under 1 GB.
pub fn connection_cap() -> Int {
  connection_cap_for(ceiling_words: heap_ceiling_words())
}

/// A sentence with the cap, the ceiling and their sum, for the log of a
/// listener that starts.
pub fn describe(cap cap: Int, ceiling_words ceiling_words: Int) -> String {
  let bytes = ceiling_words * bytes_per_word
  "connection cap "
  <> int.to_string(cap)
  <> " x heap ceiling "
  <> int.to_string(bytes)
  <> " bytes = "
  <> int.to_string(cap * bytes)
  <> " bytes, under "
  <> int.to_string(memory_limit_bytes)
}
