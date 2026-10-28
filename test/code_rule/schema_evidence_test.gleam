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
  breach_lines_when_sent(text, sent_messages: [])
}

/// The breach lines when the modules outside the message folder import the
/// message modules named in `sent_messages`.
fn breach_lines_when_sent(
  text: String,
  sent_messages sent_messages: List(String),
) -> List(Int) {
  schema_evidence.breaches(
    file: SourceFile(path: "src/planted/schema.toml", text:),
    fact_keys:,
    sent_messages:,
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
      sent_messages: [],
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
      sent_messages: [],
    )
    == []
    as "CLAUDE.md: every packet layout lives in one schema with its evidence"
}

/// A field whose values are named, with the planted fact keys as evidence.
fn valued_field(values values: String) -> String {
  "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"0x1400a9140\", named_by = \"opcode.0x2\", values_type = \"Cause\", values = [ "
  <> values
  <> " ] },"
}

pub fn a_named_value_whose_evidence_is_a_fact_key_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        valued_field(
          values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 7, name = \"idle\", evidence = \"opcode.0x1\" }",
        ),
      ],
      record_fields: [good_field],
    )
  assert breach_lines(text) == []
}

pub fn a_named_value_that_names_no_evidence_is_a_breach_at_its_field_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        valued_field(
          values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 7, name = \"idle\" }",
        ),
      ],
      record_fields: [good_field],
    )
  let assert [breach] =
    schema_evidence.breaches(
      file: SourceFile(path: "src/planted/schema.toml", text:),
      fact_keys:,
      sent_messages: [],
    )
    as "expected exactly one breach"
  assert breach.line == 8 as "the field is the first line of the fields array"
  assert string.contains(breach.rule, "planted_hello.cause")
    as "the breach names the field"
  assert string.contains(breach.rule, "idle")
    as "the breach names the value that has no evidence"
}

pub fn a_named_value_whose_evidence_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        good_field,
        valued_field(
          values: "{ value = 6, name = \"gone\", evidence = \"opcode.0x7\" }",
        ),
      ],
      record_fields: [good_field],
    )
  let assert [breach] =
    schema_evidence.breaches(
      file: SourceFile(path: "src/planted/schema.toml", text:),
      fact_keys:,
      sent_messages: [],
    )
    as "expected exactly one breach"
  assert breach.line == 9
    as "the valued field is the second line of the fields array"
  assert string.contains(breach.rule, "opcode.0x7")
    as "the breach names the key the fact file lacks"
}

pub fn a_value_or_a_name_that_two_values_share_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert breach_lines(
      schema(
        fields: [
          valued_field(
            values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 6, name = \"idle\", evidence = \"0x1400ac130\" }",
          ),
        ],
        record_fields: [good_field],
      ),
    )
    == [1]
    as "two values of 6: the schema is refused, which the rule reports as a schema that is not one"
  assert breach_lines(
      schema(
        fields: [
          valued_field(
            values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 7, name = \"gone\", evidence = \"0x1400ac130\" }",
          ),
        ],
        record_fields: [good_field],
      ),
    )
    == [1]
    as "two values named gone: the schema is refused too"
}

const named_field =
  "  { name = \"build\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"

const unnamed_field =
  "  { name = \"field_3\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\" },"

const unnamed_safe_field =
  "  { name = \"field_3\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\", safe_by = \"opcode.0x2\" },"

pub fn an_unnamed_field_with_no_safe_by_in_a_message_the_server_sends_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(fields: [named_field, unnamed_field], record_fields: [good_field])
  let assert [breach] =
    schema_evidence.breaches(
      file: SourceFile(path: "src/planted/schema.toml", text:),
      fact_keys:,
      sent_messages: ["planted_hello"],
    )
    as "expected exactly one breach"
  assert breach.line == 9 as "the field is the second line of the fields array"
  assert string.contains(breach.rule, "planted_hello.field_3")
    as "the breach names the message and the field"
  assert string.contains(breach.rule, "safe_by")
    as "the breach says what the field lacks"
}

pub fn an_unnamed_field_with_a_safe_by_key_of_the_fact_file_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(fields: [named_field, unnamed_safe_field], record_fields: [
      good_field,
    ])
  assert breach_lines_when_sent(text, sent_messages: ["planted_hello"]) == []
}

pub fn a_safe_by_key_that_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(
      fields: [
        named_field,
        string.replace(unnamed_safe_field, "opcode.0x2", "opcode.0x9"),
      ],
      record_fields: [good_field],
    )
  assert breach_lines_when_sent(text, sent_messages: ["planted_hello"]) == [9]
}

pub fn a_message_the_client_sends_may_have_unnamed_fields_with_no_safe_by_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    string.replace(
      schema(fields: [named_field, unnamed_field], record_fields: [good_field]),
      "direction = \"server_to_client\"",
      "direction = \"client_to_server\"",
    )
  assert breach_lines_when_sent(text, sent_messages: ["planted_hello"]) == []
    as "the server never writes a client-to-server message, so no value of it is the server's to prove safe"
}

