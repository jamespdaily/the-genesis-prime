//// The values the reports and window requests the game connection drops are
//// checked against (`genesis_prime/game/dropped`): what the client would send,
//// and what it would not. Expected values come from these places.
//// - `opcode.0x23d`: the sender 0x1403fa810 counts the event text's UTF-16
////   units and does not send when the count is over the limit it reads with
////   `FUN_140200220(0x947)`, which is GameFormula row 2375's dataint02. The
////   client's row 2375 is `10000 20 128 0 0`, so a text of 128 units is sent and
////   one of 129 is not. The text is wide text: a flag bit, then the count in 7
////   bits (below 128) or 15 bits, then the 16-bit units
////   (`vector.0x140336040.wide_text`: 128 characters give the bytes 01 01, so 129
////   give 03 01), and the body before it is 50 bytes (400 bits), as in the
////   recorded 81-byte body.
//// - `opcode.0x12b`: the four senders write type 0 with the input flags (1
////   always, 2, 4, 8, so 1 to 15 with bit 1 set) or type 1 with the bool of
////   `GameLib.SetSharedChallengePreference`; no other type has a sender.
//// - `opcode.0x23d`: the event's first 64-bit value is the character id of
////   the connection that sent it, in each of the 52 recorded sends of 10
////   sittings.
//// - The recorded bodies of `dropped_support`.

import dropped_support
import fixture_tables
import genesis_prime/client_connection.{Unwritten}
import genesis_prime/game/dropped.{
  EventNamesAnotherCharacter, EventTextTooLong, NotWritten,
}
import genesis_prime/message/statistic_event.{StatisticEvent}
import genesis_prime/table/game_formula
import genesis_prime/table/loader/store as table_store
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table

/// The id of each message and the one the rule names it by.
const messages = [
  #(0x023C, dropped.WatchdogReport),
  #(0x0240, dropped.FrameTimeReport),
  #(0x023F, dropped.NetworkReport),
  #(0x023E, dropped.GraphicsReport),
  #(0x023D, dropped.StatisticEvent),
  #(0x0241, dropped.PreGameActivity),
  #(0x012B, dropped.ClientOption),
  #(0x0180, dropped.ScanbotRequest),
  #(0x03ED, dropped.OwnAuctionsRequest),
  #(0x03EC, dropped.OwnCommodityOrdersRequest),
  #(0x0269, dropped.CreddExchangeRequest),
  #(0x018F, dropped.TradeCancel),
  #(0x0570, dropped.InputKeySetRequest),
]

/// A 0x023D body: the 50 bytes before the text, from the recorded body of the
/// event with an empty text (its 6 bits, 10-bit event id and six 64-bit values),
/// then a text of this many units, each the letter A.
fn statistic_event_with_text(units units: Int) -> BitArray {
  let assert Ok(before_text) =
    bit_array.slice(dropped_support.empty_text_event(), 0, 50)
  let text =
    list.fold(list.repeat(Nil, units), <<>>, fn(text, _) {
      <<text:bits, 0x41, 0x00>>
    })
  case units < 128 {
    True -> <<before_text:bits, { units * 2 }:size(8), text:bits>>
    False -> {
      // The flag bit 1, then the count in 15 bits: the count's low 7 bits
      // shifted past the flag fill the first byte, the rest is the second.
      let low = int.bitwise_or(1, int.bitwise_shift_left(units % 128, 1))
      <<before_text:bits, low:size(8), { units / 128 }:size(8), text:bits>>
    }
  }
}

/// The character the recorded bodies were sent by: the 0x07DD of that
/// connection names 13 (2026-11-05-main).
const recorded_character_id = 13

fn take(
  message message: dropped.Message,
  body body: BitArray,
) -> Result(Nil, dropped.Refusal) {
  dropped.take(
    message:,
    body:,
    tables: fixture_tables.shared(),
    character_id: Some(recorded_character_id),
  )
}

