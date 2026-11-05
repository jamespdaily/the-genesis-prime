//// A player's chat as a pure rule (genesis_prime/game/chat): what the client's
//// 0x1c3 is answered with and told to, and what a line another connection told
//// this one writes. Expected values come from the client's facts, each named in
//// the assertion: `opcode.0x1c3`, `opcode.0x1c2`, `opcode.0x1c8`,
//// `opcode.0x1d3`, `0x140402720` (ParseChatText), `0x140085ca0` (a format),
//// `ChatChannel.flags` and `0x140405cb0` (the chat message ids start at 1), and
//// from the design's decisions, each marked as such.

import character_tables
import client_tables
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/chat.{type Chat}
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell.{Line, Said, Speaker}
import genesis_prime/game/top_zone
import genesis_prime/message/bit_stream
import genesis_prime/message/chat_channel_joined.{ChatChannelJoined}
import genesis_prime/message/chat_channel_result.{
  DoesntExist, InvalidMessageText, NoPermissions, NotInGroup,
}
import genesis_prime/message/chat_format.{type ChatFormat, ItemGuid, Kind1}
import genesis_prime/message/chat_format_article_id
import genesis_prime/message/chat_format_filter_mask
import genesis_prime/message/chat_format_item_guid.{ChatFormatItemGuid}
import genesis_prime/message/chat_format_item_id
import genesis_prime/message/chat_format_item_record
import genesis_prime/message/chat_format_kind_0
import genesis_prime/message/chat_format_kind_1.{ChatFormatKind1}
import genesis_prime/message/chat_format_kind_11
import genesis_prime/message/chat_format_kind_2
import genesis_prime/message/chat_format_kind_3
import genesis_prime/message/chat_format_navigation_point
import genesis_prime/message/chat_format_quest_id
import genesis_prime/message/chat_line.{ChatLine}
import genesis_prime/message/chat_line_accepted.{ChatLineAccepted}
import genesis_prime/message/chat_result.{ChatResult}
import genesis_prime/message/chat_zone_named.{ChatZoneNamed}
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/message/send_whisper.{SendWhisper}
import genesis_prime/message/whisper_failed.{type WhisperFailed, WhisperFailed}
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/chat_channel as chat_channel_table
import genesis_prime/table/id.{ChatChannelId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import qcheck
import unitest

const world_id = 3460

const run = 77

fn speaker() -> chat_tell.Speaker {
  Speaker(
    realm_id: 1,
    character_id: 42,
    name: "Ab Cd",
    faction_id: 166,
    unit_id: 5,
    map: MapId(world_id:, instance: 0),
    incarnation: run,
  )
}

fn chat_of(speaker: chat_tell.Speaker) -> Chat {
  chat.new(speaker:, next_whisper: 1)
}

fn a_chat() -> Chat {
  chat_of(speaker())
}

fn body(
  type_id type_id: Int,
  channel_id channel_id: Int,
  text text: List(Int),
  formats formats: List(ChatFormat),
  message_id message_id: Int,
) -> BitArray {
  let assert Ok(body) =
    send_chat_line.encode(SendChatLine(
      channel_type: type_id,
      channel_id:,
      text:,
      formats:,
      chat_message_id: message_id,
    ))
    as "the line fits its fields"
  body
}

/// A plain line of text "Hello" on (type, 0) with slot 1.
fn hello(type_id: Int) -> BitArray {
  body(
    type_id:,
    channel_id: 0,
    text: bit_stream.utf16_units("Hello"),
    formats: [],
    message_id: 1,
  )
}

fn take(
  message message: chat.Message,
  chat chat: Chat,
  body body: BitArray,
  viewers viewers: List(Int),
) -> #(Chat, List(chat.Effect)) {
  let assert Ok(taken) =
    chat.take(
      chat:,
      message:,
      body:,
      viewers: set.from_list(list.map(viewers, ConnectionId)),
      realm_name: "Test Realm",
      connection: ConnectionId(1),
      tables: character_tables.shared(),
    )
    as "the body decodes"
  taken
}

fn frames_of(effects: List(chat.Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      chat.Send(frame:) -> Ok(frame)
      chat.Tell(..)
      | chat.TellWatched(..)
      | chat.UnknownZone(..)
      | chat.Watch(..)
      | chat.Unwatch(..)
      | chat.JoinGroup(..)
      | chat.LeaveGroup(..)
      | chat.Unhandled(..) -> Error(Nil)
    }
  })
}

/// The tells of the effects, in order.
fn tells_of(
  effects: List(chat.Effect),
) -> List(#(step.Address, chat_tell.Tell)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      chat.Tell(to:, tell:) -> Ok(#(to, tell))
      chat.Send(..)
      | chat.TellWatched(..)
      | chat.UnknownZone(..)
      | chat.Watch(..)
      | chat.Unwatch(..)
      | chat.JoinGroup(..)
      | chat.LeaveGroup(..)
      | chat.Unhandled(..) -> Error(Nil)
    }
  })
}

/// The numbers of the connections a line was told to, in order.
fn said_to(effects: List(chat.Effect)) -> List(Int) {
  list.filter_map(tells_of(effects), fn(told) {
    case told {
      #(step.Connection(ConnectionId(number)), Said(..)) -> Ok(number)
      #(_, _) -> Error(Nil)
    }
  })
}

fn only_frame(effects: List(chat.Effect)) -> Frame {
  let assert [frame] = frames_of(effects) as "exactly one message to the client"
  frame
}

fn accepted(effects: List(chat.Effect)) -> chat_line_accepted.ChatLineAccepted {
  let frame = only_frame(effects)
  assert frame.message_id == chat_line_accepted.message_id
    as "opcode.0x1c2: the answer to an accepted line"
  let assert Ok(accept) = chat_line_accepted.decode(frame.body)
  accept
}

fn refused(effects: List(chat.Effect)) -> chat_result.ChatResult {
  let frame = only_frame(effects)
  assert frame.message_id == chat_result.message_id
    as "opcode.0x1d3: the answer to a refused line"
  let assert Ok(result) = chat_result.decode(frame.body)
  result
}

fn nothing_told(effects: List(chat.Effect)) -> Bool {
  tells_of(effects) == []
}

fn reader_of(speaker: chat_tell.Speaker) -> List(chat.Effect) {
  let reader = chat_of(speaker)
  chat.told(
    reader,
    Said(
      speaker: Speaker(..speaker, name: "Zed Other"),
      line: Line(
        channel_type: chat_channel.Say,
        channel_id: 0,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
      ),
    ),
  ).1
}

// ---- the speaker ----

pub fn an_accepted_say_yell_or_emote_gets_one_0x1c2_with_the_slot_the_name_the_unit_and_no_item_record_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([4, 5, 8], fn(type_id) {
    let #(_, effects) =
      take(
        message: chat.LineSent,
        chat: a_chat(),
        body: hello(type_id),
        viewers: [],
      )
    assert accepted(effects)
      == ChatLineAccepted(
        chat_message_id: 1,
        gm: 0,
        name: "Ab Cd",
        realm_name: "",
        unit_id: 5,
        premium_tier: 0,
      )
      as "opcode.0x1c2: the same chat message id, the speaker's own name, an empty realm name and the speaker's unit id; Jim 2026-11-03: yell and emote work like say"
  })
}

pub fn the_speaker_gets_no_0x1c8_for_its_own_line_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    take(message: chat.LineSent, chat: a_chat(), body: hello(4), viewers: [7, 8])
  assert list.filter(frames_of(effects), fn(frame) {
      frame.message_id == chat_line.message_id
    })
    == []
    as "opcode.0x1c2, opcode.0x1c8: the accept shows the line, and a 0x1c8 as well would show it twice"
}

pub fn each_viewer_is_told_the_line_on_its_own_channel_type_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([4, 5, 8], fn(type_id) {
    let #(_, effects) =
      take(
        message: chat.LineSent,
        chat: a_chat(),
        body: hello(type_id),
        viewers: [7, 8],
      )
    assert list.sort(said_to(effects), int.compare) == [7, 8]
      as "the speaker's viewers are the players it sees: one tell to each (design C: one sender for each pair)"
    let assert [#(_, Said(speaker: told, line:)), ..] = tells_of(effects)
    assert told == speaker()
    assert line
      == Line(
        channel_type: chat_channel.from_id(type_id),
        channel_id: 0,
        text: bit_stream.utf16_units("Hello"),
        formats: [],
      )
      as "the line keeps its channel, text and formats as sent"
  })
}

pub fn a_player_out_of_sight_is_told_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    take(message: chat.LineSent, chat: a_chat(), body: hello(4), viewers: [])
  assert said_to(effects) == []
    as "chat.range: the line reaches the players who see the speaker, and with none it reaches no one"
  assert nothing_told(effects)
}

// ---- the viewer ----

