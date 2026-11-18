//// Tests of the cast messages: the item use body, and the names and evidence of the cast results.

import fact_file
import genesis_prime/message/cast_result
import genesis_prime/message/client_message
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/item_use
import genesis_prime/message_schema
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import simplifile

const schema_path = "src/genesis_prime/message/schema.toml"

/// The bytes are the client's writer's output for the body, least significant
/// bit first (WriteMessage0943Body `0x1400937b0`, `opcode.0x943`): the cast id
/// 7 (32 bits), the item place {1, 3} (9 bits, 32 bits), the target 0x1234
/// (32 bits), the second place {300, 0xffffffff}, then 1.0, 2.0 and 3.0 as the
/// bits of 32-bit floats (0x3f800000, 0x40000000, 0x40400000). The 242 bits
/// fill 31 bytes, the last with 6 bits of padding.
pub fn item_use_body_reads_in_the_client_order_test() -> Nil {
  use <- owned_test.run(5000)
  let body = <<
    0x07, 0x00, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00, 0x68, 0x24, 0x00, 0x00,
    0x58, 0xfe, 0xff, 0xff, 0xff, 0x03, 0x00, 0x00, 0xfe, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x00, 0x01, 0x01,
  >>
  let expected =
    item_use.ItemUse(
      client_cast_id: 7,
      item: ItemPlace(location: 1, bag_index: 3),
      target_unit_id: 0x1234,
      second_item: ItemPlace(location: 300, bag_index: 0xffffffff),
      position_x: 0x3f800000,
      position_y: 0x40000000,
      position_z: 0x40400000,
    )
  assert item_use.decode(body) == Ok(expected)
    as "the fields are read in the order the client writes them"
  assert client_message.decode(message_id: item_use.message_id, body:)
    == Ok(client_message.ItemUse(message: expected))
    as "message 0x943 is the client's use of an item"
  let assert Error(_) = item_use.decode(<<0x07, 0x00, 0x00, 0x00, 0x01>>)
    as "a body short of the fields is one the client's reader refuses"
  Nil
}

/// The three lists of cast results, by the message that holds each and the field's name.
const cast_result_lists = [
  #("spell_cast_refused", "result"),
  #("spell_failed", "result"),
  #("cancel_cast", "reason"),
]

pub fn the_invulnerability_cast_results_are_named_with_their_evidence_test() -> Nil {
  use <- owned_test.run(10_000)
  // `Spell.CodeEnumCastResult.306_308` and the table `Spell4CastResult` rows 306 to 308
  // (enumName Target_HostileInvulnerability, Target_InvulnerableToOther and
  // Target_BeneficialInvulnerability).
  let assert Ok(text) = simplifile.read(schema_path)
    as "the schema file is read from the project folder"
  let assert Ok(schema) = message_schema.parse(text) as "the real schema parses"
  list.each(cast_result_lists, fn(place) {
    let #(owner, field_name) = place
    let assert Ok(message) =
      list.find(schema.messages, fn(message) { message.name == owner })
      as { "the schema holds the message " <> owner }
    let assert Ok(message_schema.Field(
      kind: message_schema.Unsigned(values: Some(named), ..),
      ..,
    )) = list.find(message.fields, fn(field) { field.name == field_name })
      as { owner <> "." <> field_name <> " is a named list" }
    let found = fn(number) {
      list.find(named.values, fn(value) { value.value == number })
    }
    assert found(306)
      == Ok(message_schema.Value(
        306,
        "target_hostile_invulnerability",
        Some("Spell.CodeEnumCastResult.306_308"),
      ))
    assert found(307)
      == Ok(message_schema.Value(
        307,
        "target_invulnerable_to_other",
        Some("Spell.CodeEnumCastResult.306_308"),
      ))
    assert found(308)
      == Ok(message_schema.Value(
        308,
        "target_beneficial_invulnerability",
        Some("Spell.CodeEnumCastResult.306_308"),
      ))
  })
  let assert Ok(statement) =
    fact_file.statement(record: "Spell.CodeEnumCastResult.306_308")
    as "the evidence key is a record of the fact file"
  assert string.contains(statement, "306 Target_HostileInvulnerability")
    && string.contains(statement, "307 Target_InvulnerableToOther")
    && string.contains(statement, "308 Target_BeneficialInvulnerability")
    as "the record names the three results the schema names"
  assert cast_result.from_value(306) == cast_result.TargetHostileInvulnerability
  assert cast_result.from_value(307) == cast_result.TargetInvulnerableToOther
  assert cast_result.from_value(308)
    == cast_result.TargetBeneficialInvulnerability
    as "the generated codec reads each number as its name"
  assert list.map(
      [
        cast_result.TargetHostileInvulnerability,
        cast_result.TargetInvulnerableToOther,
        cast_result.TargetBeneficialInvulnerability,
      ],
      cast_result.to_value,
    )
    == [306, 307, 308]
}
