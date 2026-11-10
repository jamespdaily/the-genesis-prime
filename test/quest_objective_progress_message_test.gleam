//// The server's message that sets one objective's progress, 0x361. Expected values come
//// from this place.
//// - `opcode.0x361`, reader 0x14008f100 (the reader 0x35c shares): the quest id in 15
////   bits, the objective index in 32 bits and the progress in 32 bits, in that order.
////   The bit stream puts each field from the lowest bit up and pads the last byte
////   (`message_support.packed`), so the body is the widths of the client's code in its
////   order, and the bytes owe nothing to the codec under test. Worked by hand for quest
////   3668, index 2 and progress 5: the number 3668 + 2 * 2^15 + 5 * 2^47, which is
////   0x0000_0280_0001_0e54 as 10 bytes with the low byte first.
////
//// Gap: no vector is a client's or a recording's bytes. The live sitting of this step
//// shows the client taking the 0x361.

import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import message_support
import owned_test

pub fn objective_progress_message_layout_test() -> Nil {
  use <- owned_test.run(10_000)
  let body = message_support.packed([#(15, 3668), #(32, 2), #(32, 5)])
  assert body == <<0x54, 0x0e, 0x01, 0x00, 0x00, 0x80, 0x02, 0x00, 0x00, 0x00>>
    as "the hand-worked bytes: 15, 32 and 32 bits, the low byte first"
  message_support.assert_codec(
    name: "0x361 (opcode.0x361)",
    body:,
    value: QuestObjectiveProgress(
      quest_id: 3668,
      objective_index: 2,
      progress: 5,
    ),
    encode: quest_objective_progress.encode,
    decode: quest_objective_progress.decode,
  )
}
