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
import genesis_prime/message/chat_channel_joined.{ChatChannelJoined}
import genesis_prime/message/chat_channel_result.{
  DoesntExist, InvalidMessageText, NoPermissions, NotInGroup,
}
import genesis_prime/message/chat_format.{type ChatFormat, ItemGuid, Kind1}
import genesis_prime/message/chat_format_item_guid.{ChatFormatItemGuid}
import genesis_prime/message/chat_format_kind_1.{ChatFormatKind1}
import genesis_prime/message/chat_line.{ChatLine}
import genesis_prime/message/chat_line_accepted.{ChatLineAccepted}
import genesis_prime/message/chat_result.{ChatResult}
import genesis_prime/message/chat_zone_named.{ChatZoneNamed}
import genesis_prime/message/send_chat_line.{SendChatLine}
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
  chat.new(speaker:, zone_channel_id: world_id, next_whisper: 1)
}

fn a_chat() -> Chat {
  chat_of(speaker())
}

fn units(text: String) -> List(Int) {
  list.map(string.to_utf_codepoints(text), string.utf_codepoint_to_int)
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
    text: units("Hello"),
    formats: [],
    message_id: 1,
  )
}

fn take(
  chat chat: Chat,
  body body: BitArray,
  viewers viewers: List(Int),
) -> #(Chat, List(chat.Effect)) {
  let assert Ok(taken) =
    chat.take(
      chat:,
      message: chat.LineSent,
      body:,
      viewers: set.from_list(list.map(viewers, ConnectionId)),
      realm_name: "Test Realm",
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
      | chat.Warning(..)
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
      | chat.Warning(..)
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
        text: units("Hi"),
        formats: [],
      ),
    ),
  ).1
}

// ---- the speaker ----

pub fn an_accepted_say_yell_or_emote_gets_one_0x1c2_with_the_slot_the_name_the_unit_and_no_item_record_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([4, 5, 8], fn(type_id) {
    let #(_, effects) = take(chat: a_chat(), body: hello(type_id), viewers: [])
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
  let #(_, effects) = take(chat: a_chat(), body: hello(4), viewers: [7, 8])
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
      take(chat: a_chat(), body: hello(type_id), viewers: [7, 8])
    assert list.sort(said_to(effects), int.compare) == [7, 8]
      as "the speaker's viewers are the players it sees: one tell to each (design C: one sender for each pair)"
    let assert [#(_, Said(speaker: told, line:)), ..] = tells_of(effects)
    assert told == speaker()
    assert line
      == Line(
        channel_type: chat_channel.from_id(type_id),
        channel_id: 0,
        text: units("Hello"),
        formats: [],
      )
      as "the line keeps its channel, text and formats as sent"
  })
}

pub fn a_player_out_of_sight_is_told_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = take(chat: a_chat(), body: hello(4), viewers: [])
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
          text: units("Hello"),
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
      text: units("Hello"),
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
                text: units("Hi"),
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
      text: units("Hi"),
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
  let #(after, effects) = take(chat: a_chat(), body: bytes, viewers: [7])
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

pub fn more_than_499_characters_is_refused_with_result_17_and_499_is_taken_test() -> Nil {
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
  assert_refused(
    bytes: long(500),
    type_id: 4,
    channel_id: 0,
    result: InvalidMessageText,
    message_id: 3,
    because: "vector.0x140402720.lines: ParseChatText keeps at most 499, so 500 is a line the client never sends",
  )
  let #(_, effects) = take(chat: a_chat(), body: long(499), viewers: [])
  assert accepted(effects).chat_message_id == 3
    as "vector.0x140402720.lines: 499 characters are kept whole"
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
      text: units("Hello"),
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
      text: units("Hello"),
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
      chat: a_chat(),
      body: body(
        type_id: 4,
        channel_id: 0,
        text: units("Hello"),
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
      text: units("Hi"),
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
        text: units("Hi"),
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
        text: units("Hi"),
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
        text: units("Hi"),
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
        take(chat: a_chat(), body: hello(channel.0), viewers: [7])
      assert refused(effects)
        == ChatResult(
          channel_type: channel.0,
          channel_id: 0,
          result: NoPermissions,
          chat_message_id: 1,
        )
        as "Jim, 2026-11-03: Support and Instance are refused with result 3"
      assert list.contains(effects, chat.Unhandled(channel_type: channel.1))
        as "the coverage measure sees the gap: the channel is logged as unhandled"
      assert said_to(effects) == [] as "nobody else gets anything"
    },
  )
}

