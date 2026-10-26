//// The most memory a process of a map may hold on its heap before the runtime
//// kills it: one limit for the map process and one for each sender. The limits
//// are the topology trial's, four times the largest heap each kind was
//// sampled at (`heap_ceiling`, prototype C at 10,000 creatures and up to 800
//// players, rounded up to a power of two words).
////
//// A process that passes its limit is killed with reason `killed` and an
//// error is logged, so its supervisor rebuilds it and no other process is
//// touched. The limit covers the process's own heap, its stack and its
//// waiting messages, not binaries outside the heap and not ETS tables.

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
  todo as "a limit of some words"
}

/// The words of a limit, or none for no limit.
pub fn to_words(limit limit: HeapLimit) -> Option(Int) {
  todo as "the words of a limit"
}

/// The limits of one map: the map process's and each sender's.
pub type HeapLimits {
  HeapLimits(map: HeapLimit, sender: HeapLimit)
}

/// The limits measured for a map with a sender pool: 8,388,608 words (64 MB)
/// for the map process and 131,072 words (1 MB) for each sender.
pub const measured =
  HeapLimits(map: Words(count: 8_388_608), sender: Words(count: 131_072))

/// Sets the limit on the calling process, killing it with reason `killed` when
/// its heap passes the limit, and logging an error. `NoLimit` changes nothing.
/// A process calls it first in its initialiser, so the limit covers the build
/// of its state as well.
pub fn apply(limit limit: HeapLimit) -> Nil {
  todo as "sets the limit on the calling process"
}

/// Sets the calling process's heap ceiling in words, killing it when it needs
/// more and logging the kill.
@external(erlang, "heap_limit_ffi", "limit")
fn limit_heap(words: Int) -> Nil
