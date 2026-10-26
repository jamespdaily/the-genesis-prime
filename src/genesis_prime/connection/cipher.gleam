//// The connection cipher the client starts on each connection with a 64-bit
//// key (StartConnectionCipher 0x14002A050, NewConnectionCipher 0x1400C2EB0,
//// InitConnectionCipher 0x1400C2BD0). One cipher serves both ways, and each
//// message is ciphered from the same start: no state carries from one message
//// to the next. It is not a standard cipher, so it is written here from the
//// client's code.

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
  todo as "build the key schedule"
}

/// The sixteen key words of a cipher, in order.
pub fn key_words(cipher cipher: Cipher) -> List(Int) {
  todo as "the key words"
}

/// The chaining start `h` of a cipher.
pub fn chaining_start(cipher cipher: Cipher) -> Int {
  todo as "the chaining start"
}

/// The session key after message 0x58F: the 16 session-key bytes folded from
/// 0x718DA9074F2DEB91 by (h + byte) * 0xAA7F8EA9, then (h + base key) *
/// 0xAA7F8EA9, all 64-bit and wrapping (HandleLoginGameServerHello
/// 0x14003827C..0x1400382C4).
pub fn session_key(
  bytes bytes: BitArray,
  base_key base_key: Int,
) -> Result(Int, KeyError) {
  todo as "fold the session key"
}

/// Encrypts a message body. With K the key words and h the chaining start, let
/// i = n * 0xAA7F8EAA (only i mod 16 is used) and p = h for a body of n bytes.
/// Each whole 8-byte little-endian word w becomes c = K[i mod 16] xor w xor p,
/// then p = c and i = i + 1. The last n mod 8 bytes are each xored with the
/// byte at the same position of K[i mod 16] and of p. A body of 0 bytes is
/// unchanged (EncryptMessageBody 0x1400C2D10).
pub fn encrypt(cipher cipher: Cipher, body body: BitArray) -> BitArray {
  todo as "encrypt a body"
}

/// Decrypts a message body, undoing `encrypt`: with i and p started the same
/// way, each whole word c becomes K[i mod 16] xor c xor p, then p = c (the
/// ciphertext word); the last n mod 8 bytes are xored as in `encrypt`
/// (DecryptMessageBody 0x1400C2DE0).
pub fn decrypt(cipher cipher: Cipher, body body: BitArray) -> BitArray {
  todo as "decrypt a body"
}
