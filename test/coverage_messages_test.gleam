//// The coverage measure of the client's messages after the reports and window
//// requests are taken (`genesis_prime/game/dropped`). Expected values come from
//// these places.
//// - The rule of the measure's `partial` list: a handled type whose client
////   behaviour needs a server reply or state the engine lacks states it, with
////   its fact key (`measurement.status_of` gives `HandledWithGap`).
//// - The client's records of each message: the reply it waits for or the state
////   it lacks (`opcode.0x3ed` names reply 0x64D, `opcode.0x3ec` reply 0x64C,
////   `opcode.0x269` reply 0x26A, `opcode.0x18f` the trade begun by 0x192,
////   `opcode.0x180` the scanbot unit, `opcode.0x570` reply 0x56F, `opcode.0x12b`
////   the type 1 shared-challenge preference).
//// - The owning issues, as the step's design assigns them: the economy and loot
////   work #58, the paths and titles work #55, the player and account work #60
////   and the public events and challenges work #52.
//// - 0x0072 is an id the client sends that no row takes yet, so the measure
////   counts it and the ranking lists it.
//// - The planted folder is written and read back as `unhandled_ranking_test`'s
////   is.

import coverage_support
import dropped_support.{type Recorded, Recorded}
import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/coverage/engine
import genesis_prime/coverage/measurement.{
  Handled, HandledWithGap, Measured, TypeLine,
}
import genesis_prime/coverage/sent_message
import genesis_prime/game/connection as game_connection
import genesis_prime/message/world_message.{WorldMessage}
import genesis_prime/unhandled_ranking
import genesis_prime/wire_recording.{Accepted, Client, Read}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import recording_support
import unitest
import wire_replay_support as wire

/// The thirteen ids the reports and window requests take.
const dropped_ids = [
  0x023C, 0x0240, 0x023F, 0x023E, 0x023D, 0x0241, 0x012B, 0x0180, 0x03ED, 0x03EC,
  0x0269, 0x018F, 0x0570,
]

/// Each id taken with a stated gap: its fact key, words its reason holds and the
/// issue that owns the gap.
const partial_ids = [
  #(0x03ED, "opcode.0x3ed", "0x64D", "#58"),
  #(0x03EC, "opcode.0x3ec", "0x64C", "#58"),
  #(0x0269, "opcode.0x269", "0x26A", "#58"),
  #(0x018F, "opcode.0x18f", "0x192", "#58"),
  #(0x0180, "opcode.0x180", "scanbot", "#55"),
  #(0x0570, "opcode.0x570", "0x56F", "#60"),
  #(0x012B, "opcode.0x12b", "shared-challenge", "#52"),
]

fn named(message_id message_id: Int) -> String {
  "0x" <> string.pad_start(int.to_base16(message_id), 4, "0")
}

/// A message the client sends in its wrapper, under the base key.
fn sent(id id: Int, body body: BitArray) -> BitArray {
  let assert Ok(bytes) =
    encrypted_frame.wrap(
      encrypted_frame.ClientWrapper,
      Frame(message_id: id, body:),
      cipher.base(),
    )
    as "the frame is within the size limit"
  bytes
}

/// A message the client sends inside a 0x038C, as it sends world messages.
fn carried(id id: Int, body body: BitArray) -> BitArray {
  let assert Ok(inner) = frame.encode(message_id: id, body:)
    as "the frame is within the size limit"
  let assert Ok(carrier) =
    world_message.encode(WorldMessage(field_1: 0, inner_frame: inner))
    as "the carrier encodes"
  sent(id: 0x038C, body: carrier)
}

/// What the client sent, each recorded body of the thirteen ids, as it sends it:
/// 0x0241 on its own and the rest inside 0x038C.
fn as_sent(recorded: Recorded) -> BitArray {
  let Recorded(message_id:, body:, ..) = recorded
  case message_id {
    0x0241 -> sent(id: message_id, body:)
    _ -> carried(id: message_id, body:)
  }
}

pub fn dropped_ids_are_handled_and_the_missing_replies_are_stated_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let routing = coverage_support.engine_named("Client message routing")
  let handled = engine.handled_client_message_ids()
  list.each(dropped_ids, fn(id) {
    assert list.contains(handled, id)
      as {
        named(message_id: id) <> " is a routing row, so the measure counts it"
      }
  })
  assert !list.contains(handled, 0x0072) as "0x0072 has no row"
  let assert Measured(types:, breaches:, ..) =
    measurement.from_values(
      engine: routing,
      values: sent_message.all(),
      starting: [],
    )
    as "the routing engine is measured over the ids the client sends"
  assert breaches == [] as "every handled id is one the client sends"
  list.each(partial_ids, fn(entry) {
    let #(id, fact_key, words, owner) = entry
    let label = named(message_id: id)
    let assert Ok(TypeLine(status:, ..)) =
      list.find(types, fn(line) { line.type_number == id })
      as { label <> " is an id the client sends" }
    let assert HandledWithGap(reason:, fact_key: stated_key, ..) = status
      as { label <> " is handled with a stated gap, not done" }
    assert stated_key == fact_key
      as { label <> ": the gap names the client's record" }
    assert string.contains(reason, words)
      as {
        label <> ": the reason says what the client lacks (" <> reason <> ")"
      }
    assert string.contains(reason, owner)
      as { label <> ": the reason names the issue that owns it" }
  })
  let partial_numbers = list.map(partial_ids, fn(entry) { entry.0 })
  list.each(dropped_ids, fn(id) {
    case list.contains(partial_numbers, id) {
      True -> Nil
      False -> {
        let assert Ok(TypeLine(status:, ..)) =
          list.find(types, fn(line) { line.type_number == id })
          as { named(message_id: id) <> " is an id the client sends" }
        assert status == Handled
          as { named(message_id: id) <> " needs nothing the engine lacks" }
      }
    }
  })
  assert list.any(types, fn(line) { line.type_number == 0x0072 })
    && !list.any(types, fn(line) {
      line.type_number == 0x0072 && line.status == Handled
    })
    as "0x0072 is an id the client sends and is not handled"
  // The ranking of a planted folder in which the client sent every recorded body
  // of the thirteen ids and 0x0072.
  use folder <- recording_support.in_folder
  let planted =
    wire.Planted(
      rule: game_connection.rule_name,
      seed: wire.seed(1),
      ordinal: 1,
    )
  let reads =
    list.append(list.map(dropped_support.recorded(), as_sent), [
      carried(id: 0x0072, body: <<>>),
    ])
  wire.write(
    folder:,
    connections: [planted],
    steps: list.flatten([
      [wire.In(0, wire.now_at(1), Accepted)],
      list.index_map(reads, fn(bytes, index) {
        wire.In(0, wire.now_at(index + 2), Read(bytes))
      }),
      [wire.Closed(0, Client)],
    ]),
  )
  let #(lines, stopped) =
    wire.load(folder).connections
    |> list.map(fn(connection) { #(connection.name, connection.recording) })
    |> unhandled_ranking.ranking
  assert stopped == [] as "the recording reads whole"
  let ranked =
    list.map(lines, fn(line) {
      let assert [_, id, ..] = string.split(string.trim(line), "  ")
      id
    })
  assert ranked == ["0x0072"]
    as "the thirteen ids are taken, so only 0x0072, which no row takes yet, is ranked"
}
