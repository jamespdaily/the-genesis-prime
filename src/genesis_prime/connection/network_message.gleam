//// The network layer's own messages, which every connection handles before it
//// looks at any wrapper: the ping (message 0), the pong (message 1) and the
//// close notice (message 2). They travel bare, never inside 0x244 and never
//// ciphered, on the auth connection and on the game connection, in every
//// state of it. The client's frame reader answers them before it passes a
//// message on (ReadMessageFrame 0x140331990; records opcode.0x0, opcode.0x1,
//// opcode.0x2, RegisterNetworkMessages 0x140333850).
////
//// A ping is answered at once with a pong that carries its number
//// (opcode.0x0). A pong from the client answers a ping of the server and a
//// close notice says the client is closing; neither gets an answer.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/bit_stream.{type DecodeError}
import genesis_prime/message/close_notice
import genesis_prime/message/ping
import genesis_prime/message/pong.{Pong}

/// What a frame is to the network layer.
pub type Handled {
  /// Not one of the network layer's messages: the connection reads it by its
  /// own rules.
  NotNetwork
  /// A ping: send these bytes, a whole bare frame holding the pong.
  Answer(bytes: BitArray)
  /// A pong or a close notice: accepted, and nothing is sent.
  Accepted
  /// A network message whose body does not decode, which ends the connection.
  Malformed(message_id: Int, error: DecodeError)
}

/// What the network layer does with a frame.
pub fn handle(frame frame: Frame) -> Handled {
  case frame.message_id {
    id if id == ping.message_id ->
      case ping.decode(frame.body) {
        Ok(received) -> Answer(pong_of(received))
        Error(error) -> Malformed(message_id: id, error:)
      }
    id if id == pong.message_id ->
      case pong.decode(frame.body) {
        Ok(_) -> Accepted
        Error(error) -> Malformed(message_id: id, error:)
      }
    id if id == close_notice.message_id ->
      case close_notice.decode(frame.body) {
        Ok(_) -> Accepted
        Error(error) -> Malformed(message_id: id, error:)
      }
    _ -> NotNetwork
  }
}

/// The whole bare frame of the pong that answers a ping: the same number.
fn pong_of(received: ping.Ping) -> BitArray {
  let assert Ok(body) =
    pong.encode(Pong(sequence_number: received.sequence_number))
    as "a ping's number is 0 to 19, which fits the pong's 8 bits"
  let assert Ok(bytes) = frame.encode(pong.message_id, body)
    as "a pong is 7 bytes, far below the size limit"
  bytes
}
