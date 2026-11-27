//// The schema reader and the generator on the field kinds the messages of
//// character select need: arrays of unsigned values and floats, a list counted
//// by an earlier list, and a value the schema fixes. Each case is a planted
//// schema; the real schema's own check is `message_codec_test` and the full
//// check's generator comparison.

import genesis_prime/message_generator
import genesis_prime/message_schema.{
  ArrayOfFloat32, ArrayOfRecord, ArrayOfRecordCountedBy, ArrayOfUnsigned, Both,
  ConflictingValues, Constant, DuplicateTag, DuplicateValue, DuplicateValueName,
  DuplicateVariantName, HalfFloatAtLeast, MissingKey, NamedValues, NeverTag,
  OneRecord, OpenAndNamed, OpenTag, TagBeyondRefused, Union, UnknownCountField,
  UnknownRecord, UnknownVariantRecord, UnsignedArrayCountedBy, UnsignedBelow,
  ValueNamedOther, ValuesOnOtherKind, Variant, VariantKindDisagrees,
  WrongTypeOfKey,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import simplifile

const schema_path = "src/genesis_prime/message/schema.toml"

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
  let assert [file, _record, _client_message, _server_message] =
    message_generator.generate(schema)
    as "one message and one record are two modules, and the client and server message modules are the third and fourth"
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
  let assert [file, _record, _client_message, _server_message] =
    message_generator.generate(schema)
    as "one message and one record are two modules, and the client and server message modules are the third and fourth"
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
  assert message_schema.named_values(field:)
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

/// The generated file of a module, by its file name.
fn generated_file(
  files: List(message_generator.GeneratedFile),
  name: String,
) -> String {
  let assert Ok(file) =
    list.find(files, fn(file) {
      string.ends_with(file.path, "/" <> name <> ".gleam")
    })
    as { "the schema generates " <> name }
  file.text
}

fn generated(text: String) -> List(message_generator.GeneratedFile) {
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema parses"
  message_generator.generate(schema)
}

pub fn a_valued_field_is_a_custom_type_in_a_module_of_its_own_with_other_test() -> Nil {
  use <- owned_test.run(5000)
  let files = generated(schema_with(valued_field))
  let values = generated_file(files, "cause")
  list.each(
    [
      "pub type Cause {",
      "  Gone\n",
      "  TimedOut\n",
      "  Other(Int)",
      "pub fn to_value(value: Cause) -> Int {",
      "    Gone -> 6",
      "    TimedOut -> 19",
      "    Other(number) -> number",
      "pub fn from_value(number: Int) -> Cause {",
      "    6 -> Gone",
      "    19 -> TimedOut",
      "    other -> Other(other)",
    ],
    fn(text) {
      assert string.contains(values, text)
        as { "the module of the values holds `" <> text <> "`" }
    },
  )
  let message = generated_file(files, "planted")
  list.each(
    [
      "import genesis_prime/message/cause.{type Cause}",
      "Planted(cause: Cause)",
      "bit_stream.write_unsigned(\"cause\", cause.to_value(message.cause), 5)",
      "let cause = cause.from_value(cause)",
    ],
    fn(text) {
      assert string.contains(message, text)
        as { "the message converts at the edge: `" <> text <> "`" }
    },
  )
  assert !string.contains(message, "Other")
    as "the message module holds no case of the values, so another field's cannot collide with it"
}

pub fn two_valued_fields_of_one_message_have_one_module_each_and_no_shared_case_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },
  { name = \"mood\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Mood\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },",
    ))
  assert string.contains(generated_file(files, "cause"), "Other(Int)")
    as "the first type has its own fallback"
  assert string.contains(generated_file(files, "mood"), "Other(Int)")
    as "the second type has its own fallback, and a case of one name in both is no collision"
  let message = generated_file(files, "planted")
  assert string.contains(message, "Planted(cause: Cause, mood: Mood)")
    as "the message holds both"
}

pub fn two_fields_of_one_values_type_and_list_share_one_module_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },
  { name = \"earlier_cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },",
    ))
  assert list.count(files, fn(file) {
      string.ends_with(file.path, "/cause.gleam")
    })
    == 1
    as "one module for the one type"
}

pub fn a_values_type_used_with_two_different_lists_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },
  { name = \"earlier_cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 7, name = \"gone\", evidence = \"x\" } ] },",
    ))
    == Error(ConflictingValues("Cause"))
    as "one type is one module, so its values are one list"
}

pub fn a_value_named_other_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"Cause\", values = [ { value = 6, name = \"other\", evidence = \"x\" } ] },",
    ))
    == Error(ValueNamedOther("cause"))
    as "the type's own fallback is the case Other"
}

pub fn a_values_type_that_is_not_an_upper_camel_case_name_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(schema_with(
      "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"x\", values_type = \"cause\", values = [ { value = 6, name = \"gone\", evidence = \"x\" } ] },",
    ))
    == Error(WrongTypeOfKey("cause", "values_type"))
    as "a Gleam type name starts with a capital, and its module name is made from it"
}

