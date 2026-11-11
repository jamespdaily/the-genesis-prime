//// The client's use of a unit with no activate spell (`genesis_prime/message/client_activate_unit`).
//// Expected values come from these places.
//// - `opcode.0xb3`: the body is the unit id, 32 bits, and nothing else; the client
////   writes it with WriteUint32Body (`0x14007d010`) at `0x14039d583`, a 4-byte record
////   in the bit stream's order (least significant bit first).

import genesis_prime/message/client_activate_unit.{ClientActivateUnit}
import genesis_prime/message/client_message
import owned_test

pub fn client_activate_unit_reads_the_unit_id_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_activate_unit.decode(<<0x78, 0x56, 0x34, 0x12>>)
    == Ok(ClientActivateUnit(unit_id: 0x12345678))
    as "the four bytes are the unit id, least significant byte first"
  assert client_message.decode(
      message_id: client_activate_unit.message_id,
      body: <<0x78, 0x56, 0x34, 0x12>>,
    )
    == Ok(
      client_message.ClientActivateUnit(message: ClientActivateUnit(
        unit_id: 0x12345678,
      )),
    )
    as "message 0xb3 is the client's use of a unit"
  assert client_activate_unit.encode(ClientActivateUnit(unit_id: 0x12345678))
    == Ok(<<0x78, 0x56, 0x34, 0x12>>)
    as "the body is written as the client writes it"
  let assert Error(_) = client_activate_unit.decode(<<0x78, 0x56, 0x34>>)
    as "a body short of 32 bits is one the client's reader refuses"
  let assert Error(_) =
    client_activate_unit.decode(<<0x78, 0x56, 0x34, 0x12, 0>>)
    as "a byte after the unit id is more than the client writes"
  Nil
}
