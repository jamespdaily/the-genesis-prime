//// Message 0x0592 (login_request), client to server: the login request the
//// client sends the auth server once its hello has passed the version check.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x592` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x0592, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type LoginRequest {
  LoginRequest(
    build: Int,
    files_digest: Int,
    account_name: String,
    field_4: BitArray,
    field_5: BitArray,
    field_6: Int,
    field_7: Int,
    field_8: Int,
    field_9: Int,
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
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(LoginRequest, DecodeError) {
  todo
}