pub fn a_field_with_a_safe_by_says_its_value_is_safe_by_that_fact_and_one_without_does_not_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(schema_with(
      "  { name = \"field_1\", kind = \"unsigned\", bits = 8, evidence = \"x\", safe_by = \"opcode.0x3\" },
  { name = \"field_2\", kind = \"unsigned\", bits = 8, evidence = \"x\" },",
    ))
  let message = generated_file(files, "planted")
  assert string.contains(
    message,
    "    /// Safe by `opcode.0x3`: the client's code gives this field no use the\n    /// server needs, and that fact shows its value is safe.\n    field_1: Int,\n    field_2: Int,",
  )
    as "the doc of the field with a safe_by names the fact, and the field with none has no doc"
}

pub fn an_open_field_has_a_doc_with_its_question_and_a_safe_by_keeps_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(schema_with(
      "  { name = \"field_1\", kind = \"unsigned\", bits = 8, evidence = \"x\", open = \"what is it\" },
  { name = \"field_2\", kind = \"unsigned\", bits = 8, evidence = \"x\", open = \"what is this\", safe_by = \"opcode.0x3\" },
  { name = \"field_3\", kind = \"unsigned\", bits = 8, evidence = \"x\" },",
    ))
  assert string.contains(
    generated_file(files, "planted"),
    "    /// Open: what is it\n    field_1: Int,\n    /// Open: what is this\n    /// Safe by `opcode.0x3`: the client's code gives this field no use the\n    /// server needs, and that fact shows its value is safe.\n    field_2: Int,\n    field_3: Int,",
  )
    as "the open field has its question as a doc, the open field with a safe_by has both docs, and the plain field has none"
  let plain =
    generated(schema_with(
      "  { name = \"number\", kind = \"unsigned\", bits = 8, evidence = \"x\" },",
    ))
  assert string.contains(
    generated_file(plain, "planted"),
    "pub type Planted {\n  Planted(number: Int)\n}",
  )
    as "a message with no open and no safe_by field keeps the one-line constructor"
}

pub fn a_union_with_never_and_open_tags_documents_them_and_still_refuses_their_kinds_test() -> Nil {
  use <- owned_test.run(5000)
  let keys =
    "never_tags = [ { tag = 0, name = \"damage\", named_by = \"opcode.0x3\" }, { tag = 3, name = \"heal\", named_by = \"opcode.0x4\" } ]
open_tags = [ { tag = 1, question = \"what is it\" } ]"
  let union =
    generated_file(
      generated(union_with(keys:, variants: flag_and_pair)),
      "planted_union",
    )
  list.each(
    [
      "/// The client reads these kinds and the server never sends them, so no variant\n/// holds them and a read refuses them: 0 damage (the fact file's `opcode.0x3`),\n/// 3 heal (the fact file's `opcode.0x4`).",
      "/// These kinds are open, so no variant holds them and a read refuses them: 1\n/// (what is it).",
      "    _ -> Error(bit_stream.UnexpectedValue(field: \"planted_union\", value: kind))",
    ],
    fn(text) {
      assert string.contains(union, text)
        as { "the union module holds `" <> text <> "`" }
    },
  )
  list.each(["    0 ->", "    1 ->", "    3 ->"], fn(arm) {
    assert !string.contains(union, arm)
      as { "the read has no arm `" <> arm <> "` for a never or open kind" }
  })
}

// ---- unions, and lists of records counted by an earlier list ----

/// A schema with two records that start with their own 3-bit kind, a union of
/// them whose variants are `variants`, and a message with `fields`.
fn union_schema(variants variants: String, fields fields: String) -> String {
  "[[message]]\nid = 0x0001\nname = \"planted\"\ndirection = \"client_to_server\"\nevidence = \"opcode.0x1\"\nsummary = \"a planted message\"\nfields = [\n"
  <> fields
  <> "\n]\n\n[[record]]\nname = \"planted_flag\"\nevidence = \"x\"\nsummary = \"a planted flag\"\nfields = [\n  { name = \"kind\", kind = \"constant\", bits = 3, value = 2, evidence = \"x\" },\n  { name = \"on\", kind = \"unsigned\", bits = 1, evidence = \"x\" },\n]\n"
  <> "\n[[record]]\nname = \"planted_pair\"\nevidence = \"x\"\nsummary = \"a planted pair\"\nfields = [\n  { name = \"kind\", kind = \"constant\", bits = 3, value = 5, evidence = \"x\" },\n  { name = \"first\", kind = \"unsigned\", bits = 8, evidence = \"x\" },\n]\n"
  <> "\n[[union]]\nname = \"planted_union\"\nevidence = \"x\"\nsummary = \"a planted union\"\ntag_bits = 3\nvariants = [\n"
  <> variants
  <> "\n]\n"
}

const flag_and_pair =
  "  { tag = 2, name = \"flag\", record = \"planted_flag\", named_by = \"x\" },
  { tag = 5, name = \"pair\", record = \"planted_pair\" },"

const shapes_field =
  "  { name = \"shapes\", kind = \"array\", count_bits = 4, element = \"planted_union\", evidence = \"x\" },"

pub fn a_union_lists_its_variants_by_kind_and_a_list_of_it_is_a_list_of_records_test() -> Nil {
  use <- owned_test.run(5000)
  let text = union_schema(variants: flag_and_pair, fields: shapes_field)
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema parses"
  assert schema.unions
    == [
      Union(
        name: "planted_union",
        evidence: "x",
        summary: "a planted union",
        tag_bits: 3,
        variants: [
          Variant(
            tag: 2,
            name: "flag",
            record: "planted_flag",
            named_by: Some("x"),
            open: None,
          ),
          Variant(
            tag: 5,
            name: "pair",
            record: "planted_pair",
            named_by: None,
            open: None,
          ),
        ],
        refused_from: 8,
        never_tags: [],
        open_tags: [],
      ),
    ]
    as "the union holds its variants in the order the schema lists them"
  assert field_kinds(text)
    == [ArrayOfRecord(count_bits: 4, record: "planted_union")]
    as "a union is read and written as a record is, so an array of it is an array of records"
}

pub fn a_variant_of_a_kind_that_does_not_fit_the_tag_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(union_schema(
      variants: "  { tag = 8, name = \"flag\", record = \"planted_flag\" },",
      fields: shapes_field,
    ))
    == Error(WrongTypeOfKey("flag", "tag"))
    as "a 3-bit tag holds 0 to 7"
}

pub fn a_kind_given_to_two_variants_or_a_name_given_twice_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(union_schema(
      variants: "  { tag = 2, name = \"flag\", record = \"planted_flag\" },
  { tag = 2, name = \"pair\", record = \"planted_pair\" },",
      fields: shapes_field,
    ))
    == Error(DuplicateTag(union: "planted_union", tag: 2))
    as "a kind picks one layout"
  assert message_schema.parse(union_schema(
      variants: "  { tag = 2, name = \"flag\", record = \"planted_flag\" },
  { tag = 5, name = \"flag\", record = \"planted_pair\" },",
      fields: shapes_field,
    ))
    == Error(DuplicateVariantName(union: "planted_union", name: "flag"))
    as "a variant's name is its constructor, so two cannot share one"
}

pub fn a_variant_of_a_record_the_schema_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(union_schema(
      variants: "  { tag = 2, name = \"flag\", record = \"missing\" },",
      fields: shapes_field,
    ))
    == Error(UnknownVariantRecord(
      union: "planted_union",
      variant: "flag",
      record: "missing",
    ))
    as "a variant is read by a record of the schema"
}

pub fn a_variant_whose_record_does_not_start_with_its_own_kind_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(union_schema(
      variants: "  { tag = 3, name = \"flag\", record = \"planted_flag\" },",
      fields: shapes_field,
    ))
    == Error(VariantKindDisagrees(union: "planted_union", variant: "flag"))
    as "the record reads the kind again as its first field and fixes it to 2, so a variant of kind 3 could never be read"
  let without_constant =
    string.replace(
      union_schema(variants: flag_and_pair, fields: shapes_field),
      "{ name = \"kind\", kind = \"constant\", bits = 3, value = 2, evidence = \"x\" },",
      "{ name = \"kind\", kind = \"unsigned\", bits = 3, evidence = \"x\" },",
    )
  assert message_schema.parse(without_constant)
    == Error(VariantKindDisagrees(union: "planted_union", variant: "flag"))
    as "a record that does not fix its kind is no layout of one kind"
  let wider =
    string.replace(
      union_schema(variants: flag_and_pair, fields: shapes_field),
      "{ name = \"kind\", kind = \"constant\", bits = 3, value = 2, evidence = \"x\" },",
      "{ name = \"kind\", kind = \"constant\", bits = 4, value = 2, evidence = \"x\" },",
    )
  assert message_schema.parse(wider)
    == Error(VariantKindDisagrees(union: "planted_union", variant: "flag"))
    as "the kind is the union's 3 bits"
}

pub fn a_union_is_a_module_that_peeks_its_kind_and_refuses_one_no_variant_has_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(union_schema(variants: flag_and_pair, fields: shapes_field))
  let union = generated_file(files, "planted_union")
  list.each(
    [
      "pub type PlantedUnion {",
      "  Flag(PlantedFlag)",
      "  Pair(PlantedPair)",
      "    Flag(variant) -> planted_flag.write(writer, variant)",
      "    Pair(variant) -> planted_pair.write(writer, variant)",
      "  use kind <- result.try(bit_stream.peek_unsigned(reader, 3))",
      "    2 -> reader |> planted_flag.read |> result.map(pair.map_first(_, Flag))",
      "    5 -> reader |> planted_pair.read |> result.map(pair.map_first(_, Pair))",
      "    _ -> Error(bit_stream.UnexpectedValue(field: \"planted_union\", value: kind))",
    ],
    fn(text) {
      assert string.contains(union, text)
        as { "the union module holds `" <> text <> "`" }
    },
  )
  let message = generated_file(files, "planted")
  list.each(
    [
      "import genesis_prime/message/planted_union.{type PlantedUnion}",
      "Planted(shapes: List(PlantedUnion))",
      "bit_stream.write_array(\"shapes\", message.shapes, 4, planted_union.write)",
      "bit_stream.read_array(\n    reader,\n    4,\n    planted_union.read,\n  )",
    ],
    fn(text) {
      assert string.contains(message, text)
        as { "the message holds the array of the union: `" <> text <> "`" }
    },
  )
}

// ---- the open marker, never tags and the bound the client refuses from ----

/// The planted union schema of `union_schema` with `keys` lines under the
/// union's `tag_bits`.
fn union_with(keys keys: String, variants variants: String) -> String {
  string.replace(
    union_schema(variants:, fields: shapes_field),
    "tag_bits = 3\nvariants",
    "tag_bits = 3\n" <> keys <> "\nvariants",
  )
}

/// Why the schema is refused.
fn refused(text: String) -> message_schema.SchemaError {
  let assert Error(error) = message_schema.parse(text)
    as "the planted schema is refused"
  error
}

/// The one field of the planted message of `schema_with`, as the reader holds
/// it.
fn only_field(
  line: String,
) -> Result(message_schema.Field, message_schema.SchemaError) {
  use schema <- result.try(message_schema.parse(schema_with(line)))
  let assert [message] = schema.messages as "one message"
  let assert [field] = message.fields as "one field"
  Ok(field)
}

pub fn a_field_is_traced_or_open_and_never_both_test() -> Nil {
  use <- owned_test.run(5000)
  let unsigned = fn(keys) {
    "  { name = \"field_1\", kind = \"unsigned\", bits = 8, evidence = \"x\""
    <> keys
    <> " },"
  }
  let held = fn(keys) {
    let assert Ok(field) = only_field(unsigned(keys))
    #(field.open, field.named_by, field.safe_by)
  }
  assert held(", open = \"what is it\"") == #(Some("what is it"), None, None)
    as "an open field has its question and no name key"
  assert held(", open = \"what is it\", safe_by = \"opcode.0x3\"")
    == #(Some("what is it"), None, Some("opcode.0x3"))
    as "an open field may keep its safe_by"
  list.each(
    [
      #(
        "open with named_by",
        ", open = \"what is it\", named_by = \"opcode.0x3\"",
        OpenAndNamed(field: "field_1"),
      ),
      #("a blank open", ", open = \"\"", MissingKey("field_1", "open")),
      #("a white space open", ", open = \"  \"", MissingKey("field_1", "open")),
      #(
        "an open that is a number",
        ", open = 3",
        WrongTypeOfKey("field_1", "open"),
      ),
    ],
    fn(row) {
      assert only_field(unsigned(row.1)) == Error(row.2)
        as {
          row.0
          <> ": one field is traced or open, and a blank or wrong open is never read as absent"
        }
    },
  )
}

