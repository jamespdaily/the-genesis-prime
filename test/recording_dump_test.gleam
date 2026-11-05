//// The recording dump reads the committed session's recordings as messages.
//// Expected values come from these places.
//// - The session's own verdict (`verdict.txt` beside the recordings): the
////   client reported the played character as 'Tess Renamed'.
//// - The client's code: it sends 0x023C through SendWorldMessage (0x1403f4900,
////   which lists 0x23c among the ids it sends), inside 0x038C inside the
////   client's wrapper; the schema has no message of that number.

import genesis_prime/named_fields
import genesis_prime/recorded_message.{ClientToServer, ServerToClient}
import genesis_prime/recording_dump
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import wire_replay_support as support

pub fn the_dump_names_the_players_unit_and_lists_a_message_with_no_decoder_by_its_number_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(names) = named_fields.from_schema_file()
    as "the schema the codec is generated from reads"
  let connections =
    support.load(support.committed_session).connections
    |> list.map(fn(connection) { #(connection.name, connection.recording) })
  let entries = recording_dump.entries(connections:, names:)
  let assert Ok(created) =
    list.find(entries, fn(entry) {
      entry.direction == ServerToClient
      && entry.message_id == Some(0x0262)
      && entry.name == "unit_create_player"
    })
    as "the server wrote the player's unit, named by the schema"
  assert string.contains(created.fields, "name: \"Tess Renamed\"")
    as "the unit is the character the client reported (verdict.txt: strName = 'Tess Renamed')"
  let assert Ok(unhandled) =
    list.find(entries, fn(entry) {
      entry.direction == ClientToServer && entry.message_id == Some(0x023C)
    })
    as "the client sent 0x023C (0x1403f4900)"
  assert unhandled.name == "unhandled"
    as "no message of the schema the client sends has the number 0x023C"
  assert unhandled.depth == 2
    as "it came inside 0x038C inside the client's wrapper (0x1403f4900)"
}
