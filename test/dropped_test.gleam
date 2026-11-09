//// The values the reports and window requests the game connection drops are
//// checked against (`genesis_prime/game/dropped`): what the client would send,
//// and what it would not. Expected values come from these places.
//// - `opcode.0x23d`: the sender 0x1403fa810 counts the window name's UTF-16
////   units and does not send when the count is over the limit it reads with
////   `FUN_140200220(0x947)`, which is GameFormula row 2375's dataint02. The
////   client's row 2375 is `10000 20 128 0 0`, so a name of 128 units is sent and
////   one of 129 is not. The name is wide text: a flag bit, then the count in 7
////   bits (below 128) or 15 bits, then the 16-bit units
////   (`vector.0x140336040.wide_text`: 128 characters give the bytes 01 01, so 129
////   give 03 01), and the body before it is 50 bytes (400 bits), as in the
////   recorded 81-byte body.
//// - `opcode.0x12b`: the four senders write type 0 with the input flags (1
////   always, 2, 4, 8, so 1 to 15 with bit 1 set) or type 1 with the bool of
////   `GameLib.SetSharedChallengePreference`; no other type has a sender.
//// - `opcode.0x23d`: the window's first 64-bit value is the character id of
////   the connection that sent it, in each of the 52 recorded sends of 10
////   sittings.
//// - The recorded bodies of `dropped_support`.

import dropped_support.{Recorded}
import fixture_tables
import genesis_prime/game/dropped.{
  InputFlagsNotSent, OptionTypeNotSent, SharedChallengeNotABool,
  WindowNameTooLong, WindowNamesAnotherCharacter,
}
import genesis_prime/message/window_opened.{WindowOpened}
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
  #(0x023D, dropped.WindowOpened),
  #(0x0241, dropped.PreGameActivity),
  #(0x012B, dropped.ClientOption),
  #(0x0180, dropped.ScanbotRequest),
  #(0x03ED, dropped.OwnAuctionsRequest),
  #(0x03EC, dropped.OwnCommodityOrdersRequest),
  #(0x0269, dropped.CreddExchangeRequest),
  #(0x018F, dropped.TradeCancel),
  #(0x0570, dropped.InputKeySetRequest),
]

/// A 0x023D body: the 50 bytes before the name, from the recorded body of the
/// window with an empty name (its 6 bits, 10-bit window id and six 64-bit values),
/// then a name of this many units, each the letter A.
fn window_opened(units units: Int) -> BitArray {
  let assert Ok(before_name) = bit_array.slice(empty_name_window(), 0, 50)
  let name =
    list.fold(list.repeat(Nil, units), <<>>, fn(name, _) {
      <<name:bits, 0x41, 0x00>>
    })
  case units < 128 {
    True -> <<before_name:bits, { units * 2 }:size(8), name:bits>>
    False -> {
      // The flag bit 1, then the count in 15 bits: the count's low 7 bits
      // shifted past the flag fill the first byte, the rest is the second.
      let low = int.bitwise_or(1, int.bitwise_shift_left(units % 128, 1))
      <<before_name:bits, low:size(8), { units / 128 }:size(8), name:bits>>
    }
  }
}

fn empty_name_window() -> BitArray {
  let assert Ok(Recorded(body:, ..)) =
    list.find(dropped_support.recorded(), fn(recorded) {
      recorded.message_id == 0x023D
      && recorded.what == "a window with an empty name, 51 bytes"
    })
  body
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

/// The recorded window with an empty name, with the character id it names
/// changed.
fn window_opened_by(character_id character_id: Int) -> BitArray {
  let assert Ok(recorded) = window_opened.decode(empty_name_window())
  let assert Ok(body) =
    window_opened.encode(WindowOpened(..recorded, character_id:))
    as "the message the client's recorded body decodes to encodes again"
  body
}

pub fn a_window_report_naming_another_character_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  assert window_opened.decode(empty_name_window())
    == Ok(
      WindowOpened(
        field_1: 35,
        window_id: 513,
        character_id: recorded_character_id,
        field_4: 0,
        open_time: 0,
        field_6: 0,
        field_7: 0,
        field_8: 0,
        window_name: [],
      ),
    )
    as "opcode.0x23d: in 2026-11-05-main the window names the character its connection played"
  assert take(
      message: dropped.WindowOpened,
      body: window_opened_by(character_id: 13),
    )
    == Ok(Nil)
  assert take(
      message: dropped.WindowOpened,
      body: window_opened_by(character_id: 14),
    )
    == Error(WindowNamesAnotherCharacter(named: 14, own: Some(13)))
    as "opcode.0x23d: the client names its own character, so another one is refused"
  assert dropped.take(
      message: dropped.WindowOpened,
      body: window_opened_by(character_id: 13),
      tables: fixture_tables.shared(),
      character_id: None,
    )
    == Error(WindowNamesAnotherCharacter(named: 13, own: None))
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
  // 0x023D: the name limit is GameFormula row 2375's dataint02.
  assert window_opened(units: 0) == empty_name_window()
    as "the body built here with no name is the recorded body of a window with none"
  assert take(message: dropped.WindowOpened, body: window_opened(units: 128))
    == Ok(Nil)
    as "opcode.0x23d: 128 units is the limit the client's row 2375 holds, so it sends it"
  assert take(message: dropped.WindowOpened, body: window_opened(units: 129))
    == Error(WindowNameTooLong(units: 129, limit: 128))
    as "opcode.0x23d: the client does not send a name of 129 units"
  // The limit is the table's, not a number of the rule's.
  fixture_tables.changed(
    table: "GameFormula",
    id: 2375,
    with: [#("dataint02", planted_table.Integer(5))],
    body: fn(tables) {
      assert dropped.take(
          message: dropped.WindowOpened,
          body: window_opened(units: 5),
          tables:,
          character_id: Some(recorded_character_id),
        )
        == Ok(Nil)
      assert dropped.take(
          message: dropped.WindowOpened,
          body: window_opened(units: 6),
          tables:,
          character_id: Some(recorded_character_id),
        )
        == Error(WindowNameTooLong(units: 6, limit: 5))
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
      from_table: "the server's window name limit",
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
    == Error(OptionTypeNotSent(2))
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
    == Error(OptionTypeNotSent(0xFFFFFFFF))
  assert take(message: dropped.ClientOption, body: <<1, 0, 0, 0, 2, 0, 0, 0>>)
    == Error(SharedChallengeNotABool(2))
    as "opcode.0x12b: type 1 is the bool of SetSharedChallengePreference"
  assert take(message: dropped.ClientOption, body: <<1, 0, 0, 0, 1, 0, 0, 0>>)
    == Ok(Nil)
    as "the bool true"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 0, 0, 0, 0>>)
    == Error(InputFlagsNotSent(0))
    as "opcode.0x12b: type 0 always has the input flag 1 set"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 2, 0, 0, 0>>)
    == Error(InputFlagsNotSent(2))
    as "flag 2 alone leaves flag 1 clear"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 0x11, 0, 0, 0>>)
    == Error(InputFlagsNotSent(0x11))
    as "a bit above 8 has no flag"
  assert take(message: dropped.ClientOption, body: <<0, 0, 0, 0, 0x0F, 0, 0, 0>>)
    == Ok(Nil)
    as "flags 1, 2, 4 and 8 together are the largest the senders write"
}
