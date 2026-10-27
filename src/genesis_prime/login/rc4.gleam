//// An RC4 stream under the session key of the SRP exchange. After the
//// exchange the NC platform library puts RC4 under the 64-byte session key on
//// the connection, one state for the bytes sent and a separate one for the
//// bytes received, both from the same key, no bytes dropped, each running on
//// across messages (StsConnLib64.MT.dll!0x18003a7d0). A stream is a value:
//// ciphering gives the bytes and the stream after them, so a rule can hold it
//// in its state and a recording replays it.

import gleam/bit_array
import gleam/int
import gleam/order

/// One direction's RC4 state: the 256-byte permutation and the two indexes,
/// the one that walks the permutation and the one it swaps with.
pub opaque type Stream {
  Stream(permutation: BitArray, position: Int, swapped_with: Int)
}

/// Why a stream could not start.
pub type StartError {
  /// RC4 is keyed with 1 to 256 bytes; the library's key is 64.
  KeyLengthOutOfRange(bytes: Int)
}

/// A new stream under `key`, at its first byte.
pub fn start(key key: BitArray) -> Result(Stream, StartError) {
  let length = bit_array.byte_size(key)
  case length >= 1 && length <= 256 {
    False -> Error(KeyLengthOutOfRange(bytes: length))
    True ->
      Ok(Stream(
        permutation: schedule(
          key:,
          length:,
          position: 0,
          swapped_with: 0,
          permutation: identity(),
        ),
        position: 0,
        swapped_with: 0,
      ))
  }
}

/// The permutation 0, 1 .. 255.
fn identity() -> BitArray {
  identity_from(0, <<>>)
}

fn identity_from(next: Int, built: BitArray) -> BitArray {
  case next {
    256 -> built
    _ -> identity_from(next + 1, <<built:bits, next>>)
  }
}

/// RC4's key schedule: for each position, the second index moves on by the
/// permutation's byte there and the key's byte at the position modulo the key
/// length, and the two bytes swap.
fn schedule(
  key key: BitArray,
  length length: Int,
  position position: Int,
  swapped_with swapped_with: Int,
  permutation permutation: BitArray,
) -> BitArray {
  case position {
    256 -> permutation
    _ -> {
      let swapped_with =
        {
          swapped_with
          + byte_at(permutation, position)
          + byte_at(key, position % length)
        }
        % 256
      schedule(
        key:,
        length:,
        position: position + 1,
        swapped_with:,
        permutation: swap(permutation:, first: position, second: swapped_with),
      )
    }
  }
}

/// The byte at an index of a byte string known to be long enough.
fn byte_at(bytes: BitArray, index: Int) -> Int {
  let assert <<_:bytes-size(index), byte, _:bytes>> = bytes
    as "the index is inside the bytes"
  byte
}

/// The permutation with the bytes at two indexes exchanged.
fn swap(
  permutation permutation: BitArray,
  first first: Int,
  second second: Int,
) -> BitArray {
  case int.compare(first, second) {
    order.Eq -> permutation
    order.Lt -> swap_ordered(permutation:, low: first, high: second)
    order.Gt -> swap_ordered(permutation:, low: second, high: first)
  }
}

fn swap_ordered(
  permutation permutation: BitArray,
  low low: Int,
  high high: Int,
) -> BitArray {
  let assert <<
    before:bytes-size(low),
    low_byte,
    between:bytes-size(high - low - 1),
    high_byte,
    after:bytes,
  >> = permutation
    as "both indexes are inside the 256 bytes"
  <<before:bits, high_byte, between:bits, low_byte, after:bits>>
}

/// The bytes ciphered with the stream's next bytes, and the stream after
/// them; the same call deciphers.
pub fn crypt(
  stream stream: Stream,
  bytes bytes: BitArray,
) -> #(Stream, BitArray) {
  crypt_each(stream:, bytes:, done: <<>>)
}

fn crypt_each(
  stream stream: Stream,
  bytes bytes: BitArray,
  done done: BitArray,
) -> #(Stream, BitArray) {
  case bytes {
    <<>> -> #(stream, done)
    <<byte, rest:bytes>> -> {
      let position = { stream.position + 1 } % 256
      let swapped_with =
        { stream.swapped_with + byte_at(stream.permutation, position) } % 256
      let permutation =
        swap(
          permutation: stream.permutation,
          first: position,
          second: swapped_with,
        )
      let keystream =
        byte_at(
          permutation,
          {
            byte_at(permutation, position) + byte_at(permutation, swapped_with)
          }
            % 256,
        )
      crypt_each(
        stream: Stream(permutation:, position:, swapped_with:),
        bytes: rest,
        done: <<done:bits, { int.bitwise_exclusive_or(byte, keystream) }>>,
      )
    }
    _ -> panic as "RC4 ciphers whole bytes"
  }
}
