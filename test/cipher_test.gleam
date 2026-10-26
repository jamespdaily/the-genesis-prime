//// The connection cipher and its keys, on the client's own bytes: the fact
//// file's `vector.*` records are emulator runs of the client's code (Ghidra's
//// p-code emulator over the instructions), copied into `connection_vectors`.
//// The expected values are not computed at test time. Each test names the
//// record or the client address its values come from.

import connection_vectors as vectors
import genesis_prime/connection/cipher
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/string
import owned_test
import seeded
import unitest

fn cipher_for(key: Int) -> cipher.Cipher {
  let assert Ok(built) = cipher.new(key) as "a key other than 0 builds a cipher"
  built
}

/// Whether the cipher built from `key` encrypts every short base-key vector
/// to the client's bytes. The vectors are the fact file's
/// vector.0x1400c2d10.base_key.
fn agrees_with_the_base_key_vectors(key: Int) -> Bool {
  let built = cipher_for(key)
  list.all(vectors.base_key_vectors(), fn(vector) {
    let #(length, expected) = vector
    cipher.encrypt(built, vectors.counting_bytes(length))
    == vectors.hex(expected)
  })
}

fn sha256_hex(bytes: BitArray) -> String {
  bit_array.base16_encode(crypto.hash(crypto.Sha256, bytes))
  |> string.lowercase
}

pub fn the_key_schedule_gives_the_clients_sixteen_words_and_start_under_the_base_key_test() -> Nil {
  use <- owned_test.run(5000)
  let built = cipher_for(cipher.base_key)
  assert cipher.key_words(built)
    == [
      0x5e5632d58e9ac486,
      0x3e99523e2158e443,
      0x8ca81d11b739ae08,
      0x696c006343452715,
      0xbb4864fac37046aa,
      0x87d80e73e857c607,
      0xc84b2b519ef3706c,
      0xbb8d2b5a1e55f319,
      0x96f2844490ad2d4e,
      0x7068e86380d7004b,
      0xe1ef14e2ecfe9f50,
      0xf13a1a4082d65f9d,
      0x75a929e1a3220872,
      0x3e071ed02065a30f,
      0x836922f247accab4,
      0x6a6f8be7ea7e7ca1,
    ]
    as "vector.0x1400c2eb0.base_key: the sixteen words of NewConnectionCipher 0x1400c2eb0 under 0xD283F5B34A8DC685"
  assert cipher.chaining_start(built) == 0x7d546d1d1994c849
    as "vector.0x1400c2eb0.base_key: h of InitConnectionCipher 0x1400c2bd0 under the base key"
}

pub fn the_key_schedule_gives_the_clients_sixteen_words_and_start_under_the_session_key_test() -> Nil {
  use <- owned_test.run(5000)
  let built = cipher_for(vectors.session_key)
  assert cipher.key_words(built)
    == [
      0x515164e35aba7337,
      0xed91845a751813cd,
      0x58f29bb112644ad3,
      0x2f69b4787833f1c9,
      0x884f11770cef9e2f,
      0xa25f159d990f0185,
      0x616b9052e68b494b,
      0xb21f1b4f14a07f01,
      0xf972af89c5b5e827,
      0xee8e29f4f305663d,
      0xe2dbb2021d59d6c3,
      0x6825e2cab3fc7339,
      0xf4ba115652a9311f,
      0xc300ab52d52221f5,
      0x2bef6d51a2b9d33b,
      0x53178e8aedecae71,
    ]
    as "vector.0x1400c2eb0.base_key: the sixteen words under the session key 0xE096253F50C8934E"
  assert cipher.chaining_start(built) == 0x8c35ff38c10b4d11
    as "vector.0x1400c2eb0.base_key: h under the session key"
}

pub fn a_key_of_zero_builds_no_cipher_test() -> Nil {
  use <- owned_test.run(5000)
  assert cipher.new(0) == Error(cipher.ZeroKey)
    as "NewConnectionCipher 0x1400c2eb0: 0x1400c2ed3 test r8, r8; je refuses a key of 0"
}

pub fn the_base_key_is_the_clients_derivation_test() -> Nil {
  use <- owned_test.run(5000)
  let mask = 0xFFFF_FFFF_FFFF_FFFF
  let start = 0x718DA9074F2DEB91
  let derived =
    { { { start + 0x5B88D61139619662 } * 0xAA7F8EA9 + 16_042 } * start }
    + 0x064F77F4AB4E81A0
  assert int.bitwise_and(derived, mask) == cipher.base_key
    as "0x14000a6db..0x14000a70f: the game object's 0x1630 is ((h + 0x5B88D61139619662) * 0xAA7F8EA9 + 16042) * h + 0x064F77F4AB4E81A0 in 64 bits; the emulator run gave 0xd283f5b34a8dc685"
  assert cipher.base_key == 0xD283F5B34A8DC685
    as "0x14000a6db: the emulator run of the client's computation gave 0xD283F5B34A8DC685"
}

pub fn encrypting_the_counting_bytes_under_the_base_key_gives_the_clients_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  let built = cipher_for(cipher.base_key)
  list.each(vectors.base_key_vectors(), fn(vector) {
    let #(length, expected) = vector
    assert cipher.encrypt(built, vectors.counting_bytes(length))
      == vectors.hex(expected)
      as "vector.0x1400c2d10.base_key: EncryptMessageBody 0x1400c2d10 under 0xD283F5B34A8DC685 on 00 01 02 .. of this length"
  })
}

