//// The schema-evidence rule: every field of the message schema names its
//// evidence, a key of the client's fact file (CLAUDE.md: every packet layout
//// lives in one schema with its evidence), and every field of a message the
//// server sends is traced or open and every union kind of one is a traced
//// variant, a never tag or an open tag, unless the allow-list lists it. Every
//// case is planted in a made-up schema, as a row of a table that one check
//// runs; the last tests read the real schema and the real fact file.

import code_rule/repository
import code_rule/schema_evidence
import code_rule/source.{SourceFile}
import code_rule/untraced_gaps.{type Gap, UnclassifiedTags, UntracedFields}
import genesis_prime/message_schema
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import simplifile
import unitest

const fact_keys = ["opcode.0x1", "0x1400a9140", "0x1400ac130", "opcode.0x2"]

// ---- planted schemas ----

/// A planted field of 32 bits, with the keys `extra` adds.
fn unsigned(name: String, extra: String) -> String {
  "  { name = \""
  <> name
  <> "\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\""
  <> extra
  <> " },"
}

const traced = ", named_by = \"opcode.0x2\""

const good_field =
  "  { name = \"build\", kind = \"unsigned\", bits = 32, evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"

const entries_field =
  "  { name = \"entries\", kind = \"array\", count_bits = 4, element = \"planted_entry\", evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"

const shapes_field =
  "  { name = \"shapes\", kind = \"array\", count_bits = 4, element = \"planted_union\", evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"

/// A planted constant of 3 bits.
fn constant_field(
  name name: String,
  value value: Int,
  extra extra: String,
) -> String {
  "  { name = \""
  <> name
  <> "\", kind = \"constant\", bits = 3, value = "
  <> int.to_string(value)
  <> ", evidence = \"0x1400a9140\""
  <> extra
  <> " },"
}

fn record_block(
  name name: String,
  fields fields: List(String),
) -> List(String) {
  list.flatten([
    [
      "[[record]]",
      "name = \"" <> name <> "\"",
      "evidence = \"0x1400ac130\"",
      "summary = \"a planted record\"",
      "fields = [",
    ],
    fields,
    ["]", ""],
  ])
}

/// A message whose fields are `fields`, then each of `records` as a record,
/// then each of `unions` as a union text; a planted union's variants need the
/// records `planted_flag` (kind 2) and `planted_pair` (kind 5), which come with
/// the unions.
fn planted_with(
  direction direction: String,
  fields fields: List(String),
  records records: List(#(String, List(String))),
  unions unions: List(String),
) -> String {
  let union_records = case unions {
    [] -> []
    _ -> [
      #("planted_flag", [
        constant_field(name: "kind", value: 2, extra: traced),
        unsigned("on", traced),
      ]),
      #("planted_pair", [
        constant_field(name: "kind", value: 5, extra: traced),
        unsigned("first", traced),
      ]),
    ]
  }
  string.join(
    list.flatten([
      [
        "[[message]]",
        "id = 0x0001",
        "name = \"planted_hello\"",
        "direction = \"" <> direction <> "\"",
        "evidence = \"opcode.0x1\"",
        "summary = \"a planted message\"",
        "fields = [",
      ],
      fields,
      ["]", ""],
      list.flat_map(list.append(records, union_records), fn(record) {
        record_block(name: record.0, fields: record.1)
      }),
      unions,
    ]),
    "\n",
  )
}

