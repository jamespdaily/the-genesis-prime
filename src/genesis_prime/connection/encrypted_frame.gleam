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
import gleam/bit_array
import gleam/result

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
  case wrapper {
    ClientWrapper -> 0x0244
    AuthWrapper -> 0x0076
    GameWrapper -> 0x03DC
  }
}

/// The bytes of the wrapper message around `inner`: the outer frame, whose
/// body is the inner frame with every byte after its first 4 encrypted.
pub fn wrap(
  wrapper wrapper: Wrapper,
  inner inner: Frame,
  cipher cipher: Cipher,
) -> Result(BitArray, FrameError) {
  use inner_bytes <- result.try(frame.encode(inner.message_id, inner.body))
  case inner_bytes {
    <<length:bytes-size(4), after_the_length:bytes>> ->
      frame.encode(message_id(wrapper:), <<
        length:bits,
        cipher.encrypt(cipher, after_the_length):bits,
      >>)
    _ -> Error(frame.ShorterThanHeader(bit_array.byte_size(inner_bytes)))
  }
}

/// The inner frame inside a wrapper frame: reads the inner length, decrypts the
/// bytes after it and parses the inner frame. The wrapper's own message id is
/// checked, and the inner length must account for the whole outer body.
pub fn unwrap(
  outer outer: Frame,
  cipher cipher: Cipher,
) -> Result(Frame, WrapError) {
  case outer.message_id {
    0x0244 | 0x0076 | 0x03DC ->
      case outer.body {
        <<length:bytes-size(4), after_the_length:bytes>> ->
          frame.parse(<<
            length:bits,
            cipher.decrypt(cipher, after_the_length):bits,
          >>)
          |> result.map_error(BadFrame)
        body ->
          Error(BadFrame(frame.ShorterThanHeader(bit_array.byte_size(body))))
      }
    other -> Error(NotAWrapper(other))
  }
}