pub fn a_viewer_writes_one_0x1c8_with_every_field_the_design_lists_test() -> Nil {
  use <- owned_test.run(5000)
  let viewer =
    chat_of(
      Speaker(
        ..speaker(),
        character_id: 9,
        name: "Zed Other",
        faction_id: 166,
        unit_id: 6,
      ),
    )
  let #(_, effects) =
    chat.told(
      viewer,
      Said(
        speaker: speaker(),
        line: Line(
          channel_type: chat_channel.Yell,
          channel_id: 0,
          text: bit_stream.utf16_units("Hello"),
          formats: [Kind1(ChatFormatKind1(start: 0, end: 5, field_4: 0xA1B2))],
        ),
      ),
    )
  let frame = only_frame(effects)
  assert frame.message_id == chat_line.message_id
  let assert Ok(line) = chat_line.decode(frame.body)
  assert line
    == ChatLine(
      channel_type: 5,
      channel_id: 0,
      gm: 0,
      from_self: 0,
      auto_response: 0,
      sender_realm_id: 1,
      sender_character_id: 42,
      sender_name: "Ab Cd",
      sender_realm_name: "",
      presence_state: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [Kind1(ChatFormatKind1(start: 0, end: 5, field_4: 0xA1B2))],
      cross_faction: 0,
      field_14: 0,
      unit_id: 5,
      premium_tier: 0,
    )
    as "opcode.0x1c8 and the design's 0x1c8 fields: the line's channel; bGM, bSelf, bAutoResponse, presence, premium tier and the unread value 0; the speaker's realm, character, name and unit; an empty realm name; the same faction"
}

pub fn bcrossfaction_is_1_only_when_the_factions_differ_on_every_channel_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [chat_channel.Say, chat_channel.Yell, chat_channel.Emote],
    fn(channel) {
      let told = fn(reader_faction) {
        let reader =
          chat_of(
            Speaker(..speaker(), character_id: 9, faction_id: reader_faction),
          )
        let #(_, effects) =
          chat.told(
            reader,
            Said(
              speaker: speaker(),
              line: Line(
                channel_type: channel,
                channel_id: 0,
                text: bit_stream.utf16_units("Hi"),
                formats: [],
              ),
            ),
          )
        let assert Ok(line) = chat_line.decode(only_frame(effects).body)
        line.cross_faction
      }
      assert told(166) == 0 as "chat.cross_faction: the same faction, no flag"
      assert told(167) == 1
        as "chat.cross_faction: another faction sets bCrossFaction, on every channel (Jim, 2026-11-03)"
    },
  )
}

pub fn a_viewer_drops_a_line_naming_another_map_or_another_run_of_the_map_test() -> Nil {
  use <- owned_test.run(5000)
  let reader = chat_of(Speaker(..speaker(), character_id: 9))
  let line =
    Line(
      channel_type: chat_channel.Say,
      channel_id: 0,
      text: bit_stream.utf16_units("Hi"),
      formats: [],
    )
  list.each(
    [
      Speaker(..speaker(), map: MapId(world_id: 1387, instance: 0)),
      Speaker(..speaker(), incarnation: run + 1),
    ],
    fn(other) {
      assert chat.told(reader, Said(speaker: other, line:)).1 == []
        as "a line from another map or run is dropped, as unit news is: the unit id there may name another unit (server choice)"
    },
  )
}

pub fn a_viewer_the_speaker_no_longer_sees_still_writes_the_line_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.length(frames_of(reader_of(speaker()))) == 1
    as "the design's failure table: a viewer just Unwatched is told and writes, since channel (t, 0) is always held"
}

// ---- refusals ----

fn assert_refused(
  bytes bytes: BitArray,
  type_id type_id: Int,
  channel_id channel_id: Int,
  result result: chat_channel_result.ChatChannelResult,
  message_id message_id: Int,
  because because: String,
) -> Nil {
  let #(after, effects) =
    take(message: chat.LineSent, chat: a_chat(), body: bytes, viewers: [7])
  assert refused(effects)
    == ChatResult(
      channel_type: type_id,
      channel_id:,
      result:,
      chat_message_id: message_id,
    )
    as because
  assert nothing_told(effects) as "nobody else gets anything"
  assert after == a_chat() as "a refused line changes nothing"
}

pub fn a_line_of_501_units_is_taken_and_502_is_refused_with_result_17_test() -> Nil {
  use <- owned_test.run(5000)
  let long = fn(count) {
    body(
      type_id: 4,
      channel_id: 0,
      text: list.repeat(0x61, count),
      formats: [],
      message_id: 3,
    )
  }
  list.each([499, 500, 501], fn(count) {
    let #(_, effects) =
      take(
        message: chat.LineSent,
        chat: a_chat(),
        body: long(count),
        viewers: [],
      )
    assert accepted(effects).chat_message_id == 3
      as "chat.sent_text_length: the cut at 499 runs once for each pass, so a link or waypoint tag at 498 units sends a text of 500 or 501 units"
  })
  assert_refused(
    bytes: long(502),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 3,
    because: "chat.sent_text_length: no pass of ParseChatText sends more than 501 units",
  )
}

pub fn an_unclosed_type_1_or_2_format_goes_with_end_65535_and_other_ranges_are_checked_test() -> Nil {
  use <- owned_test.run(5000)
  let unclosed_1 =
    chat_format.Kind1(chat_format_kind_1.ChatFormatKind1(
      start: 2,
      end: 65_535,
      field_4: 9,
    ))
  let unclosed_2 =
    chat_format.Kind2(chat_format_kind_2.ChatFormatKind2(
      start: 0,
      end: 65_535,
      field_4: 0,
    ))
  let closed_empty =
    chat_format.Kind1(chat_format_kind_1.ChatFormatKind1(
      start: 3,
      end: 3,
      field_4: 9,
    ))
  list.each([unclosed_1, unclosed_2, closed_empty], fn(format) {
    let #(_, effects) =
      take(
        message: chat.LineSent,
        chat: a_chat(),
        body: body(
          type_id: 4,
          channel_id: 0,
          text: bit_stream.utf16_units("Hello"),
          formats: [format],
          message_id: 5,
        ),
        viewers: [7],
      )
    assert accepted(effects).chat_message_id == 5
      as "chat.format_bounds: an unclosed <#> or <*> is sent with end 65535, and a closed type 1 or 2 can have start = end"
    let assert [#(_, Said(line:, ..))] = tells_of(effects)
    assert line.formats == [format]
      as "it is relayed as sent, end 65535 included"
  })
  let past_the_text =
    chat_format.ItemId(chat_format_item_id.ChatFormatItemId(
      start: 0,
      end: 65_535,
      item_id: 1,
    ))
  assert_refused(
    bytes: body(
      type_id: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [past_the_text],
      message_id: 5,
    ),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 5,
    because: "chat.format_bounds: only types 1 and 2 go unclosed; a link with its end past the text's units is refused",
  )
  let start_past_text =
    chat_format.Kind1(chat_format_kind_1.ChatFormatKind1(
      start: 6,
      end: 65_535,
      field_4: 9,
    ))
  assert_refused(
    bytes: body(
      type_id: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [start_past_text],
      message_id: 5,
    ),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 5,
    because: "chat.format_bounds: every format starts within the text, an unclosed one too",
  )
}

pub fn a_character_parsechattext_drops_is_refused_and_0xa0_is_taken_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      0x00,
      0x01,
      0x0A,
      0x0D,
      0x1E,
      0x7F,
      0x80,
      0x9F,
      0xAD,
      0x2028,
      0x2029,
      0xFEFF,
      0xFFFE,
      0xFFFF,
      0xFDD0,
      0xFDEF,
    ],
    fn(character) {
      assert_refused(
        bytes: body(
          type_id: 4,
          channel_id: 0,
          text: [0x61, character, 0x62],
          formats: [],
          message_id: 2,
        ),
        type_id: 4,
        channel_id: 0,
        result: InvalidMessageText,
        message_id: 2,
        because: "0x140402720 and 0x1403e0ae0: ParseChatText drops this character, so the client never sends it",
      )
    },
  )
  let #(_, effects) =
    take(
      message: chat.LineSent,
      chat: a_chat(),
      body: body(
        type_id: 4,
        channel_id: 0,
        text: [0x61, 0xA0, 0x62],
        formats: [],
        message_id: 2,
      ),
      viewers: [],
    )
  assert accepted(effects).chat_message_id == 2
    as "vector.0x140402720.lines: ParseChatText keeps 0xa0"
}

pub fn an_empty_0x1c3_is_refused_with_result_17_test() -> Nil {
  use <- owned_test.run(5000)
  assert_refused(
    bytes: body(type_id: 4, channel_id: 0, text: [], formats: [], message_id: 4),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 4,
    because: "0x140401e40, 0x140402720: the client sends 0x1c3 only for a text it kept, and an empty one only after ParseChatText dropped every character",
  )
}

pub fn a_format_whose_start_is_past_its_end_or_whose_end_is_past_the_text_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let guid = fn(start, end) {
    ItemGuid(ChatFormatItemGuid(start:, end:, item_guid: 1))
  }
  assert_refused(
    bytes: body(
      type_id: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [guid(3, 2)],
      message_id: 5,
    ),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 5,
    because: "0x140085ca0: a format's start past its end is no range of a text",
  )
  assert_refused(
    bytes: body(
      type_id: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [guid(0, 6)],
      message_id: 5,
    ),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 5,
    because: "0x140085ca0: a format's end past the text's 5 UTF-16 units",
  )
  let #(_, effects) =
    take(
      message: chat.LineSent,
      chat: a_chat(),
      body: body(
        type_id: 4,
        channel_id: 0,
        text: bit_stream.utf16_units("Hello"),
        formats: [guid(0, 5)],
        message_id: 5,
      ),
      viewers: [],
    )
  assert accepted(effects).chat_message_id == 5
    as "a range that ends at the text's end is a range of it"
}