/// The message `planted_hello` with `fields`, and the record `planted_entry`
/// with `record_fields`, which the message holds only when `fields` hold
/// `entries_field`.
fn planted(
  direction direction: String,
  fields fields: List(String),
  record_fields record_fields: List(String),
  unions unions: List(String),
) -> String {
  planted_with(
    direction:,
    fields:,
    records: [#("planted_entry", record_fields)],
    unions:,
  )
}

/// A union of 3-bit kinds with the given keys (`refused_from`, `never_tags`,
/// `open_tags`) and variants.
fn union_block(
  keys keys: List(String),
  variants variants: List(String),
) -> String {
  string.join(
    list.flatten([
      [
        "[[union]]",
        "name = \"planted_union\"",
        "evidence = \"0x1400ac130\"",
        "summary = \"a planted union\"",
        "tag_bits = 3",
      ],
      keys,
      ["variants = [", ..variants],
      ["]", ""],
    ]),
    "\n",
  )
}

const flag_variant =
  "  { tag = 2, name = \"flag\", record = \"planted_flag\", named_by = \"opcode.0x2\" },"

/// The breaches of a planted schema with the allow-list `gaps`, each as its
/// line and rule.
fn found(text: String, gaps: List(Gap)) -> List(#(Int, String)) {
  schema_evidence.breaches(
    file: SourceFile(path: "src/planted/schema.toml", text:),
    fact_keys:,
    gaps:,
  )
  |> list.map(fn(breach) { #(breach.line, breach.rule) })
}

fn rule_lines(text: String, gaps: List(Gap)) -> List(Int) {
  found(text, gaps) |> list.map(fn(breach) { breach.0 })
}

/// The number of the first line of the text that holds `needle`.
fn line_with(text: String, needle: String) -> Int {
  let assert Ok(#(_, number)) =
    string.split(text, "\n")
    |> list.index_map(fn(line, index) { #(line, index + 1) })
    |> list.find(fn(numbered) { string.contains(numbered.0, needle) })
    as { "the planted text holds " <> needle }
  number
}

/// A table row: what the case is, the schema, the allow-list and the breaches
/// expected, each as the number of its line and a part of its rule. A case with
/// no breach expects none.
type Row =
  #(String, String, List(Gap), List(#(Int, String)))

/// Runs each row through the rule: the breaches are exactly the expected ones.
fn check_rows(rows: List(Row)) -> Nil {
  list.each(rows, fn(row) {
    let #(case_name, text, gaps, expected) = row
    let got = found(text, gaps)
    let shown =
      string.join(
        list.map(got, fn(breach) { int.to_string(breach.0) <> " " <> breach.1 }),
        "; ",
      )
    assert list.length(got) == list.length(expected)
      as { case_name <> ": the breaches are " <> shown }
    list.each(expected, fn(wanted) {
      assert list.any(got, fn(breach) {
        breach.0 == wanted.0 && string.contains(breach.1, wanted.1)
      })
        as {
          case_name
          <> ": wanted "
          <> int.to_string(wanted.0)
          <> " "
          <> wanted.1
          <> " in "
          <> shown
        }
    })
  })
}

// ---- the evidence of every field ----

pub fn a_field_that_names_no_evidence_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    planted(
      direction: "client_to_server",
      fields: [
        good_field,
        "  { name = \"other\", kind = \"unsigned\", bits = 32 },",
      ],
      record_fields: [good_field],
      unions: [],
    )
  let assert [#(line, rule)] = found(text, []) as "expected exactly one breach"
  assert line == 9 as "the field is the second line of the fields array"
  assert string.contains(rule, "planted_hello.other")
    as "the breach names the message and the field"
}

pub fn a_field_of_a_record_that_names_no_evidence_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    planted(
      direction: "client_to_server",
      fields: [good_field],
      record_fields: ["  { name = \"loose\", kind = \"wide_text\" },"],
      unions: [],
    )
  assert rule_lines(text, []) == [16]
}

pub fn a_field_whose_evidence_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    planted(
      direction: "client_to_server",
      fields: [
        "  { name = \"build\", kind = \"unsigned\", bits = 32, evidence = \"planted.not_a_fact_key\" },",
      ],
      record_fields: [good_field],
      unions: [],
    )
  assert rule_lines(text, []) == [8]
}

pub fn a_named_by_key_that_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    planted(
      direction: "client_to_server",
      fields: [unsigned("build", ", named_by = \"opcode.0x9\"")],
      record_fields: [good_field],
      unions: [],
    )
  assert rule_lines(text, []) == [8]
}

pub fn a_message_whose_evidence_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    string.replace(
      planted(
        direction: "client_to_server",
        fields: [good_field],
        record_fields: [good_field],
        unions: [],
      ),
      "evidence = \"opcode.0x1\"",
      "evidence = \"opcode.0x7\"",
    )
  assert rule_lines(text, []) == [5]
}

pub fn fields_that_name_their_evidence_are_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    planted(
      direction: "client_to_server",
      fields: [good_field, unsigned("named", traced)],
      record_fields: [good_field],
      unions: [],
    )
  assert rule_lines(text, []) == []
}

pub fn a_file_that_is_not_a_schema_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert rule_lines("[[message]]\nid = \"seven\"\n", []) == [1]
}

