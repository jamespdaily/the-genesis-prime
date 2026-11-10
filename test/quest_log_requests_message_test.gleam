//// The messages a player's quest log is changed in: the client's 0x35a (abandon),
//// 0x360 (mention or withdraw), 0x364 (track) and 0x35e (ignore). Expected values come
//// from these places.
//// - `opcode.0x35a`: the quest id in 15 bits and nothing else.
//// - `opcode.0x360`: the quest id in 15 bits and then one bit, which is 1 to mention and
//// 0 to withdraw.
//// - `opcode.0x364`: the quest id in 15 bits and then one bit, 1 to track and 0 to stop.
//// - `opcode.0x35e`: the quest id in 15 bits and then one bit, 1 to ignore and 0 to stop
////   ignoring.
//// - The bit stream puts each field from the lowest bit up and pads the last byte
////   (`message_support.packed`), so each body is the widths of the client's code in its
////   order, and the bytes owe nothing to the codec under test. Worked by hand:
////   0x35a of 1872 is 0x0750, bytes 50 07 with the low byte first; with the bit set
////   the number gains 2^15, so 0x360 of (1872, 1) is 0x8750, bytes 50 87; 0x35e of
////   (2417, 0) is 0x0971, bytes 71 09.
////
//// Gap: no vector is a client's or a recording's bytes. The live sitting of this step
//// shows the client's own requests being taken.

import genesis_prime/message/quest_abandon.{QuestAbandon}
import genesis_prime/message/quest_ignore.{QuestIgnore}
import genesis_prime/message/quest_mention.{QuestMention}
import genesis_prime/message/quest_track.{QuestTrack}
import message_support
import owned_test

pub fn quest_log_requests_decode_as_the_client_writes_them_test() -> Nil {
  use <- owned_test.run(10_000)
  // Abandon: the quest id alone.
  let abandon = message_support.packed([#(15, 1872)])
  assert abandon == <<0x50, 0x07>> as "the hand-worked bytes of the abandon"
  message_support.assert_codec(
    name: "0x35a (opcode.0x35a)",
    body: abandon,
    value: QuestAbandon(quest_id: 1872),
    encode: quest_abandon.encode,
    decode: quest_abandon.decode,
  )
  // Mention: the quest id and the bit.
  let mention = message_support.packed([#(15, 1872), #(1, 1)])
  assert mention == <<0x50, 0x87>> as "the hand-worked bytes of the mention"
  message_support.assert_codec(
    name: "0x360 mentioned (opcode.0x360)",
    body: mention,
    value: QuestMention(quest_id: 1872, mentioned: 1),
    encode: quest_mention.encode,
    decode: quest_mention.decode,
  )
  let withdraw = message_support.packed([#(15, 2417), #(1, 0)])
  assert withdraw == <<0x71, 0x09>> as "the hand-worked bytes of the withdraw"
  message_support.assert_codec(
    name: "0x360 withdrawn (opcode.0x360)",
    body: withdraw,
    value: QuestMention(quest_id: 2417, mentioned: 0),
    encode: quest_mention.encode,
    decode: quest_mention.decode,
  )
  // Track: the quest id and the bit.
  let track = message_support.packed([#(15, 1872), #(1, 1)])
  assert track == <<0x50, 0x87>> as "the hand-worked bytes of the track"
  message_support.assert_codec(
    name: "0x364 tracked (opcode.0x364)",
    body: track,
    value: QuestTrack(quest_id: 1872, tracked: 1),
    encode: quest_track.encode,
    decode: quest_track.decode,
  )
  let untrack = message_support.packed([#(15, 2417), #(1, 0)])
  assert untrack == <<0x71, 0x09>> as "the hand-worked bytes of the untrack"
  message_support.assert_codec(
    name: "0x364 untracked (opcode.0x364)",
    body: untrack,
    value: QuestTrack(quest_id: 2417, tracked: 0),
    encode: quest_track.encode,
    decode: quest_track.decode,
  )
  // Ignore: the quest id and the bit.
  let ignore = message_support.packed([#(15, 2417), #(1, 1)])
  assert ignore == <<0x71, 0x89>> as "the hand-worked bytes of the ignore"
  message_support.assert_codec(
    name: "0x35e ignored (opcode.0x35e)",
    body: ignore,
    value: QuestIgnore(quest_id: 2417, ignored: 1),
    encode: quest_ignore.encode,
    decode: quest_ignore.decode,
  )
  let stop_ignoring = message_support.packed([#(15, 2417), #(1, 0)])
  assert stop_ignoring == <<0x71, 0x09>>
    as "the hand-worked bytes of the stop ignoring"
  message_support.assert_codec(
    name: "0x35e stopped (opcode.0x35e)",
    body: stop_ignoring,
    value: QuestIgnore(quest_id: 2417, ignored: 0),
    encode: quest_ignore.encode,
    decode: quest_ignore.decode,
  )
}
