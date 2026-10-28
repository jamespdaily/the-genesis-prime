//// The schema reader and the generator on the field kinds the messages of
//// character select need: arrays of unsigned values and floats, a list counted
//// by an earlier list, and a value the schema fixes. Each case is a planted
//// schema; the real schema's own check is `message_codec_test` and the full
//// check's generator comparison.

import genesis_prime/message_generator
import genesis_prime/message_schema.{
  ArrayOfFloat32, ArrayOfUnsigned, Both, Constant, DuplicateValue,
  DuplicateValueName, NamedValues, UnknownCountField, UnsignedArrayCountedBy,
  UnsignedBelow, ValuesOnOtherKind, WrongTypeOfKey,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

fn schema_with(fields: String) -> String {
  "[[message]]\nid = 0x0001\nname = \"planted\"\ndirection = \"client_to_server\"\nevidence = \"opcode.0x1\"\nsummary = \"a planted message\"\nfields = [\n"
  <> fields
  <> "\n]\n\n[[record]]\nname = \"planted_record\"\nevidence = \"x\"\nsummary = \"a planted record\"\nfields = [\n  { name = \"id\", kind = \"unsigned\", bits = 8, evidence = \"x\" },\n]\n"
}

fn field_kinds(text: String) -> List(message_schema.Kind) {
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema parses"
  let assert [message] = schema.messages
    as "the planted schema holds one message"
  list.map(message.fields, fn(field) { field.kind })
}

pub fn the_reader_knows_arrays_of_values_floats_and_fixed_values_test() -> Nil {
  use <- owned_test.run(5000)
  assert field_kinds(schema_with(
      "  { name = \"labels\", kind = \"array\", count_bits = 4, element = \"unsigned\", element_bits = 32, evidence = \"x\" },
  { name = \"values\", kind = \"array\", counted_by = \"labels\", element = \"unsigned\", element_bits = 16, evidence = \"x\" },
  { name = \"bones\", kind = \"array\", count_bits = 32, element = \"float32\", evidence = \"x\" },
  { name = \"tag\", kind = \"constant\", bits = 6, value = 20, evidence = \"x\" },",
    ))
    == [
      ArrayOfUnsigned(count_bits: 4, bits: 32),
      UnsignedArrayCountedBy(counted_by: "labels", bits: 16),
      ArrayOfFloat32(count_bits: 32),
      Constant(bits: 6, value: 20),
    ]
}

pub fn a_list_counted_by_a_field_that_is_not_an_earlier_array_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"values\", kind = \"array\", counted_by = \"labels\", element = \"unsigned\", element_bits = 32, evidence = \"x\" },
  { name = \"labels\", kind = \"array\", count_bits = 4, element = \"unsigned\", element_bits = 32, evidence = \"x\" },",
    ))
    == Error(UnknownCountField(field: "values", counted_by: "labels"))
    as "a decoder reads the fields in order, so the count must be read before the list it counts"
  assert message_schema.parse(schema_with(
      "  { name = \"labels\", kind = \"unsigned\", bits = 4, evidence = \"x\" },
  { name = \"values\", kind = \"array\", counted_by = \"labels\", element = \"unsigned\", element_bits = 32, evidence = \"x\" },",
    ))
    == Error(UnknownCountField(field: "values", counted_by: "labels"))
    as "a plain value is a count, not a list the length of which another list may take"
}

pub fn a_fixed_value_that_does_not_fit_its_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"tag\", kind = \"constant\", bits = 2, value = 4, evidence = \"x\" },",
    ))
    == Error(WrongTypeOfKey("tag", "value"))
    as "a 2-bit value holds 0 to 3"
}

pub fn a_fixed_value_is_written_by_the_encoder_and_is_no_field_of_the_type_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(schema) =
    message_schema.parse(schema_with(
      "  { name = \"kind\", kind = \"constant\", bits = 6, value = 20, evidence = \"x\" },
  { name = \"id\", kind = \"unsigned\", bits = 32, evidence = \"x\" },",
    ))
    as "the planted schema parses"
  let assert [file, _record, _client_message] =
    message_generator.generate(schema)
    as "one message and one record are two modules, and the client message module is the third"
  assert string.contains(
    file.text,
    "bit_stream.write_constant(\"kind\", 20, 6)",
  )
    as "the encoder writes the fixed value"
  assert string.contains(
    file.text,
    "use reader <- result.try(bit_stream.read_constant(reader, \"kind\", 6, 20))",
  )
    as "the decoder refuses any other"
  assert !string.contains(file.text, "kind: Int")
    as "the type holds no field for it"
  assert string.contains(file.text, "Planted(id: Int)")
    as "the type holds the field that is not fixed"
}