/// A field whose values are named, with the planted fact keys as evidence.
fn valued_field(values values: String) -> String {
  "  { name = \"cause\", kind = \"unsigned\", bits = 5, evidence = \"0x1400a9140\", named_by = \"opcode.0x2\", values_type = \"Cause\", values = [ "
  <> values
  <> " ] },"
}

fn received(fields: List(String)) -> String {
  planted(
    direction: "client_to_server",
    fields:,
    record_fields: [good_field],
    unions: [],
  )
}

pub fn a_named_value_whose_evidence_is_a_fact_key_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert rule_lines(
      received([
        valued_field(
          values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 7, name = \"idle\", evidence = \"opcode.0x1\" }",
        ),
      ]),
      [],
    )
    == []
}

pub fn a_named_value_that_names_no_evidence_is_a_breach_at_its_field_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    received([
      valued_field(
        values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 7, name = \"idle\" }",
      ),
    ])
  let assert [#(line, rule)] = found(text, []) as "expected exactly one breach"
  assert line == 8 as "the field is the first line of the fields array"
  assert string.contains(rule, "planted_hello.cause")
    as "the breach names the field"
  assert string.contains(rule, "idle")
    as "the breach names the value that has no evidence"
}

pub fn a_named_value_whose_evidence_is_not_a_fact_key_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let text =
    received([
      good_field,
      valued_field(
        values: "{ value = 6, name = \"gone\", evidence = \"opcode.0x7\" }",
      ),
    ])
  let assert [#(line, rule)] = found(text, []) as "expected exactly one breach"
  assert line == 9 as "the valued field is the second line of the fields array"
  assert string.contains(rule, "opcode.0x7")
    as "the breach names the key the fact file lacks"
}

pub fn a_value_or_a_name_that_two_values_share_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert rule_lines(
      received([
        valued_field(
          values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 6, name = \"idle\", evidence = \"0x1400ac130\" }",
        ),
      ]),
      [],
    )
    == [1]
    as "two values of 6: the schema is refused, which the rule reports as a schema that is not one"
  assert rule_lines(
      received([
        valued_field(
          values: "{ value = 6, name = \"gone\", evidence = \"0x1400ac130\" }, { value = 7, name = \"gone\", evidence = \"0x1400ac130\" }",
        ),
      ]),
      [],
    )
    == [1]
    as "two values named gone: the schema is refused too"
}

// ---- the fields of a message the server sends ----

pub fn a_field_of_a_sent_message_is_traced_or_open_or_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let untraced = "a field of a message the server sends"
  let rows: List(#(String, String, Bool)) = [
    #("a word name with named_by", unsigned("build", traced), False),
    #(
      "a constant with named_by",
      constant_field(name: "kind", value: 1, extra: traced),
      False,
    ),
    #(
      "field_of_view is no position name",
      unsigned("field_of_view", traced),
      False,
    ),
    #(
      "a position name with open",
      unsigned("field_3", ", open = \"what is it\""),
      False,
    ),
    #(
      "a word name with open",
      unsigned("build", ", open = \"what is it\""),
      False,
    ),
    #("neither named_by nor open", unsigned("build", ""), True),
    #(
      "a constant with neither",
      constant_field(name: "kind", value: 1, extra: ""),
      True,
    ),
    #("safe_by only", unsigned("field_3", ", safe_by = \"opcode.0x2\""), True),
    #("a position name with named_by", unsigned("field_3", traced), True),
  ]
  check_rows(
    list.map(rows, fn(row) {
      let text =
        planted(
          direction: "server_to_client",
          fields: [row.1],
          record_fields: [good_field],
          unions: [],
        )
      #(row.0, text, [], case row.2 {
        True -> [#(8, untraced)]
        False -> []
      })
    }),
  )
}

