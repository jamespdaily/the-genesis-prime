//// The generated codec matches the schema. CLAUDE.md: the codec is generated,
//// states the size and byte order of every field, and is never edited by hand.
//// The full check runs the same comparison (`gleam run -m
//// genesis_prime/generate_messages -- check`); these tests prove it sees a
//// hand edit, a missing file and a stale one, and that the committed files
//// are the generated ones. Every case is planted from the generated files, so
//// no expected text is written here.

import genesis_prime/message_generator.{
  type GeneratedFile, Edited, GeneratedFile, Missing, Stale,
}
import genesis_prime/message_schema
import gleam/list
import gleam/string
import owned_test
import simplifile

const schema_path = "src/genesis_prime/message/schema.toml"

const directory = "src/genesis_prime/message"

fn generated() -> List(GeneratedFile) {
  let assert Ok(text) = simplifile.read(schema_path)
    as "the schema file could not be read"
  let assert Ok(schema) = message_schema.parse(text)
    as "the schema file is a schema"
  message_generator.generate(schema)
}

fn committed() -> List(GeneratedFile) {
  let assert Ok(paths) = simplifile.get_files(directory)
    as "the codec directory could not be listed"
  paths
  |> list.filter(string.ends_with(_, ".gleam"))
  |> list.map(fn(path) {
    let assert Ok(text) = simplifile.read(path)
      as { "a committed file could not be read: " <> path }
    GeneratedFile(path:, text:)
  })
}

fn file_named(files: List(GeneratedFile), name: String) -> GeneratedFile {
  let assert Ok(file) =
    list.find(files, fn(file) { string.ends_with(file.path, "/" <> name) })
    as { "the schema generates " <> name }
  file
}

pub fn the_schema_generates_one_module_for_each_message_and_record_test() -> Nil {
  use <- owned_test.run(5000)
  let paths =
    generated()
    |> list.map(fn(file) { file.path })
    |> list.sort(string.compare)
  assert paths
    == [
      "src/genesis_prime/message/character_list.gleam",
      "src/genesis_prime/message/character_list_entry.gleam",
      "src/genesis_prime/message/character_select_start.gleam",
      "src/genesis_prime/message/choose_realm.gleam",
      "src/genesis_prime/message/client_wrapper.gleam",
      "src/genesis_prime/message/create_character.gleam",
      "src/genesis_prime/message/create_character_carrier.gleam",
      "src/genesis_prime/message/create_character_result.gleam",
      "src/genesis_prime/message/delete_character.gleam",
      "src/genesis_prime/message/delete_character_result.gleam",
      "src/genesis_prime/message/disconnect_notice.gleam",
      "src/genesis_prime/message/enter_world.gleam",
      "src/genesis_prime/message/game_hello_reply.gleam",
      "src/genesis_prime/message/game_server_handoff.gleam",
      "src/genesis_prime/message/item_visual.gleam",
      "src/genesis_prime/message/login_accepted.gleam",
      "src/genesis_prime/message/login_request.gleam",
      "src/genesis_prime/message/max_character_level.gleam",
      "src/genesis_prime/message/movement_send_interval.gleam",
      "src/genesis_prime/message/play_character.gleam",
      "src/genesis_prime/message/play_character_refused.gleam",
      "src/genesis_prime/message/player_entered_world.gleam",
      "src/genesis_prime/message/realm_entry.gleam",
      "src/genesis_prime/message/realm_handoff.gleam",
      "src/genesis_prime/message/realm_list.gleam",
      "src/genesis_prime/message/realm_select_start.gleam",
      "src/genesis_prime/message/rename_character.gleam",
      "src/genesis_prime/message/rename_character_result.gleam",
      "src/genesis_prime/message/server_hello.gleam",
      "src/genesis_prime/message/terrain_loaded.gleam",
      "src/genesis_prime/message/text_group.gleam",
      "src/genesis_prime/message/unit_create_player.gleam",
      "src/genesis_prime/message/unit_destroyed.gleam",
      "src/genesis_prime/message/unit_is_player.gleam",
      "src/genesis_prime/message/world_message.gleam",
    ]
    as "the schema holds the 13 Milestone 1 messages of the issue and the 2 records inside the realm list, and the 18 messages and 2 records of character select and entering the world"
}

pub fn the_committed_codec_is_what_the_schema_generates_test() -> Nil {
  use <- owned_test.run(10_000)
  assert message_generator.mismatches(generated(), committed()) == []
    as "CLAUDE.md: the codec is generated and never edited by hand; run `gleam run -m genesis_prime/generate_messages`"
}

pub fn a_planted_hand_edit_to_a_generated_file_is_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let target = file_named(files, "server_hello.gleam")
  let edited =
    list.map(files, fn(file) {
      case file == target {
        True -> GeneratedFile(..file, text: file.text <> "\n// a hand edit\n")
        False -> file
      }
    })
  assert message_generator.mismatches(files, edited) == [Edited(target.path)]
    as "a committed file that differs from the generated text is named"
  let narrowed =
    list.map(files, fn(file) {
      case file == target {
        True ->
          GeneratedFile(
            ..file,
            text: string.replace(
              file.text,
              "\"field_7\", message.field_7, 5)",
              "\"field_7\", message.field_7, 6)",
            ),
          )
        False -> file
      }
    })
  assert narrowed != files
    as "the planted edit changes a field's width in the generated text"
  assert message_generator.mismatches(files, narrowed) == [Edited(target.path)]
    as "a one-digit edit to a width is seen"
}

pub fn a_generated_file_that_is_not_committed_is_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let target = file_named(files, "realm_list.gleam")
  let without = list.filter(files, fn(file) { file != target })
  assert message_generator.mismatches(files, without) == [Missing(target.path)]
    as "a file the schema generates and the repository lacks is named"
}

pub fn a_committed_generated_file_the_schema_no_longer_generates_is_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let old =
    GeneratedFile(
      path: "src/genesis_prime/message/removed_message.gleam",
      text: message_generator.generated_marker <> " from an older schema\n",
    )
  assert message_generator.mismatches(files, [old, ..files])
    == [Stale(old.path)]
    as "a generated file with no message or record in the schema is named"
}

pub fn a_hand_written_module_beside_the_generated_ones_is_not_a_mismatch_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = generated()
  let hand_written =
    GeneratedFile(
      path: "src/genesis_prime/message/bit_stream.gleam",
      text: "//// How a message body is written and read.\n",
    )
  assert message_generator.mismatches(files, [hand_written, ..files]) == []
    as "only files that carry the generated marker are compared"
}

pub fn a_generated_encoder_states_the_width_of_every_field_test() -> Nil {
  use <- owned_test.run(10_000)
  let text = file_named(generated(), "server_hello.gleam").text
  assert string.contains(
    text,
    "bit_stream.write_unsigned(\"build\", message.build, 32)",
  )
    as "ReadMessage0003Body 0x1400a9140: the build is 32 bits, written in the code"
  assert string.contains(
    text,
    "bit_stream.write_unsigned(\"field_5\", message.field_5, 64)",
  )
    as "ReadMessage0003Body 0x1400a9140: the fifth value is 64 bits"
  assert string.contains(
    text,
    "bit_stream.write_unsigned(\"field_7\", message.field_7, 5)",
  )
    as "ReadMessage0003Body 0x1400a9140: the seventh value is 5 bits"
  assert string.contains(text, "bit_stream.read_unsigned(reader, 5)")
    as "the reader states the same width"
}
