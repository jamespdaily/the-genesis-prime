//// The SHA-256 digest as the text the server and its tools compare: lower-case
//// hex, the form `sha256sum` and `shasum -a 256` print.

import gleam/bit_array
import gleam/crypto
import gleam/string

/// The SHA-256 of the bytes as lower-case hex.
pub fn sha256(bytes: BitArray) -> String {
  crypto.hash(crypto.Sha256, bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}
