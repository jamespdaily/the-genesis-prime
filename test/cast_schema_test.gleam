//// The unnamed fields of the cast messages the server sends each name the fact
//// that shows the value sent is safe (`code_rule/schema_evidence` holds the rule
//// for the whole schema; this holds which fact each of these fields names). The
//// keys and the safe values are the decode's records for 0x7ff, 0x7f4 and the
//// cast messages' lists: `opcode.0x7ff.caster_item_level` (0),
//// `opcode.0x7ff.own_cast` (1), `opcode.0x7ff.activate` (0),
//// `opcode.0x7f4.effect_time` (0), `opcode.0x7f4.effect_bit` (0) and
//// `spell.empty_lists` (the lists the server sends empty), whose statements name
//// the safe value; each statement is read from the fact file here.

import fact_file
import genesis_prime/message_schema.{type Field}
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import simplifile

const schema_path = "src/genesis_prime/message/schema.toml"

/// The fields the cast messages leave unnamed, by the owner's name, with the
/// fact each names and the words of that fact's statement that give the safe
/// value the server sends.
const unnamed = [
  #(
    "spell_started",
    "field_6",
    "opcode.0x7ff.caster_item_level",
    "Safe value: 0",
  ),
  #("spell_started", "field_12", "opcode.0x7ff.own_cast", "Safe value: 1"),
  #(
    "spell_started",
    "field_13",
    "opcode.0x7ff.activate",
    "Safe value for ability casts: 0",
  ),
  #("spell_effect_info", "field_4", "opcode.0x7f4.effect_time", "Safe value: 0"),
  #("spell_effect_bit", "field_2", "opcode.0x7f4.effect_bit", "Safe value: 0"),
  #("spell_initial_position", "field_2", "spell.empty_lists", "may be empty"),
  #("spell_initial_position", "field_4", "spell.empty_lists", "may be empty"),
  #("spell_initial_position", "field_5", "spell.empty_lists", "may be empty"),
  #("spell_telegraph_position", "field_1", "spell.empty_lists", "may be empty"),
  #("spell_telegraph_position", "field_3", "spell.empty_lists", "may be empty"),
  #("spell_telegraph_position", "field_5", "spell.empty_lists", "may be empty"),
  #("spell_telegraph_position", "field_6", "spell.empty_lists", "may be empty"),
  #("spell_missile_info", "field_1", "spell.empty_lists", "may be empty"),
  #("spell_missile_info", "field_2", "spell.empty_lists", "may be empty"),
  #("spell_missile_info", "field_3", "spell.empty_lists", "may be empty"),
  #("spell_missile_info", "field_4", "spell.empty_lists", "may be empty"),
  #("spell_missile_info", "field_5", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_1", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_2", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_3", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_4", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_5", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_6", "spell.empty_lists", "may be empty"),
  #("spell_hit_entry", "field_7", "spell.empty_lists", "may be empty"),
]

fn fields_of(owner owner: String) -> List(Field) {
  let assert Ok(text) = simplifile.read(schema_path)
    as "the schema file is read from the project folder"
  let assert Ok(schema) = message_schema.parse(text) as "the real schema parses"
  case list.find(schema.messages, fn(message) { message.name == owner }) {
    Ok(message) -> message.fields
    Error(Nil) -> {
      let assert Ok(record) =
        list.find(schema.records, fn(record) { record.name == owner })
        as { "the schema holds no message or record named " <> owner }
      record.fields
    }
  }
}

pub fn each_unnamed_field_of_the_cast_messages_names_the_fact_that_shows_its_value_safe_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(unnamed, fn(row) {
    let #(owner, field, key, safe_words) = row
    let assert Ok(found) =
      list.find(fields_of(owner:), fn(candidate) { candidate.name == field })
      as { owner <> " holds no field " <> field }
    assert found.safe_by == Some(key)
      as {
        owner
        <> "."
        <> field
        <> " names "
        <> key
        <> " as what shows its value safe"
      }
    let assert Ok(statement) = fact_file.statement(record: key)
      as { key <> " is a record of the fact file" }
    assert string.contains(statement, safe_words)
      as { key <> " states the safe value: " <> safe_words }
  })
}
