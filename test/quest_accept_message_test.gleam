//// The messages a quest is accepted and retried in: the client's 0x35b and 0x365 and
//// the server's answer 0x35c. Expected values come from these places.
//// - `opcode.0x35b`, writer 0x14008b200: the item place (a 9-bit location and a
////   32-bit bag index; 300 and 0xFFFFFFFF when no item starts the quest, the dialog's
////   defaults at 0x140c7dc6c and 0x140c7dc70) and then the quest id in 15 bits.
//// - `opcode.0x365`, writer 0x14007eea0: the quest id in 15 bits and nothing else.
//// - `opcode.0x35c`, reader 0x14008f100: the quest id in 15 bits, the state in 32 and
////   the QuestObjective id in 32.
//// - The bit stream puts each field from the lowest bit up and pads the last byte
////   (`message_support.packed`), so each body is the widths of the client's code in its
////   order, and the bytes owe nothing to the codec under test. Worked by hand for
////   the first of each: 0x35b of (300, 0xFFFFFFFF, 1872) is the number
////   300 + 0xFFFFFFFF * 2^9 + 1872 * 2^41, which is 2cffffffffa10e as 7 bytes with the
////   low byte first; 0x365 of 2417 is 0x0971 as 7109; 0x35c of (2417, 1, 0) is
////   71890000000000000000.
////
//// Gap: no vector is a client's or a recording's bytes. The live sitting of this step
//// shows the client taking the 0x35c answer.

import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/quest_retry.{QuestRetry}
import genesis_prime/message/quest_state.{QuestState}
import message_support
import owned_test

pub fn quest_accept_requests_decode_as_the_client_writes_them_test() -> Nil {
  use <- owned_test.run(10_000)
  // The dialog's accept: location 300, bag index all ones, quest 1872.
  let dialog =
    message_support.packed([#(9, 300), #(32, 0xFFFFFFFF), #(15, 1872)])
  assert dialog == <<0x2c, 0xff, 0xff, 0xff, 0xff, 0xa1, 0x0e>>
    as "the hand-worked bytes of the dialog's accept"
  message_support.assert_codec(
    name: "0x35b from the dialog (opcode.0x35b)",
    body: dialog,
    value: QuestAccept(
      item: ItemPlace(location: 300, bag_index: 0xFFFFFFFF),
      quest_id: 1872,
    ),
    encode: quest_accept.encode,
    decode: quest_accept.decode,
  )
  // An item's accept: location 1, bag index 0, quest 2417.
  let item = message_support.packed([#(9, 1), #(32, 0), #(15, 2417)])
  assert item == <<0x01, 0x00, 0x00, 0x00, 0x00, 0xe2, 0x12>>
    as "the hand-worked bytes of the item's accept"
  message_support.assert_codec(
    name: "0x35b from an item (opcode.0x35b)",
    body: item,
    value: QuestAccept(
      item: ItemPlace(location: 1, bag_index: 0),
      quest_id: 2417,
    ),
    encode: quest_accept.encode,
    decode: quest_accept.decode,
  )
  // The retry: the quest id alone.
  let retry = message_support.packed([#(15, 2417)])
  assert retry == <<0x71, 0x09>> as "the hand-worked bytes of the retry"
  message_support.assert_codec(
    name: "0x365 (opcode.0x365)",
    body: retry,
    value: QuestRetry(quest_id: 2417),
    encode: quest_retry.encode,
    decode: quest_retry.decode,
  )
  // The answer: quest, state, objective, each as the client's reader takes it.
  let answer = message_support.packed([#(15, 2417), #(32, 1), #(32, 0)])
  assert answer == <<0x71, 0x89, 0, 0, 0, 0, 0, 0, 0, 0>>
    as "the hand-worked bytes of the answer"
  message_support.assert_codec(
    name: "0x35c (opcode.0x35c)",
    body: answer,
    value: QuestState(quest_id: 2417, state: 1, objective_id: 0),
    encode: quest_state.encode,
    decode: quest_state.decode,
  )
}
