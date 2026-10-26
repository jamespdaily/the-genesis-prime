//// The server's side of the SRP-6a exchange, against the vector the library's
//// own code made: fact file `vector.StsConnLib64.MT.dll!0x18002d4e0.srp`
//// (account jim, password secret, salt 01 .. 10, the client's a = 21 22 .. 40
//// and the server's b = 51 52 .. 70, run on Ghidra's p-code emulator), with the
//// group and the session-key derivation from the records
//// `StsConnLib64.MT.dll!0x18002d0f0` and `StsConnLib64.MT.dll!0x18002ce20`.

import genesis_prime/login/srp
import gleam/bit_array
import gleam/crypto
import gleam/int
import login_vectors as vector
import message_support
import owned_test

fn challenge() -> srp.Challenge {
  let assert Ok(#(started, _)) =
    srp.challenge(
      name: vector.name,
      salt: vector.salt(),
      verifier: vector.verifier(),
      secret: vector.server_secret(),
    )
    as "the vector's account starts an exchange"
  started
}

/// The digest bytes of a byte string.
fn sha256(bytes: BitArray) -> BitArray {
  crypto.hash(crypto.Sha256, bytes)
}

/// K as the record `StsConnLib64.MT.dll!0x18002ce20` builds it from E and F: K
/// holds, for i from 0 to 15, G[2i], H[2i], G[2i+1], H[2i+1] at 4i to 4i+3,
/// where G and H are the SHA-256 of E and of F.
fn session_key_of(e e: BitArray, f f: BitArray) -> BitArray {
  interleave(sha256(e), sha256(f), 0, <<>>)
}

fn interleave(
  g: BitArray,
  h: BitArray,
  index: Int,
  built: BitArray,
) -> BitArray {
  case index {
    16 -> built
    _ -> {
      let assert Ok(g_pair) = bit_array.slice(g, 2 * index, 2)
        as "G has 32 bytes"
      let assert Ok(h_pair) = bit_array.slice(h, 2 * index, 2)
        as "H has 32 bytes"
      let assert <<g0, g1>> = g_pair as "a pair"
      let assert <<h0, h1>> = h_pair as "a pair"
      interleave(g, h, index + 1, <<built:bits, g0, h0, g1, h1>>)
    }
  }
}

pub fn the_multiplier_is_the_records_k_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.multiplier()
    == 0x7D78058F0E39285AB924601B3E49AC400652ABEF7D9CCE1D52AABFBC57FF397A
    as "StsConnLib64.MT.dll!0x18002d0f0: k = 0x7D78058F0E39285AB924601B3E49AC400652ABEF7D9CCE1D52AABFBC57FF397A"
}

pub fn the_group_prime_is_the_1024_bit_prime_of_rfc_5054_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.group_prime()
    == 0xEEAF0AB9ADB38DD69C33F80AFA8FC5E86072618775FF3C0B9EA2314C9C256576D674DF7496EA81D3383B4813D692C6E0E0D5D8E250B98BE48E495C1D6089DAD15DC7D7B46154D6B6CE8EF4AD69B15D4982559B297BCF1885C529F566660E57EC68EDBC3C05726CC02FD4CBF4976EAA9AFD5138FE8376435B9FC61D2FC0EB06E3
    as "StsConnLib64.MT.dll!0x18002d0f0: N is the 1024-bit prime of RFC 5054"
  assert bit_array.byte_size(srp.number_bytes(srp.group_prime())) == 128
    as "StsConnLib64.MT.dll!0x18002d0f0: N is 128 bytes"
}

pub fn a_number_is_its_32_bit_words_low_word_first_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.number_bytes(2) == <<2, 0, 0, 0>>
    as "StsConnLib64.MT.dll!0x18002d0f0: g is 02 00 00 00"
  assert srp.number_bytes(0x0102030405) == <<5, 4, 3, 2, 1, 0, 0, 0>>
    as "StsConnLib64.MT.dll!0x18002d0f0: words low word first, each little-endian, no zero top word"
  assert srp.number_bytes(0) == <<>>
    as "StsConnLib64.MT.dll!0x18002d0f0: no zero top word, so zero has no word"
}

pub fn the_verifier_of_jim_and_secret_is_the_vectors_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.verifier(
      name: vector.name,
      password: vector.password,
      salt: vector.salt(),
    )
    == vector.verifier()
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: v's bytes for jim, secret and the salt 01 .. 10"
}

pub fn the_servers_first_key_data_is_the_vectors_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#(_, key_data)) =
    srp.challenge(
      name: vector.name,
      salt: vector.salt(),
      verifier: vector.verifier(),
      secret: vector.server_secret(),
    )
    as "the exchange starts"
  assert key_data == vector.server_key_data()
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: the server's KeyData for b = 51 .. 70 (salt and B)"
}

pub fn a_client_that_proves_its_password_gets_the_vectors_key_and_m2_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.prove(challenge(), vector.client_key_data())
    == Ok(srp.Proven(
      session_key: vector.session_key(),
      server_key_data: vector.second_server_key_data(),
    ))
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: K and the server's second KeyData (M2) for the client's A and M1"
}

pub fn a_client_whose_m1_has_one_bit_changed_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(head) = bit_array.slice(vector.client_key_data(), 0, 167)
    as "the client's key data is 168 bytes"
  let assert Ok(<<last>>) = bit_array.slice(vector.client_key_data(), 167, 1)
    as "the client's key data is 168 bytes"
  let altered = <<head:bits, int.bitwise_exclusive_or(last, 1)>>
  assert srp.prove(challenge(), altered) == Error(srp.ProofRefused)
    as "vector.StsConnLib64.MT.dll!0x18002d4e0: a client that cannot make M1 does not know the password; the library refuses an M2 with one bit changed the same way"
}