pub fn text_and_formats_reach_readers_as_sent_with_no_format_added_and_no_word_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let text = units("damn <b>word</b> fuck")
  let formats = [
    Kind1(ChatFormatKind1(start: 1, end: 2, field_4: 3)),
    ItemGuid(ChatFormatItemGuid(start: 0, end: 4, item_guid: 9)),
  ]
  let #(_, effects) =
    take(
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

const zone_channel_id = 3460

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
  let assert Ok(taken) =
    chat.world_zone_reported(chat:, world_zone_id:, top_zones: top_zones())
    as "the zone has a row or is 0"
  taken
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

fn warnings_of(effects: List(chat.Effect)) -> List(String) {
  list.filter_map(effects, fn(effect) {
    case effect {
      chat.Warning(text:) -> Ok(text)
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
    chat:,
    body: body(
      type_id: 9,
      channel_id: zone_channel_id,
      text: units("Hello"),
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
    as "opcode.0x1bc: type 9, the map's world id as the id, an empty name and three zeros; the order lets the flag 0x400 row take the name 0x1da last gave"
  assert zone == zone_channel(4961)
}

pub fn no_0x1bc_is_written_for_a_channel_the_client_makes_itself_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = in_zone(speaker(), 6009)
  let types =
    list.filter_map(frames_of(effects), fn(frame) {
      case frame.message_id == chat_channel_joined.message_id {
        True -> {
          let assert Ok(joined) = chat_channel_joined.decode(frame.body)
          Ok(joined.channel_type)
        }
        False -> Error(Nil)
      }
    })
  assert types == [9]
    as "0x140404ee0: the client makes Say, Yell, Emote, Whisper and AccountWhisper itself, and a 0x1bc for one only prints a join again; Zone is the one the server joins"
}

pub fn entering_the_same_map_again_sends_the_same_channel_id_test() -> Nil {
  use <- owned_test.run(5000)
  let joined_id = fn(speaker) {
    let #(_, effects) = in_zone(speaker, 6009)
    let assert [_, _, chat.Send(frame), _] = effects
    let assert Ok(joined) = chat_channel_joined.decode(frame.body)
    joined.channel_id
  }
  assert joined_id(speaker())
    == joined_id(Speaker(..speaker(), incarnation: run + 5))
    as "server choice: the id is the map's world id in every run, so a new entry joins the one channel and does not make a second"
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
  assert warnings_of(in_0) == []
    as "zone 0 is the table's own no-zone value, so no warning"
  let #(_, no_row) = in_zone(speaker(), 1132)
  assert named_by_0x1da(no_row) == [0]
  assert list.length(warnings_of(no_row)) == 1
    as "a place zone with no WorldZone row is server data gone wrong: a warning, and the connection does not end"
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
    as "0x140403670: the client only renames the channel, so the id Z stays: leave the old group, join the new, write 0x1da with the new top zone"
  let #(_, line) = zone_line(chat, 3)
  let assert [#(address, chat_tell.ZoneLine(line: told, ..))] = tells_of(line)
  assert address == zone_channel(35)
  assert told.channel_id == zone_channel_id as "the channel is still the one Z"
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

pub fn a_report_of_a_zone_with_no_row_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  assert chat.world_zone_reported(
      chat: run_zone(1411),
      world_zone_id: 1132,
      top_zones: top_zones(),
    )
    == Error(chat.ZoneWithNoRow(world_zone_id: 1132))
    as "CLAUDE.md: refuse a value the client's tables would not allow; WorldZone has no row 1132"
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
        text: units("Hi"),
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
    as "opcode.0x1c8: one 0x1c8 on (9, Z)"
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

pub fn a_zone_line_before_its_0x1bc_or_on_another_id_is_refused_with_result_1_test() -> Nil {
  use <- owned_test.run(5000)
  let refuse = fn(chat, channel_id) {
    let #(_, effects) =
      take(
        chat:,
        body: body(
          type_id: 9,
          channel_id:,
          text: units("Hi"),
          formats: [],
          message_id: 8,
        ),
        viewers: [],
      )
    refused(effects)
  }
  let expected = fn(channel_id) {
    ChatResult(
      channel_type: 9,
      channel_id:,
      result: DoesntExist,
      chat_message_id: 8,
    )
  }
  assert refuse(a_chat(), zone_channel_id) == expected(zone_channel_id)
    as "0x140401cb0: the client holds a Zone channel only after the server's 0x1bc"
  assert refuse(run_zone(1411), zone_channel_id + 1)
    == expected(zone_channel_id + 1)
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
        | chat.Warning(..)
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
