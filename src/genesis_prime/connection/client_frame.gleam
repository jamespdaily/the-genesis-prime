//// What one whole frame from the client is to a connection that takes the
//// client's wrapper (the auth connection and the game connection): a network
//// message, answered before any wrapper is looked at
//// (genesis_prime/connection/network_message); the frame inside the wrapper
//// 0x0244, read under the cipher the connection holds at that moment
//// (genesis_prime/connection/encrypted_frame); or a message the connection
//// does not take. The rule that holds the connection decides what each of
//// them does.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{ClientWrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/connection/network_message
import genesis_prime/message/bit_stream.{type DecodeError}

/// What a whole frame from the client is.
pub type Received {
  /// A ping: these bytes, a whole bare frame holding the pong, are the
  /// answer.
  Pong(bytes: BitArray)
  /// A pong or a close notice: accepted, nothing is sent.
  Noted
  /// A network message whose body does not decode: the client's own reader
  /// would refuse it.
  Malformed(message_id: Int, error: DecodeError)
  /// The frame inside the client's wrapper.
  Wrapped(inner: Frame)
  /// A whole frame of a message the connection does not take, bare or in a
  /// wrapper that is not the client's.
  Unknown(message_id: Int)
  /// The client's wrapper, or the frame inside it, is no frame the client's
  /// reader accepts.
  Broken(error: FrameError)
}

/// Sorts a whole frame: the network layer's messages first, then the client's
/// wrapper opened with `cipher`, then the rest.
pub fn receive(frame frame: Frame, cipher cipher: Cipher) -> Received {
  case network_message.handle(frame:) {
    network_message.Answer(bytes:) -> Pong(bytes:)
    network_message.Accepted -> Noted
    network_message.Malformed(message_id:, error:) ->
      Malformed(message_id:, error:)
    network_message.NotNetwork ->
      case frame.message_id == encrypted_frame.message_id(ClientWrapper) {
        False -> Unknown(message_id: frame.message_id)
        True ->
          case encrypted_frame.unwrap(frame, cipher) {
            Ok(inner) -> Wrapped(inner:)
            Error(encrypted_frame.NotAWrapper(message_id:)) ->
              Unknown(message_id:)
            Error(encrypted_frame.BadFrame(error)) -> Broken(error:)
          }
      }
  }
}