pub fn a_format_range_counts_utf_16_units_not_characters_test() -> Nil {
  use <- owned_test.run(5000)
  // U+1F600 is two UTF-16 units: the text is 3 units of 2 characters.
  let text = [0x61, 0xD83D, 0xDE00]
  let format = fn(end) {
    ItemGuid(ChatFormatItemGuid(start: 0, end:, item_guid: 1))
  }
  let #(_, effects) =
    take(
      message: chat.LineSent,
      chat: a_chat(),
      body: body(
        type_id: 4,
        channel_id: 0,
        text:,
        formats: [format(3)],
        message_id: 6,
      ),
      viewers: [],
    )
  assert accepted(effects).chat_message_id == 6
    as "0x140336040: the count and the ranges are in 16-bit units, so a range to 3 is inside a text of 3 units"
  assert_refused(
    bytes: body(
      type_id: 4,
      channel_id: 0,
      text:,
      formats: [format(4)],
      message_id: 6,
    ),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 6,
    because: "a range to 4 is past a text of 3 units",
  )
}

pub fn a_lone_surrogate_is_relayed_as_the_client_sent_it_test() -> Nil {
  use <- owned_test.run(5000)
  let text = [0x61, 0xD800, 0x62]
  let #(_, effects) =
    take(
      message: chat.LineSent,
      chat: a_chat(),
      body: body(type_id: 4, channel_id: 0, text:, formats: [], message_id: 7),
      viewers: [9],
    )
  assert accepted(effects).chat_message_id == 7
    as "0x1403e0ae0 lets 0xD800 through ParseChatText, so a sound client may send it and the server does not refuse it"
  let assert [#(_, Said(line:, ..))] = tells_of(effects)
  assert line.text == text as "the unit reaches the readers unchanged"
}

pub fn chat_message_id_0_is_refused_with_result_17_test() -> Nil {
  use <- owned_test.run(5000)
  assert_refused(
    bytes: body(
      type_id: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hi"),
      formats: [],
      message_id: 0,
    ),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 0,
    because: "0x140405cb0: the client's ids start at 1, and no answer could free slot 0",
  )
}

pub fn a_channel_the_player_does_not_hold_is_refused_with_result_1_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#(15, 0), #(11, 0), #(4, 5), #(5, 1), #(8, 9)], fn(channel) {
    assert_refused(
      bytes: body(
        type_id: channel.0,
        channel_id: channel.1,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
        message_id: 8,
      ),
      type_id: channel.0,
      channel_id: channel.1,
      result: DoesntExist,
      message_id: 8,
      because: "ChatChannel.flags, 0x140401cb0: Guild (4) and Trade (0x80, joined by the server only) are not held, and a made-by-the-client channel has id 0 only",
    )
  })
}

pub fn a_row_without_flag_4_is_refused_with_result_3_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2, 20], fn(type_id) {
    assert_refused(
      bytes: body(
        type_id:,
        channel_id: 0,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
        message_id: 9,
      ),
      type_id:,
      channel_id: 0,
      result: NoPermissions,
      message_id: 9,
      because: "ChatChannel.flags: Command (8), System (8) and NPCSay (24) are held and have no flag 4, so the player may not send on them",
    )
  })
}

pub fn type_6_or_34_in_a_0x1c3_is_refused_with_result_3_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([6, 34], fn(type_id) {
    assert_refused(
      bytes: body(
        type_id:,
        channel_id: 0,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
        message_id: 9,
      ),
      type_id:,
      channel_id: 0,
      result: NoPermissions,
      message_id: 9,
      because: "0x140401e40: the client sends a whisper only as 0x1d4",
    )
  })
}

pub fn party_is_refused_with_result_8_test() -> Nil {
  use <- owned_test.run(5000)
  assert_refused(
    bytes: hello(7),
    type_id: 7,
    channel_id: 0,
    result: NotInGroup,
    message_id: 1,
    because: "lua.ChatSystemLib.ChatChannelResult: no group exists, and 8 is the client's own text for that (server choice)",
  )
}

pub fn support_and_instance_are_refused_with_result_3_and_named_as_unhandled_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [#(19, chat_channel.Support), #(32, chat_channel.Instance)],
    fn(channel) {
      let #(_, effects) =
        take(
          message: chat.LineSent,
          chat: a_chat(),
          body: hello(channel.0),
          viewers: [7],
        )
      assert refused(effects)
        == ChatResult(
          channel_type: channel.0,
          channel_id: 0,
          result: NoPermissions,
          chat_message_id: 1,
        )
        as "Jim, 2026-11-03: Support and Instance are refused with result 3"
      assert list.contains(effects, chat.Unhandled(channel_type: channel.1))
        as "the channel is logged as unhandled"
      assert said_to(effects) == [] as "nobody else gets anything"
    },
  )
}

pub fn text_and_formats_reach_readers_as_sent_with_no_format_added_and_no_word_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let text = bit_stream.utf16_units("damn <b>word</b> fuck")
  let formats = [
    Kind1(ChatFormatKind1(start: 1, end: 2, field_4: 3)),
    ItemGuid(ChatFormatItemGuid(start: 0, end: 4, item_guid: 9)),
  ]
  let #(_, effects) =
    take(
      message: chat.LineSent,
      chat: a_chat(),
      body: body(type_id: 4, channel_id: 0, text:, formats:, message_id: 1),
      viewers: [7],
    )
  assert accepted(effects).chat_message_id == 1
    as "0x140c45f50: ParseChatText runs no word filter, so no line is refused for its words"
  let assert [#(_, Said(line:, ..))] = tells_of(effects)
  assert line.text == text
  assert line.formats == formats
    as "0x140c45f50: each reader masks its own filter's words, so the server adds no type 7 format"
}

pub fn every_0x1c3_gets_exactly_one_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  let generator =
    qcheck.tuple4(
      qcheck.from_generators(qcheck.return(4), [
        qcheck.return(5),
        qcheck.return(8),
        qcheck.return(9),
        qcheck.return(6),
        qcheck.return(7),
        qcheck.return(15),
        qcheck.return(19),
        qcheck.return(1),
        qcheck.return(34),
        qcheck.bounded_int(from: 0, to: 40),
      ]),
      qcheck.from_generators(qcheck.return(0), [
        qcheck.bounded_int(from: 0, to: 4),
      ]),
      qcheck.generic_list(
        qcheck.from_generators(qcheck.bounded_int(from: 0x20, to: 0x7E), [
          qcheck.bounded_int(from: 0, to: 0x30),
          qcheck.bounded_int(from: 0xD7F0, to: 0xE010),
        ]),
        qcheck.from_generators(qcheck.bounded_int(from: 0, to: 6), [
          qcheck.bounded_int(from: 495, to: 505),
        ]),
      ),
      qcheck.bounded_int(from: 0, to: 3),
    )
  use #(type_id, channel_id, text, message_id) <- qcheck.given(generator)
  let #(_, effects) =
    take(
      message: chat.LineSent,
      chat: a_chat(),
      body: body(type_id:, channel_id:, text:, formats: [], message_id:),
      viewers: [7],
    )
  let answers =
    list.filter(frames_of(effects), fn(frame) {
      frame.message_id == chat_line_accepted.message_id
      || frame.message_id == chat_result.message_id
    })
  assert list.length(answers) == 1
    as "opcode.0x1c2: every 0x1c3 gets exactly one of 0x1c2 or 0x1d3, whatever its channel, text and slot"
  assert list.length(frames_of(effects)) == 1
    as "and no other message to the client"
}

// ---- the planted rows ----

pub fn the_planted_chat_channel_rows_and_the_channel_types_are_the_clients_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let real = client_tables.shared()
  list.each(character_tables.chat_channels(), fn(planted) {
    let #(row_id, name, flags) = planted
    let assert Ok(row) =
      chat_channel_table.get(tables: real, id: ChatChannelId(row_id))
      as "the planted channel has a row in the client's table"
    assert #(row.enum_name, row.flags) == #(name, flags)
      as "ChatChannel: the planted enumName and flags are the real ones"
  })
  list.each(
    [
      #(chat_channel.Say, "Say"),
      #(chat_channel.Yell, "Yell"),
      #(chat_channel.Whisper, "Whisper"),
      #(chat_channel.Party, "Party"),
      #(chat_channel.Emote, "Emote"),
      #(chat_channel.Zone, "Zone"),
      #(chat_channel.Support, "Support"),
      #(chat_channel.Instance, "Instance"),
      #(chat_channel.AccountWhisper, "AccountWhisper"),
    ],
    fn(channel) {
      let assert Ok(row) =
        chat_channel_table.get(
          tables: real,
          id: ChatChannelId(chat_channel.id(channel.0)),
        )
        as "the channel type's id is a ChatChannel row"
      assert row.enum_name == channel.1
        as "the row's enumName is the channel type's name"
      assert chat_channel.from_id(row.id) == channel.0
    },
  )
}

