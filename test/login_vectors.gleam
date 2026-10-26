//// The emulator vectors of the NC platform library's SRP login, copied from the
//// fact file's `vector.StsConnLib64.MT.dll!0x18002d4e0.srp` and
//// `vector.StsConnLib64.MT.dll!0x1800f7420.rc4` (the library's own code run on
//// Ghidra's p-code emulator) for the SRP, RC4 and STS session tests. The login
//// is account `jim`, password `secret`, salt 01 02 .. 10, the server's secret
//// value b the 32 bytes 51 52 .. 70 (little-endian) and the client's A and M1
//// as in the vector.

import message_support

/// The account name of the vector.
pub const name = "jim"

/// The password of the vector.
pub const password = "secret"

/// The server's secret value b of the vector: the bytes 51 52 .. 70.
pub fn server_secret() -> BitArray {
  message_support.hex(
    "5152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f70",
  )
}

/// The salt of the vector: the bytes 01 02 .. 10.
pub fn salt() -> BitArray {
  message_support.session_key()
}

/// The verifier v of the vector, 128 bytes.
pub fn verifier() -> BitArray {
  message_support.hex(
    "d2395dc97de4055b3fe1c0c64df8dd105346bcba5323ffd945bafd90d1fb 64a870fa542da7c6613be72ed03013d983c9083ecba9415905f0bf5ae6e6 5a2dcabc099dd0ce5c0b3d422d57da6c32cd01b23f456c5148e58fa142a4 94fbed4f569815ef5ffe1157991fc014d90526874586663bdfcc925c705d ebb3a820971c571a",
  )
}

/// The server's first KeyData of the vector: the salt and B, each with its 32-bit length.
pub fn server_key_data() -> BitArray {
  message_support.hex(
    "100000000102030405060708090a0b0c0d0e0f10800000000b12657b1e8e f6bac80c0d7da96c1b4d40f7ce6bd14c2e78e35d0f127a4289f104ff4685 ef439f8ec031a25b30c1290c816897e8f631c4e83775829ef3984327e154 540bb3b02164f22a94be6f0a0c65b398e54933c2dca179cd96ee1fc7c7cb 1a5b1c8aa85a370a6029a15c510a0a6379c9cceac789cc01ea85e902d70c 9520",
  )
}

/// The client's KeyData of the vector: A and M1, each with its 32-bit length.
pub fn client_key_data() -> BitArray {
  message_support.hex(
    "800000005731c398b67289a5846a3e3629731e6e35613c9eb91b4792694e fa2161ef5ec1706c665b283b2f7ad8fa24bd451913ff9ef862b3a0b0f122 c9f110431fec049d2fd2c5f5e1042cb45a00ba0bbc521b54a3a112ca91bc fb08f3f616aa4fd4e1e19fc039aabac8fbf4121921d6475c1223463d861c 417388e9ccdcb606191d9aa4200000006a82e1fd55749d389039786b29bb 1282a7941ba555b9531dbda76025ad62262a",
  )
}

/// The session key K of the vector, 64 bytes.
pub fn session_key() -> BitArray {
  message_support.hex(
    "8e258c4634f929c6ff46dbff8769542234134fb91c4d4048833f7df0662a b6ba25537d30e7430c6ad59f17fada2358f71bab2eb38e93de80d1df98b9 e98d19f3",
  )
}

/// The server's second KeyData of the vector: the length 32 and M2.
pub fn second_server_key_data() -> BitArray {
  message_support.hex(
    "20000000adbf4675ff32174270e72a028a16b3bec015b74c2d04f863ef96 3b9ea2d2df91",
  )
}

/// The server's first KeyData of the vector in base64, as the library reads
/// it in a reply (the vector's own base64).
pub const server_key_data_base64 =
  "EAAAAAECAwQFBgcICQoLDA0ODxCAAAAACxJlex6O9rrIDA19qWwbTUD3zmvRTC54410PEnpCifEE/0aF70OfjsAxolswwSkMgWiX6PYxxOg3dYKe85hDJ+FUVAuzsCFk8iqUvm8KDGWzmOVJM8LcoXnNlu4fx8fLGlsciqhaNwpgKaFcUQoKY3nJzOrHicwB6oXpAtcMlSA="

/// The client's KeyData of the vector in base64, as the library writes it in
/// its request (the vector's own base64).
pub const client_key_data_base64 =
  "gAAAAFcxw5i2comlhGo+NilzHm41YTyeuRtHkmlO+iFh717BcGxmWyg7L3rY+iS9RRkT/574YrOgsPEiyfEQQx/sBJ0v0sX14QQstFoAugu8UhtUo6ESypG8+wjz9haqT9Th4Z/AOaq6yPv0Ehkh1kdcEiNGPYYcQXOI6czctgYZHZqkIAAAAGqC4f1VdJ04kDl4aym7EoKnlBulVblTHb2nYCWtYiYq"

/// The server's second KeyData of the vector in base64 (the vector's M2 bytes
/// encoded as the library encodes binary data, standard base64 with padding).
pub const second_server_key_data_base64 =
  "IAAAAK2/RnX/MhdCcOcqAooWs77AFbdMLQT4Y++WO56i0t+R"
