//// The server's 0x179, the Tutorial row the client queues to show. The client
//// has no writer for it, so no recorded vector exists. Expected values come
//// from the fact `opcode.0x179` (registered at message 0x179, its reader
//// 0x14007ab50 reads one 32-bit value) and from the Tutorial id the client's
//// own table gives the Northern Wilds welcome: 332 (Tutorial.tbl row 332).
//// 332 is 0x14C, which a 32-bit value writes least significant byte first.

import genesis_prime/message/server_tutorial.{ServerTutorial}
import message_support
import owned_test

pub fn server_tutorial_encodes_its_tutorial_id_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_tutorial.message_id == 0x0179
    as "opcode.0x179: the message number the client registers its reader for"
  message_support.assert_codec(
    name: "opcode.0x179 body: one 32-bit tutorial id, 332 as 4c 01 00 00",
    body: message_support.hex("4c 01 00 00"),
    value: ServerTutorial(tutorial_id: 332),
    encode: server_tutorial.encode,
    decode: server_tutorial.decode,
  )
}
