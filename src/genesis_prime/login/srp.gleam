//// The server's side of the SRP-6a login the NC platform library speaks
//// (StsConnLib64.MT.dll, record StsConnLib64.MT.dll!0x18002d0f0): SHA-256
//// over the 1024-bit group of RFC 5054 with g = 2, every number hashed and
//// sent as its 32-bit words low word first, each little-endian, with no zero
//// top word, and a digest read as a big-endian number. The library derives
//// the 64-byte session key K with a fault, and the server copies it exactly
//// (StsConnLib64.MT.dll!0x18002ce20): of the bytes of S, starting from the
//// lowest, it drops the ones that are not zero while more than 4 remain, and
//// the key is made only from what is left, which for most S is the top 4
//// bytes.
////
//// The functions are pure: the secret value the server draws is an input.

import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/int
import gleam/list

/// Why a step of the exchange fails. Each ends the login.
pub type SrpError {
  /// The client's key data is not a 32-bit length and A, then 32 and M1,
  /// with nothing after (StsConnLib64.MT.dll!0x18002d4e0).
  KeyDataMalformed
  /// A is zero or not below N, so it gives the client no proof of anything.
  ClientValueRejected
  /// The scrambling value u is zero.
  ScramblerZero
  /// The client's M1 is not the one the server computes: the password is
  /// wrong.
  ProofRefused
  /// The server's secret value is not 32 bytes, the size of the client's own
  /// (StsConnLib64.MT.dll!0x18002d4e0).
  SecretNotThirtyTwoBytes(bytes: Int)
}

/// What the server holds between its first key data and the client's answer.
pub opaque type Challenge {
  Challenge(
    name: String,
    salt: BitArray,
    server_value: Int,
    secret: Int,
    verifier: Int,
  )
}

/// What a client that proved its password gets: the session key K for the RC4
/// that covers the rest of the connection, and the server's second key data
/// (its 32-bit length 32 and M2).
pub type Proven {
  Proven(session_key: BitArray, server_key_data: BitArray)
}

/// The prime N of RFC 5054's 1024-bit group
/// (StsConnLib64.MT.dll!0x18002d0f0).
pub fn group_prime() -> Int {
  0xEEAF0AB9ADB38DD69C33F80AFA8FC5E86072618775FF3C0B9EA2314C9C256576D674DF7496EA81D3383B4813D692C6E0E0D5D8E250B98BE48E495C1D6089DAD15DC7D7B46154D6B6CE8EF4AD69B15D4982559B297BCF1885C529F566660E57EC68EDBC3C05726CC02FD4CBF4976EAA9AFD5138FE8376435B9FC61D2FC0EB06E3
}

/// The generator g of the group, 2.
const generator = 2

/// The multiplier k = H(N | g), where each number is hashed as its
/// `number_bytes` (StsConnLib64.MT.dll!0x18002d0f0).
pub fn multiplier() -> Int {
  digest_number(hash([number_bytes(group_prime()), number_bytes(generator)]))
}

/// The bytes of a number as the library hashes and sends them: 32-bit words,
/// low word first, each little-endian, with no zero top word. Zero has no
/// bytes.
pub fn number_bytes(number: Int) -> BitArray {
  case number {
    0 -> <<>>
    _ -> {
      let bits = words_in(number, 0) * 32
      <<number:size(bits)-little>>
    }
  }
}

/// How many 32-bit words a number needs.
fn words_in(number: Int, counted: Int) -> Int {
  case number {
    0 -> counted
    _ -> words_in(int.bitwise_shift_right(number, 32), counted + 1)
  }
}

/// The number the bytes are, read as `number_bytes` writes them.
fn bytes_number(bytes: BitArray) -> Int {
  let bits = bit_array.bit_size(bytes)
  let assert <<number:size(bits)-little>> = bytes
    as "whole bytes are a little-endian number"
  number
}

/// The SHA-256 of the parts, one after another.
fn hash(parts: List(BitArray)) -> BitArray {
  crypto.hash(crypto.Sha256, bit_array.concat(parts))
}