pub fn a_message_is_sent_by_its_direction_and_not_by_an_import_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let untraced = "a field of a message the server sends"
  check_rows(
    list.map(
      [
        #("server to client, whatever imports it", "server_to_client", True),
        #("both ways", "both", True),
        #("client to server", "client_to_server", False),
      ],
      fn(row) {
        let text =
          planted(
            direction: row.1,
            fields: [unsigned("field_3", "")],
            record_fields: [good_field],
            unions: [],
          )
        #(row.0, text, [], case row.2 {
          True -> [#(8, untraced)]
          False -> []
        })
      },
    ),
  )
}

pub fn a_record_a_sent_message_reaches_is_sent_and_one_only_a_received_message_holds_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let inners_field =
    "  { name = \"inners\", kind = \"array\", count_bits = 4, element = \"planted_inner\", evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"
  let ids_field =
    "  { name = \"ids\", kind = \"array\", count_bits = 4, element = \"unsigned\", element_bits = 32, evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"
  let counted_inners_field =
    "  { name = \"inners\", kind = \"array\", counted_by = \"ids\", element = \"planted_inner\", evidence = \"0x1400a9140\", named_by = \"opcode.0x2\" },"
  let nested = fn(direction, entry_fields, inner_fields) {
    planted_with(
      direction:,
      fields: [entries_field],
      records: [
        #("planted_entry", entry_fields),
        #("planted_inner", inner_fields),
      ],
      unions: [],
    )
  }
  let rows: List(#(String, String, String)) = [
    #(
      "a record held by an array of a sent message",
      nested("server_to_client", [unsigned("field_3", "")], [good_field]),
      "planted_entry.field_3",
    ),
    #(
      "a record inside a record",
      nested("server_to_client", [inners_field], [unsigned("field_4", "")]),
      "planted_inner.field_4",
    ),
    #(
      "a record counted by an earlier array",
      nested("server_to_client", [ids_field, counted_inners_field], [
        unsigned("field_4", ""),
      ]),
      "planted_inner.field_4",
    ),
    #(
      "a record a union variant of a sent message holds",
      string.replace(
        planted_with(
          direction: "server_to_client",
          fields: [shapes_field],
          records: [],
          unions: [
            union_block(
              keys: ["refused_from = 3", never_damage, open_one],
              variants: [flag_variant],
            ),
          ],
        ),
        unsigned("on", traced),
        unsigned("on", ""),
      ),
      "planted_flag.on",
    ),
  ]
  check_rows(
    list.map(rows, fn(row) {
      let field_name = case string.split(row.2, ".") {
        [_, name] -> name
        _ -> row.2
      }
      #(row.0, row.1, [], [
        #(line_with(row.1, "{ name = \"" <> field_name <> "\","), row.2),
      ])
    }),
  )
  check_rows([
    #(
      "a record only a client to server message holds",
      nested("client_to_server", [unsigned("field_3", "")], [
        unsigned("field_4", ""),
      ]),
      [],
      [],
    ),
  ])
}

// ---- the kinds of a union of a message the server sends ----

const never_damage =
  "never_tags = [\n  { tag = 0, name = \"damage\", named_by = \"opcode.0x2\" },\n]"

const open_one = "open_tags = [\n  { tag = 1, question = \"what is it\" },\n]"

const unmarked_variant =
  "  { tag = 2, name = \"flag\", record = \"planted_flag\" },"

const positional_variant =
  "  { tag = 2, name = \"field_3\", record = \"planted_flag\", named_by = \"opcode.0x2\" },"

/// A planted message holding one array of the union with `keys` and `variants`.
fn union_message(
  direction direction: String,
  keys keys: List(String),
  variants variants: List(String),
) -> String {
  planted_with(direction:, fields: [shapes_field], records: [], unions: [
    union_block(keys:, variants:),
  ])
}

fn union_line(text: String) -> Int {
  line_with(text, "name = \"planted_union\"")
}

fn kind_rule(tag: Int) -> String {
  "planted_union kind " <> int.to_string(tag)
}