// ---- zone ----

/// The zone channel's id: one for every world (the coordinator's design on
/// the zone chat step; the client has no rule on it, `chat.zone_channel_id`).
const zone_channel_id = 1

fn top_zones() -> top_zone.TopZones {
  top_zone.top_zones(character_tables.shared())
}

/// A chat that has entered the world with its place in `world_zone_id`.
fn in_zone(
  speaker: chat_tell.Speaker,
  world_zone_id: Int,
) -> #(Chat, List(chat.Effect)) {
  chat.entered_world(
    chat: chat_of(speaker),
    world_zone_id:,
    top_zones: top_zones(),
  )
}

fn run_zone(world_zone_id: Int) -> Chat {
  in_zone(speaker(), world_zone_id).0
}

fn zone_channel(top_zone_id: Int) -> step.Address {
  step.ZoneChannel(
    map: MapId(world_id:, instance: 0),
    incarnation: run,
    top_zone_id:,
  )
}

fn reported(chat: Chat, world_zone_id: Int) -> #(Chat, List(chat.Effect)) {
  chat.world_zone_reported(chat:, world_zone_id:, top_zones: top_zones())
}

fn terrain_ready(chat: Chat, world_zone_id: Int) -> #(Chat, List(chat.Effect)) {
  chat.terrain_ready(chat:, world_zone_id:, top_zones: top_zones())
}

fn named_by_0x1da(effects: List(chat.Effect)) -> List(Int) {
  list.filter_map(frames_of(effects), fn(frame) {
    case frame.message_id == chat_zone_named.message_id {
      True -> {
        let assert Ok(named) = chat_zone_named.decode(frame.body)
        Ok(named.world_zone_id)
      }
      False -> Error(Nil)
    }
  })
}

/// The (channel type, channel id) each 0x1bc among the effects gives.
fn joined_by_0x1bc(effects: List(chat.Effect)) -> List(#(Int, Int)) {
  list.filter_map(frames_of(effects), fn(frame) {
    case frame.message_id == chat_channel_joined.message_id {
      True -> {
        let assert Ok(joined) = chat_channel_joined.decode(frame.body)
        Ok(#(joined.channel_type, joined.channel_id))
      }
      False -> Error(Nil)
    }
  })
}

fn unknown_zones_of(effects: List(chat.Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      chat.UnknownZone(world_zone_id:) -> Ok(world_zone_id)
      chat.Send(..)
      | chat.Tell(..)
      | chat.TellWatched(..)
      | chat.Watch(..)
      | chat.Unwatch(..)
      | chat.JoinGroup(..)
      | chat.LeaveGroup(..)
      | chat.Unhandled(..) -> Error(Nil)
    }
  })
}

fn zone_line(chat: Chat, message_id: Int) -> #(Chat, List(chat.Effect)) {
  take(
    message: chat.LineSent,
    chat:,
    body: body(
      type_id: 9,
      channel_id: zone_channel_id,
      text: bit_stream.utf16_units("Hello"),
      formats: [],
      message_id:,
    ),
    viewers: [7],
  )
}

fn zone_named_frame(world_zone_id: Int) -> Frame {
  let assert Ok(body) = chat_zone_named.encode(ChatZoneNamed(world_zone_id:))
  Frame(message_id: chat_zone_named.message_id, body:)
}

pub fn the_entry_burst_names_the_channel_joins_it_and_joins_the_groups_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = in_zone(speaker(), 6009)
  let assert [
    chat.JoinGroup(named),
    chat.Send(named_zone),
    chat.Send(joined),
    chat.JoinGroup(zone),
  ] = effects
    as "after 0x61: the name group, 0x1da, 0x1bc and the zone channel's group"
  assert named == step.CharacterNamed("ab cd")
    as "the folded name (design: string.lowercase)"
  assert chat_zone_named.decode(named_zone.body)
    == Ok(ChatZoneNamed(world_zone_id: 4961))
    as "opcode.0x1da: the channel is named after the top zone 4961 of the place's zone 6009 (6009 -> 4962 -> 4961)"
  assert joined.message_id == chat_channel_joined.message_id
  assert chat_channel_joined.decode(joined.body)
    == Ok(ChatChannelJoined(
      channel_type: 9,
      channel_id: zone_channel_id,
      name: "",
      field_4: 0,
      field_5: 0,
      field_6: 0,
    ))
    as "opcode.0x1bc: type 9, the fixed id 1, an empty name and three zeros; the order lets the flag 0x400 row take the name 0x1da last gave"
  assert zone == zone_channel(4961)
}

pub fn no_0x1bc_is_written_for_a_channel_the_client_makes_itself_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = in_zone(speaker(), 6009)
  let types = list.map(joined_by_0x1bc(effects), fn(joined) { joined.0 })
  assert types == [9]
    as "0x140404ee0: the client makes Say, Yell, Emote, Whisper and AccountWhisper itself, and a 0x1bc for one only prints a join again; Zone is the one the server joins"
}

pub fn the_entry_burst_gives_the_zone_channel_id_1_in_every_world_test() -> Nil {
  use <- owned_test.run(5000)
  let joined_id = fn(speaker) {
    let #(_, effects) = in_zone(speaker, 6009)
    let assert [_, chat.Send(named), chat.Send(frame), _] = effects
    assert named.message_id == chat_zone_named.message_id
      && frame.message_id == chat_channel_joined.message_id
      as "0x1da comes before 0x1bc"
    let assert [#(9, channel_id)] = joined_by_0x1bc(effects)
    channel_id
  }
  assert joined_id(speaker()) == 1
    as "chat.zone_channel_id, server choice: the client has no rule on a Zone channel's id, and one id is one ChatLog save key"
  assert joined_id(
      Speaker(..speaker(), map: MapId(world_id: 1387, instance: 0)),
    )
    == 1
    as "the same id in another world, so a caught Zone stays viewed there"
  assert joined_id(Speaker(..speaker(), incarnation: run + 5)) == 1
    as "and in another run of the map"
}

pub fn the_first_0xf2_of_a_stay_writes_0x1bc_for_the_zone_channel_again_and_no_later_one_does_test() -> Nil {
  use <- owned_test.run(5000)
  let #(entered, _) = in_zone(speaker(), 6009)
  let #(first_stay, first) = terrain_ready(entered, 6009)
  assert joined_by_0x1bc(first) == [#(9, 1)]
    as "chat.zone_join_trigger: ChatLog registers ChatJoin after 0xad, so the first 0xf2 of the stay gives the client the Zone channel again; a 0x1bc for a held channel only raises ChatJoin, which changes no window's channels (OnChatJoin's nil test) but posts the join line and closes the input boxes again (ChatLog.lua 954-959, chat.zone_view)"
  let #(first_stay, second) = terrain_ready(first_stay, 6009)
  assert joined_by_0x1bc(second) == []
    as "a second 0xf2 in the same stay writes none"
  let #(_, third) = terrain_ready(first_stay, 648)
  assert joined_by_0x1bc(third) == []
    as "nor does one that reports another top zone; it only renames the channel"
  let #(new_stay, _) = in_zone(speaker(), 6009)
  assert joined_by_0x1bc(terrain_ready(new_stay, 6009).1) == [#(9, 1)]
    as "a new Chat (made at each entry, after a camp) writes it again"
}

pub fn a_place_zone_that_is_0_or_has_no_row_leaves_the_player_in_no_zone_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat_in_0, in_0) = in_zone(speaker(), 0)
  assert named_by_0x1da(in_0) == [0]
    as "0x140403670: 0x1da with 0 shows the channel with an empty name"
  assert list.length(frames_of(in_0)) == 2
    as "0x1bc is still written: the client makes the zone channel from it"
  assert list.filter(in_0, fn(effect) {
      effect == chat.JoinGroup(zone_channel(0))
    })
    == []
  assert unknown_zones_of(in_0) == []
    as "zone 0 is the table's own no-zone value, so nothing is named"
  let #(_, no_row) = in_zone(speaker(), 1132)
  assert named_by_0x1da(no_row) == [0]
  assert unknown_zones_of(no_row) == [1132]
    as "a place zone with no WorldZone row is server data gone wrong: the zone is named for a warning, and the connection does not end"
  let #(_, line) = zone_line(chat_in_0, 1)
  assert accepted(line).chat_message_id == 1
    as "a zone line of a player in no zone is accepted"
  assert tells_of(line) == [] as "and reaches no one"
}

pub fn a_report_under_the_same_top_zone_writes_nothing_and_keeps_the_group_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, effects) = reported(run_zone(1411), 1305)
  assert effects == []
    as "chat.zone_reach: 1411 and 1305 are both under the top zone 1304, so nothing changes"
  let #(_, line) = zone_line(chat, 2)
  assert list.map(tells_of(line), fn(told) { told.0 }) == [zone_channel(1304)]
    as "the group is kept"
}

