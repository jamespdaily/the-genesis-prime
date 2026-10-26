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

/// The prime N of RFC 5054's 1024-bit group.
pub fn group_prime() -> Int {
  todo as "N"
}

/// The multiplier k = H(N | g) (StsConnLib64.MT.dll!0x18002d0f0).
pub fn multiplier() -> Int {
  todo as "k"
}

/// The bytes of a number as the library hashes and sends them: 32-bit words,
/// low word first, each little-endian, with no zero top word. Zero has no
/// bytes.
pub fn number_bytes(number number: Int) -> BitArray {
  todo as "the bytes of a number"
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
  todo as "the verifier"
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
  todo as "the first key data"
}

/// Checks the client's key data, its A and M1, and answers with the session
/// key and the server's M2 = SHA-256(A | M1 | K).
pub fn prove(
  challenge challenge: Challenge,
  key_data key_data: BitArray,
) -> Result(Proven, SrpError) {
  todo as "check M1 and answer M2"
}

/// The 64-byte session key made from the bytes of S, with the library's
/// fault (StsConnLib64.MT.dll!0x18002ce20).
pub fn session_key(
  shared_secret_bytes shared_secret_bytes: BitArray,
) -> BitArray {
  todo as "K from S"
}