/// A digest read as a number the way the library reads it: its eight 4-byte
/// groups, the first group the most significant, each group a little-endian
/// word. This is what gives k its value in the record, 0x7D78058F... for a
/// digest that starts 8F 05 78 7D (StsConnLib64.MT.dll!0x18002d0f0).
fn digest_number(digest: BitArray) -> Int {
  digest_words(digest, 0)
}

fn digest_words(digest: BitArray, built: Int) -> Int {
  case digest {
    <<word:size(32)-little, rest:bytes>> ->
      digest_words(rest, built * 4_294_967_296 + word)
    _ -> built
  }
}

@external(erlang, "genesis_prime_login_ffi", "mod_pow")
fn mod_pow(base: Int, exponent: Int, modulus: Int) -> Int

/// P = SHA-256(name ':' password), the value the client keeps of the
/// password (StsConnLib64.MT.dll!0x18002ccd0).
fn password_hash(name: String, password: String) -> BitArray {
  hash([<<name:utf8>>, <<":":utf8>>, <<password:utf8>>])
}

/// The private value x = SHA-256(salt | P) read as a number, with the salt as the library's
/// bytes of the number it reads from the server's key data.
fn private_key(salt: BitArray, password_hash: BitArray) -> Int {
  digest_number(hash([number_bytes(bytes_number(salt)), password_hash]))
}

/// The verifier v = g^x mod N, as `number_bytes`, for a name, a password and
/// a salt, where x = SHA-256(salt | P) and P = SHA-256(name ':' password)
/// (StsConnLib64.MT.dll!0x18002ccd0, 0x18002d4e0). The name is the lower-case
/// name the client sends. The account keeps the result, never the password.
pub fn verifier(
  name name: String,
  password password: String,
  salt salt: BitArray,
) -> BitArray {
  let private_value = private_key(salt, password_hash(name, password))
  number_bytes(mod_pow(generator, private_value, group_prime()))
}

/// Starts the exchange for an account: `secret` is 32 random bytes, the
/// server's b read little-endian. Gives the server's key data to send back to
/// the client, a 32-bit length and the salt, then a 32-bit length and
/// B = (k v + g^b) mod N.
pub fn challenge(
  name name: String,
  salt salt: BitArray,
  verifier verifier: BitArray,
  secret secret: BitArray,
) -> Result(#(Challenge, BitArray), SrpError) {
  case bit_array.byte_size(secret) {
    32 -> {
      let prime = group_prime()
      let secret_value = bytes_number(secret)
      let verifier_value = bytes_number(verifier)
      let server_value =
        {
          multiplier()
          * verifier_value
          + mod_pow(generator, secret_value, prime)
        }
        % prime
      let salt_bytes = number_bytes(bytes_number(salt))
      let started =
        Challenge(
          name:,
          salt: salt_bytes,
          server_value:,
          secret: secret_value,
          verifier: verifier_value,
        )
      Ok(
        #(started, <<
          { bit_array.byte_size(salt_bytes) }:size(32)-little,
          salt_bytes:bits,
          { bit_array.byte_size(number_bytes(server_value)) }:size(32)-little,
          { number_bytes(server_value) }:bits,
        >>),
      )
    }
    size -> Error(SecretNotThirtyTwoBytes(bytes: size))
  }
}

/// Checks the client's key data, its A and M1, and answers with the session
/// key and the server's M2 = SHA-256(A | M1 | K).
pub fn prove(
  challenge challenge: Challenge,
  key_data key_data: BitArray,
) -> Result(Proven, SrpError) {
  case key_data {
    <<
      length:size(32)-little,
      client_bytes:bytes-size(length),
      32:size(32)-little,
      client_proof:bytes-size(32),
    >> -> {
      let client_value = bytes_number(client_bytes)
      case client_value == 0 || client_value >= group_prime() {
        True -> Error(ClientValueRejected)
        False -> prove_value(challenge:, client_value:, client_proof:)
      }
    }
    _ -> Error(KeyDataMalformed)
  }
}

