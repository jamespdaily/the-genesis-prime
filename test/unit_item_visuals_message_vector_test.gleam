//// The message that changes a unit's item visuals (0x933) against the layout the
//// client's reader states: `ReadMessage0933Body` 0x1400978c0 reads the unit id (32
//// bits), a count (32 bits) and that many item visuals, each `ReadItemVisual`
//// 0x1400ab890: the slot (7 bits), the display (15 bits), the colour set (14 bits) and
//// the dye (32 bits), packed from the lowest bit (`opcode.0x933`). The bytes below were
//// packed by hand from that layout: the first visual is slot 64 (EngineerMechSuit,
//// `-- ItemSlot 64`) with ItemDisplay 4807 (`-- ItemDisplay 4807`), colour set 0 and
//// dye 0, so its first 22 bits are 64 + 4807 * 128 = 0x0963C0, and the second is the
//// weapon slot 20 with display 3409, colour set 5 and dye 0x12345, which starts at bit
//// 68 of the stream, so it does not begin on a byte.

import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/unit_item_visuals_changed.{UnitItemVisualsChanged}
import message_support
import owned_test

pub fn the_message_number_is_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert unit_item_visuals_changed.message_id == 0x933
    as "opcode.0x933: message 0x933 (2355)"
}

pub fn a_visuals_change_is_the_unit_a_count_and_the_visuals_packed_to_the_clients_reader_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x933: unit 5, a count of 1, slot 64 with display 4807, colour set 0 and dye 0",
    body: message_support.hex(
      "05 00 00 00 01 00 00 00 c0 63 09 00 00 00 00 00 00",
    ),
    value: UnitItemVisualsChanged(unit_id: 5, item_visuals: [
      ItemVisual(slot: 64, display_id: 4807, item_color_set_id: 0, dye: 0),
    ]),
    encode: unit_item_visuals_changed.encode,
    decode: unit_item_visuals_changed.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x933: two visuals, the second not on a byte boundary",
    body: message_support.hex(
      "05 00 00 00 02 00 00 00 c0 63 09 00 00 00 00 00 40 89 6a 14 00 45 23 01 00",
    ),
    value: UnitItemVisualsChanged(unit_id: 5, item_visuals: [
      ItemVisual(slot: 64, display_id: 4807, item_color_set_id: 0, dye: 0),
      ItemVisual(slot: 20, display_id: 3409, item_color_set_id: 5, dye: 0x12345),
    ]),
    encode: unit_item_visuals_changed.encode,
    decode: unit_item_visuals_changed.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x933: a count of 0 holds no visual",
    body: message_support.hex("01 20 00 00 00 00 00 00"),
    value: UnitItemVisualsChanged(unit_id: 0x2001, item_visuals: []),
    encode: unit_item_visuals_changed.encode,
    decode: unit_item_visuals_changed.decode,
  )
}
