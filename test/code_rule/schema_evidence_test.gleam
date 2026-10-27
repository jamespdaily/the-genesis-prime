//// The schema-evidence rule: every field of the message schema names its
//// evidence, a key of the client's fact file (CLAUDE.md: every packet layout
//// lives in one schema with its evidence). A field with no `evidence`, or one
//// whose key is not in the fact file, is a breach at the field's line, and so
//// is a `named_by` key the fact file lacks. Every case is planted in a made-up
//// schema; the last test reads the real schema and the real fact file.

import code_rule/repository
import code_rule/schema_evidence
import code_rule/source.{SourceFile}
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

const fact_keys = ["opcode.0x1", "0x1400a9140", "0x1400ac130", "opcode.0x2"]

fn schema(
  fields fields: List(String),
  record_fields record_fields: List(String),
) -> String {
  string.join(
    list.flatten([
      [
        "[[message]]",
        "id = 0x0001",
        "name = \"planted_hello\"",
        "direction = \"server_to_client\"",
        "evidence = \"opcode.0x1\"",
        "summary = \"a planted message\"",
        "fields = [",
      ],
      fields,
      [
        "]",
        "",
        "[[record]]",
        "name = \"planted_entry\"",
        "evidence = \"0x1400ac130\"",
        "summary = \"a planted record\"",
        "fields = [",
      ],
      record_fields,
      ["]", ""],
    ]),
    "\n",
  )
}

const good_field =
  "  { name = \"build\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\" },"

fn breach_lines(text: String) -> List(Int) {
  schema_evidence.breaches(
    file: SourceFile(path: "src/planted/schema.toml", text:),
    fact_keys:,
  )
  |> list.map(fn(breach) { breach.line })
}

pub fn a_field_that_names_no_evidence_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        good_field,
        "  { name = \"other\", kind = \"unsigned\", bits = 32 },",
      ],
      record_fields: [good_field],
    )
  let breaches =
    schema_evidence.breaches(
      file: SourceFile(path: "src/planted/schema.toml", text:),
      fact_keys:,
    )
  let assert [breach] = breaches as "expected exactly one breach"
  assert breach.path == "src/planted/schema.toml"
  assert breach.line == 9 as "the field is the second line of the fields array"
  assert string.contains(breach.rule, "planted_hello.other")
    as "the breach names the message and the field"
}

pub fn a_field_of_a_record_that_names_no_evidence_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(fields: [good_field], record_fields: [
      "  { name = \"loose\", kind = \"wide_text\" },",
    ])
  assert breach_lines(text) == [16]
}

pub fn a_field_whose_evidence_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        "  { name = \"build\", kind = \"unsigned\", bits = 32, evidence = \"planted.not_a_fact_key\" },",
      ],
      record_fields: [good_field],
    )
  assert breach_lines(text) == [8]
}

pub fn a_named_by_key_that_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        "  { name = \"build\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\", named_by = \"opcode.0x9\" },",
      ],
      record_fields: [good_field],
    )
  assert breach_lines(text) == [8]
}

pub fn a_message_whose_evidence_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    string.replace(
      schema(fields: [good_field], record_fields: [good_field]),
      "evidence = \"opcode.0x1\"",
      "evidence = \"opcode.0x7\"",
    )
  assert breach_lines(text) == [5]
}

pub fn fields_that_name_their_evidence_are_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        good_field,
        "  { name = \"named\", kind = \"unsigned\", bits = 8, evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },",
      ],
      record_fields: [good_field],
    )
  assert breach_lines(text) == []
}

pub fn a_file_that_is_not_a_schema_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breach_lines("[[message]]\nid = \"seven\"\n") == [1]
}

pub fn every_field_of_the_message_schema_names_its_evidence_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  assert schema_evidence.breaches(
      file: SourceFile(path: "src/genesis_prime/message/schema.toml", text:),
      fact_keys: repository.fact_keys(),
    )
    == []
    as "CLAUDE.md: every packet layout lives in one schema with its evidence"
}
