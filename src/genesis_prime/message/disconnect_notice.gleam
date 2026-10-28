//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x036A (disconnect_notice), server to client: tells the client it
//// is being disconnected, with the reason it shows as a text. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x36a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x036A

/// The body of message 0x036A, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type DisconnectNotice {
  DisconnectNotice(reason: DisconnectReason)
}

/// The values of the `reason` field that `schema.toml` names, each with the
/// evidence for its meaning, and `Other` for any value it does not name.
pub type DisconnectReason {
  /// The value 6, the fact file's `0x1400168a0`.
  LoggedOutByGm
  /// The value 7, the fact file's `0x1400168a0`.
  Inactivity
  /// The value 8, the fact file's `0x1400168a0`.
  LostUserServer
  /// The value 12, the fact file's `0x1400168a0`.
  LostGatewayServer
  /// The value 15, the fact file's `0x1400168a0`.
  LostWorldServer
  /// The value 16, the fact file's `0x1400168a0`.
  OutOfGameTime
  /// The value 19, the fact file's `0x1400168a0`.
  AccountDisconnected
  /// The value 20, the fact file's `0x1400168a0`.
  CriticalTransactionFailure
  /// A value the schema does not name.
  Other(Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: DisconnectNotice) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("reason", reason_to_value(message.reason), 5)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(DisconnectNotice, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  let reason = reason_from_value(reason)
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(DisconnectNotice(reason:))
}

/// The number the encoder writes for the `reason` field's type.
fn reason_to_value(reason: DisconnectReason) -> Int {
  case reason {
    LoggedOutByGm -> 6
    Inactivity -> 7
    LostUserServer -> 8
    LostGatewayServer -> 12
    LostWorldServer -> 15
    OutOfGameTime -> 16
    AccountDisconnected -> 19
    CriticalTransactionFailure -> 20
    Other(value) -> value
  }
}

/// The `reason` field's type for a number the decoder read.
fn reason_from_value(value: Int) -> DisconnectReason {
  case value {
    6 -> LoggedOutByGm
    7 -> Inactivity
    8 -> LostUserServer
    12 -> LostGatewayServer
    15 -> LostWorldServer
    16 -> OutOfGameTime
    19 -> AccountDisconnected
    20 -> CriticalTransactionFailure
    other -> Other(other)
  }
}
