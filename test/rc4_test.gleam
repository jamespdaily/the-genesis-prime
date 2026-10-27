//// The RC4 the NC platform library puts on the connection after the SRP
//// exchange: one state per direction, each keyed with the 64-byte session key,
//// running on across messages (record StsConnLib64.MT.dll!0x18003a7d0; vector
//// `vector.StsConnLib64.MT.dll!0x1800f7420.rc4`, the library's Rc4Crypt run
//// on Ghidra's p-code emulator and equal to standard RC4). Expected values
//// come from these places.
//// - RFC 6229's keystreams: the key 0x0102030405 and the key
////   0x0102030405060708090a0b0c0d0e0f10, the 16 bytes at each listed offset.
//// - OTP's RC4, `crypto:crypto_one_time(rc4, ...)`, which `rc4_oracle_ffi`
////   calls in one piece for a whole message.

import genesis_prime/login/rc4
import gleam/bit_array
import gleam/list
import login_vectors as vector
import message_support
import owned_test
import seeded

@external(erlang, "rc4_oracle_ffi", "encrypt")
fn otp_rc4(key: BitArray, data: BitArray) -> BitArray

fn counting_bytes_to_1f() -> BitArray {
  message_support.hex(
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
  )
}

fn started() -> rc4.Stream {
  let assert Ok(stream) = rc4.start(vector.session_key())
    as "a 64-byte key starts a stream"
  stream
}

fn started_under(key: BitArray) -> rc4.Stream {
  let assert Ok(stream) = rc4.start(key) as "a key of 1 to 256 bytes starts"
  stream
}

pub fn the_bytes_00_to_1f_encrypt_to_the_vectors_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert rc4.crypt(started(), counting_bytes_to_1f()).1
    == message_support.hex(
      "33b03353f0dd9c3bfc19692ca27a45434bb1faaff30a722ddd99edb384eae33c",
    )
    as "vector.StsConnLib64.MT.dll!0x1800f7420.rc4: the bytes 00..1f under K encrypt to 33b03353 ... eae33c"
}

pub fn the_stream_runs_on_across_calls_test() -> Nil {
  use <- owned_test.run(5000)
  let #(stream, _written) = rc4.crypt(started(), counting_bytes_to_1f())
  assert rc4.crypt(stream, <<0, 0, 0, 0>>).1 == message_support.hex("64470a37")
    as "vector.StsConnLib64.MT.dll!0x1800f7420.rc4: the next four zero bytes encrypt to 64470a37 on the same state"
}

pub fn a_second_stream_under_the_same_key_deciphers_the_first_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, sent) = rc4.crypt(started(), counting_bytes_to_1f())
  assert rc4.crypt(started(), sent).1 == counting_bytes_to_1f()
    as "StsConnLib64.MT.dll!0x18003a7d0: the receiving state is keyed with the same key as the sending one, and RC4 deciphers with the same bytes"
}

pub fn a_key_of_no_bytes_does_not_start_a_stream_test() -> Nil {
  use <- owned_test.run(5000)
  assert rc4.start(<<>>) == Error(rc4.KeyLengthOutOfRange(bytes: 0))
    as "RC4 is keyed with 1 to 256 bytes, and the library's key is the 64-byte session key (StsConnLib64.MT.dll!0x18003a7d0)"
}

pub fn a_key_of_more_than_256_bytes_does_not_start_a_stream_test() -> Nil {
  use <- owned_test.run(5000)
  assert rc4.start(<<0:size(2056)>>)
    == Error(rc4.KeyLengthOutOfRange(bytes: 257))
    as "RC4's key is 1 to 256 bytes (RFC 6229 section 1)"
}

/// The 16 keystream bytes RFC 6229 lists at each offset, for the key 0x0102030405
/// (section 2, "Key length: 40 bits").
fn rfc_6229_40_bit_rows() -> List(#(Int, BitArray)) {
  [
    #(0, message_support.hex("b2396305f03dc027ccc3524a0a1118a8")),
    #(16, message_support.hex("6982944f18fc82d589c403a47a0d0919")),
    #(240, message_support.hex("28cb1132c96ce286421dcaadb8b69eae")),
    #(256, message_support.hex("1cfcf62b03eddb641d77dfcf7f8d8c93")),
    #(496, message_support.hex("42b7d0cdd918a8a33dd51781c81f4041")),
    #(512, message_support.hex("6459844432a7da923cfb3eb4980661f6")),
    #(1008, message_support.hex("45129048e6a0ed0b56b490338f078da5")),
    #(1024, message_support.hex("30abbcc7c20b01609f23ee2d5f6bb7df")),
    #(4080, message_support.hex("068326a2118416d21f9d04b2cd1ca050")),
    #(4096, message_support.hex("ff25b58995996707e51fbdf08b34d875")),
  ]
}