pub fn encrypting_the_counting_bytes_under_the_session_key_gives_the_clients_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(key) =
    cipher.session_key(vectors.session_key_bytes(), cipher.base_key)
    as "the session key bytes are 16"
  assert key == vectors.session_key
    as "vector.0x14003827c.session_fold: key bytes 01 .. 10 fold to 0xE096253F50C8934E"
  let built = cipher_for(key)
  list.each(vectors.session_key_vectors(), fn(vector) {
    let #(length, expected) = vector
    assert cipher.encrypt(built, vectors.counting_bytes(length))
      == vectors.hex(expected)
      as "vector.0x1400c2d10.session_key: EncryptMessageBody 0x1400c2d10 under the folded session key on 00 01 02 .. of this length"
  })
}

pub fn encrypting_53248_bytes_gives_the_clients_hash_under_both_keys_test() -> Nil {
  use <- owned_test.run(10_000)
  let input = vectors.counting_bytes(vectors.long_vector_length)
  assert sha256_hex(input) == vectors.long_vector_input_hash
    as "vector.0x1400c2d10.base_key: the SHA-256 of the 53248-byte input 00 01 02 .."
  assert sha256_hex(cipher.encrypt(cipher_for(cipher.base_key), input))
    == vectors.long_vector_base_key_output_hash
    as "vector.0x1400c2d10.base_key: the SHA-256 of EncryptMessageBody's 53248-byte output under the base key"
  assert sha256_hex(cipher.encrypt(cipher_for(vectors.session_key), input))
    == vectors.long_vector_session_key_output_hash
    as "vector.0x1400c2d10.session_key: the SHA-256 of EncryptMessageBody's 53248-byte output under the session key"
}

pub fn decrypting_the_clients_17_encrypted_bytes_gives_the_counting_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  let counting = vectors.counting_bytes(17)
  assert cipher.decrypt(
      cipher_for(cipher.base_key),
      vectors.hex("195668f6fb7cbd9b8c00b47fb76b8965ee"),
    )
    == counting
    as "vector.0x1400c2de0.length_17: DecryptMessageBody 0x1400c2de0 under the base key gives 00 01 .. 10"
  assert cipher.decrypt(
      cipher_for(vectors.session_key),
      vectors.hex("d29a50df3e48e869e3e0a667f8a7c30eec"),
    )
    == counting
    as "vector.0x1400c2de0.length_17: DecryptMessageBody 0x1400c2de0 under the session key gives 00 01 .. 10"
}

pub fn the_session_key_fold_gives_the_clients_value_for_three_keys_test() -> Nil {
  use <- owned_test.run(5000)
  assert cipher.session_key(vectors.session_key_bytes(), cipher.base_key)
    == Ok(0xE096253F50C8934E)
    as "vector.0x14003827c.session_fold: key bytes 01 02 .. 10 give 0xE096253F50C8934E"
  assert cipher.session_key(<<0:size(128)>>, cipher.base_key)
    == Ok(0x9A868DE642EF9906)
    as "vector.0x14003827c.session_fold: sixteen 00 bytes give 0x9A868DE642EF9906"
  assert cipher.session_key(
      <<0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF:size(128)>>,
      cipher.base_key,
    )
    == Ok(0xBF22CC71B69A0136)
    as "vector.0x14003827c.session_fold: sixteen ff bytes give 0xBF22CC71B69A0136"
}

pub fn a_session_key_of_another_size_is_not_folded_test() -> Nil {
  use <- owned_test.run(5000)
  assert cipher.session_key(<<1, 2, 3>>, cipher.base_key)
    == Error(cipher.SessionKeyNotSixteenBytes(3))
    as "opcode.0x58f: the session key is 16 bytes, folded byte by byte from game 0x1638"
}

pub fn decrypting_what_was_encrypted_gives_the_body_back_for_random_keys_and_bodies_test() -> Nil {
  use <- owned_test.run(120_000)
  let largest_body = 131_064
  let checked =
    int.range(from: 1, to: 1001, with: #(20_261_026, 0), run: fn(state, _case) {
      let #(random, checked) = state
      let #(length, random) = seeded.up_to(random, largest_body)
      let #(key_draw, random) = seeded.up_to(random, 0xFFFF_FFFF_FFFF_FFFE)
      let #(body, random) = seeded.bytes(random, length)
      let built = cipher_for(key_draw + 1)
      assert cipher.decrypt(built, cipher.encrypt(built, body)) == body
        as "DecryptMessageBody 0x1400c2de0 undoes EncryptMessageBody 0x1400c2d10: the emulator run gave every input back; 131064 is the largest body of a frame within the size limit 131070 (0x140335ec0) less its 6 header bytes"
      #(random, checked + 1)
    })
  assert checked.1 == 1000 as "every generated case was checked"
}

pub fn a_cipher_with_one_key_byte_changed_fails_the_clients_vectors_test() -> Nil {
  use <- owned_test.run(5000)
  assert agrees_with_the_base_key_vectors(cipher.base_key)
    as "vector.0x1400c2d10.base_key: the right key passes the vector check"
  let planted_key = int.bitwise_exclusive_or(cipher.base_key, 1)
  assert !agrees_with_the_base_key_vectors(planted_key)
    as "vector.0x1400c2d10.base_key: a key whose low byte is changed gives other bytes, so the check can see a wrong cipher"
}
