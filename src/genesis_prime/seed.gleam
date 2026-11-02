//// A connection's seed: the 32 bytes all of the rule's random values are drawn
//// from (genesis_prime/random). A recording's header holds it and a script
//// hands it to the shell, so a value of this type is always 32 bytes and a
//// recording that holds any other length is not read.

import gleam/bit_array
import gleam/bool
import gleam/crypto

/// How many bytes a seed holds: the 32 bytes the operating system's strong
/// random source gives each connection (`step.Accepted`).
pub const byte_count = 32

/// A seed: exactly `byte_count` bytes, made only by `from_bytes` and
/// `from_system`.
pub opaque type Seed {
  Seed(bytes: BitArray)
}

/// Why bytes are no seed.
pub type NotASeed {
  /// The bytes number `found`, not `byte_count`.
  WrongLength(found: Int)
}

/// The seed these bytes make, or why they make none.
pub fn from_bytes(bytes bytes: BitArray) -> Result(Seed, NotASeed) {
  use <- bool.guard(
    when: bit_array.byte_size(bytes) != byte_count || !is_whole_bytes(bytes),
    return: Error(WrongLength(found: bit_array.byte_size(bytes))),
  )
  Ok(Seed(bytes:))
}

/// Whether the bit array is a whole number of bytes.
fn is_whole_bytes(bytes: BitArray) -> Bool {
  case bytes {
    <<_:bytes>> -> True
    _ -> False
  }
}

/// A seed from the operating system's strong random source.
pub fn from_system() -> Seed {
  Seed(bytes: crypto.strong_random_bytes(byte_count))
}

/// The seed of 32 zero bytes: what a decoder holds in the place of a seed it
/// refused. No connection is given it.
pub fn zeros() -> Seed {
  Seed(bytes: <<0:size(256)>>)
}

/// The seed's bytes.
pub fn bytes(seed seed: Seed) -> BitArray {
  seed.bytes
}
