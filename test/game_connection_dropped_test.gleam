//// The reports and window requests the game connection takes and drops
//// (`genesis_prime/game/dropped`): the twelve the client sends inside 0x038C
//// with the player in the world, and 0x0241, which it sends on its own from
//// character select and in the world. Expected values come from these places.
//// - The bodies of `dropped_support`: what the client sent, from its sittings.
//// - `opcode.0x241` and the opcode records of each id: the client waits for no
////   answer to any of them (the replies some of them lead to are other messages,
////   and are not sent here), so a taken message writes nothing and logs
////   nothing.
//// - The client's own reader refuses a body of another size, and the connection
////   ends for what the reader would refuse (the project rule, as for any body
////   the client's code never writes): each layout's size is in its record
////   (`opcode.0x23c.body`, `opcode.0x240.body`, `opcode.0x23f.body`, `opcode.0x23d`,
////   `opcode.0x12b`, `opcode.0x180`, `opcode.0x570` and the empty ones).

import character_support
import connection_rule_support as support
import dropped_support.{type Recorded, Recorded}
import game_connection_support as connection_support
import genesis_prime/client_connection.{FromHandOff, FromMap, FromStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/hand_off.{Taken}
import genesis_prime/step.{LogError}
import genesis_prime/store.{
  Character, CharacterId, CharacterLoaded, ForSelect, ForWorld, Listed,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test

/// The message as the client sends it: 0x0241 on its own, any other inside 0x038C.
fn sent(message_id message_id: Int, body body: BitArray) -> BitArray {
  case message_id {
    0x0241 -> connection_support.keyed_message(message_id:, body:)
    _ -> connection_support.world_message(message_id:, body:)
  }
}

/// The connection in the world as the character the recorded bodies were sent
/// by: the 0x07DD of that connection names 13 (2026-11-05-main), and the
/// window report names the connection's own character (`opcode.0x23d`).
fn in_world_of_the_recorded_sender() -> game_connection.State {
  connection_support.entered_as(
    Character(
      ..connection_support.world_character(),
      character_id: CharacterId(13),
    ),
  ).0
}

/// The id as the log names it, four hex digits.
fn named(message_id message_id: Int) -> String {
  "0x" <> string.pad_start(int.to_base16(message_id), 4, "0")
}

pub fn each_dropped_message_is_taken_with_nothing_logged_or_sent_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(dropped_support.recorded(), fn(recorded: Recorded) {
    let Recorded(message_id:, body:, what:, ..) = recorded
    let label = named(message_id:) <> ", " <> what
    let #(state, taken) =
      connection_support.read(
        state: in_world_of_the_recorded_sender(),
        bytes: sent(message_id:, body:),
      )
    assert support.logs(taken) == []
      as { label <> ": taken with no log line, so it leaves the unhandled log" }
    assert support.writes(taken) == []
      as { label <> ": the client waits for no answer" }
    assert support.asked(taken) == None && !support.stops(taken)
      as { label <> ": nothing is asked and the connection goes on" }
    let #(_, again) =
      connection_support.read(state:, bytes: sent(message_id:, body:))
    assert support.logs(again) == []
      as { label <> ": taken each time, with no log line kept for a repeat" }
    assert support.writes(again) == [] && !support.stops(again)
  })
}

/// Every recorded body one byte longer and, where it has bytes, one byte shorter.
fn wrong_sizes() -> List(#(Int, BitArray, String)) {
  list.flat_map(dropped_support.recorded(), fn(recorded: Recorded) {
    let Recorded(message_id:, body:, what:, ..) = recorded
    let size = bit_array.byte_size(body)
    let longer = #(message_id, <<body:bits, 0>>, what <> ", one byte longer")
    case size {
      0 -> [longer]
      _ -> {
        let assert Ok(shorter) = bit_array.slice(body, 0, size - 1)
        [longer, #(message_id, shorter, what <> ", one byte shorter")]
      }
    }
  })
}

pub fn a_body_of_the_wrong_size_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(wrong_sizes(), fn(wrong) {
    let #(message_id, body, what) = wrong
    let label = named(message_id:) <> ", " <> what
    let #(refusing, taken) =
      connection_support.read(
        state: connection_support.in_world(),
        bytes: sent(message_id:, body:),
      )
    let assert [line] = support.logs_of(step: taken, level: LogError)
      as {
        label <> ": one error line says the client's reader would refuse it"
      }
    assert support.says(line, named(message_id:))
      as { label <> ": the line names the message" }
    assert support.says(line, "does not decode")
      as { label <> ": and that its body is not one" }
    assert connection_support.ask_request(taken)
      == connection_support.save_asked(1, connection_support.entry_place())
      as { label <> ": the place is saved, as for any refused message" }
    assert support.writes(taken) == []
    assert !support.stops(taken)
    let #(_, taken) =
      connection_support.answer(
        state: refusing,
        taken:,
        outcome: connection_support.place_saved(),
      )
    assert support.effects_of(taken) == [step.Stop]
      as { label <> ": the save answered, the connection ends" }
  })
}

pub fn pre_game_activity_before_world_entry_is_dropped_test() -> Nil {
  use <- owned_test.run(10_000)
  // In character select.
  let #(_, taken) =
    connection_support.read(
      state: connection_support.in_select(),
      bytes: sent(message_id: 0x0241, body: <<>>),
    )
  assert support.logs(taken) == []
    as "opcode.0x241: the client sends it from its character-select update and waits for no answer"
  assert support.writes(taken) == [] && !support.stops(taken)
  // Read in the same bytes as the request that asks the store, so it waits for
  // the answer and is taken after it.
  let #(state, taken) =
    connection_support.read(connection_support.connected(), <<
      connection_support.hello_reply():bits,
      connection_support.select_start():bits,
      sent(message_id: 0x0241, body: <<>>):bits,
    >>)
  assert support.unhandled_ids(taken) == []
  let #(state, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromHandOff(Taken(holder: connection_support.holder())),
      ),
    )
  let #(state, taken) = connection_support.claimed(state:, taken:)
  assert support.unhandled_ids(taken) == []
    as "0x0241 follows 0x07E0 in the bytes and waits for the store's answer"
  let #(_, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed(characters: [])))),
    )
  assert support.unhandled_ids(taken) == []
    as "then the frame that waited is taken, and logs nothing as unhandled"
  assert !support.stops(taken)
  // Read in the same bytes as the request to play, so it waits for the store
  // and the map and is taken in the world, where 0x0241 is also sent.
  let #(state, taken) =
    connection_support.read(connection_support.in_select(), <<
      connection_support.play_message(42):bits,
      sent(message_id: 0x0241, body: <<>>):bits,
    >>)
  assert support.unhandled_ids(taken) == []
    as "0x0241 follows 0x07DD in the bytes and waits for the world-entry asks"
  let #(state, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(
            CharacterLoaded(
              connection_support.world_character(),
              character_support.epoch(1),
              None,
              saved_experience: None,
              items: [],
            ),
          ),
        ),
      ),
    )
  assert support.unhandled_ids(taken) == []
  let #(_, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(connection_support.map_answer(taken))),
    )
  assert support.unhandled_ids(taken) == []
    as "then the frame that waited is taken in the world, and logs nothing as unhandled"
  assert !support.stops(taken)
}