pub fn a_union_lists_its_never_and_open_tags_and_the_bound_the_client_refuses_from_test() -> Nil {
  use <- owned_test.run(5000)
  let keys =
    "refused_from = 6
never_tags = [ { tag = 0, name = \"damage\", named_by = \"opcode.0x3\" } ]
open_tags = [ { tag = 1, question = \"what is it\", named_by = \"opcode.0x4\" }, { tag = 3, question = \"and this\" } ]"
  let assert Ok(schema) =
    message_schema.parse(union_with(keys:, variants: flag_and_pair))
    as "the planted schema parses"
  let assert [union] = schema.unions as "one union"
  assert union.refused_from == 6
  assert union.never_tags
    == [NeverTag(tag: 0, name: "damage", named_by: "opcode.0x3")]
  assert union.open_tags
    == [
      OpenTag(tag: 1, question: "what is it", named_by: Some("opcode.0x4")),
      OpenTag(tag: 3, question: "and this", named_by: None),
    ]
  let assert Ok(plain) =
    message_schema.parse(union_with(keys: "", variants: flag_and_pair))
    as "a union with no marks parses"
  let assert [plain_union] = plain.unions as "one union"
  assert #(
      plain_union.refused_from,
      plain_union.never_tags,
      plain_union.open_tags,
    )
    == #(8, [], [])
    as "no marks means no never tags, no open tags and the width's own limit of 2^3"
}

pub fn a_union_tag_listed_twice_or_beyond_the_bound_or_without_its_key_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let never = fn(tag) {
    "{ tag = "
    <> int.to_string(tag)
    <> ", name = \"damage\", named_by = \"opcode.0x3\" }"
  }
  let open = fn(tag) {
    "{ tag = " <> int.to_string(tag) <> ", question = \"what is it\" }"
  }
  let rows = [
    #(
      "a tag both a variant and a never tag",
      "never_tags = [ " <> never(2) <> " ]",
      DuplicateTag(union: "planted_union", tag: 2),
    ),
    #(
      "a tag both a never tag and an open tag",
      "never_tags = [ " <> never(0) <> " ]\nopen_tags = [ " <> open(0) <> " ]",
      DuplicateTag(union: "planted_union", tag: 0),
    ),
    #(
      "a tag twice among the never tags",
      "never_tags = [ " <> never(0) <> ", " <> never(0) <> " ]",
      DuplicateTag(union: "planted_union", tag: 0),
    ),
    #(
      "a never tag at the bound",
      "refused_from = 6\nnever_tags = [ " <> never(6) <> " ]",
      TagBeyondRefused(union: "planted_union", tag: 6),
    ),
    #(
      "an open tag above the bound",
      "refused_from = 6\nopen_tags = [ " <> open(7) <> " ]",
      TagBeyondRefused(union: "planted_union", tag: 7),
    ),
    #(
      "a variant at the bound",
      "refused_from = 5",
      TagBeyondRefused(union: "planted_union", tag: 5),
    ),
    #(
      "a bound of 0",
      "refused_from = 0",
      WrongTypeOfKey("planted_union", "refused_from"),
    ),
    #(
      "a bound above 2^3",
      "refused_from = 9",
      WrongTypeOfKey("planted_union", "refused_from"),
    ),
    #(
      "a never tag with no named_by",
      "never_tags = [ { tag = 0, name = \"damage\" } ]",
      MissingKey("damage", "named_by"),
    ),
    #(
      "an open tag with no question",
      "open_tags = [ { tag = 1 } ]",
      MissingKey("open tag 1", "question"),
    ),
    #(
      "an open tag with a blank question",
      "open_tags = [ { tag = 1, question = \" \" } ]",
      MissingKey("open tag 1", "question"),
    ),
    #(
      "an open tag whose named_by is a number",
      "open_tags = [ { tag = 1, question = \"what is it\", named_by = 3 } ]",
      WrongTypeOfKey("open tag 1", "named_by"),
    ),
  ]
  list.each(rows, fn(row) {
    assert refused(union_with(keys: row.1, variants: flag_and_pair)) == row.2
      as row.0
  })
}

