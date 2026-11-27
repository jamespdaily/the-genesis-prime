//// The codec the generator writes for a planted schema round-trips. The
//// schema (`test/planted_codec/schema.toml`) holds a message with a field of
//// every kind a schema has and a record inside it; the generator's files are
//// written into a scratch Gleam project beside the bit stream module, built
//// and run by `gleam` with a driver (`test/planted_codec/driver.gleam.txt`)
//// that encodes planted messages, reads them back and checks every refusal.
//// Expected values come from these places.
//// - The schema's kinds (dev/genesis_prime/message_schema.gleam, `Kind`): the
////   planted message has one field of each.
//// - The bit stream's rules (WriteBits 0x140336380, ReadBits32 0x14006c090): a
////   message reads back as it was written, a body cut inside a field ends in
////   `EndOfData` (0x80070026), a value out of its width or limit is refused.
//// - The scratch project depends on the project's own copy of the standard
////   library (`build/packages/gleam_stdlib`) by path, so no package is
////   fetched.

import genesis_prime/message_generator.{type GeneratedFile, GeneratedFile}
import genesis_prime/message_schema
import gleam/list
import gleam/result
import gleam/string
import owned_test
import recording_support
import scratch_project
import simplifile

const bit_stream_path = "src/genesis_prime/message/bit_stream.gleam"

const half_float_path = "src/genesis_prime/message/half_float.gleam"

pub fn the_codec_generated_for_a_schema_with_a_field_of_every_kind_round_trips_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let ran = build_and_run(folder:, files: planted_files())
  let assert Ok(output) = ran
    as "the scratch project builds and the driver passes"
  list.each(
    [
      "the empty message round-trips",
      "the full message round-trips",
      "the mixed message round-trips",
      "the refusals hold",
    ],
    fn(line) {
      assert string.contains(output, line)
        as { "the driver printed: " <> line <> "; it printed: " <> output }
    },
  )
}

pub fn generator_writes_must_encode_naming_each_message_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = planted_files()
  let assert Ok(text) = simplifile.read("test/planted_codec/schema.toml")
    as "the planted schema reads"
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema is a schema"
  assert schema.messages != [] as "the planted schema holds a message"
  list.each(schema.messages, fn(message) {
    let path = "src/genesis_prime/message/" <> message.name <> ".gleam"
    let assert Ok(file) = list.find(files, fn(file) { file.path == path })
      as { "the generator writes " <> path }
    assert string.contains(file.text, "pub fn must_encode(")
      as { message.name <> " has a must_encode" }
    assert string.contains(
      file.text,
      "bit_stream.must(encode(message), \"" <> message.name <> "\")",
    )
      as { message.name <> "'s must_encode names the message from the schema" }
  })
}

pub fn the_planted_codec_with_an_open_field_and_a_union_of_never_and_open_tags_builds_and_refuses_those_tags_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let files = planted_files()
  assert list.any(files, fn(file) {
    string.ends_with(file.path, "/planted_flag.gleam")
    && string.contains(file.text, "/// Open: what the client does with the")
  })
    as "the open field's question is a doc of the generated record"
  let ran = build_and_run(folder:, files:)
  let assert Ok(output) = ran
    as "the scratch project builds with the open field and the marked union, and the driver passes"
  assert string.contains(output, "the never and open kinds are refused")
    as {
      "the driver printed that kinds 3 (never) and 4 (open) fail with UnexpectedValue; it printed: "
      <> output
    }
  assert string.contains(output, "the full message round-trips")
    as "the round trips still pass"
}

pub fn a_generated_codec_whose_decoder_reads_another_width_fails_the_round_trip_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let files =
    list.map(planted_files(), fn(file) {
      case string.ends_with(file.path, "/planted_message.gleam") {
        True ->
          GeneratedFile(
            ..file,
            text: string.replace(
              file.text,
              "bit_stream.read_unsigned(reader, 3)",
              "bit_stream.read_unsigned(reader, 4)",
            ),
          )
        False -> file
      }
    })
  assert files != planted_files()
    as "the planted edit changes the width the decoder reads"
  assert result.is_error(build_and_run(folder:, files:))
    as "a decoder that reads a 4-bit field where the encoder writes 3 does not read the message back, so the driver exits with an error"
}

pub fn a_generated_union_that_peeks_fewer_bits_than_its_kind_fails_the_round_trip_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let files =
    list.map(planted_files(), fn(file) {
      case string.ends_with(file.path, "/planted_union.gleam") {
        True ->
          GeneratedFile(
            ..file,
            text: string.replace(
              file.text,
              "bit_stream.peek_unsigned(reader, 3)",
              "bit_stream.peek_unsigned(reader, 2)",
            ),
          )
        False -> file
      }
    })
  assert files != planted_files()
    as "the planted edit changes the width the union peeks"
  assert result.is_error(build_and_run(folder:, files:))
    as "a union that peeks 2 bits of a 3-bit kind picks the wrong layout or none, so the driver exits with an error"
}

/// The files the planted schema generates.
fn planted_files() -> List(GeneratedFile) {
  let assert Ok(text) = simplifile.read("test/planted_codec/schema.toml")
    as "the planted schema reads"
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema is a schema"
  message_generator.generate(schema)
}

/// Writes `files`, the bit stream module and the driver into a scratch
/// project in `folder` and runs the driver.
fn build_and_run(
  folder folder: String,
  files files: List(GeneratedFile),
) -> Result(String, #(Int, String)) {
  let project =
    scratch_project.create(folder:, name: "planted_codec", packages: [
      "gleam_stdlib",
    ])
  let assert Ok(driver) = simplifile.read("test/planted_codec/driver.gleam.txt")
    as "the driver reads"
  let assert Ok(bit_stream) = simplifile.read(bit_stream_path)
    as "the bit stream module reads"
  let assert Ok(half_float) = simplifile.read(half_float_path)
    as "the half float module, which the bit stream's half float field reads, reads"
  list.each(
    [
      GeneratedFile(path: "src/planted_driver.gleam", text: driver),
      GeneratedFile(path: bit_stream_path, text: bit_stream),
      GeneratedFile(path: half_float_path, text: half_float),
      ..files
    ],
    fn(file) {
      scratch_project.write_file(project:, path: file.path, text: file.text)
    },
  )
  scratch_project.gleam(project:, arguments: [
    "run",
    "--module",
    "planted_driver",
  ])
}
