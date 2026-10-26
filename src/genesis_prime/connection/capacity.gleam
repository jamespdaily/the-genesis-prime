//// How much memory a connection may hold and how many connections the server
//// accepts: the heap ceiling of one socket owner and the connection cap, which
//// together keep the connections under 1 GB.

/// The memory all connections together may be allowed to hold, in bytes: 1 GB.
pub const memory_limit_bytes = 1_000_000_000

/// The heap ceiling for a socket owner whose measured peak is `peak_words`
/// words: four times the peak, rounded up to a power of two words.
pub fn heap_ceiling_for_peak(peak_words peak_words: Int) -> Int {
  todo as "four times the peak, as a power of two"
}

/// The most connections whose heap ceilings of `ceiling_words` words each
/// stay under `memory_limit_bytes` together.
pub fn connection_cap_for(ceiling_words ceiling_words: Int) -> Int {
  todo as "the memory limit divided by the ceiling, in whole connections"
}

/// The largest heap a socket owner reached in the measured load, shared
/// binaries counted, in words.
pub fn peak_heap_words() -> Int {
  todo as "the measured peak"
}

/// The most words a socket owner's heap may need, shared binaries counted,
/// before the runtime kills it. A word is 8 bytes.
pub fn heap_ceiling_words() -> Int {
  todo as "the ceiling for the measured peak"
}

/// The most connections one listener serves at once.
pub fn connection_cap() -> Int {
  todo as "the cap for the ceiling"
}
