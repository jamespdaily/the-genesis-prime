//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0003 (server_hello), server to client: the hello every server
//// sends on a new connection, with the build and the message table checksum
//// the client checks. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x3` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0003

/// The body of message 0x0003, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ServerHello {
  ServerHello(
    build: Int,
    realm_id: Int,
    unread_3: Int,
    unread_4: Int,
    unread_5: Int,
    unread_6: Int,
    unread_7: Int,
    message_table_checksum: Int,
    unread_9: Int,
    unread_10: Int,
    unread_11: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ServerHello) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("build", message.build, 32)
  |> bit_stream.write_unsigned("realm_id", message.realm_id, 32)
  |> bit_stream.write_unsigned("unread_3", message.unread_3, 32)
  |> bit_stream.write_unsigned("unread_4", message.unread_4, 32)
  |> bit_stream.write_unsigned("unread_5", message.unread_5, 64)
  |> bit_stream.write_unsigned("unread_6", message.unread_6, 16)
  |> bit_stream.write_unsigned("unread_7", message.unread_7, 5)
  |> bit_stream.write_unsigned(
    "message_table_checksum",
    message.message_table_checksum,
    32,
  )
  |> bit_stream.write_unsigned("unread_9", message.unread_9, 32)
  |> bit_stream.write_unsigned("unread_10", message.unread_10, 64)
  |> bit_stream.write_unsigned("unread_11", message.unread_11, 32)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: ServerHello) -> BitArray {
  bit_stream.must(encode(message), "server_hello")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ServerHello, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(build, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unread_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unread_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unread_5, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(unread_6, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(unread_7, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(message_table_checksum, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(unread_9, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unread_10, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(unread_11, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ServerHello(
    build:,
    realm_id:,
    unread_3:,
    unread_4:,
    unread_5:,
    unread_6:,
    unread_7:,
    message_table_checksum:,
    unread_9:,
    unread_10:,
    unread_11:,
  ))
}