pub fn a_report_under_another_top_zone_changes_the_group_and_renames_the_channel_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, effects) = reported(run_zone(1411), 648)
  assert effects
    == [
      chat.LeaveGroup(zone_channel(1304)),
      chat.JoinGroup(zone_channel(35)),
      chat.Send(zone_named_frame(35)),
    ]
    as "0x140403670: the client only renames the channel, so the id 1 stays: leave the old group, join the new, write 0x1da with the new top zone"
  let #(_, line) = zone_line(chat, 3)
  let assert [#(address, chat_tell.ZoneLine(line: told, ..))] = tells_of(line)
  assert address == zone_channel(35)
  assert told.channel_id == zone_channel_id as "the channel is still (9, 1)"
}

pub fn a_report_of_zone_0_leaves_the_group_and_names_no_zone_and_a_zone_line_reaches_no_one_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, effects) = reported(run_zone(1411), 0)
  assert effects
    == [chat.LeaveGroup(zone_channel(1304)), chat.Send(zone_named_frame(0))]
    as "0x14036d040: the client reports 0 before any probe answer; 0x140403670: 0x1da with 0 shows the empty name"
  let #(_, line) = zone_line(chat, 4)
  assert accepted(line).chat_message_id == 4
    as "a zone line from that player is accepted"
  assert tells_of(line) == [] as "and reaches no one"
  let #(_, again) = reported(chat, 0)
  assert again == [] as "a second report of 0 writes nothing"
  let #(_, back) = reported(chat, 1411)
  assert back
    == [chat.JoinGroup(zone_channel(1304)), chat.Send(zone_named_frame(1304))]
    as "a zone after zone 0 joins its group and names the channel"
}

pub fn a_report_of_a_zone_with_no_row_is_no_zone_and_is_named_not_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, effects) = reported(run_zone(1411), 1132)
  assert effects
    == [
      chat.UnknownZone(world_zone_id: 1132),
      chat.LeaveGroup(zone_channel(1304)),
      chat.Send(zone_named_frame(0)),
    ]
    as "0x140403670: the client accepts a zone with no row and names the channel with an empty name, so the report is no refusal (the coordinator's decision): the player leaves its group, 0x1da gives 0, and the zone is named for one warning"
  let #(_, line) = zone_line(chat, 4)
  assert accepted(line).chat_message_id == 4 && tells_of(line) == []
    as "a zone line of that player is accepted and reaches no one"
  let #(_, again) = reported(chat, 1132)
  assert again == [chat.UnknownZone(world_zone_id: 1132)]
    as "a second report of the same zone writes nothing more; the rule names it again and the connection logs it once"
}

pub fn a_zone_line_is_accepted_and_told_to_the_group_of_the_speakers_run_and_top_zone_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = zone_line(run_zone(1411), 5)
  assert accepted(effects).chat_message_id == 5
  let assert [
    #(address, chat_tell.ZoneLine(speaker: told, top_zone_id:, line:)),
  ] = tells_of(effects)
  assert address == zone_channel(1304) && top_zone_id == 1304
    as "Jim, 2026-11-03: the reach is the top zone of the zone the client reports, in the same map run"
  assert told == speaker()
  assert line.channel_type == chat_channel.Zone
    && line.channel_id == zone_channel_id
}

fn member_hears(
  member member: Chat,
  zone_line_from speaker: chat_tell.Speaker,
  top top_zone_id: Int,
) -> List(chat.Effect) {
  chat.told(
    member,
    chat_tell.ZoneLine(
      speaker:,
      top_zone_id:,
      line: Line(
        channel_type: chat_channel.Zone,
        channel_id: zone_channel_id,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
      ),
    ),
  ).1
}

fn other_player() -> chat_tell.Speaker {
  Speaker(..speaker(), character_id: 9, name: "Zed Other", unit_id: 6)
}

pub fn a_member_of_the_group_writes_the_line_on_the_zone_channel_and_the_speaker_drops_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let member = in_zone(other_player(), 1305).0
  let effects =
    member_hears(member: member, zone_line_from: speaker(), top: 1304)
  let assert Ok(line) = chat_line.decode(only_frame(effects).body)
  assert line.channel_type == 9
    && line.channel_id == zone_channel_id
    && line.sender_name == "Ab Cd"
    as "opcode.0x1c8: one 0x1c8 on (9, 1)"
  assert member_hears(
      member: run_zone(1411),
      zone_line_from: speaker(),
      top: 1304,
    )
    == []
    as "a zone line from the player's own character is dropped: the accept shows it"
}

pub fn two_players_in_different_sub_zones_of_one_top_zone_share_the_group_and_others_do_not_test() -> Nil {
  use <- owned_test.run(5000)
  let address_of = fn(speaker, zone) {
    let #(_, effects) = zone_line(in_zone(speaker, zone).0, 6)
    let assert [#(address, _)] = tells_of(effects)
    address
  }
  assert address_of(speaker(), 1411) == address_of(other_player(), 1305)
    as "chat.zone_reach: the client reports the leaf, 1411 and 1305 are leaves of the top zone 1304: both hear each other"
  assert address_of(speaker(), 1411) != address_of(other_player(), 648)
    as "a player in the same map under another top zone gets nothing (Jim, 2026-11-03)"
  assert address_of(speaker(), 1411)
    != address_of(
      Speaker(..other_player(), map: MapId(world_id: 1387, instance: 0)),
      1305,
    )
    as "a player in another map gets nothing"
  assert address_of(speaker(), 1411)
    != address_of(Speaker(..other_player(), incarnation: run + 1), 1305)
    as "a player in another run of the map gets nothing"
}

pub fn a_member_that_changed_top_zone_or_run_drops_a_line_told_to_the_old_group_test() -> Nil {
  use <- owned_test.run(5000)
  let moved = reported(in_zone(other_player(), 1305).0, 648).0
  assert member_hears(member: moved, zone_line_from: speaker(), top: 1304) == []
    as "the design's failure table: it left the group but was still listed when the speaker told it, so it drops the line as being for another top zone"
  let other_run =
    in_zone(Speaker(..other_player(), incarnation: run + 1), 1305).0
  assert member_hears(member: other_run, zone_line_from: speaker(), top: 1304)
    == []
    as "or for another run"
  let no_zone = reported(in_zone(other_player(), 1305).0, 0).0
  assert member_hears(member: no_zone, zone_line_from: speaker(), top: 1304)
    == []
    as "a player in no zone takes no zone line"
}

pub fn a_speaker_that_camps_after_speaking_has_told_the_group_and_leaves_its_groups_test() -> Nil {
  use <- owned_test.run(5000)
  let chat = run_zone(1411)
  let #(_, line) = zone_line(chat, 7)
  assert list.length(tells_of(line)) == 1
    as "the line was told in the step that took it, so the others still get it"
  assert chat.left(chat)
    == [
      chat.LeaveGroup(step.CharacterNamed("ab cd")),
      chat.LeaveGroup(zone_channel(1304)),
    ]
    as "the camp's leave: no zone line reaches the player after it, and a new entry joins again"
}

pub fn a_zone_line_on_channel_1_is_taken_and_one_before_its_0x1bc_or_on_the_worlds_id_is_refused_with_result_1_test() -> Nil {
  use <- owned_test.run(5000)
  let send = fn(chat, channel_id) {
    take(
      message: chat.LineSent,
      chat:,
      body: body(
        type_id: 9,
        channel_id:,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
        message_id: 8,
      ),
      viewers: [],
    ).1
  }
  let refuse = fn(chat, channel_id) { refused(send(chat, channel_id)) }
  let expected = fn(channel_id) {
    ChatResult(
      channel_type: 9,
      channel_id:,
      result: DoesntExist,
      chat_message_id: 8,
    )
  }
  assert accepted(send(run_zone(1411), 1)).chat_message_id == 8
    as "chat.zone_channel_id: the held Zone channel's id is 1, so a line on (9, 1) is taken"
  assert refuse(a_chat(), 1) == expected(1)
    as "0x140401cb0: the client holds a Zone channel only after the server's 0x1bc"
  assert refuse(run_zone(1411), world_id) == expected(world_id)
    as "0x140401cb0: (9, the map's world id) is a channel the player does not hold"
  assert refuse(run_zone(1411), 2) == expected(2)
    as "another id is no channel the player holds"
  assert refuse(run_zone(1411), 0) == expected(0)
    as "Zone is never made by the client with id 0"
}

pub fn the_memberships_one_player_holds_after_entering_changing_zone_camping_and_entering_again_are_one_for_each_group_test() -> Nil {
  use <- owned_test.run(5000)
  // The groups the effects leave a connection in, with a join of a group already
  // held keeping one membership, as the registry does (`registry_group_test`).
  let apply = fn(groups: List(step.Address), effects: List(chat.Effect)) {
    list.fold(effects, groups, fn(groups, effect) {
      case effect {
        chat.JoinGroup(address:) ->
          case list.contains(groups, address) {
            True -> groups
            False -> [address, ..groups]
          }
        chat.LeaveGroup(address:) ->
          list.filter(groups, fn(held) { held != address })
        chat.Send(..)
        | chat.Tell(..)
        | chat.TellWatched(..)
        | chat.UnknownZone(..)
        | chat.Watch(..)
        | chat.Unwatch(..)
        | chat.Unhandled(..) -> groups
      }
    })
  }
  let name = step.CharacterNamed("ab cd")
  let #(chat, entered) = in_zone(speaker(), 1411)
  let groups = apply([], entered)
  assert same_groups(groups, [name, zone_channel(1304)])
  let #(chat, changed) = reported(chat, 648)
  let groups = apply(groups, changed)
  assert same_groups(groups, [name, zone_channel(35)])
    as "a change of top zone leaves the old group and joins the new one"
  let groups = apply(groups, chat.left(chat))
  assert groups == [] as "the camp leaves every group"
  let #(_, again) = in_zone(speaker(), 1411)
  let groups = apply(groups, again)
  assert same_groups(groups, [name, zone_channel(1304)])
    as "a new entry joins again: exactly one membership for each group"
}

/// Whether the groups held are exactly these, each once.
fn same_groups(held: List(step.Address), expected: List(step.Address)) -> Bool {
  list.length(held) == list.length(expected)
  && list.all(expected, fn(group) { list.contains(held, group) })
}

// ---- whisper ----

const first_watch = 100

fn whisper_body(
  target target: String,
  realm realm: String,
  text text: String,
  message_id message_id: Int,
  account account: Int,
) -> BitArray {
  let assert Ok(body) =
    send_whisper.encode(SendWhisper(
      target_name: bit_stream.utf16_units(target),
      target_realm_name: bit_stream.utf16_units(realm),
      text: bit_stream.utf16_units(text),
      formats: [],
      chat_message_id: message_id,
      account:,
    ))
    as "the whisper fits its fields"
  body
}

fn whisper(chat chat: Chat, body body: BitArray) -> #(Chat, List(chat.Effect)) {
  take(message: chat.WhisperSent, chat:, body:, viewers: [])
}