pub fn a_union_tag_of_a_sent_message_is_a_variant_never_sent_open_or_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let marks = ["refused_from = 3", never_damage, open_one]
  let open_variant =
    "  { tag = 2, name = \"flag\", record = \"planted_flag\", open = \"what is it\" },"
  let sent = fn(keys, variants) {
    union_message(direction: "server_to_client", keys:, variants:)
  }
  let tag_line = fn(text, tag) {
    line_with(text, "{ tag = " <> int.to_string(tag) <> ",")
  }
  let bad_never =
    sent(
      [
        "refused_from = 3",
        "never_tags = [\n  { tag = 0, name = \"damage\", named_by = \"opcode.0x9\" },\n]",
        open_one,
      ],
      [flag_variant],
    )
  let bad_open =
    sent(
      [
        "refused_from = 3",
        never_damage,
        "open_tags = [\n  { tag = 1, question = \"what is it\", named_by = \"opcode.0x9\" },\n]",
      ],
      [flag_variant],
    )
  let below_the_bound =
    sent(["refused_from = 4", never_damage, open_one], [flag_variant])
  let no_bound = sent([never_damage, open_one], [flag_variant])
  let unmarked = sent(marks, [unmarked_variant])
  let positional = sent(marks, [positional_variant])
  let in_a_record =
    planted_with(
      direction: "server_to_client",
      fields: [entries_field],
      records: [#("planted_entry", [shapes_field])],
      unions: [
        union_block(
          keys: ["refused_from = 4", never_damage, open_one],
          variants: [flag_variant],
        ),
      ],
    )
  check_rows([
    #(
      "a variant, a never tag and an open tag below the bound",
      sent(marks, [flag_variant]),
      [],
      [],
    ),
    #("a kind below the bound that is none of them", below_the_bound, [], [
      #(union_line(below_the_bound), kind_rule(3)),
    ]),
    #(
      "the kinds from the bound up are not checked",
      sent(["refused_from = 2", never_damage, open_one], []),
      [],
      [],
    ),
    #(
      "a union with no bound checks every kind its tag holds",
      no_bound,
      [],
      list.map([3, 4, 5, 6, 7], fn(tag) {
        #(union_line(no_bound), kind_rule(tag))
      }),
    ),
    #("a variant with no named_by and no open", unmarked, [], [
      #(union_line(unmarked), kind_rule(2)),
    ]),
    #("a variant with open", sent(marks, [open_variant]), [], []),
    #("a variant named by its position with named_by only", positional, [], [
      #(union_line(positional), kind_rule(2)),
    ]),
    #(
      "a union only a client to server message holds",
      union_message(direction: "client_to_server", keys: [], variants: [
        flag_variant,
      ]),
      [],
      [],
    ),
    #("a union a record of a sent message holds", in_a_record, [], [
      #(union_line(in_a_record), kind_rule(3)),
    ]),
    #("a never tag whose named_by is no fact key", bad_never, [], [
      #(tag_line(bad_never, 0), "opcode.0x9"),
    ]),
    #("an open tag whose named_by is no fact key", bad_open, [], [
      #(tag_line(bad_open, 1), "opcode.0x9"),
    ]),
    #("an open tag with no named_by", sent(marks, [flag_variant]), [], []),
  ])
}

// ---- the allow-list ----

