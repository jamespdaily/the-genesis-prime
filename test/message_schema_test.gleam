//// The schema reader and the generator on the field kinds the messages of
//// character select need: arrays of unsigned values and floats, a list counted
//// by an earlier list, and a value the schema fixes. Each case is a planted
//// schema; the real schema's own check is `message_codec_test` and the full
//// check's generator comparison.

import genesis_prime/message_generator
import genesis_prime/message_schema.{
  ArrayOfFloat32, ArrayOfRecord, ArrayOfRecordCountedBy, ArrayOfUnsigned, Both,
  ConflictingValues, Constant, DuplicateTag, DuplicateValue, DuplicateValueName,
  DuplicateVariantName, HalfFloatAtLeast, NamedValues, OneRecord, Union,
  UnknownCountField, UnknownRecord, UnknownVariantRecord, UnsignedArrayCountedBy,
  UnsignedBelow, ValueNamedOther, ValuesOnOtherKind, Variant,
  VariantKindDisagrees, WrongTypeOfKey,
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
          ),
          Variant(tag: 5, name: "pair", record: "planted_pair", named_by: None),
        ],
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