/// The same for the key 0x0102030405060708090a0b0c0d0e0f10 (section 2, "Key
/// length: 128 bits").
fn rfc_6229_128_bit_rows() -> List(#(Int, BitArray)) {
  [
    #(0, message_support.hex("9ac7cc9a609d1ef7b2932899cde41b97")),
    #(16, message_support.hex("5248c4959014126a6e8a84f11d1a9e1c")),
    #(240, message_support.hex("065902e4b620f6cc36c8589f66432f2b")),
    #(256, message_support.hex("d39d566bc6bce3010768151549f3873f")),
    #(496, message_support.hex("b6d1e6c4a5e4771cad79538df295fb11")),
    #(512, message_support.hex("c68c1d5c559a974123df1dbc52a43b89")),
    #(1008, message_support.hex("e7a72574f8782ae26aabcf9ebcd66065")),
    #(1024, message_support.hex("bdf0324e6083dcc6d3cedd3ca8c53c16")),
    #(4080, message_support.hex("ff38265c1642c1abe8d3c2fe5e572bf8")),
    #(4096, message_support.hex("a36a4c301ae8ac13610ccbc12256cacc")),
  ]
}

/// Walks one stream through the rows in order: ciphering zero bytes up to each
/// offset and then 16 more, so every row is read after several calls.
fn assert_rows(key: BitArray, rows: List(#(Int, BitArray))) -> Nil {
  let _ =
    list.fold(rows, #(started_under(key), 0), fn(walk, row) {
      let #(stream, position) = walk
      let #(offset, expected) = row
      let #(stream, _skipped) =
        rc4.crypt(stream, <<0:size({ offset - position } * 8)>>)
      let #(stream, keystream) = rc4.crypt(stream, <<0:size(128)>>)
      assert keystream == expected
        as "RFC 6229 section 2: the keystream's 16 bytes at this offset"
      #(stream, offset + 16)
    })
  Nil
}

pub fn the_40_bit_key_gives_rfc_6229s_keystream_at_each_offset_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_rows(<<1, 2, 3, 4, 5>>, rfc_6229_40_bit_rows())
}

pub fn the_128_bit_key_gives_rfc_6229s_keystream_at_each_offset_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_rows(message_support.session_key(), rfc_6229_128_bit_rows())
}

/// `count` whole numbers, the first `first`.
fn count_from(first: Int, count: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, count), fn(_, index) { first + index })
}

/// A message of `length` random bytes and the advanced state.
fn message(state state: Int, length length: Int) -> #(BitArray, Int) {
  seeded.bytes(state:, count: length)
}

/// Ciphers the messages one after another on one stream, and gives each
/// result.
fn crypt_each(stream: rc4.Stream, messages: List(BitArray)) -> List(BitArray) {
  case messages {
    [] -> []
    [first, ..rest] -> {
      let #(stream, ciphered) = rc4.crypt(stream, first)
      [ciphered, ..crypt_each(stream, rest)]
    }
  }
}

pub fn random_keys_and_lengths_give_otps_bytes_across_several_calls_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(count_from(1, 200), fn(round) {
    let state = 20_261_300 + round
    let #(key_length, state) = seeded.up_to(state:, most: 255)
    let #(key, state) = seeded.bytes(state:, count: key_length + 1)
    let #(call_count, state) = seeded.up_to(state:, most: 5)
    let #(messages, _state) =
      list.fold(count_from(0, call_count + 1), #([], state), fn(drawn, _) {
        let #(built, state) = drawn
        let #(length, state) = seeded.up_to(state:, most: 600)
        let #(bytes, state) = message(state:, length:)
        #([bytes, ..built], state)
      })
    let messages = list.reverse(messages)
    assert bit_array.concat(crypt_each(started_under(key), messages))
      == otp_rc4(key, bit_array.concat(messages))
      as "OTP's RC4 over the whole message equals the Gleam RC4 over its parts, in order"
  })
}