pub fn a_listed_gap_is_not_a_breach_and_a_stale_or_repeated_one_is_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let issue = 979
  let two_fields = fn(first, second) {
    planted(
      direction: "server_to_client",
      fields: [first, second],
      record_fields: [good_field],
      unions: [],
    )
  }
  let untraced_pair =
    two_fields(unsigned("field_3", ""), unsigned("field_4", ""))
  let hello = fn(fields) {
    [UntracedFields(owner: "planted_hello", fields:, issue:)]
  }
  let owner_line = 3
  let received_text =
    planted(
      direction: "client_to_server",
      fields: [unsigned("field_3", "")],
      record_fields: [good_field],
      unions: [],
    )
  let marks = ["refused_from = 3", never_damage, open_one]
  let union_text = fn(keys, variants) {
    union_message(direction: "server_to_client", keys:, variants:)
  }
  let union_gap = fn(tags) {
    [UnclassifiedTags(union: "planted_union", tags:, issue:)]
  }
  let at_union = union_line(union_text(marks, [flag_variant]))
  check_rows([
    #(
      "a listed field passes and its sibling is a breach",
      untraced_pair,
      hello(["field_3"]),
      [#(9, "planted_hello.field_4")],
    ),
    #(
      "a listed field that now has named_by",
      two_fields(unsigned("build", traced), unsigned("field_4", "")),
      hello(["build", "field_4"]),
      [#(owner_line, "planted_hello.build")],
    ),
    #(
      "a listed field that is now an open question",
      two_fields(
        unsigned("field_3", ", open = \"what is it\""),
        unsigned("field_4", ""),
      ),
      hello(["field_3", "field_4"]),
      [#(owner_line, "planted_hello.field_3")],
    ),
    #(
      "a listed field the owner lacks",
      untraced_pair,
      hello(["field_3", "field_4", "field_9"]),
      [#(owner_line, "planted_hello.field_9")],
    ),
    #(
      "a listed field of an owner only a client to server message reaches",
      received_text,
      hello(["field_3"]),
      [#(owner_line, "owner no message the server sends holds")],
    ),
    #(
      "an owner the schema lacks",
      untraced_pair,
      list.append(hello(["field_3", "field_4"]), [
        UntracedFields(owner: "planted_gone", fields: ["field_1"], issue:),
      ]),
      [#(1, "planted_gone")],
    ),
    #(
      "an owner listed in two entries",
      untraced_pair,
      list.append(hello(["field_3"]), hello(["field_4"])),
      [
        #(owner_line, "repeats the owner planted_hello"),
        #(owner_line, "repeats the owner planted_hello"),
      ],
    ),
    #(
      "one entry that lists a field twice",
      untraced_pair,
      hello(["field_3", "field_4", "field_3"]),
      [#(owner_line, "planted_hello.field_3 twice")],
    ),
    #("an entry that lists no field", untraced_pair, hello([]), [
      #(owner_line, "lists no field"),
      #(8, "planted_hello.field_3"),
      #(9, "planted_hello.field_4"),
    ]),
    #(
      "a listed field whose evidence is no fact key still fails its evidence",
      two_fields(
        "  { name = \"field_3\", kind = \"unsigned\", bits = 32, evidence = \"opcode.0x9\" },",
        unsigned("build", traced),
      ),
      hello(["field_3"]),
      [#(8, "opcode.0x9")],
    ),
    #(
      "a listed kind that is unclassified passes",
      union_text(marks, [unmarked_variant]),
      union_gap([2]),
      [],
    ),
    #(
      "a listed kind that is now a traced variant",
      union_text(marks, [flag_variant]),
      union_gap([2]),
      [#(at_union, "planted_union kind 2")],
    ),
    #(
      "a listed kind that is now a never tag",
      union_text(marks, [flag_variant]),
      union_gap([0]),
      [#(at_union, "planted_union kind 0")],
    ),
    #(
      "a listed kind that is now an open tag",
      union_text(marks, [flag_variant]),
      union_gap([1]),
      [#(at_union, "planted_union kind 1")],
    ),
    #(
      "a listed kind at or above the bound",
      union_text(marks, [flag_variant]),
      union_gap([3]),
      [#(at_union, "planted_union kind 3")],
    ),
    #(
      "a union listed in two entries",
      union_text(marks, [unmarked_variant]),
      list.append(union_gap([2]), union_gap([2])),
      [
        #(at_union, "repeats the union planted_union"),
        #(at_union, "repeats the union planted_union"),
      ],
    ),
    #(
      "one entry that lists a kind twice",
      union_text(["refused_from = 4", ..list.drop(marks, 1)], [unmarked_variant]),
      union_gap([2, 3, 2]),
      [#(at_union, "planted_union kind 2 twice")],
    ),
    #(
      "an entry that lists no kind",
      union_text(marks, [flag_variant]),
      union_gap([]),
      [#(at_union, "lists no kind")],
    ),
    #(
      "a union the schema lacks",
      union_text(marks, [flag_variant]),
      [UnclassifiedTags(union: "planted_gone", tags: [1], issue:)],
      [#(1, "planted_gone")],
    ),
    #(
      "a union no message the server sends reaches",
      string.replace(
        union_text(marks, [unmarked_variant]),
        "direction = \"server_to_client\"",
        "direction = \"client_to_server\"",
      ),
      union_gap([2]),
      [#(at_union, "whose union no message the server sends holds")],
    ),
  ])
}

