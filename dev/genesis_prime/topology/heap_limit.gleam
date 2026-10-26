//// The most memory a process of prototype C may hold on its heap, before the
//// runtime kills it: one limit for the map process and one for each sender.
//// A map and a sender differ by orders of magnitude in what they hold, so each
//// kind has a limit of its own, chosen from the peak its kind was measured at.
////
//// A process that passes its limit is killed with reason `killed` and an error
//// is logged, so its supervisor rebuilds it and no other process is touched.
//// The limit covers the process's own heap, its stack and its waiting messages
//// (`total_heap_size`), not binaries outside the heap and not ETS tables.

import genesis_prime/topology/measurement
import gleam/bool
import gleam/option.{type Option}

/// The most words a process's heap may hold, or no limit. A word is 8 bytes on
/// the machines the server runs on. A limit is made by `words` or `no_limit`,
/// so it is never 0 words, which the runtime reads as no limit.
pub opaque type HeapLimit {
  /// The process may grow without bound.
  NoLimit
  /// The process is killed when its heap passes this many words; at least 1.
  Words(count: Int)
}

/// No limit: the process may grow without bound.
pub const no_limit = NoLimit

/// A limit of `count` words, or an error when `count` is below 1.
pub fn words(count count: Int) -> Result(HeapLimit, Nil) {
  use <- bool.guard(when: count < 1, return: Error(Nil))
  Ok(Words(count:))
}

/// The words of a limit, or none for no limit.
pub fn to_words(limit limit: HeapLimit) -> Option(Int) {
  case limit {
    NoLimit -> option.None
    Words(count:) -> option.Some(count)
  }
}

/// The limits of one prototype C: the map process's and each sender's.
pub type HeapLimits {
  HeapLimits(map: HeapLimit, sender: HeapLimit)
}

/// No limit for the map process and none for the senders.
pub const no_limits = HeapLimits(map: no_limit, sender: no_limit)

/// Makes the limit chosen by the rule from the largest peak a kind of process
/// reached, in words: four times the peak, rounded up to a power of two words.
/// A peak is a reading of `total_heap_size` every 100 milliseconds, and the
/// runtime counts toward the limit the memory a collection needs while the old
/// and the new heap exist together: a sender killed at twice its peak held
/// 69,621 words in its kill report, 2.15 times the 32,317 words sampled. Four
/// times leaves room for that and for the load to grow, and a power of two is
/// the size the runtime grows a heap in. The peak is at least 1 word.
pub fn for_peak(peak_words peak_words: Int) -> HeapLimit {
  assert peak_words >= 1 as "a peak is at least 1 word"
  Words(count: power_of_two_from(1, at_least: 4 * peak_words))
}

/// The smallest power of two that is at least `target`, found by doubling
/// `candidate`, a power of two.
fn power_of_two_from(candidate: Int, at_least target: Int) -> Int {
  use <- bool.guard(when: candidate >= target, return: candidate)
  power_of_two_from(candidate * 2, at_least: target)
}

/// Sets the limit on the calling process, killing it with reason `killed` when
/// its heap passes the limit, and logging an error. `NoLimit` changes nothing.
/// A process calls it first in its initialiser, so the limit covers the build
/// of its state as well.
pub fn apply(limit limit: HeapLimit) -> Nil {
  case limit {
    NoLimit -> Nil
    Words(count:) -> measurement.set_max_heap_size(count)
  }
}
