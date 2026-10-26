//// How much memory a connection may hold and how many connections the server
//// accepts: the heap ceiling of one socket owner and the connection cap, which
//// together keep the connections under 1 GB.

/// The most words a socket owner's heap may need, shared binaries counted,
/// before the runtime kills it. A word is 8 bytes.
pub fn heap_ceiling_words() -> Int {
  todo as "four times the measured peak, as a power of two"
}

/// The most connections one listener serves at once: the largest number whose
/// heap ceilings together stay under 1 GB.
pub fn connection_cap() -> Int {
  todo as "memory limit divided by the heap ceiling"
}
