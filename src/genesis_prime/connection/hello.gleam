//// The hello every server sends the client first on a new connection: the
//// auth server bare, the game server in its wrapper under the base key. It
//// carries build 16042 and the message table checksum 0x097998A0, which the
//// client checks (CheckAuthServerVersion 0x140037b70), the realm's id, and 0
//// in every field the client never reads (opcode.0x3). Any other message
//// before it ends the client's login (0x1400370d0).

import genesis_prime/client_archive
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/server_hello.{ServerHello}

/// The message table checksum the client checks in the hello
/// (CheckAuthServerVersion 0x140037b70).
const message_table_checksum = 0x097998A0

/// The hello's frame for the realm with this id, for the caller to write bare
/// or in a wrapper.
pub fn frame(realm_id realm_id: Int) -> Frame {
  let assert Ok(body) =
    server_hello.encode(ServerHello(
      build: client_archive.target_build,
      realm_id:,
      field_3: 0,
      field_4: 0,
      field_5: 0,
      field_6: 0,
      field_7: 0,
      message_table_checksum:,
      field_9: 0,
      field_10: 0,
      field_11: 0,
    ))
    as "the realm's id is within 32 bits"
  Frame(message_id: server_hello.message_id, body:)
}
