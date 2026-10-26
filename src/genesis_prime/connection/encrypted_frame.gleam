//// The messages that carry another message's whole frame, with the bytes
//// after the inner frame's 4-byte length ciphered: 0x0244 from the client,
//// 0x0076 from the auth server and 0x03DC from a game server. The body of each
//// is one inner frame: its 32-bit length in the clear, then its 16-bit id and
//// body encrypted with the connection's cipher over the inner length minus 4
//// bytes (opcode records 0x244, 0x76 and 0x3DC; WriteWholeFrameBody
//// 0x140079F30, ReadWholeFrameBody 0x140079F70, HandleServerMessage
//// 0x140014F10). The inner frame's own message is 0x038C on the world
//// connection; that is the message layer's, not this module's.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/frame.{type Frame, type FrameError}

/// Which message carries the inner frame.
pub type Wrapper {
  /// 0x0244, client to server.
  ClientWrapper
  /// 0x0076, auth server to client.
  AuthWrapper
  /// 0x03DC, game server to client.
  GameWrapper
}

/// Why a frame could not be wrapped or unwrapped.
pub type WrapError {
  /// The frame's message is none of the three wrappers.
  NotAWrapper(message_id: Int)
  /// The outer or inner frame is malformed.
  BadFrame(FrameError)
}

/// The message id of a wrapper.
pub fn message_id(wrapper wrapper: Wrapper) -> Int {
  todo as "the wrapper's message id"
}

/// The bytes of the wrapper message around `inner`: the outer frame, whose
/// body is the inner frame with every byte after its first 4 encrypted.
pub fn wrap(
  wrapper wrapper: Wrapper,
  inner inner: Frame,
  cipher cipher: Cipher,
) -> Result(BitArray, FrameError) {
  todo as "wrap an inner frame"
}

/// The inner frame inside a wrapper frame: reads the inner length, decrypts the
/// bytes after it and parses the inner frame. The wrapper's own message id is
/// checked, and the inner length must account for the whole outer body.
pub fn unwrap(
  outer outer: Frame,
  cipher cipher: Cipher,
) -> Result(Frame, WrapError) {
  todo as "unwrap an inner frame"
}