pub fn the_real_schema_marks_the_combat_log_types_the_client_logs_itself_as_never_sent_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(text) = simplifile.read(schema_path)
    as "the schema file is read from the project folder"
  let assert Ok(schema) = message_schema.parse(text) as "the real schema parses"
  let assert Ok(union) =
    list.find(schema.unions, fn(union) { union.name == "combat_log_entry" })
    as "the schema holds the combat log union"
  // The client builds the log lines of these types itself from a spell
  // result (LogEffectResult 0x140563dc0), so a server copy would double the
  // line.
  assert list.map(union.never_tags, fn(never) { #(never.tag, never.name) })
    == [
      #(3, "damage"),
      #(4, "damage_shields"),
      #(6, "multi_hit"),
      #(7, "multi_hit_shields"),
      #(12, "heal"),
      #(13, "multi_heal"),
      #(17, "deflect"),
    ]
  list.each(union.never_tags, fn(never) {
    assert never.named_by == "opcode.0x247." <> never.name
    assert !list.any(union.variants, fn(variant) { variant.tag == never.tag })
      as { never.name <> " is no variant" }
  })
}

pub fn the_real_unions_state_where_the_client_refuses_their_tags_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(text) = simplifile.read(schema_path)
    as "the schema file is read from the project folder"
  let assert Ok(schema) = message_schema.parse(text) as "the real schema parses"
  // Each union's own `evidence` fact gives its bound: opcode.0x247 (type above
  // 35 fails the read), 0x140c1f070 and opcode.0x637 (kinds 0 to 29),
  // 0x140085ca0 (chat type above 11 fails), 0x140094890 (tags 2 and 3 fail),
  // 0x140096230 (form 3 refuses), opcode.0x938 (all 32 stats are read).
  assert list.map(schema.unions, fn(union) { #(union.name, union.refused_from) })
    == [
      #("unit_stat_value", 3),
      #("movement_command", 30),
      #("relayed_movement", 30),
      #("start_movement", 30),
      #("chat_format", 12),
      #("spell_effect_result", 2),
      #("unit_stat_change", 32),
      #("combat_log_entry", 36),
    ]
}

const counted_records =
  "  { name = \"ids\", kind = \"array\", count_bits = 4, element = \"unsigned\", element_bits = 32, evidence = \"x\" },
  { name = \"pairs\", kind = \"array\", counted_by = \"ids\", element = \"planted_pair\", evidence = \"x\" },"

pub fn the_reader_knows_records_counted_by_an_earlier_array_test() -> Nil {
  use <- owned_test.run(5000)
  assert field_kinds(union_schema(
      variants: flag_and_pair,
      fields: counted_records,
    ))
    == [
      ArrayOfUnsigned(count_bits: 4, bits: 32),
      ArrayOfRecordCountedBy(counted_by: "ids", record: "planted_pair"),
    ]
}

pub fn records_counted_by_a_field_that_is_not_an_earlier_array_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(union_schema(
      variants: flag_and_pair,
      fields: "  { name = \"pairs\", kind = \"array\", counted_by = \"ids\", element = \"planted_pair\", evidence = \"x\" },
  { name = \"ids\", kind = \"array\", count_bits = 4, element = \"unsigned\", element_bits = 32, evidence = \"x\" },",
    ))
    == Error(UnknownCountField(field: "pairs", counted_by: "ids"))
    as "a decoder reads the fields in order, so the count must be read before the records it counts"
  assert message_schema.parse(union_schema(
      variants: flag_and_pair,
      fields: "  { name = \"ids\", kind = \"array\", count_bits = 4, element = \"unsigned\", element_bits = 32, evidence = \"x\" },
  { name = \"pairs\", kind = \"array\", counted_by = \"ids\", element = \"missing\", evidence = \"x\" },",
    ))
    == Error(UnknownRecord(field: "pairs", record: "missing"))
    as "the records are one of the schema's"
}

pub fn records_counted_by_an_array_are_written_and_read_with_no_count_of_their_own_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(union_schema(variants: flag_and_pair, fields: counted_records))
  let message = generated_file(files, "planted")
  list.each(
    [
      "import genesis_prime/message/planted_pair.{type PlantedPair}",
      "Planted(ids: List(Int), pairs: List(PlantedPair))",
      "bit_stream.write_array_like(\n    \"pairs\",\n    message.pairs,\n    message.ids,\n    planted_pair.write,\n  )",
      "bit_stream.read_array_like(\n    reader,\n    ids,\n    planted_pair.read,\n  )",
    ],
    fn(text) {
      assert string.contains(message, text)
        as { "the message holds `" <> text <> "`" }
    },
  )
}

const one_record_and_a_half_float =
  "  { name = \"shape\", kind = \"record\", record = \"planted_union\", evidence = \"x\" },
  { name = \"speed\", kind = \"half_float_at_least\", minimum = \"0.00001\", evidence = \"x\" },"

pub fn the_reader_knows_one_record_in_place_and_a_half_float_with_a_minimum_test() -> Nil {
  use <- owned_test.run(5000)
  assert field_kinds(union_schema(
      variants: flag_and_pair,
      fields: one_record_and_a_half_float,
    ))
    == [OneRecord(record: "planted_union"), HalfFloatAtLeast(minimum: 0.00001)]
}

pub fn a_record_field_names_a_record_or_union_the_schema_holds_and_a_minimum_is_a_float_test() -> Nil {
  use <- owned_test.run(5000)
  assert message_schema.parse(union_schema(
      variants: flag_and_pair,
      fields: "  { name = \"shape\", kind = \"record\", record = \"missing\", evidence = \"x\" },",
    ))
    == Error(UnknownRecord(field: "shape", record: "missing"))
    as "the record is one of the schema's"
  assert message_schema.parse(union_schema(
      variants: flag_and_pair,
      fields: "  { name = \"speed\", kind = \"half_float_at_least\", minimum = \"fast\", evidence = \"x\" },",
    ))
    == Error(WrongTypeOfKey("speed", "minimum"))
    as "the minimum is a number written as text"
  assert message_schema.parse(union_schema(
      variants: flag_and_pair,
      fields: "  { name = \"speed\", kind = \"half_float_at_least\", minimum = 0.00001, evidence = \"x\" },",
    ))
    == Error(WrongTypeOfKey("speed", "minimum"))
    as "a TOML float is refused, since the TOML reader's float of 0.00001 is 1.0000000000000004e-5"
  assert message_schema.parse(union_schema(
      variants: flag_and_pair,
      fields: "  { name = \"speed\", kind = \"half_float_at_least\", evidence = \"x\" },",
    ))
    == Error(message_schema.MissingKey("speed", "minimum"))
    as "a half float with a minimum names it"
}

pub fn a_record_in_place_is_written_and_read_by_its_module_and_a_half_float_refuses_below_its_minimum_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(union_schema(
      variants: flag_and_pair,
      fields: one_record_and_a_half_float,
    ))
  let message = generated_file(files, "planted")
  list.each(
    [
      "import genesis_prime/message/planted_union.{type PlantedUnion}",
      "Planted(shape: PlantedUnion, speed: Int)",
      "|> planted_union.write(message.shape)",
      "bit_stream.write_half_float_at_least(\"speed\", message.speed, 1.0e-5)",
      "use #(shape, reader) <- result.try(planted_union.read(reader))",
      "bit_stream.read_half_float_at_least(\n    reader,\n    \"speed\",\n    1.0e-5,\n  )",
    ],
    fn(text) {
      assert string.contains(message, text)
        as { "the message holds `" <> text <> "`" }
    },
  )
}

pub fn a_module_that_sorts_before_the_bit_stream_is_imported_before_it_test() -> Nil {
  use <- owned_test.run(5000)
  let files =
    generated(string.replace(
      schema_with(
        "  { name = \"records\", kind = \"array\", count_bits = 4, element = \"planted_record\", evidence = \"x\" },",
      ),
      "planted_record",
      "aaa_record",
    ))
  let message = generated_file(files, "planted")
  let assert Ok(#(before_bit_stream, _)) =
    string.split_once(
      message,
      "import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}",
    )
    as "the message imports the bit stream"
  assert string.contains(
    before_bit_stream,
    "import genesis_prime/message/aaa_record.{type AaaRecord}",
  )
    as "`gleam format` keeps imports in the order of their modules' names, so the codec writes them in that order and the full check's comparison of the generated files holds"
}

// ---- the modules that read a message by its number ----

/// A planted schema of two messages that share the number 0x0010 and travel
/// server to client, in the order given: each starts with the field `kind`, as
/// `first_kind` and `second_kind` say, then holds a byte.
fn two_messages_sharing_a_number(
  first_kind first_kind: String,
  second_kind second_kind: String,
) -> String {
  let message = fn(name: String, kind: String) {
    "[[message]]\nid = 0x0010\nname = \""
    <> name
    <> "\"\ndirection = \"server_to_client\"\nevidence = \"x\"\nsummary = \"a planted message\"\nfields = [\n  "
    <> kind
    <> ",\n  { name = \"byte\", kind = \"unsigned\", bits = 8, evidence = \"x\" },\n]\n\n"
  }
  message("first_message", first_kind)
  <> message("second_message", second_kind)
  <> "[[record]]\nname = \"planted_record\"\nevidence = \"x\"\nsummary = \"a planted record\"\nfields = [\n  { name = \"id\", kind = \"unsigned\", bits = 8, evidence = \"x\" },\n]\n"
}

const open_kind =
  "{ name = \"kind\", kind = \"unsigned\", bits = 6, evidence = \"x\" }"

const kind_3 =
  "{ name = \"kind\", kind = \"constant\", bits = 6, value = 3, evidence = \"x\" }"

const kind_4 =
  "{ name = \"kind\", kind = \"constant\", bits = 6, value = 4, evidence = \"x\" }"

/// The names of the messages the server's reader tries for the number 0x0010,
/// in the order it tries them.
fn tried_in_order(schema: String) -> List(String) {
  let reader = generated_file(generated(schema), "server_message")
  ["first_message", "second_message"]
  |> list.map(fn(name) {
    let assert Ok(#(before, _)) = string.split_once(reader, name <> ".decode,")
      as { "the server's reader tries " <> name }
    #(string.length(before), name)
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(tried) { tried.1 })
}

pub fn a_message_with_a_fixed_field_is_tried_before_one_with_none_test() -> Nil {
  use <- owned_test.run(5000)
  assert tried_in_order(two_messages_sharing_a_number(
      first_kind: open_kind,
      second_kind: kind_3,
    ))
    == ["second_message", "first_message"]
    as "a message with no fixed field reads any body its layout fits, so it is tried last: the messages that check a fixed field decide which bodies are theirs"
}

pub fn messages_that_fix_their_kind_or_that_leave_it_open_are_tried_in_the_schemas_order_test() -> Nil {
  use <- owned_test.run(5000)
  assert tried_in_order(two_messages_sharing_a_number(
      first_kind: kind_3,
      second_kind: kind_4,
    ))
    == ["first_message", "second_message"]
    as "two that fix their kind keep the schema's order"
  assert tried_in_order(two_messages_sharing_a_number(
      first_kind: open_kind,
      second_kind: open_kind,
    ))
    == ["first_message", "second_message"]
    as "two that leave it open keep the schema's order"
}

/// The planted message of `schema_with`, named `name`, sent both ways so both
/// modules that read by number import it.
fn named_both_ways(name: String) -> List(message_generator.GeneratedFile) {
  generated(
    string.replace(
      schema_with(
        "  { name = \"number\", kind = \"unsigned\", bits = 8, evidence = \"x\" },",
      ),
      "client_to_server",
      "both",
    )
    |> string.replace("name = \"planted\"", "name = \"" <> name <> "\""),
  )
}

pub fn an_import_of_exactly_81_characters_is_one_line_and_one_of_82_is_split_test() -> Nil {
  use <- owned_test.run(5000)
  // `gleam format` keeps an import whole when it fits in 80 characters without
  // its closing brace, so a line of 81 with the brace stays on one line.
  let whole =
    "import genesis_prime/message/aaaaaaaa_bbbbbbbb_ccccc.{type AaaaaaaaBbbbbbbbCcccc}"
  assert string.length(whole) == 81
    as "the planted name makes the import 81 characters"
  let reader =
    generated_file(named_both_ways("aaaaaaaa_bbbbbbbb_ccccc"), "server_message")
  assert string.contains(reader, whole <> "\n")
    as "the import is one line, as `gleam format` lays it out"
  let split =
    "import genesis_prime/message/aaaaaa_bbbbbb_cccccc_ddd.{\n  type AaaaaaBbbbbbCcccccDdd,\n}"
  let longer =
    generated_file(
      named_both_ways("aaaaaa_bbbbbb_cccccc_ddd"),
      "server_message",
    )
  assert string.contains(longer, split)
    as "an import of 82 characters is split, one type to a line"
}

fn schema_with_gaps(message_gaps: String, record_gaps: String) -> String {
  "[[message]]\nid = 0x0001\nname = \"planted\"\ndirection = \"client_to_server\"\nevidence = \"opcode.0x1\"\nsummary = \"a planted message\"\n"
  <> message_gaps
  <> "fields = [\n  { name = \"id\", kind = \"unsigned\", bits = 8, evidence = \"x\" },\n]\n\n[[record]]\nname = \"planted_record\"\nevidence = \"x\"\nsummary = \"a planted record\"\n"
  <> record_gaps
  <> "fields = [\n  { name = \"id\", kind = \"unsigned\", bits = 8, evidence = \"x\" },\n]\n"
}

pub fn a_schema_message_with_gaps_generates_a_gaps_function_with_exactly_those_entries_test() -> Nil {
  use <- owned_test.run(5000)
  let long_sentence =
    "the client's code does not show what the third word of the body does, so the server writes 0 and the codec checks nothing"
  let text =
    schema_with_gaps(
      "gaps = [\n  { area = \"Planted area\", missing = \"first sentence\" },\n  { area = \"Planted area\", missing = \"a \\\"quoted\\\" second sentence\" },\n  { area = \"Other area\", missing = \""
        <> long_sentence
        <> "\" },\n]\n",
      "gaps = [\n  { area = \"Record area\", missing = \"the record's sentence\" },\n]\n",
    )
  let assert Ok(schema) = message_schema.parse(text)
    as "the planted schema parses"
  let assert [message] = schema.messages
  let assert [record] = schema.records
  assert message.gaps
    == [
      message_schema.Gap(area: "Planted area", missing: "first sentence"),
      message_schema.Gap(
        area: "Planted area",
        missing: "a \"quoted\" second sentence",
      ),
      message_schema.Gap(area: "Other area", missing: long_sentence),
    ]
    as "the reader keeps each message gap in the order written"
  assert record.gaps
    == [
      message_schema.Gap(area: "Record area", missing: "the record's sentence"),
    ]
    as "a record's gaps are read the same way"
  let files = generated(text)
  assert string.contains(
    generated_file(files, "planted"),
    "\nimport genesis_prime/gap\nimport genesis_prime/message/bit_stream.{",
  )
    as "the module imports the gap type before the message modules"
  assert string.ends_with(
    generated_file(files, "planted"),
    "}\n\n/// What this message's codec leaves unhandled, which the coverage measure prints.\npub fn gaps() -> List(gap.Entry) {\n  [\n    gap.Entry(area: \"Planted area\", missing: \"first sentence\"),\n    gap.Entry(area: \"Planted area\", missing: \"a \\\"quoted\\\" second sentence\"),\n    gap.Entry(\n      area: \"Other area\",\n      missing: \""
      <> long_sentence
      <> "\",\n    ),\n  ]\n}\n",
  )
    as "the message's gaps function lists exactly the three entries, a quote escaped, each on one line when it fits in 80 columns and else with one argument to a line"
  assert string.ends_with(
    generated_file(files, "planted_record"),
    "\n/// What this record's codec leaves unhandled, which the coverage measure prints.\npub fn gaps() -> List(gap.Entry) {\n  [\n    gap.Entry(area: \"Record area\", missing: \"the record's sentence\"),\n  ]\n}\n",
  )
    as "a record's gaps function is the same, said of the record"
  let without = generated(schema_with_gaps("", ""))
  list.each(["planted", "planted_record"], fn(name) {
    let module = generated_file(without, name)
    assert !string.contains(module, "gaps")
      && !string.contains(module, "genesis_prime/gap")
      as {
        "a module with no gaps generates no gaps function or import: " <> name
      }
  })
}

/// The kind of one field of one message or record of the schema.
fn field_kind(
  schema schema: message_schema.Schema,
  message owner: String,
  field field_name: String,
) -> Result(message_schema.Kind, Nil) {
  use fields <- result.try(message_schema.fields_of(schema:, owner:))
  use field <- result.map(
    list.find(fields, fn(field) { field.name == field_name }),
  )
  field.kind
}

pub fn a_value_the_client_sends_and_the_server_writes_back_has_one_width_both_ways_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(text) = simplifile.read(schema_path)
    as "the schema file could not be read"
  let assert Ok(schema) = message_schema.parse(text)
    as "the schema file is a schema"
  // A value the client sent is written back at the width it was read with, so
  // the server's `bit_stream.must` of it cannot fail on length: the server
  // writes back the value it decoded, at the same field.
  let pairs = [
    #("send_chat_line", "text", "chat_line", "text"),
    #("send_chat_line", "formats", "chat_line", "formats"),
    #("send_whisper", "text", "chat_line", "text"),
    #("send_whisper", "formats", "chat_line", "formats"),
    #("send_whisper", "target_name", "whisper_failed", "target_name"),
    #("rename_character", "name", "rename_character_result", "name"),
    #("action_set_save", "amp_ids", "action_set_amps", "amp_ids"),
  ]
  list.each(pairs, fn(pair) {
    let #(sent, sent_field, written, written_field) = pair
    let assert Ok(sent_kind) =
      field_kind(schema:, message: sent, field: sent_field)
      as { sent <> "." <> sent_field <> " is a field of the schema" }
    assert field_kind(schema:, message: written, field: written_field)
      == Ok(sent_kind)
      as {
        written
        <> "."
        <> written_field
        <> " has the width of "
        <> sent
        <> "."
        <> sent_field
      }
  })
}