pub fn each_known_gap_names_the_open_issue_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let open_issues: List(Int) = [979]
  assert list.all(untraced_gaps.known_gaps, fn(gap) {
    list.contains(open_issues, gap.issue)
  })
    as "each entry of the allow-list names the open issue whose work removes it"
}

// ---- the real schema ----

pub fn the_real_schema_has_no_gap_the_allow_list_does_not_name_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  assert schema_evidence.breaches(
      file: SourceFile(path: "src/genesis_prime/message/schema.toml", text:),
      fact_keys: repository.fact_keys(),
      gaps: untraced_gaps.known_gaps,
    )
    == []
    as "CLAUDE.md: every field of a message the server sends is traced or open, in the three messages no module builds as in the rest, and every union kind is a traced variant, a never tag or an open tag; no entry of the allow-list is stale; each key a never tag or an open tag names is a fact"
}

// ---- the combat log and stat unions ----

/// One union the client reads by a tag: its bound (the first tag the client's
/// reader refuses), the tags the client reads that the server must not send, and
/// the tags it reads that nothing in the server builds yet.
type TagRow {
  TagRow(
    union: String,
    refused_from: Int,
    never: List(Int),
    open: List(Int),
    reason: String,
  )
}

const combat_and_stat_rows = [
  TagRow(
    union: "combat_log_entry",
    refused_from: 36,
    never: [3, 4, 6, 7, 12, 13, 17],
    open: [
      0, 5, 8, 9, 10, 11, 15, 16, 19, 20, 21, 25, 26, 27, 28, 29, 30, 31, 32, 33,
      34, 35,
    ],
    reason: "union-kinds.md: the client reads types 0 to 35; the NEVER rows are never sent, every other lacking type waits for its system or for a question about the client's dispatch",
  ),
  TagRow(
    union: "unit_stat_change",
    refused_from: 32,
    never: [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 16, 18, 19, 23, 24, 25, 27, 28, 29,
      30, 31,
    ],
    open: [0, 11, 15, 17, 26],
    reason: "union-kinds.md: the client reads stats 0 to 31; 23 of the 28 lacking stats are NEVER by 0x938, five wait for their systems or for a question",
  ),
  TagRow(
    union: "unit_stat_value",
    refused_from: 3,
    never: [],
    open: [2],
    reason: "fact 0x140096230: forms 0 to 2 are read, 3 refuses the message; form 2 (two integers) has no verdict",
  ),
]

pub fn the_combat_log_and_stat_unions_classify_every_tag_the_client_reads_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  let assert Ok(schema) = message_schema.parse(text)
    as "the schema file is not a schema"
  let fact_keys = repository.fact_keys()
  let listed_unions =
    list.filter_map(untraced_gaps.known_gaps, fn(gap) {
      case gap {
        UnclassifiedTags(union:, ..) -> Ok(union)
        UntracedFields(..) -> Error(Nil)
      }
    })
  list.each(combat_and_stat_rows, fn(row) {
    let assert Ok(union) =
      list.find(schema.unions, fn(union) { union.name == row.union })
      as { "no union named " <> row.union }
    let variants = list.map(union.variants, fn(variant) { variant.tag })
    let never = list.map(union.never_tags, fn(never) { never.tag })
    let open = list.map(union.open_tags, fn(open) { open.tag })
    assert union.refused_from == row.refused_from as row.reason
    assert list.sort(never, int.compare) == row.never as row.reason
    assert list.sort(open, int.compare) == row.open as row.reason
    let classified = list.flatten([variants, never, open])
    assert list.sort(classified, int.compare)
      == int.range(from: 0, to: row.refused_from, with: [], run: fn(tags, tag) {
        list.append(tags, [tag])
      })
      as {
        row.union
        <> ": each tag the client reads is a variant, never or open once"
      }
    let cited =
      list.flatten([
        list.map(union.never_tags, fn(never) { never.named_by }),
        list.filter_map(union.open_tags, fn(open) {
          option.to_result(open.named_by, Nil)
        }),
      ])
    assert list.filter(cited, fn(key) { !list.contains(fact_keys, key) }) == []
      as { row.union <> ": each key a never or open tag cites is a fact" }
    assert !list.contains(listed_unions, row.union)
      as { row.union <> ": no allow-list entry once every tag is classified" }
  })
}

