//// The client's own cipher bytes, copied from the fact file's `vector.*`
//// records (emulator runs of the client's code) and shared by the cipher and
//// wrapper tests. Every input is the bytes 00 01 02 .. (byte i = i mod 256).

import gleam/bit_array

/// The session key folded from the key bytes 01 02 .. 10
/// (vector.0x14003827c.session_fold).
pub const session_key = 0xE096253F50C8934E

/// The 16 session-key bytes 01 02 .. 10.
pub fn session_key_bytes() -> BitArray {
  <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
}

/// The bytes of a hexadecimal text.
pub fn hex(text: String) -> BitArray {
  let assert Ok(bytes) = bit_array.base16_decode(text)
    as "the vector text is valid hexadecimal"
  bytes
}

/// The bytes 00 01 02 .. of the given length (byte i = i mod 256).
pub fn counting_bytes(length: Int) -> BitArray {
  counting_from(0, length, <<>>)
}

fn counting_from(position: Int, length: Int, built: BitArray) -> BitArray {
  case position >= length {
    True -> built
    False ->
      counting_from(position + 1, length, <<
        built:bits,
        { position % 256 }:size(8),
      >>)
  }
}

/// The length and encrypted bytes of each short vector under the base key
/// 0xD283F5B34A8DC685 (vector.0x1400c2d10.base_key).
pub fn base_key_vectors() -> List(#(Int, String)) {
  [
    #(0, ""),
    #(1, "19"),
    #(7, "25b96584484319"),
    #(8, "cf0d0c94cc5a0424"),
    #(9, "195668f6fb7cbd9b8c"),
    #(15, "25b96584484319b234433a911e659a"),
    #(16, "cf0d0c94cc5a042484e05ebefe059315"),
    #(17, "195668f6fb7cbd9b8c00b47fb76b8965ee"),
    #(
      100,
      "07e43b8a5deca0ec44ede6013209c69304630afec4083f658125c667980f1b8bd30cc6e75d0394d9f48689eca130bdc8707d17986727e27ce9385349bc91b3292fbd8b842de6a330241099ee5ff974417ceff20a1ab18a9a3191ed1225ecb8acfbb6ffb2",
    ),
  ]
}

/// The length and encrypted bytes of each short vector under the session key
/// 0xE096253F50C8934E (vector.0x1400c2d10.session_key).
pub fn session_key_vectors() -> List(#(Int, String)) {
  [
    #(0, ""),
    #(1, "d2"),
    #(7, "5a0582246e6a58"),
    #(8, "263fb398df9e62da"),
    #(9, "d29a50df3e48e869e3"),
    #(15, "5a0582246e6a58ea5373283b2d7c49"),
    #(16, "263fb398df9e62dae325a1e68917fd38"),
    #(17, "d29a50df3e48e869e3e0a667f8a7c30eec"),
    #(
      100,
      "36a4bc07b555417203cbb3ff4d71c193d00cf8f15bd60c66f1661e598d293711ce769528ff1dabc2137e9dd6819b852e189c1647e4c35c32510bc0915270755e26393888f5516248a3636ab6e398bdea20785cf7065619e5b1d035d422bf2e95fe2fb8bb",
    ),
  ]
}

/// The length of the long vectors.
pub const long_vector_length = 53_248

/// The SHA-256 of the long vector's input, the same under both keys
/// (vector.0x1400c2d10.base_key and vector.0x1400c2d10.session_key).
pub const long_vector_input_hash =
  "c0fdd63b4c643d6a8c1ce86942a2115e2b3c85207f47e7a911189c4885067b01"

/// The SHA-256 of the long vector's output under the base key.
pub const long_vector_base_key_output_hash =
  "63d2c158a7981dcefd2b8925a04fffc93dc0211804253c60b4f642e92cd5a637"

/// The SHA-256 of the long vector's output under the session key.
pub const long_vector_session_key_output_hash =
  "cb0d1a36a8094e0cf3824bc5d0929eeb8e81f64be2484d0c87bcb7965fb67f7b"
