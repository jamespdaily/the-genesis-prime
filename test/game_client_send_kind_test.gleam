//// The kind the scripted client puts in 0x038C for a message id
//// (`game_client.world_send_kind`): each id at the kind of the sender the
//// client's own code sends it through. Expected values come from the fact
//// records of the four senders (`opcode.0x38c.send_kind`; 0x1403f4900,
//// 0x1403f4740, 0x140016010 and 0x1400161d0): the ids each lists and the
//// count of ids at 11 and at 19.

import game_client
import genesis_prime/connection/frame
import genesis_prime/message/send_chat_line
import genesis_prime/message/send_whisper
import genesis_prime/message/world_message
import gleam/int
import gleam/list
import owned_test

pub fn each_message_id_goes_at_the_kind_of_the_sender_the_client_uses_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    // SendWorldMessage: 3.
    #(0x0637, 3, "the movement report"),
    #(0x009A, 3, "the ability press"),
    #(0x07A5, 3, "the level-up fanfare replay"),
    #(0x0956, 3, "the last id of the first sender's list"),
    // SendWorldMessageKind0B and the game connection's 0x140016010: 11.
    #(send_chat_line.message_id, 11, "a chat line"),
    #(send_whisper.message_id, 11, "a whisper"),
    #(0x07CC, 11, "the reward rotation"),
    #(0x03F2, 11, "the first id of the game connection's sender of 11"),
    #(0x0959, 11, "the last id of SendWorldMessageKind0B"),
    // SendGameMessageKind13: 19.
    #(0x082D, 19, "the store catalog ask"),
    #(0x0233, 19, "the first id of the sender of 19"),
  ]
  list.each(rows, fn(row) {
    let #(message_id, kind, reason) = row
    assert game_client.world_send_kind(message_id) == kind
      as { reason <> ": 0x" <> int.to_base16(message_id) }
    let sent = game_client.world_message_body(message_id:, body: <<1>>)
    let assert Ok(carried) = world_message.decode(sent)
      as { reason <> ": 0x038C decodes" }
    assert carried.send_kind == kind
      as { reason <> ": the sent 0x038C carries the kind" }
    let assert Ok(inner) = frame.encode(message_id, <<1>>)
    assert carried.inner_frame == inner
      as { reason <> ": and the message's own frame" }
  })
}

pub fn sixty_five_ids_go_at_11_and_twenty_three_at_19_and_none_at_another_kind_test() -> Nil {
  use <- owned_test.run(5000)
  let kinds =
    int.range(from: 0, to: 0x10000, with: [], run: fn(kinds, message_id) {
      [game_client.world_send_kind(message_id), ..kinds]
    })
  let count = fn(kind) { list.count(kinds, fn(found) { found == kind }) }
  assert count(11) == 65 as "the 58 ids of SendWorldMessageKind0B and 7 more"
  assert count(19) == 23 as "the ids of SendGameMessageKind13"
  assert count(3) == 0x10000 - 65 - 23 as "every other id is at 3"
}
