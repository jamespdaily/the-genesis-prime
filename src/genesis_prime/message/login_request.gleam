//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0592 (login_request), client to server: the login request the
//// client sends the auth server once its hello has passed the version check.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x592` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0592

/// The body of message 0x0592, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type LoginRequest {
  LoginRequest(
    build: Int,
    files_digest: Int,
    account_name: String,
    user_id: BitArray,
    game_token: BitArray,
    client_address: Int,
    language: Int,
    premium_system: Int,
    unset_word: Int,
    processor_manufacturer: String,
    processor_name: String,
    processor_description: String,
    processor_family: Int,
    processor_level: Int,
    processor_revision: Int,
    processor_clock_speed: Int,
    processor_core_count: Int,
    memory_mebibytes: Int,
    video_adapter_description: String,
    video_adapter_vendor_id: Int,
    video_adapter_device_id: Int,
    video_adapter_subsystem_id: Int,
    video_adapter_revision: Int,
    video_adapter_memory_mebibytes: Int,
    processor_architecture: Int,
    windows_version: Int,
    service_pack: Int,
    os_flags: Int,
    realm_data_center_id: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: LoginRequest) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("build", message.build, 32)
  |> bit_stream.write_unsigned("files_digest", message.files_digest, 64)
  |> bit_stream.write_counted_wide_text(
    "account_name",
    message.account_name,
    250,
  )
  |> bit_stream.write_guid("user_id", message.user_id)
  |> bit_stream.write_guid("game_token", message.game_token)
  |> bit_stream.write_unsigned("client_address", message.client_address, 32)
  |> bit_stream.write_unsigned("language", message.language, 32)
  |> bit_stream.write_unsigned("premium_system", message.premium_system, 32)
  |> bit_stream.write_unsigned("unset_word", message.unset_word, 32)
  |> bit_stream.write_wide_text(
    "processor_manufacturer",
    message.processor_manufacturer,
  )
  |> bit_stream.write_wide_text("processor_name", message.processor_name)
  |> bit_stream.write_wide_text(
    "processor_description",
    message.processor_description,
  )
  |> bit_stream.write_unsigned("processor_family", message.processor_family, 32)
  |> bit_stream.write_unsigned("processor_level", message.processor_level, 32)
  |> bit_stream.write_unsigned(
    "processor_revision",
    message.processor_revision,
    32,
  )
  |> bit_stream.write_unsigned(
    "processor_clock_speed",
    message.processor_clock_speed,
    32,
  )
  |> bit_stream.write_unsigned(
    "processor_core_count",
    message.processor_core_count,
    32,
  )
  |> bit_stream.write_unsigned("memory_mebibytes", message.memory_mebibytes, 32)
  |> bit_stream.write_wide_text(
    "video_adapter_description",
    message.video_adapter_description,
  )
  |> bit_stream.write_unsigned(
    "video_adapter_vendor_id",
    message.video_adapter_vendor_id,
    32,
  )
  |> bit_stream.write_unsigned(
    "video_adapter_device_id",
    message.video_adapter_device_id,
    32,
  )
  |> bit_stream.write_unsigned(
    "video_adapter_subsystem_id",
    message.video_adapter_subsystem_id,
    32,
  )
  |> bit_stream.write_unsigned(
    "video_adapter_revision",
    message.video_adapter_revision,
    32,
  )
  |> bit_stream.write_unsigned(
    "video_adapter_memory_mebibytes",
    message.video_adapter_memory_mebibytes,
    32,
  )
  |> bit_stream.write_unsigned(
    "processor_architecture",
    message.processor_architecture,
    32,
  )
  |> bit_stream.write_unsigned("windows_version", message.windows_version, 32)
  |> bit_stream.write_unsigned("service_pack", message.service_pack, 32)
  |> bit_stream.write_unsigned("os_flags", message.os_flags, 32)
  |> bit_stream.write_unsigned(
    "realm_data_center_id",
    message.realm_data_center_id,
    32,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: LoginRequest) -> BitArray {
  bit_stream.must(encode(message), "login_request")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(LoginRequest, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(build, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(files_digest, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(account_name, reader) <- result.try(bit_stream.read_counted_wide_text(
    reader,
    250,
  ))
  use #(user_id, reader) <- result.try(bit_stream.read_guid(reader))
  use #(game_token, reader) <- result.try(bit_stream.read_guid(reader))
  use #(client_address, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(language, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(premium_system, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(unset_word, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(processor_manufacturer, reader) <- result.try(bit_stream.read_wide_text(
    reader,
  ))
  use #(processor_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(processor_description, reader) <- result.try(bit_stream.read_wide_text(
    reader,
  ))
  use #(processor_family, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(processor_level, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(processor_revision, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(processor_clock_speed, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(processor_core_count, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(memory_mebibytes, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(video_adapter_description, reader) <- result.try(
    bit_stream.read_wide_text(reader),
  )
  use #(video_adapter_vendor_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(video_adapter_device_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(video_adapter_subsystem_id, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(video_adapter_revision, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(video_adapter_memory_mebibytes, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(processor_architecture, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(windows_version, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(service_pack, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(os_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(realm_data_center_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(LoginRequest(
    build:,
    files_digest:,
    account_name:,
    user_id:,
    game_token:,
    client_address:,
    language:,
    premium_system:,
    unset_word:,
    processor_manufacturer:,
    processor_name:,
    processor_description:,
    processor_family:,
    processor_level:,
    processor_revision:,
    processor_clock_speed:,
    processor_core_count:,
    memory_mebibytes:,
    video_adapter_description:,
    video_adapter_vendor_id:,
    video_adapter_device_id:,
    video_adapter_subsystem_id:,
    video_adapter_revision:,
    video_adapter_memory_mebibytes:,
    processor_architecture:,
    windows_version:,
    service_pack:,
    os_flags:,
    realm_data_center_id:,
  ))
}
