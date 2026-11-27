//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0356 (dialog_responses_shown), client to server: the client has
//// built more than one response for the dialog the server opened and shows it,
//// with an empty body and no answer awaited. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x356` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0356

/// The body of message 0x0356, which is empty.
pub type DialogResponsesShown {
  DialogResponsesShown
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: DialogResponsesShown) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(DialogResponsesShown, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(DialogResponsesShown)
}