/// The recorded event with an empty text, with the character id it names
/// changed.
fn statistic_event_of(character_id character_id: Int) -> BitArray {
  dropped_support.statistic_event_changed(fn(recorded) {
    StatisticEvent(..recorded, character_id:)
  })
}

/// The refusal of a value of 0x012B the client never writes.
fn option_not_written(
  field field: String,
  value value: Int,
) -> dropped.Refusal {
  NotWritten(Unwritten(message_id: 0x012B, field:, value:))
}

/// The refusal of a value of 0x023D the client never writes.
fn event_not_written(field field: String, value value: Int) -> dropped.Refusal {
  NotWritten(Unwritten(message_id: 0x023D, field:, value:))
}

pub fn a_statistic_event_naming_another_character_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  assert statistic_event.decode(dropped_support.empty_text_event())
    == Ok(
      StatisticEvent(
        category: 35,
        event_id: 513,
        character_id: recorded_character_id,
        zero_value_2: 0,
        event_value_3: 0,
        event_value_4: 0,
        event_value_5: 0,
        zero_value_6: 0,
        event_text: [],
      ),
    )
    as "opcode.0x23d: in 2026-11-05-main the event names the character its connection played"
  assert take(
      message: dropped.StatisticEvent,
      body: statistic_event_of(character_id: 13),
    )
    == Ok(Nil)
  assert take(
      message: dropped.StatisticEvent,
      body: statistic_event_of(character_id: 14),
    )
    == Error(EventNamesAnotherCharacter(named: 14, own: Some(13)))
    as "opcode.0x23d: the client names its own character, so another one is refused"
  assert dropped.take(
      message: dropped.StatisticEvent,
      body: statistic_event_of(character_id: 13),
      tables: fixture_tables.shared(),
      character_id: None,
    )
    == Error(EventNamesAnotherCharacter(named: 13, own: None))
    as "a connection with no character in the world has none to name"
}

pub fn values_the_client_would_not_send_are_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // Every body the client was seen to send is taken, whichever message it is.
  list.each(dropped_support.recorded(), fn(recorded) {
    let assert Ok(#(_, message)) =
      list.find(messages, fn(entry) { entry.0 == recorded.message_id })
    assert take(message:, body: recorded.body) == Ok(Nil)
      as {
        recorded.what
        <> " ("
        <> recorded.seen_in
        <> ") is a body the client sent"
      }
  })
  // 0x023D: the event text limit is GameFormula row 2375's dataint02.
  assert statistic_event_with_text(units: 0)
    == dropped_support.empty_text_event()
    as "the body built here with no text is the recorded body of the event with none"
  assert take(
      message: dropped.StatisticEvent,
      body: statistic_event_with_text(units: 128),
    )
    == Ok(Nil)
    as "opcode.0x23d: 128 units is the limit the client's row 2375 holds, so it sends it"
  assert take(
      message: dropped.StatisticEvent,
      body: statistic_event_with_text(units: 129),
    )
    == Error(EventTextTooLong(units: 129, limit: 128))
    as "opcode.0x23d: the client does not send an event text of 129 units"
  // The limit is the table's, not a number of the rule's.
  fixture_tables.changed(
    table: "GameFormula",
    id: 2375,
    with: [#("dataint02", planted_table.Integer(5))],
    body: fn(tables) {
      assert dropped.take(
          message: dropped.StatisticEvent,
          body: statistic_event_with_text(units: 5),
          tables:,
          character_id: Some(recorded_character_id),
        )
        == Ok(Nil)
      assert dropped.take(
          message: dropped.StatisticEvent,
          body: statistic_event_with_text(units: 6),
          tables:,
          character_id: Some(recorded_character_id),
        )
        == Error(EventTextTooLong(units: 6, limit: 5))
        as "the row's dataint02 is the limit, read from the table"
    },
  )
  // The table load requires the row, so a client without it fails the start.
  let assert Ok(rows) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "GameFormula",
      id: 2375,
    )
    as "the client's table holds row 2375"
  assert fixture_tables.edited(
      rows:,
      entries: [game_formula.entry()],
      requirements: dropped.requirements(),
      derivations: [],
    )
    == Error(table_store.RowMissing(
      from_table: "the server's event text limit",
      column: "GameFormula id",
      to_table: "GameFormula",
      id: 2375,
    ))
    as "opcode.0x23d: the limit is read from GameFormula row 2375, so a load without it fails"
  assert dropped.requirements()
    |> list.flat_map(fn(requirement) {
      requirement.missing(fixture_tables.shared())
    })
    == []
    as "the client's GameFormula holds row 2375"
  // 0x012B: the types and values a sender writes.
  assert take(message: dropped.ClientOption, body: <<2, 0, 0, 0, 0, 0, 0, 0>>)
    == Error(option_not_written(field: "the option type", value: 2))
    as "opcode.0x12b: the senders write type 0 or 1"
  assert take(message: dropped.ClientOption, body: <<
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      1,
      0,
      0,
      0,
    >>)
    == Error(option_not_written(field: "the option type", value: 0xFFFFFFFF))
  assert take(message: dropped.ClientOption, body: <<1, 0, 0, 0, 2, 0, 0, 0>>)
    == Error(option_not_written(field: "type 1's value", value: 2))
    as "opcode.0x12b: type 1 is the bool of SetSharedChallengePreference"
  assert take(message: dropped.ClientOption, body: <<1, 0, 0, 0, 1, 0, 0, 0>>)
    == Ok(Nil)
    as "the bool true"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 0, 0, 0, 0>>)
    == Error(option_not_written(field: "type 0's input flags", value: 0))
    as "opcode.0x12b: type 0 always has the input flag 1 set"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 2, 0, 0, 0>>)
    == Error(option_not_written(field: "type 0's input flags", value: 2))
    as "flag 2 alone leaves flag 1 clear"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 0x11, 0, 0, 0>>)
    == Error(option_not_written(field: "type 0's input flags", value: 0x11))
    as "a bit above 8 has no flag"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 0x0F, 0, 0, 0>>)
    == Ok(Nil)
    as "flags 1, 2, 4 and 8 together are the largest the senders write"
}