/// A whisper "Hi" to the target, with slot 3.
fn whisper_to(chat: Chat, target: String) -> #(Chat, List(chat.Effect)) {
  whisper(
    chat:,
    body: whisper_body(
      target:,
      realm: "",
      text: "Hi",
      message_id: 3,
      account: 0,
    ),
  )
}

fn failed(effects: List(chat.Effect)) -> WhisperFailed {
  let frame = only_frame(effects)
  assert frame.message_id == whisper_failed.message_id
    as "opcode.0x1d9: the answer to a whisper that was not delivered"
  let assert Ok(failure) = whisper_failed.decode(frame.body)
  failure
}

fn target_player() -> chat_tell.Speaker {
  Speaker(
    ..speaker(),
    character_id: 9,
    name: "Cd Ef",
    faction_id: 166,
    unit_id: 6,
  )
}

fn the_whisper(effects: List(chat.Effect)) -> chat_tell.Tell {
  let assert [chat.Watch(..), chat.TellWatched(tell:, ..)] = effects
    as "a watch of the target's name, then a tell through it"
  tell
}

pub fn a_whisper_to_an_online_character_watches_its_name_tells_through_the_watch_and_waits_for_the_reply_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = whisper_to(a_chat(), "Cd Ef")
  assert effects
    == [
      chat.Watch(
        watch: step.WatchId(first_watch + 1),
        target: step.CharacterNamed("cd ef"),
      ),
      chat.TellWatched(
        watch: step.WatchId(first_watch + 1),
        tell: chat_tell.Whisper(
          whisper: 1,
          speaker: speaker(),
          from: ConnectionId(1),
          line: Line(
            channel_type: chat_channel.Whisper,
            channel_id: 0,
            text: bit_stream.utf16_units("Hi"),
            formats: [],
          ),
        ),
      ),
    ]
    as "the design's sequence: Watch(w, CharacterNamed(folded name)), then the tell through that watch; nothing is written until the reply"
}

pub fn the_target_writes_one_0x1c8_on_the_whisper_channel_and_tells_the_speaker_heard_test() -> Nil {
  use <- owned_test.run(5000)
  let tell = the_whisper(whisper_to(a_chat(), "Cd Ef").1)
  let #(_, effects) = chat.told(chat_of(target_player()), tell)
  let assert [chat.Send(frame), chat.Tell(to:, tell: heard)] = effects
  let assert Ok(line) = chat_line.decode(frame.body)
  assert line.channel_type == 6
    && line.channel_id == 0
    && line.sender_name == "Ab Cd"
    && line.text == bit_stream.utf16_units("Hi")
    && line.cross_faction == 0
    as "opcode.0x1d4, opcode.0x1c8: the target gets one 0x1c8 on (6, 0) with the speaker's name"
  assert to == step.Connection(ConnectionId(1))
  assert heard == chat_tell.Heard(whisper: 1, name: "Cd Ef")
}

pub fn the_speaker_gets_one_0x1c2_with_the_targets_name_when_heard_and_forgets_the_whisper_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, _) = whisper_to(a_chat(), "Cd Ef")
  let #(chat, effects) =
    chat.told(chat, chat_tell.Heard(whisper: 1, name: "Cd Ef"))
  let assert [chat.Unwatch(watch:), chat.Send(frame)] = effects
  assert watch == step.WatchId(first_watch + 1)
  let assert Ok(accept) = chat_line_accepted.decode(frame.body)
  assert accept.chat_message_id == 3 && accept.name == "Cd Ef"
    as "opcode.0x1c2: the speaker sees 'To <target>', so the name is the target's"
  assert chat.told(chat, chat_tell.Heard(whisper: 1, name: "Cd Ef")).1 == []
    as "a doubled reply finds no whisper number and is dropped"
}

pub fn a_whisper_to_a_target_of_the_other_faction_is_delivered_with_bcrossfaction_1_test() -> Nil {
  use <- owned_test.run(5000)
  let tell = the_whisper(whisper_to(a_chat(), "Cd Ef").1)
  let other_faction = chat_of(Speaker(..target_player(), faction_id: 167))
  let assert [chat.Send(frame), chat.Tell(..)] =
    chat.told(other_faction, tell).1
  let assert Ok(line) = chat_line.decode(frame.body)
  assert line.cross_faction == 1
    as "chat.cross_faction: the client never refuses a whisper to the other faction; the flag only colours the name (Jim, 2026-11-03; retail opened cross-faction chat on 2016-04-13, MMOBomb, a retail record)"
}

pub fn the_targets_name_matches_without_case_by_the_fold_of_the_unique_index_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [chat.Watch(target:, ..), ..] = whisper_to(a_chat(), "cD eF").1
  assert target == step.CharacterNamed("cd ef")
    as "server choice (the CreateCharacter record's gap): the name is matched as the database's unique index folds it"
}

pub fn an_empty_whisper_is_answered_only_when_the_target_is_not_found_test() -> Nil {
  use <- owned_test.run(5000)
  let empty =
    whisper_body(
      target: "Cd Ef",
      realm: "",
      text: "",
      message_id: 4,
      account: 0,
    )
  let #(chat, effects) = whisper(chat: a_chat(), body: empty)
  let tell = the_whisper(effects)
  assert chat.told(chat_of(target_player()), tell).1
    == [
      chat.Tell(
        to: step.Connection(ConnectionId(1)),
        tell: chat_tell.Heard(whisper: 1, name: "Cd Ef"),
      ),
    ]
    as "the target writes nothing for an empty whisper but tells the speaker it was found"
  let #(_, found) = chat.told(chat, chat_tell.Heard(whisper: 1, name: "Cd Ef"))
  assert found == [chat.Unwatch(watch: step.WatchId(first_watch + 1))]
    as "the trace's recommendation: nothing to anyone when the target is found; the client frees the slot silently after 30 s (0x140405cb0)"
  assert failed(
      chat.told(chat, chat_tell.NotHeard(whisper: 1)).1 |> drop_unwatch,
    )
    == WhisperFailed(
      target_name: bit_stream.utf16_units("Cd Ef"),
      account: 0,
      chat_message_id: 4,
    )
    as "0x1d9 when the target is not in the world"
  assert failed(
      chat.watch_ended(chat, step.WatchId(first_watch + 1))
      |> unwrap_ok
      |> drop_unwatch,
    )
    == WhisperFailed(
      target_name: bit_stream.utf16_units("Cd Ef"),
      account: 0,
      chat_message_id: 4,
    )
    as "0x1d9 when no connection holds the name"
}

fn unwrap_ok(
  result: Result(#(Chat, List(chat.Effect)), Nil),
) -> List(chat.Effect) {
  let assert Ok(#(_, effects)) = result as "the watch is a whisper's"
  effects
}

/// The effects without the `Unwatch` of a reply.
fn drop_unwatch(effects: List(chat.Effect)) -> List(chat.Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      chat.Unwatch(..) -> False
      chat.Send(..)
      | chat.Tell(..)
      | chat.TellWatched(..)
      | chat.UnknownZone(..)
      | chat.Watch(..)
      | chat.JoinGroup(..)
      | chat.LeaveGroup(..)
      | chat.Unhandled(..) -> True
    }
  })
}

