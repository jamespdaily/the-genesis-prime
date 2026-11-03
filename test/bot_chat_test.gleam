//// The scripted client's chat (`game_client`): the line it reads from a 0x1c8 by
//// its strSender and text, and the count of lines that would send it to ask a
//// name (0x597). Saying a line and reading its accept are proven on the whole
//// server (`game_wire_test`). Expected values come from `opcode.0x1c8` (the
//// channel, strSender and text a 0x1c8 carries) and `chat.name_lookup` (no chat
//// line makes the client ask for a name the line already carries).

import game_client.{HeardLine}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/bit_stream
import genesis_prime/message/chat_line
import owned_test

fn line_frame(sender sender: String, text text: String) -> Frame {
  let assert Ok(body) =
    chat_line.encode(chat_line.ChatLine(
      channel_type: 4,
      channel_id: 0,
      gm: 0,
      from_self: 0,
      auto_response: 0,
      sender_realm_id: 1,
      sender_character_id: 42,
      sender_name: sender,
      sender_realm_name: "",
      presence_state: 0,
      text: bit_stream.utf16_units(text),
      formats: [],
      cross_faction: 0,
      field_14: 0,
      unit_id: 5,
      premium_tier: 0,
    ))
  Frame(message_id: chat_line.message_id, body:)
}

pub fn the_bot_reads_a_0x1c8_by_its_channel_sender_and_text_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_client.heard_line(frame: line_frame(
      sender: "Jim Dee",
      text: "Hello",
    ))
    == Ok(HeardLine(
      channel_type: 4,
      channel_id: 0,
      sender: "Jim Dee",
      text: "Hello",
    ))
    as "opcode.0x1c8: the channel's type and id, strSender and the text"
}

pub fn the_bot_reads_nothing_from_a_message_that_is_no_chat_line_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_client.heard_line(frame: Frame(message_id: 0x0262, body: <<>>))
    == Error(Nil)
}

pub fn the_bot_counts_the_lines_that_show_no_sender_as_the_lookups_it_would_ask_test() -> Nil {
  use <- owned_test.run(5000)
  let named =
    HeardLine(channel_type: 4, channel_id: 0, sender: "Jim Dee", text: "a")
  let unnamed = HeardLine(..named, sender: "")
  assert game_client.name_lookups_needed(lines: [named, named]) == 0
    as "chat.name_lookup: a line that carries its sender's name needs no lookup"
  assert game_client.name_lookups_needed(lines: [named, unnamed, unnamed]) == 2
}
