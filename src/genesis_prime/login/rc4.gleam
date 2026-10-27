//// An RC4 stream under the session key of the SRP exchange. After the
//// exchange the NC platform library puts RC4 under the 64-byte session key on
//// the connection, one state for the bytes sent and a separate one for the
//// bytes received, both from the same key, no bytes dropped, each running on
//// across messages (StsConnLib64.MT.dll!0x18003a7d0). A stream is a value:
//// ciphering gives the bytes and the stream after them, so a rule can hold it
//// in its state and a recording replays it.

/// One direction's RC4 state: the 256-byte permutation and the two indexes.
pub opaque type Stream {
  Stream(permutation: BitArray, i: Int, j: Int)
}

/// Why a stream could not start.
pub type StartError {
  /// RC4 is keyed with 1 to 256 bytes; the library's key is 64.
  KeyLengthOutOfRange(bytes: Int)
}

/// A new stream under `key`, at its first byte.
pub fn start(key key: BitArray) -> Result(Stream, StartError) {
  todo as "the build follows the shape commit"
}

/// The bytes ciphered with the stream's next bytes, and the stream after
/// them; the same call deciphers.
pub fn crypt(
  stream stream: Stream,
  bytes bytes: BitArray,
) -> #(Stream, BitArray) {
  todo as "the build follows the shape commit"
}