/// A message whose one field is an array of `planted_entry`, whose last field
/// is an array of `planted_inner`; the fields of each record are given.
fn schema_with_nested_records(
  entry_fields entry_fields: List(String),
  inner_fields inner_fields: List(String),
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
        "  { name = \"entries\", kind = \"array\", count_bits = 32, element = \"planted_entry\", evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },",
        "]",
        "",
        "[[record]]",
        "name = \"planted_entry\"",
        "evidence = \"0x1400ac130\"",
        "summary = \"a planted record\"",
        "fields = [",
      ],
      entry_fields,
      [
        "  { name = \"inners\", kind = \"array\", count_bits = 4, element = \"planted_inner\", evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },",
        "]",
        "",
        "[[record]]",
        "name = \"planted_inner\"",
        "evidence = \"0x1400ac130\"",
        "summary = \"a planted record inside a record\"",
        "fields = [",
      ],
      inner_fields,
      ["]", ""],
    ]),
    "\n",
  )
}

fn breach_rules(text: String, sent_messages: List(String)) -> List(String) {
  schema_evidence.breaches(
    file: SourceFile(path: "src/planted/schema.toml", text:),
    fact_keys:,
    sent_messages:,
  )
  |> list.map(fn(breach) { breach.rule })
}

pub fn an_unnamed_field_with_no_safe_by_in_a_record_a_message_the_server_sends_holds_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema_with_nested_records(
      entry_fields: [named_field, unnamed_field],
      inner_fields: [
        named_field,
      ],
    )
  let assert [breach] = breach_rules(text, ["planted_hello"])
    as "the entry's field is sent inside the message's array, so it needs a name or a safe_by"
  assert string.contains(breach, "planted_entry.field_3")
    as "the breach names the record and the field"
  assert breach_rules(text, []) == []
    as "a message no module outside the message folder imports is never sent, nor its records"
}

pub fn an_unnamed_field_with_no_safe_by_in_a_record_inside_a_record_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema_with_nested_records(entry_fields: [named_field], inner_fields: [
      named_field,
      unnamed_field,
    ])
  let assert [breach] = breach_rules(text, ["planted_hello"])
    as "the inner record is sent inside the entry, which is sent inside the message"
  assert string.contains(breach, "planted_inner.field_3")
  let safe =
    schema_with_nested_records(entry_fields: [named_field], inner_fields: [
      named_field,
      unnamed_safe_field,
    ])
  assert breach_rules(safe, ["planted_hello"]) == []
}

pub fn a_record_only_a_message_the_client_sends_holds_may_have_unnamed_fields_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    string.replace(
      schema_with_nested_records(
        entry_fields: [named_field, unnamed_field],
        inner_fields: [
          unnamed_field,
        ],
      ),
      "direction = \"server_to_client\"",
      "direction = \"client_to_server\"",
    )
  assert breach_rules(text, ["planted_hello"]) == []
    as "the server never writes a message the client sends, so no value of its records is the server's"
}

pub fn a_message_no_module_outside_the_message_folder_imports_is_not_sent_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    schema(fields: [named_field, unnamed_field], record_fields: [good_field])
  assert breach_lines_when_sent(text, sent_messages: ["another_message"]) == []
    as "a message nothing imports is never written by the server"
}

pub fn the_sent_messages_are_the_ones_a_module_outside_the_message_folder_imports_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let sources = [
    SourceFile(
      path: "src/genesis_prime/login/planted_rule.gleam",
      text: "import genesis_prime/message/planted_hello.{PlantedHello}\nimport genesis_prime/message/bit_stream\nimport genesis_prime/message/other as renamed\n",
    ),
    SourceFile(
      path: "src/genesis_prime/message/planted_carrier.gleam",
      text: "import genesis_prime/message/planted_inner\n",
    ),
  ]
  assert schema_evidence.sent_messages(sources)
    == ["bit_stream", "other", "planted_hello"]
    as "each module imported outside src/genesis_prime/message/, sorted and once; the message folder's own imports do not count"
}

pub fn every_unnamed_field_of_a_message_the_server_sends_names_its_safe_by_in_the_real_schema_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  let sent_messages =
    schema_evidence.sent_messages(repository.sources(under: ["src"]))
  assert list.contains(sent_messages, "server_hello")
    as "the auth rule imports the hello, so the real schema is read with it as a sent message"
  assert schema_evidence.breaches(
      file: SourceFile(path: "src/genesis_prime/message/schema.toml", text:),
      fact_keys: repository.fact_keys(),
      sent_messages:,
    )
    == []
    as "CLAUDE.md: a value the server sends that the client never reads is shown safe by a fact"
}

pub fn the_game_servers_messages_with_their_records_name_every_field_or_its_safe_by_in_the_real_schema_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  let sent_messages =
    schema_evidence.sent_messages(repository.sources(under: ["src"]))
  assert list.all(
    [
      "server_hello",
      "character_list",
      "disconnect_notice",
      "create_character_result",
      "play_character_refused",
      "max_character_level",
      "enter_world",
      "unit_create_player",
      "unit_is_player",
      "player_path",
      "client_control_granted",
      "movement_send_interval",
      "player_entered_world",
    ],
    list.contains(sent_messages, _),
  )
    as "the game rule imports the hello (through genesis_prime/connection/hello), the character list, the disconnect notice, the create result, the play refusal and the highest level, and world entry imports the seven messages that put the player in the world, so each is read as sent"
  assert schema_evidence.breaches(
      file: SourceFile(path: "src/genesis_prime/message/schema.toml", text:),
      fact_keys: repository.fact_keys(),
      sent_messages:,
    )
    == []
    as "CLAUDE.md: a value the server sends that the client never reads is shown safe by a fact, in the character list's entry and its visuals as in the messages, and in the player's 0x262 with its stats, movement commands and properties, 0xAD, 0x19B, 0x6BC and 0xF1"
}