pub fn the_reader_knows_a_value_below_a_limit_and_a_message_sent_both_ways_test() -> Nil {
  use <- owned_test.run(5000)
  let text =
    string.replace(
      schema_with(
        "  { name = \"number\", kind = \"unsigned_below\", bits = 8, limit = 20, evidence = \"x\" },",
      ),
      "client_to_server",
      "both",
    )
  assert field_kinds(text) == [UnsignedBelow(bits: 8, limit: 20)]
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema parses"
  let assert [message] = schema.messages as "one message"
  assert message.direction == Both
    as "a message either side sends has the direction both"
  let assert [file, _record, _client_message] =
    message_generator.generate(schema)
    as "one message and one record are two modules, and the client message module is the third"
  assert string.contains(file.text, "either direction")
  assert string.contains(
    file.text,
    "bit_stream.read_unsigned_below(\n    reader,\n    \"number\",\n    8,\n    20,\n  )",
  )
    as "the decoder refuses a value at or above the limit"
}

pub fn a_limit_above_the_fields_width_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"number\", kind = \"unsigned_below\", bits = 4, limit = 17, evidence = \"x\" },",
    ))
    == Error(WrongTypeOfKey("number", "limit"))
    as "a 4-bit value is below 16 at the most"
}

const valued_field =
  "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" }, { value = 19, name = \"timed_out\" } ] },"

pub fn a_field_lists_its_named_values_with_their_evidence_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(schema) = message_schema.parse(schema_with(valued_field))
    as "the planted schema parses"
  let assert [message] = schema.messages as "one message"
  let assert [field] = message.fields as "one field"
  assert field.named_values
    == Some(
      NamedValues(type_name: "Cause", values: [
        message_schema.Value(value: 6, name: "gone", evidence: Some("x")),
        message_schema.Value(value: 19, name: "timed_out", evidence: None),
      ]),
    )
    as "each value keeps its number, its name and the evidence it names, if any"
}

pub fn a_value_listed_twice_or_named_twice_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" }, { value = 6, name = \"idle\", evidence = \"x\" } ] },",
    ))
    == Error(DuplicateValue(field: "cause", value: 6))
    as "one number has one case"
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" }, { value = 7, name = \"gone\", evidence = \"x\" } ] },",
    ))
    == Error(DuplicateValueName(field: "cause", name: "gone"))
    as "one name is one case"
}

pub fn a_value_that_does_not_fit_the_fields_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 32, name = \"gone\", evidence = \"x\" } ] },",
    ))
    == Error(WrongTypeOfKey("cause", "value"))
    as "a 5-bit field holds 0 to 31"
}

pub fn values_on_a_field_that_is_not_an_unsigned_value_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"wide_text\", evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },",
    ))
    == Error(ValuesOnOtherKind("cause"))
    as "only an unsigned value has numbers to name"
}

pub fn a_valued_field_is_a_custom_type_with_other_decoded_and_encoded_at_the_edge_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(schema) = message_schema.parse(schema_with(valued_field))
    as "the planted schema parses"
  let assert [file, _record, _client_message] =
    message_generator.generate(schema)
    as "one message and one record are two modules, and the client message module is the third"
  list.each(
    [
      "pub type Cause {",
      "  Gone\n",
      "  TimedOut\n",
      "  Other(Int)",
      "Planted(cause: Cause)",
      "bit_stream.write_unsigned(\"cause\", cause_to_value(message.cause), 5)",
      "let cause = cause_from_value(cause)",
      "    6 -> Gone",
      "    19 -> TimedOut",
      "    other -> Other(other)",
      "    Gone -> 6",
      "    TimedOut -> 19",
      "    Other(value) -> value",
    ],
    fn(text) {
      assert string.contains(file.text, text)
        as { "the generated module holds `" <> text <> "`" }
    },
  )
}
