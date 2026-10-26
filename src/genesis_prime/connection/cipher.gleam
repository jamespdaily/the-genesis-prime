//// The connection cipher the client starts on each connection with a 64-bit
//// key (StartConnectionCipher 0x14002A050, NewConnectionCipher 0x1400C2EB0,
//// InitConnectionCipher 0x1400C2BD0). One cipher serves both ways, and each
//// message is ciphered from the same start: no state carries from one message
//// to the next. It is not a standard cipher, so it is written here from the
//// client's code.

import gleam/bit_array
import gleam/int
import gleam/list

const mask = 0xFFFF_FFFF_FFFF_FFFF

const multiplier = 0xAA7F8EA9

const start = 0x718DA9074F2DEB91

/// Which way a body is ciphered: the chain takes the output word when
/// encrypting and the input word when decrypting.
type Direction {
  Encrypting
  Decrypting
}

/// A connection cipher: the sixteen key words and the chaining start `h`,
/// built from a 64-bit key by `new`.
pub opaque type Cipher {
  Cipher(key_words: List(Int), chaining_start: Int)
}

/// Why a cipher or a session key could not be built.
pub type KeyError {
  /// The client refuses a key of 0 (0x1400C2ED3 test r8, r8; je).
  ZeroKey
  /// A session key is 16 bytes.
  SessionKeyNotSixteenBytes(bytes: Int)
}

/// The client's base cipher key, 0xD283F5B34A8DC685. It keys the auth
/// connection and each new game connection, and is folded into the session
/// key. The client computes it once at start from the build, all 64-bit and
/// wrapping (0x14000A6DB in the game object's constructor 0x14000A490):
/// `((0x718DA9074F2DEB91 + 0x5B88D61139619662) * 0xAA7F8EA9 + 16042) *
/// 0x718DA9074F2DEB91 + 0x064F77F4AB4E81A0`, where 16042 is the build.
pub const base_key = 0xD283F5B34A8DC685

/// Builds a cipher from a 64-bit key. With x = key + 0x718DA9074F2DEB91, each
/// of the sixteen key words in turn is x * 0xAA7F8EA9 (64-bit, wrapping), and x
/// becomes that word + key before the next. The chaining start `h` begins at
/// 0x718DA9074F2DEB91 and, for each key word in order, becomes
/// (h + word) * 0xAA7F8EA9. A key of 0 is refused (0x1400C2EB0, 0x1400C2BD0).
pub fn new(key key: Int) -> Result(Cipher, KeyError) {
  let key = int.bitwise_and(key, mask)
  case key {
    0 -> Error(ZeroKey)
    _ -> {
      let key_words =
        schedule(
          key:,
          x: int.bitwise_and(key + start, mask),
          remaining: 16,
          built: [],
        )
      Ok(Cipher(key_words:, chaining_start: chain(key_words)))
    }
  }
}

fn schedule(
  key key: Int,
  x x: Int,
  remaining remaining: Int,
  built built: List(Int),
) -> List(Int) {
  case remaining {
    0 -> list.reverse(built)
    _ -> {
      let word = int.bitwise_and(x * multiplier, mask)
      schedule(
        key:,
        x: int.bitwise_and(word + key, mask),
        remaining: remaining - 1,
        built: [word, ..built],
      )
    }
  }
}

fn chain(key_words: List(Int)) -> Int {
  list.fold(key_words, start, fn(h, word) {
    int.bitwise_and({ h + word } * multiplier, mask)
  })
}

/// The sixteen key words of a cipher, in order.
pub fn key_words(cipher cipher: Cipher) -> List(Int) {
  cipher.key_words
}

/// The chaining start `h` of a cipher.
pub fn chaining_start(cipher cipher: Cipher) -> Int {
  cipher.chaining_start
}