pub fn the_realm_name_of_the_server_in_any_case_or_none_is_the_same_realm_and_any_other_is_not_delivered_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(["", "Test Realm", "tEST rEALM"], fn(realm) {
    let body =
      whisper_body(
        target: "Cd Ef",
        realm:,
        text: "Hi",
        message_id: 3,
        account: 0,
      )
    let assert [chat.Watch(..), chat.TellWatched(..)] =
      whisper(chat: a_chat(), body:).1
      as "opcode.0x1d4: the same realm is delivered"
  })
  let body =
    whisper_body(
      target: "Cd Ef",
      realm: "Other Realm",
      text: "Hi",
      message_id: 3,
      account: 0,
    )
  assert failed(whisper(chat: a_chat(), body:).1)
    == WhisperFailed(
      target_name: bit_stream.utf16_units("Cd Ef"),
      account: 0,
      chat_message_id: 3,
    )
    as "opcode.0x1d4: any other realm gets 0x1d9, with no watch"
}

pub fn no_online_character_gives_0x1d9_with_the_name_as_sent_bit_0_and_the_slot_and_no_0x1c2_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, _) = whisper_to(a_chat(), "cD eF")
  let #(chat, effects) = case
    chat.watch_ended(chat, step.WatchId(first_watch + 1))
  {
    Ok(taken) -> taken
    Error(Nil) -> panic as "the watch is a whisper's"
  }
  assert failed(effects)
    == WhisperFailed(
      target_name: bit_stream.utf16_units("cD eF"),
      account: 0,
      chat_message_id: 3,
    )
    as "opcode.0x1d9: the name as sent, bit 0 and the id"
  assert chat.watch_ended(chat, step.WatchId(first_watch + 1)) == Error(Nil)
    as "the whisper is forgotten, so its watch's end is taken once"
}

pub fn a_name_that_breaks_rule_0_is_watched_like_any_name_nobody_holds_and_gets_0x1d9_when_the_watch_ends_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(["Abc", "Ab1 Cd", "Ab  Cd", " Ab Cd", "A B C"], fn(target) {
    let #(chat, effects) = whisper_to(a_chat(), target)
    let assert [
      chat.Watch(target: step.CharacterNamed(folded_name:), ..),
      chat.TellWatched(..),
    ] = effects
      as "the whisper goes to the watch on the folded name, as for any name; the rule is the database's, so the chat rule does not test it"
    assert folded_name == string.lowercase(target)
    let assert Ok(#(_, ended)) =
      chat.watch_ended(chat, step.WatchId(first_watch + 1))
      as "the watch is a whisper's"
    assert failed(ended)
      == WhisperFailed(
        target_name: bit_stream.utf16_units(target),
        account: 0,
        chat_message_id: 3,
      )
      as "opcode.0x1d9: no character holds a name the database refuses, so the answer is the one for a name nobody holds: the name as sent, bit 0 and the slot"
  })
}

pub fn an_account_whisper_gets_0x1d9_with_bit_1_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    whisper_body(
      target: "Cd Ef",
      realm: "",
      text: "Hi",
      message_id: 3,
      account: 1,
    )
  assert failed(whisper(chat: a_chat(), body:).1)
    == WhisperFailed(
      target_name: bit_stream.utf16_units("Cd Ef"),
      account: 1,
      chat_message_id: 3,
    )
    as "opcode.0x1d4: there are no account friends, so the answer is always not delivered"
}

pub fn a_whisper_to_oneself_writes_0x1c8_and_0x1c2_in_one_step_with_no_watch_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = whisper_to(a_chat(), "ab cd")
  let assert [chat.Send(line_frame), chat.Send(accept_frame)] = effects
    as "server choice: no watch and no tell on one's own process"
  assert line_frame.message_id == chat_line.message_id
  let assert Ok(accept) = chat_line_accepted.decode(accept_frame.body)
  assert accept.name == "Ab Cd" && accept.chat_message_id == 3
}

pub fn a_whisper_that_fails_the_line_rules_is_refused_with_0x1d3_on_the_whisper_channel_test() -> Nil {
  use <- owned_test.run(5000)
  let refuse = fn(text, message_id) {
    let body =
      whisper_body(target: "Cd Ef", realm: "", text:, message_id:, account: 0)
    refused(whisper(chat: a_chat(), body:).1)
  }
  assert refuse(string.repeat("a", 502), 3)
    == ChatResult(
      channel_type: 6,
      channel_id: 0,
      result: InvalidMessageText,
      chat_message_id: 3,
    )
    as "chat.sent_text_length: 502 units; the refusal is on (6, 0) with the line's id"
  assert refuse("a\u{0001}", 4).result == InvalidMessageText
  assert refuse("Hi", 0).chat_message_id == 0
    as "0x140405cb0: slot 0 is refused"
}

pub fn a_late_or_doubled_reply_for_a_finished_whisper_is_dropped_and_numbers_never_repeat_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, _) = whisper_to(a_chat(), "Cd Ef")
  let #(chat, _) = chat.told(chat, chat_tell.NotHeard(whisper: 1))
  assert chat.told(chat, chat_tell.NotHeard(whisper: 1)).1 == []
    as "a second reply for whisper 1 finds nothing"
  assert chat.told(chat, chat_tell.Heard(whisper: 7, name: "Zed Other")).1 == []
    as "a reply for a number never made is dropped"
  let #(chat, second) = whisper_to(chat, "Cd Ef")
  assert chat.next_whisper(chat) == 3
    as "the number counts on: 1 and 2 are used"
  let assert [chat.Watch(watch:, ..), ..] = second
  assert watch == step.WatchId(first_watch + 2)
  let kept = chat.new(speaker: speaker(), next_whisper: 3)
  assert chat.next_whisper(kept) == 3
    as "a new stay in the world starts from the connection's number, so a stale reply never meets a new whisper"
}

pub fn the_first_reply_for_a_whisper_is_the_only_answer_when_a_takeover_gives_two_replies_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, _) = whisper_to(a_chat(), "Cd Ef")
  let #(chat, first) =
    chat.told(chat, chat_tell.Heard(whisper: 1, name: "Cd Ef"))
  assert list.length(frames_of(first)) == 1
  assert chat.watch_ended(chat, step.WatchId(first_watch + 1)) == Error(Nil)
    as "the design's failure table: whichever of the two is found, the speaker gets exactly one answer; the second input finds no whisper"
  let #(chat, _) = whisper_to(a_chat(), "Cd Ef")
  let #(chat, ended) = case
    chat.watch_ended(chat, step.WatchId(first_watch + 1))
  {
    Ok(taken) -> taken
    Error(Nil) -> panic as "the watch is a whisper's"
  }
  assert list.length(frames_of(ended)) == 1
  assert chat.told(chat, chat_tell.Heard(whisper: 1, name: "Cd Ef")).1 == []
    as "target ended after writing 0x1c8, before Heard: WatchEnded gave 0x1d9 and a Heard that comes after is dropped (the accepted gap, the target's client showed the line)"
}

pub fn a_camp_answers_each_pending_whisper_0x1d9_and_stops_watching_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(chat, _) = whisper_to(a_chat(), "Cd Ef")
  let #(chat, _) = whisper_to(chat, "gH iJ")
  let left = chat.left(chat)
  let assert [
    chat.LeaveGroup(name),
    chat.Unwatch(first),
    chat.Send(first_frame),
    chat.Unwatch(second),
    chat.Send(second_frame),
  ] = left
    as "the camp leaves the name group, then drops each whisper's watch and answers it"
  assert name == step.CharacterNamed("ab cd")
  assert first == step.WatchId(first_watch + 1)
    && second == step.WatchId(first_watch + 2)
  assert failed([chat.Send(first_frame)])
    == WhisperFailed(
      target_name: bit_stream.utf16_units("Cd Ef"),
      account: 0,
      chat_message_id: 3,
    )
    as "the design: every 0x1d4 keeps exactly one answer, so a whisper the speaker's camp drops is answered 0x1d9"
  assert failed([chat.Send(second_frame)]).target_name
    == bit_stream.utf16_units("gH iJ")
}

pub fn a_format_of_a_type_the_clients_text_never_makes_is_refused_with_result_17_in_a_line_and_a_whisper_test() -> Nil {
  use <- owned_test.run(5000)
  let record =
    chat_format.ItemRecord(
      chat_format_item_record.ChatFormatItemRecord(
        start: 0,
        end: 2,
        item_guid: 1,
        item_id: 2,
        character_id: 3,
        field_4: 0,
        field_5: 0,
        field_6: 0,
        field_7: 0,
        field_8: 0,
        field_9: 0,
        field_10: 0,
        list_a: [],
        list_b: [],
      ),
    )
  let never_made = [
    #(
      0,
      chat_format.Kind0(chat_format_kind_0.ChatFormatKind0(
        start: 0,
        end: 2,
        field_4: 0,
      )),
    ),
    #(
      3,
      chat_format.Kind3(chat_format_kind_3.ChatFormatKind3(
        start: 0,
        end: 2,
        field_4: 0,
      )),
    ),
    #(
      7,
      chat_format.FilterMask(chat_format_filter_mask.ChatFormatFilterMask(
        start: 0,
        end: 2,
        seed: 5,
      )),
    ),
    #(8, record),
  ]
  list.each(never_made, fn(made) {
    let #(type_id, format) = made
    assert_refused(
      bytes: body(
        type_id: 4,
        channel_id: 0,
        text: bit_stream.utf16_units("Hi"),
        formats: [format],
        message_id: 3,
      ),
      type_id: 4,
      channel_id: 0,
      result: InvalidMessageText,
      message_id: 3,
      because: "0x140402720: no tag of ParseChatText makes a format of type "
        <> int.to_string(type_id)
        <> ", so the client never sends one; the reader accepts it, so it is refused with 17, not a connection end",
    )
    let whisper_body = whisper_formats_body(formats: [format], message_id: 3)
    assert refused(whisper(chat: a_chat(), body: whisper_body).1).result
      == InvalidMessageText
      as "the same in a whisper"
  })
}