/// The proof of a client whose A is a valid value: the shared secret S =
/// (A v^u)^b mod N, the session key from it, and M1 and M2.
fn prove_value(
  challenge challenge: Challenge,
  client_value client_value: Int,
  client_proof client_proof: BitArray,
) -> Result(Proven, SrpError) {
  let prime = group_prime()
  let client_bytes = number_bytes(client_value)
  let server_bytes = number_bytes(challenge.server_value)
  let scrambler = digest_number(hash([client_bytes, server_bytes]))
  use <- bool.guard(when: scrambler == 0, return: Error(ScramblerZero))
  let verifier_power = mod_pow(challenge.verifier, scrambler, prime)
  let shared =
    mod_pow(client_value * verifier_power % prime, challenge.secret, prime)
  let key = session_key(number_bytes(shared))
  let expected =
    hash([
      xor(hash([number_bytes(prime)]), hash([number_bytes(generator)])),
      hash([<<challenge.name:utf8>>]),
      challenge.salt,
      client_bytes,
      server_bytes,
      key,
    ])
  case crypto.secure_compare(client_proof, expected) {
    True ->
      Ok(
        Proven(session_key: key, server_key_data: <<
          32:size(32)-little,
          { hash([client_bytes, client_proof, key]) }:bits,
        >>),
      )
    False -> Error(ProofRefused)
  }
}

fn xor(left: BitArray, right: BitArray) -> BitArray {
  case left, right {
    <<first, left_rest:bytes>>, <<second, right_rest:bytes>> -> <<
      int.bitwise_exclusive_or(first, second),
      xor(left_rest, right_rest):bits,
    >>
    _, _ -> <<>>
  }
}

/// The 64-byte session key made from the bytes of S, with the library's
/// fault (StsConnLib64.MT.dll!0x18002ce20): from the lowest byte of S, bytes
/// that are not zero are dropped while more than 4 remain. Of the `n` bytes
/// left, E is the `n / 2` bytes taken from the top down, every second one
/// starting with the top byte, and F the same starting with the byte below the
/// top. K takes, for each pair of bytes of SHA-256(E) and SHA-256(F), the first
/// byte of E's pair, the first of F's, the second of E's and the second of F's.
pub fn session_key(shared_secret_bytes: BitArray) -> BitArray {
  let kept = drop_non_zero_bytes(shared_secret_bytes)
  let from_the_top = list.reverse(byte_list(kept))
  let half = bit_array.byte_size(kept) / 2
  let top = every_second(from_the_top, half)
  let below_the_top = every_second(list.drop(from_the_top, 1), half)
  interleave(
    from_top: hash([bytes_of(top)]),
    from_below: hash([bytes_of(below_the_top)]),
    built: <<>>,
  )
}

fn drop_non_zero_bytes(bytes: BitArray) -> BitArray {
  case bytes {
    <<first, rest:bytes>> ->
      case first != 0 && bit_array.byte_size(bytes) > 4 {
        True -> drop_non_zero_bytes(rest)
        False -> bytes
      }
    _ -> bytes
  }
}

fn byte_list(bytes: BitArray) -> List(Int) {
  case bytes {
    <<first, rest:bytes>> -> [first, ..byte_list(rest)]
    _ -> []
  }
}

fn bytes_of(items: List(Int)) -> BitArray {
  list.fold(items, <<>>, fn(built, item) { <<built:bits, item>> })
}

fn every_second(items: List(Int), count: Int) -> List(Int) {
  case count, items {
    0, _ -> []
    _, [first, ..rest] -> [first, ..every_second(list.drop(rest, 1), count - 1)]
    _, [] -> []
  }
}

fn interleave(
  from_top from_top: BitArray,
  from_below from_below: BitArray,
  built built: BitArray,
) -> BitArray {
  case from_top, from_below {
    <<first, second, top_rest:bytes>>, <<third, fourth, below_rest:bytes>> ->
      interleave(from_top: top_rest, from_below: below_rest, built: <<
        built:bits,
        first,
        third,
        second,
        fourth,
      >>)
    _, _ -> built
  }
}
