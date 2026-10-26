//// An RC4 stream under the session key of the SRP exchange. After the
//// exchange the NC platform library puts RC4 under the 64-byte session key on
//// the connection, one state for the bytes sent and a separate one for the
//// bytes received, both from the same key, no bytes dropped, each running on
//// across messages (StsConnLib64.MT.dll!0x18003a7d0). OTP's `crypto` holds
//// the state of a stream, and using a stream advances it.

/// One direction's RC4 state. It advances every time it ciphers bytes, so
/// the bytes of a direction are ciphered in the order they travel.
pub type Stream

/// Why a stream could not start.
pub type StartError {
  /// This OTP build has no RC4 cipher.
  Unsupported
  /// RC4 is keyed with at least one byte; the library's key is 64.
  EmptyKey
}

/// A new stream under `key`, at its first byte.
pub fn start(key key: BitArray) -> Result(Stream, StartError) {
  todo as "start a stream"
}

/// The bytes ciphered with the stream's next bytes; the same call
/// deciphers.
pub fn crypt(stream stream: Stream, bytes bytes: BitArray) -> BitArray {
  todo as "cipher the bytes"
}