fn whisper_formats_body(
  formats formats: List(ChatFormat),
  message_id message_id: Int,
) -> BitArray {
  let assert Ok(body) =
    send_whisper.encode(SendWhisper(
      target_name: bit_stream.utf16_units("Cd Ef"),
      target_realm_name: [],
      text: bit_stream.utf16_units("Hi"),
      formats:,
      chat_message_id: message_id,
      account: 0,
    ))
  body
}

pub fn the_formats_the_clients_text_makes_are_taken_test() -> Nil {
  use <- owned_test.run(5000)
  let made = [
    chat_format.Kind1(chat_format_kind_1.ChatFormatKind1(
      start: 0,
      end: 2,
      field_4: 5,
    )),
    chat_format.Kind2(chat_format_kind_2.ChatFormatKind2(
      start: 0,
      end: 2,
      field_4: 0,
    )),
    chat_format.ItemId(chat_format_item_id.ChatFormatItemId(
      start: 0,
      end: 2,
      item_id: 1,
    )),
    chat_format.QuestId(chat_format_quest_id.ChatFormatQuestId(
      start: 0,
      end: 2,
      quest_id: 1,
    )),
    chat_format.ArticleId(chat_format_article_id.ChatFormatArticleId(
      start: 0,
      end: 2,
      article_id: 1,
    )),
    chat_format.ItemGuid(ChatFormatItemGuid(start: 0, end: 2, item_guid: 9)),
    chat_format.NavigationPoint(
      chat_format_navigation_point.ChatFormatNavigationPoint(
        start: 0,
        end: 2,
        zone_id: 1,
        x: 0,
        y: 0,
      ),
    ),
    chat_format.Kind11(chat_format_kind_11.ChatFormatKind11(
      start: 0,
      end: 2,
      field_4: 0,
    )),
  ]
  list.each(made, fn(format) {
    let #(_, effects) =
      take(
        message: chat.LineSent,
        chat: a_chat(),
        body: body(
          type_id: 4,
          channel_id: 0,
          text: bit_stream.utf16_units("Hi"),
          formats: [format],
          message_id: 3,
        ),
        viewers: [],
      )
    assert accepted(effects).chat_message_id == 3
      as "0x140402720: ParseChatText makes types 1, 2, 4, 5, 6, 9, 10 and 11, so a line with one is taken and relayed"
  })
}

pub fn a_target_name_or_realm_that_is_not_valid_utf_16_gets_0x1d9_with_the_name_as_sent_test() -> Nil {
  use <- owned_test.run(5000)
  let encoded = fn(target: List(Int), realm: List(Int)) {
    let assert Ok(body) =
      send_whisper.encode(SendWhisper(
        target_name: target,
        target_realm_name: realm,
        text: bit_stream.utf16_units("Hi"),
        formats: [],
        chat_message_id: 3,
        account: 0,
      ))
    body
  }
  let lone = [0x41, 0x62, 0x20, 0xD800, 0x64]
  assert failed(whisper(chat: a_chat(), body: encoded(lone, [])).1)
    == WhisperFailed(target_name: lone, account: 0, chat_message_id: 3)
    as "a name that is not valid UTF-16 cannot be read as text, so no watch can name it: the whisper is answered 0x1d9 at once with the name as sent, and the connection does not end"
  assert failed(
      whisper(
        chat: a_chat(),
        body: encoded(bit_stream.utf16_units("Cd Ef"), [0xDC00]),
      ).1,
    ).target_name
    == bit_stream.utf16_units("Cd Ef")
    as "a realm name that is not valid UTF-16 is no realm's"
}

pub fn every_0x1d4_gets_exactly_one_answer_except_an_empty_whisper_to_a_found_target_test() -> Nil {
  use <- owned_test.run(60_000)
  let generator =
    qcheck.tuple4(
      qcheck.from_generators(qcheck.return("Cd Ef"), [
        qcheck.return("cD eF"),
        qcheck.return("Ab Cd"),
        qcheck.return("abc"),
        qcheck.return("Ab1 Cd"),
        qcheck.return(""),
        qcheck.return("A  B"),
      ]),
      qcheck.from_generators(qcheck.return(""), [
        qcheck.return("Test Realm"),
        qcheck.return("tEsT rEaLm"),
        qcheck.return("Other"),
      ]),
      qcheck.generic_list(
        qcheck.from_generators(qcheck.bounded_int(from: 0x20, to: 0x7E), [
          qcheck.bounded_int(from: 0, to: 0x30),
          qcheck.bounded_int(from: 0xD7F0, to: 0xE010),
        ]),
        qcheck.from_generators(qcheck.bounded_int(from: 0, to: 5), [
          qcheck.bounded_int(from: 498, to: 503),
        ]),
      ),
      qcheck.tuple2(
        qcheck.bounded_int(from: 0, to: 2),
        qcheck.bounded_int(from: 0, to: 1),
      ),
    )
  use #(target, realm, text, #(message_id, account)) <- qcheck.given(generator)
  let assert Ok(body) =
    send_whisper.encode(SendWhisper(
      target_name: bit_stream.utf16_units(target),
      target_realm_name: bit_stream.utf16_units(realm),
      text:,
      formats: [],
      chat_message_id: message_id,
      account:,
    ))
  let #(after, effects) = whisper(chat: a_chat(), body:)
  let answers = fn(effects: List(chat.Effect)) {
    list.length(
      list.filter(frames_of(effects), fn(frame) {
        frame.message_id == chat_line_accepted.message_id
        || frame.message_id == chat_result.message_id
        || frame.message_id == whisper_failed.message_id
      }),
    )
  }
  let waits_on_a_target =
    list.any(effects, fn(effect) {
      case effect {
        chat.Watch(..) -> True
        chat.Send(..)
        | chat.Tell(..)
        | chat.TellWatched(..)
        | chat.UnknownZone(..)
        | chat.Unwatch(..)
        | chat.JoinGroup(..)
        | chat.LeaveGroup(..)
        | chat.Unhandled(..) -> False
      }
    })
  case waits_on_a_target {
    True -> {
      assert answers(effects) == 0
        as "a whisper that waits on its target is answered by the reply"
      assert answers(chat.told(after, chat_tell.NotHeard(whisper: 1)).1) == 1
        as "opcode.0x1d9: NotHeard is its one answer"
      assert answers(
          unwrap_ok(chat.watch_ended(after, step.WatchId(first_watch + 1))),
        )
        == 1
        as "and so is the end of its watch"
      assert answers(chat.left(after))
        == case text {
          [] -> 0
          [_, ..] -> 1
        }
        as "a camp answers a whisper with text 0x1d9 and an empty one nothing (0x140405cb0), and unwatches either"
      assert list.contains(
        chat.left(after),
        chat.Unwatch(step.WatchId(first_watch + 1)),
      )
        as "every pending whisper is unwatched on camp"
      assert answers(
          chat.told(after, chat_tell.Heard(whisper: 1, name: "Cd Ef")).1,
        )
        == case text {
          [] -> 0
          [_, ..] -> 1
        }
        as "and Heard is 0x1c2, except for an empty whisper, which is silent when its target is found (0x140405cb0)"
    }
    False -> {
      assert answers(effects) == 1
        || {
          answers(effects) == 0 && text == [] && account == 0 && message_id != 0
        }
        as "every other 0x1d4 gets exactly one of 0x1c2, 0x1d3 or 0x1d9; the one without is an empty whisper to oneself, found"
    }
  }
}

pub fn a_camp_writes_no_0x1d9_for_an_empty_whisper_pending_and_still_unwatches_it_test() -> Nil {
  use <- owned_test.run(5000)
  let empty =
    whisper_body(
      target: "Cd Ef",
      realm: "",
      text: "",
      message_id: 4,
      account: 0,
    )
  let #(chat, _) = whisper(chat: a_chat(), body: empty)
  let #(chat, _) = whisper_to(chat, "Gh Ij")
  assert chat.left(chat)
    == [
      chat.LeaveGroup(step.CharacterNamed("ab cd")),
      chat.Unwatch(step.WatchId(first_watch + 1)),
      chat.Unwatch(step.WatchId(first_watch + 2)),
      chat.Send(failed_frame_of(target: "Gh Ij", message_id: 3)),
    ]
    as "the design: an empty whisper is answered 0x1d9 only when its target is not found; a camp does not know, so the client frees its slot silently (0x140405cb0), while a whisper with text is still answered; every pending whisper is unwatched"
}

fn failed_frame_of(target target: String, message_id message_id: Int) -> Frame {
  let assert Ok(body) =
    whisper_failed.encode(WhisperFailed(
      target_name: bit_stream.utf16_units(target),
      account: 0,
      chat_message_id: message_id,
    ))
  Frame(message_id: whisper_failed.message_id, body:)
}