// ---- the connection, realm and spell cast messages ----

/// The owners of the connection, login, character select and realm messages
/// the server sends or has ready to send.
const connection_and_realm_owners = [
  "server_hello", "login_refused", "delete_character_result",
  "create_character_result", "character_list", "character_list_entry",
  "enter_world", "unit_is_player", "action_set", "realm_list", "realm_entry",
  "text_group", "realm_handoff",
]

/// The owners of the spell cast messages the server sends, each a message or a
/// record of the schema.
const spell_cast_owners = [
  "spell_hit_entry",
  "spell_missile_info",
  "spell_initial_position",
  "spell_telegraph_position",
  "spell_started",
  "spell_effect_info",
  "spell_effect_bit",
  "spell_failed",
  "spell_miss",
]

/// The owners of the unit create, destroy, death and dialog messages and of
/// the chat channel, chat line and chat format messages the server sends, each
/// a message or a record of the schema.
const unit_and_chat_owners = [
  "unit_create_tail", "unit_create_ghost", "unit_death_state", "unit_destroyed",
  "unit_dialog_open", "chat_channel_joined", "chat_line",
  "chat_format_item_record", "chat_format_kind_0", "chat_format_kind_1",
  "chat_format_kind_2", "chat_format_kind_3", "chat_format_kind_11",
]

/// The fields of an owner that the schema check does not count as traced (not
/// named for what they are, not open with a question), or that name a key the
/// fact file does not hold.
fn untraced_fields(
  schema schema: message_schema.Schema,
  owner owner: String,
  fact_keys fact_keys: List(String),
) -> List(String) {
  let fields = case
    list.find(schema.messages, fn(message) { message.name == owner })
  {
    Ok(message) -> message.fields
    Error(Nil) ->
      case list.find(schema.records, fn(record) { record.name == owner }) {
        Ok(record) -> record.fields
        Error(Nil) -> panic as { "no owner named " <> owner <> " in the schema" }
      }
  }
  list.filter_map(fields, fn(field) {
    let names_a_fact = case field.named_by {
      Some(key) -> list.contains(fact_keys, key)
      None -> True
    }
    case schema_evidence.is_traced(field) && names_a_fact {
      True -> Error(Nil)
      False -> Ok(field.name)
    }
  })
}

/// Asserts that every field of each owner is traced or open and that the
/// allow-list of untraced fields holds no entry for any of them.
fn assert_owners_are_traced(owners: List(String)) -> Nil {
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  let assert Ok(schema) = message_schema.parse(text)
    as "the schema file is not a schema"
  let fact_keys = repository.fact_keys()
  let listed =
    list.filter_map(untraced_gaps.known_gaps, fn(gap) {
      case gap {
        UntracedFields(owner:, ..) -> Ok(owner)
        UnclassifiedTags(..) -> Error(Nil)
      }
    })
  assert list.map(owners, fn(owner) {
      #(owner, untraced_fields(schema:, owner:, fact_keys:))
    })
    == list.map(owners, fn(owner) { #(owner, []) })
    as "CLAUDE.md: every field of a message the server sends is traced or open: each field of these owners is named by a fact or open with its question"
  assert list.filter(owners, list.contains(listed, _)) == []
    as "these owners are traced, so the allow-list has no entry for them"
}

pub fn the_connection_and_realm_messages_carry_no_untraced_field_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  assert_owners_are_traced(connection_and_realm_owners)
}

pub fn the_spell_cast_messages_carry_no_untraced_field_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  assert_owners_are_traced(spell_cast_owners)
}

pub fn the_unit_and_chat_messages_carry_no_untraced_field_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  assert_owners_are_traced(unit_and_chat_owners)
}