pub fn statistic_event_values_the_client_never_writes_are_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // `opcode.0x23d.category` and `opcode.0x23d.zero_values`: the category is 35
  // and the 2nd and 6th values are 0 from every sender.
  let rows = [
    #(
      fn(event) { StatisticEvent(..event, category: 34) },
      event_not_written(field: "the category", value: 34),
      "the category is 35 from every sender",
    ),
    #(
      fn(event) { StatisticEvent(..event, category: 0) },
      event_not_written(field: "the category", value: 0),
      "no sender writes category 0",
    ),
    #(
      fn(event) { StatisticEvent(..event, zero_value_2: 1) },
      event_not_written(field: "the second value", value: 1),
      "the 2nd value is 0 from every sender",
    ),
    #(
      fn(event) { StatisticEvent(..event, zero_value_6: 1) },
      event_not_written(field: "the sixth value", value: 1),
      "the 6th value is 0 from every sender",
    ),
    #(
      fn(event) { StatisticEvent(..event, category: 34, character_id: 14) },
      event_not_written(field: "the category", value: 34),
      "the values are checked before the character, so a character other than the connection's does not hide them",
    ),
  ]
  list.each(rows, fn(row) {
    let #(change, refusal, why) = row
    assert take(
        message: dropped.StatisticEvent,
        body: dropped_support.statistic_event_changed(change),
      )
      == Error(refusal)
      as why
  })
  // The ids with emitters, with category 35, are taken.
  list.each(
    [499, 502, 503, 504, 505, 506, 507, 508, 509, 510, 512, 513],
    fn(id) {
      assert take(
          message: dropped.StatisticEvent,
          body: dropped_support.statistic_event_changed(fn(event) {
            StatisticEvent(..event, event_id: id)
          }),
        )
        == Ok(Nil)
        as {
          "opcode.0x23d.events: event "
          <> int.to_string(id)
          <> " has an emitter"
        }
    },
  )
}
