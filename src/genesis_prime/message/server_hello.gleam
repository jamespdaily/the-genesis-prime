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
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type ServerHello {
  ServerHello(
    build: Int,
    realm_id: Int,
    field_3: Int,
    field_4: Int,
    field_5: Int,
    field_6: Int,
    field_7: Int,
    message_table_checksum: Int,
    field_9: Int,
    field_10: Int,
    field_11: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ServerHello) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("build", message.build, 32)
  |> bit_stream.write_unsigned("realm_id", message.realm_id, 32)
  |> bit_stream.write_unsigned("field_3", message.field_3, 32)
  |> bit_stream.write_unsigned("field_4", message.field_4, 32)
  |> bit_stream.write_unsigned("field_5", message.field_5, 64)
  |> bit_stream.write_unsigned("field_6", message.field_6, 16)
  |> bit_stream.write_unsigned("field_7", message.field_7, 5)
  |> bit_stream.write_unsigned(
    "message_table_checksum",
    message.message_table_checksum,
    32,
  )
  |> bit_stream.write_unsigned("field_9", message.field_9, 32)
  |> bit_stream.write_unsigned("field_10", message.field_10, 64)
  |> bit_stream.write_unsigned("field_11", message.field_11, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ServerHello, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(build, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(message_table_checksum, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_11, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ServerHello(
    build:,
    realm_id:,
    field_3:,
    field_4:,
    field_5:,
    field_6:,
    field_7:,
    message_table_checksum:,
    field_9:,
    field_10:,
    field_11:,
  ))
}