pub fn the_wrong_password_gives_a_verifier_whose_proof_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let other =
    srp.verifier(name: vector.name, password: "Secret", salt: vector.salt())
  let assert Ok(#(started, _)) =
    srp.challenge(
      name: vector.name,
      salt: vector.salt(),
      verifier: other,
      secret: vector.server_secret(),
    )
    as "the exchange starts"
  assert srp.prove(started, vector.client_key_data()) == Error(srp.ProofRefused)
    as "the proof M1 holds K, which holds the verifier: a client that typed another password cannot make M1 (StsConnLib64.MT.dll!0x18002d4e0)"
}

pub fn a_client_value_of_zero_is_rejected_test() -> Nil {
  use <- owned_test.run(5000)
  let zero_a = <<
    4:size(32)-little,
    0:size(32),
    32:size(32)-little,
    0:size(256),
  >>
  assert srp.prove(challenge(), zero_a) == Error(srp.ClientValueRejected)
    as "SRP-6a: a server refuses A = 0 mod N, for which S is 0 whatever the password (RFC 5054 section 2.5.4)"
}

pub fn a_client_value_that_is_not_below_n_is_rejected_test() -> Nil {
  use <- owned_test.run(5000)
  let n = srp.number_bytes(srp.group_prime())
  let at_n = <<128:size(32)-little, n:bits, 32:size(32)-little, 0:size(256)>>
  assert srp.prove(challenge(), at_n) == Error(srp.ClientValueRejected)
    as "StsConnLib64.MT.dll!0x18002d4e0: the client's A is g^a mod N, below N, so a value of N or more is not a client's"
}

pub fn key_data_that_is_not_a_and_m1_with_their_lengths_is_malformed_test() -> Nil {
  use <- owned_test.run(5000)
  let whole = vector.client_key_data()
  let assert Ok(short) = bit_array.slice(whole, 0, 167)
    as "a shorter run of the key data"
  assert srp.prove(challenge(), short) == Error(srp.KeyDataMalformed)
    as "StsConnLib64.MT.dll!0x18002d4e0: the client's answer is a length and A, then a length and M1, with nothing missing"
  assert srp.prove(challenge(), <<whole:bits, 0>>)
    == Error(srp.KeyDataMalformed)
    as "StsConnLib64.MT.dll!0x18002d4e0: nothing after M1"
  assert srp.prove(challenge(), <<>>) == Error(srp.KeyDataMalformed)
    as "StsConnLib64.MT.dll!0x18002d4e0: the answer has its lengths"
}

pub fn a_server_secret_that_is_not_32_bytes_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.challenge(
      name: vector.name,
      salt: vector.salt(),
      verifier: vector.verifier(),
      secret: <<1, 2, 3>>,
    )
    == Error(srp.SecretNotThirtyTwoBytes(3))
    as "StsConnLib64.MT.dll!0x18002d4e0: the client draws 32 random bytes for its secret value, and the server's is as long"
}

pub fn the_session_key_is_made_from_the_top_four_bytes_of_s_when_no_byte_is_zero_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.session_key(message_support.hex("01 02 03 04 05 06 07 08"))
    == session_key_of(e: <<8, 6>>, f: <<7, 5>>)
    as "StsConnLib64.MT.dll!0x18002ce20: S bytes 01..08 gave G = SHA-256(08 06) and H = SHA-256(07 05)"
}

pub fn the_session_key_of_nine_bytes_drops_five_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.session_key(message_support.hex("01 02 03 04 05 06 07 08 09"))
    == session_key_of(e: <<9, 7>>, f: <<8, 6>>)
    as "StsConnLib64.MT.dll!0x18002ce20: S bytes 01..09 gave SHA-256(09 07) and SHA-256(08 06)"
}

pub fn the_session_key_stops_dropping_at_the_first_zero_byte_test() -> Nil {
  use <- owned_test.run(5000)
  assert srp.session_key(message_support.hex("00 00 05 06 07 08 09 0a"))
    == session_key_of(e: <<0x0A, 8, 6, 0>>, f: <<9, 7, 5, 0>>)
    as "StsConnLib64.MT.dll!0x18002ce20: S bytes 00 00 05..0a gave SHA-256(0a 08 06 00) and SHA-256(09 07 05 00)"
}

pub fn the_session_key_is_64_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_array.byte_size(srp.session_key(<<1, 2, 3, 4>>)) == 64
    as "StsConnLib64.MT.dll!0x18002ce20: K is 64 bytes, the 32 bytes of each digest interleaved"
}

pub fn a_salt_with_a_zero_top_word_is_hashed_and_sent_without_it_test() -> Nil {
  use <- owned_test.run(5000)
  let short = message_support.hex("01 02 03 04 05 06 07 08 09 0a 0b 0c")
  let padded = <<short:bits, 0, 0, 0, 0>>
  assert srp.verifier(
      name: vector.name,
      password: vector.password,
      salt: padded,
    )
    == srp.verifier(name: vector.name, password: vector.password, salt: short)
    as "StsConnLib64.MT.dll!0x18002d4e0: the library reads the salt as a number and hashes the library's bytes of it, which have no zero top word (StsConnLib64.MT.dll!0x18002d0f0)"
  let assert Ok(#(_, key_data)) =
    srp.challenge(
      name: vector.name,
      salt: padded,
      verifier: vector.verifier(),
      secret: vector.server_secret(),
    )
    as "the exchange starts"
  let assert <<12:size(32)-little, sent:bytes-size(12), _:bytes>> = key_data
    as "the salt is sent with its own 32-bit length"
  assert sent == short
    as "StsConnLib64.MT.dll!0x18002d4e0: the client reads the salt into a number, so the bytes it hashes are the number's"
}
