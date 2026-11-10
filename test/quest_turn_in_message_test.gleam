//// The message a quest is turned in with: the client's 0x35d. Expected values come from
//// `opcode.0x35d`: the quest id in 15 bits, the chosen reward's Quest2Reward id in 15 bits
//// and one bit that tells whether the communicator opened the dialog, then nothing.
////
//// The bit stream puts each field from the lowest bit up and pads the last byte
//// (`message_support.packed`), so the body is the widths of the client's code in its
//// order, and the bytes owe nothing to the codec under test. Worked by hand for quest
//// 10518 (0x2916), reward 2368 (0x940) and the bit 1: 0x2916 + 0x940 * 2^15 + 2^30 is
//// 0x44a02916, which is 16 29 a0 44 with the low byte first.
////
//// Gap: no vector is a client's or a recording's bytes. The live sitting of this step
//// shows the client's own turn-in taking the answer.

import genesis_prime/message/quest_turn_in.{QuestTurnIn}
import gleam/result
import message_support
import owned_test

pub fn quest_turn_in_reads_the_client_layout_test() -> Nil {
  use <- owned_test.run(10_000)
  let body = message_support.packed([#(15, 10_518), #(15, 2368), #(1, 1)])
  assert body == <<0x16, 0x29, 0xa0, 0x44>> as "the hand-worked bytes"
  message_support.assert_codec(
    name: "0x35d of quest 10518, reward 2368, by communicator (opcode.0x35d)",
    body:,
    value: QuestTurnIn(quest_id: 10_518, reward_id: 2368, by_communicator: 1),
    encode: quest_turn_in.encode,
    decode: quest_turn_in.decode,
  )
  assert result.is_error(quest_turn_in.decode(<<0x16, 0x29, 0xa0>>))
    as "a body shorter than the 31 bits the client's reader takes is refused"
}