/// The session key after message 0x58F: the 16 session-key bytes folded from
/// 0x718DA9074F2DEB91 by (h + byte) * 0xAA7F8EA9, then (h + base key) *
/// 0xAA7F8EA9, all 64-bit and wrapping (HandleLoginGameServerHello
/// 0x14003827C..0x1400382C4).
pub fn session_key(
  bytes bytes: BitArray,
  base_key base_key: Int,
) -> Result(Int, KeyError) {
  case bit_array.byte_size(bytes) {
    16 ->
      Ok(int.bitwise_and(
        { fold_bytes(bytes, start) + base_key } * multiplier,
        mask,
      ))
    size -> Error(SessionKeyNotSixteenBytes(size))
  }
}

fn fold_bytes(bytes: BitArray, h: Int) -> Int {
  case bytes {
    <<byte, rest:bytes>> ->
      fold_bytes(rest, int.bitwise_and({ h + byte } * multiplier, mask))
    _ -> h
  }
}

/// Encrypts a message body. With K the key words and h the chaining start, let
/// i = n * 0xAA7F8EAA (only i mod 16 is used) and p = h for a body of n bytes.
/// Each whole 8-byte little-endian word w becomes c = K[i mod 16] xor w xor p,
/// then p = c and i = i + 1. The last n mod 8 bytes are each xored with the
/// byte at the same position of K[i mod 16] and of p. A body of 0 bytes is
/// unchanged (EncryptMessageBody 0x1400C2D10).
pub fn encrypt(cipher cipher: Cipher, body body: BitArray) -> BitArray {
  cipher_body(cipher:, body:, direction: Encrypting)
}

/// Decrypts a message body, undoing `encrypt`: with i and p started the same
/// way, each whole word c becomes K[i mod 16] xor c xor p, then p = c (the
/// ciphertext word); the last n mod 8 bytes are xored as in `encrypt`
/// (DecryptMessageBody 0x1400C2DE0).
pub fn decrypt(cipher cipher: Cipher, body body: BitArray) -> BitArray {
  cipher_body(cipher:, body:, direction: Decrypting)
}

/// Ciphers a body in the given direction. The key word index i starts at
/// n * 0xAA7F8EAA, of which only i mod 16 is used, which is 10 n mod 16.
fn cipher_body(
  cipher cipher: Cipher,
  body body: BitArray,
  direction direction: Direction,
) -> BitArray {
  let #(before, from_first) =
    list.split(cipher.key_words, { bit_array.byte_size(body) * 10 } % 16)
  let keys = list.append(from_first, before)
  words(
    body:,
    keys:,
    all: keys,
    previous: cipher.chaining_start,
    direction:,
    done: <<>>,
  )
}

/// Ciphers the whole 8-byte words, taking the key words in turn, then the tail
/// of fewer than 8 bytes. `keys` starts at K[i mod 16] and `all` is the same
/// sixteen words from K[i mod 16], restarted after the last.
fn words(
  body body: BitArray,
  keys keys: List(Int),
  all all: List(Int),
  previous previous: Int,
  direction direction: Direction,
  done done: BitArray,
) -> BitArray {
  case keys, body {
    [], _ ->
      case all {
        [] -> panic as "a cipher holds sixteen key words"
        [_, ..] -> words(body:, keys: all, all:, previous:, direction:, done:)
      }
    [key, ..following], <<word:size(64)-little, rest:bytes>> -> {
      let ciphered =
        int.bitwise_exclusive_or(int.bitwise_exclusive_or(key, word), previous)
      let chained = case direction {
        Encrypting -> ciphered
        Decrypting -> word
      }
      words(
        body: rest,
        keys: following,
        all:,
        previous: chained,
        direction:,
        done: <<done:bits, ciphered:size(64)-little>>,
      )
    }
    [key, ..], tail -> <<
      done:bits,
      { tail_bytes(tail, int.bitwise_exclusive_or(key, previous)) }:bits,
    >>
  }
}

/// The last bytes of fewer than 8, each xored with the byte at the same
/// position of the key word xor the chaining word, both little-endian.
fn tail_bytes(tail: BitArray, mask_word: Int) -> BitArray {
  let bits = bit_array.bit_size(tail)
  case tail {
    <<value:size(bits)-little>> -> <<
      int.bitwise_exclusive_or(
        value,
        int.bitwise_and(mask_word, int.bitwise_shift_left(1, bits) - 1),
      ):size(bits)-little,
    >>
    _ -> tail
  }
}
