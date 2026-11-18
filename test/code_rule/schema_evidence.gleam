//// Every field of the message schema names its evidence: a key of the client's
//// fact file that gives its width, and, when its name is more than its
//// position, a key that says what it is. So does every message and record, and
//// every named value of a field, which names the key that shows the client
//// gives the value that meaning (the schema reader refuses a number or a name
//// listed twice). So does every union, and each of its variants, never tags
//// and open tags that names a key.
////
//// A message is sent when it does not travel only from the client; a record is
//// sent when a sent message holds it, directly or inside another sent record,
//// and the records of a union's variants are held by whatever holds the union.
//// A union is sent when a sent message or record holds it.
////
//// ```text
//// schema.toml -> sent owners -> untraced fields, unclassified tags
////                               -> minus the allow-list's entries -> breaches
//// ```
////
//// - A field of a sent owner is traced when it has a `named_by` and a name
////   that is not its position (`field_3`), or is `open` with its question. A
////   `safe_by` key is no licence: it shows a value is safe, not what it is.
//// - Each tag below the union's `refused_from` is a variant that is traced
////   (`named_by`, or `open`), a never tag or an open tag.
//// - An entry of the allow-list drops the tracing breach of what it lists and
////   nothing else: a key the fact file lacks is still a breach. An entry whose
////   owner or union no sent message reaches, that lists what is now traced, a
////   name or tag twice, nothing, or an owner or union another entry lists, is a
////   breach too, so a rename or a classification removes its line.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/untraced_gaps.{type Gap, UnclassifiedTags, UntracedFields}
import genesis_prime/message_schema.{
  type Field, type Record, type Schema, type Union, ArrayOfFloat32,
  ArrayOfRecord, ArrayOfRecordCountedBy, ArrayOfUnsigned, ArrayOfWideText,
  ClientToServer, Constant, CountedWideText, Endpoint, Float32, Guid,
  HalfFloatAtLeast, OneRecord, RawBytes, Unsigned, UnsignedArrayCountedBy,
  UnsignedBelow, WholeFrame, WideText, WideUnits,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/string

/// Each field, message or record of the schema that names no evidence or
/// names a key the fact file does not hold, at the line of the field; each
/// `safe_by`, `named_by` or tag key the fact file does not hold; each field of
/// a message the server sends that is neither traced nor open, and each tag of
/// a union it sends that is neither a traced variant, a never tag nor an open
/// tag, unless `gaps` lists it; and each entry of `gaps` that does not match.
pub fn breaches(
  file file: SourceFile,
  fact_keys fact_keys: List(String),
  gaps gaps: List(Gap),
) -> List(Breach) {
  case message_schema.parse(file.text) {
    Error(error) -> [
      Breach(
        path: file.path,
        line: 1,
        rule: "a schema file that is not a schema: "
          <> message_schema.describe(error),
      ),
    ]
    Ok(schema) -> owners_breaches(file:, schema:, fact_keys:, gaps:)
  }
}

type Owner {
  Owner(name: String, evidence: String, fields: List(Field), sent: Bool)
}

fn owners(schema: Schema) -> List(Owner) {
  let sent =
    list.filter(schema.messages, fn(message) {
      message.direction != ClientToServer
    })
  let sent_records =
    records_reached(
      records: schema.records,
      unions: schema.unions,
      from: list.flat_map(sent, fn(message) { message.fields }),
      found: [],
    )
  list.append(
    list.map(schema.messages, fn(message) {
      Owner(
        message.name,
        message.evidence,
        message.fields,
        sent: list.contains(sent, message),
      )
    }),
    list.map(schema.records, fn(record) {
      Owner(
        record.name,
        record.evidence,
        record.fields,
        sent: list.contains(sent_records, record.name),
      )
    }),
  )
}

/// The record or union a field holds, when it holds one.
fn held_record(field: Field) -> Option(String) {
  case field.kind {
    ArrayOfRecord(record:, ..)
    | ArrayOfRecordCountedBy(record:, ..)
    | OneRecord(record:) -> Some(record)
    Unsigned(..)
    | UnsignedBelow(..)
    | HalfFloatAtLeast(..)
    | Float32
    | WideText
    | WideUnits
    | CountedWideText(..)
    | Guid
    | Endpoint
    | RawBytes(..)
    | WholeFrame
    | ArrayOfWideText(..)
    | ArrayOfUnsigned(..)
    | ArrayOfFloat32(..)
    | UnsignedArrayCountedBy(..)
    | Constant(..) -> None
  }
}

/// The names of the records the fields hold in arrays, the records of the
/// variants of each union they hold, and the records those hold in turn, each
/// once.
fn records_reached(
  records records: List(Record),
  unions unions: List(Union),
  from fields: List(Field),
  found found: List(String),
) -> List(String) {
  let named =
    list.filter_map(fields, fn(field) {
      option.to_result(held_record(field), Nil)
    })
    |> list.flat_map(records_of(unions:, name: _))
    |> list.filter(fn(record) { !list.contains(found, record) })
    |> list.unique
  case named {
    [] -> found
    _ ->
      records_reached(
        records:,
        unions:,
        from: list.flat_map(records, fn(record) {
          case list.contains(named, record.name) {
            True -> record.fields
            False -> []
          }
        }),
        found: list.append(found, named),
      )
  }
}

/// The records a name stands for: the records of a union's variants, or the
/// record itself.
fn records_of(unions unions: List(Union), name name: String) -> List(String) {
  case list.find(unions, fn(union) { union.name == name }) {
    Ok(union) -> list.map(union.variants, fn(variant) { variant.record })
    Error(Nil) -> [name]
  }
}

/// The unions a sent message or a sent record holds.
fn sent_unions(schema: Schema, owners: List(Owner)) -> List(Union) {
  let held =
    owners
    |> list.filter(fn(owner) { owner.sent })
    |> list.flat_map(fn(owner) { owner.fields })
    |> list.filter_map(fn(field) { option.to_result(held_record(field), Nil) })
  list.filter(schema.unions, fn(union) { list.contains(held, union.name) })
}

/// A field is traced when it names a fact and a name that is not its position,
/// or is open with its question.
fn is_traced(field: Field) -> Bool {
  is_named_or_open(name: field.name, named_by: field.named_by, open: field.open)
}

/// The test of `is_traced`, for a field and a union variant alike.
fn is_named_or_open(
  name name: String,
  named_by named_by: Option(String),
  open open: Option(String),
) -> Bool {
  case open, named_by {
    Some(_), _ -> True
    None, Some(_) -> !is_position_name(name)
    None, None -> False
  }
}

/// `field_` and then digits only: the name a field has until a fact names it.
fn is_position_name(name: String) -> Bool {
  case string.remove_prefix(name, "field_") {
    "" -> False
    digits ->
      name != digits
      && list.all(string.to_graphemes(digits), string.contains("0123456789", _))
  }
}

/// The kinds below a union's `refused_from` that no variant, never tag or open
/// tag holds, and the variants that have neither a `named_by` with a name that is not
/// their position nor `open`.
fn untraced_tags(union: Union) -> List(Int) {
  int.range(from: 0, to: union.refused_from, with: [], run: fn(tags, tag) {
    [tag, ..tags]
  })
  |> list.reverse
  |> list.filter(fn(tag) {
    case list.find(union.variants, fn(variant) { variant.tag == tag }) {
      Ok(variant) ->
        !is_named_or_open(
          name: variant.name,
          named_by: variant.named_by,
          open: variant.open,
        )
      Error(Nil) ->
        !list.any(union.never_tags, fn(never) { never.tag == tag })
        && !list.any(union.open_tags, fn(open) { open.tag == tag })
    }
  })
}

fn owners_breaches(
  file file: SourceFile,
  schema schema: Schema,
  fact_keys fact_keys: List(String),
  gaps gaps: List(Gap),
) -> List(Breach) {
  let lines = string.split(file.text, "\n")
  let owners = owners(schema)
  let sent_unions = sent_unions(schema, owners)
  list.flatten([
    list.flat_map(schema.unions, union_breaches(
      file:,
      lines:,
      union: _,
      fact_keys:,
    )),
    list.flat_map(sent_unions, untraced_tag_breaches(
      file:,
      lines:,
      union: _,
      gaps:,
    )),
    owners_field_breaches(file:, lines:, owners:, fact_keys:, gaps:),
    gap_breaches(file:, lines:, owners:, sent_unions:, gaps:),
  ])
}

fn at(file file: SourceFile, line line: Int, rule rule: String) -> Breach {
  Breach(path: file.path, line:, rule:)
}

/// Each union whose evidence is not a key of the fact file, at its evidence's
/// line, and each variant, never tag or open tag whose `named_by` is not, at
/// its line.
fn union_breaches(
  file file: SourceFile,
  lines lines: List(String),
  union union: Union,
  fact_keys fact_keys: List(String),
) -> List(Breach) {
  let union_line =
    line_of(lines:, from: 0, text: "name = \"" <> union.name <> "\"")
  let own = case list.contains(fact_keys, union.evidence) {
    True -> []
    False -> [
      at(
        file:,
        line: line_of(
          lines:,
          from: union_line - 1,
          text: "evidence = \"" <> union.evidence <> "\"",
        ),
        rule: "a schema owner whose evidence is not a key of the fact file: "
          <> union.name
          <> " names "
          <> union.evidence,
      ),
    ]
  }
  let variants =
    list.filter_map(union.variants, fn(variant) {
      unknown_tag_key(
        file:,
        line: line_of(
          lines:,
          from: union_line,
          text: "name = \"" <> variant.name <> "\"",
        ),
        what: "variant",
        where: union.name <> "." <> variant.name,
        key: variant.named_by,
        fact_keys:,
      )
    })
  let never_tags =
    list.filter_map(union.never_tags, fn(never) {
      unknown_tag_key(
        file:,
        line: tag_line(lines:, union_line:, tag: never.tag),
        what: "never tag",
        where: union.name <> " kind " <> int.to_string(never.tag),
        key: Some(never.named_by),
        fact_keys:,
      )
    })
  let open_tags =
    list.filter_map(union.open_tags, fn(open) {
      unknown_tag_key(
        file:,
        line: tag_line(lines:, union_line:, tag: open.tag),
        what: "open tag",
        where: union.name <> " kind " <> int.to_string(open.tag),
        key: open.named_by,
        fact_keys:,
      )
    })
  list.flatten([own, variants, never_tags, open_tags])
}

fn unknown_tag_key(
  file file: SourceFile,
  line line: Int,
  what what: String,
  where where: String,
  key key: Option(String),
  fact_keys fact_keys: List(String),
) -> Result(Breach, Nil) {
  case key {
    Some(key) ->
      case list.contains(fact_keys, key) {
        True -> Error(Nil)
        False ->
          Ok(at(
            file:,
            line:,
            rule: "a schema "
              <> what
              <> " whose named_by is not a key of the fact file: "
              <> where
              <> " names "
              <> key,
          ))
      }
    None -> Error(Nil)
  }
}

fn tag_line(
  lines lines: List(String),
  union_line union_line: Int,
  tag tag: Int,
) -> Int {
  line_of(
    lines:,
    from: union_line,
    text: "{ tag = " <> int.to_string(tag) <> ",",
  )
}

/// Each kind below a sent union's `refused_from` that is no traced variant, no
/// never tag and no open tag and that `gaps` does not list, at the union's line.
fn untraced_tag_breaches(
  file file: SourceFile,
  lines lines: List(String),
  union union: Union,
  gaps gaps: List(Gap),
) -> List(Breach) {
  let line = line_of(lines:, from: 0, text: "name = \"" <> union.name <> "\"")
  untraced_tags(union)
  |> list.filter(fn(tag) {
    !list.any(gaps, fn(gap) {
      case gap {
        UnclassifiedTags(union: listed, tags:, ..) ->
          listed == union.name && list.contains(tags, tag)
        UntracedFields(..) -> False
      }
    })
  })
  |> list.map(fn(tag) {
    at(
      file:,
      line:,
      rule: "a union kind of a message the server sends that is no traced variant, never tag or open tag: "
        <> union.name
        <> " kind "
        <> int.to_string(tag),
    )
  })
}

fn owners_field_breaches(
  file file: SourceFile,
  lines lines: List(String),
  owners owners: List(Owner),
  fact_keys fact_keys: List(String),
  gaps gaps: List(Gap),
) -> List(Breach) {
  list.flat_map(owners, fn(owner) {
    let owner_line =
      line_of(lines:, from: 0, text: "name = \"" <> owner.name <> "\"")
    let own = case list.contains(fact_keys, owner.evidence) {
      True -> []
      False -> [
        at(
          file:,
          line: line_of(
            lines:,
            from: owner_line - 1,
            text: "evidence = \"" <> owner.evidence <> "\"",
          ),
          rule: "a schema owner whose evidence is not a key of the fact file: "
            <> owner.name
            <> " names "
            <> owner.evidence,
        ),
      ]
    }
    list.append(
      own,
      list.flat_map(owner.fields, fn(field) {
        let line =
          line_of(
            lines:,
            from: owner_line,
            text: "{ name = \"" <> field.name <> "\",",
          )
        field_breaches(file:, owner:, field:, line:, fact_keys:, gaps:)
      }),
    )
  })
}

fn field_breaches(
  file file: SourceFile,
  owner owner: Owner,
  field field: Field,
  line line: Int,
  fact_keys fact_keys: List(String),
  gaps gaps: List(Gap),
) -> List(Breach) {
  let where = owner.name <> "." <> field.name
  let evidence = case field.evidence {
    None -> [
      at(file:, line:, rule: "a schema field that names no evidence: " <> where),
    ]
    Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
  }
  let named_by = case field.named_by {
    None -> []
    Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
  }
  let safe_by = case field.safe_by {
    None -> []
    Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
  }
  let untraced = case
    owner.sent && !is_traced(field) && !listed(gaps:, owner:, field:)
  {
    True -> [
      at(
        file:,
        line:,
        rule: "a field of a message the server sends that is neither traced nor open: "
          <> where,
      ),
    ]
    False -> []
  }
  let values = case message_schema.named_values(field:) {
    None -> []
    Some(named_values) ->
      list.flat_map(named_values.values, fn(value) {
        let where = where <> " value " <> value.name
        case value.evidence {
          None -> [
            at(
              file:,
              line:,
              rule: "a schema value that names no evidence: " <> where,
            ),
          ]
          Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
        }
      })
  }
  list.flatten([evidence, named_by, safe_by, untraced, values])
}

fn listed(
  gaps gaps: List(Gap),
  owner owner: Owner,
  field field: Field,
) -> Bool {
  list.any(gaps, fn(gap) {
    case gap {
      UntracedFields(owner: listed, fields:, ..) ->
        listed == owner.name && list.contains(fields, field.name)
      UnclassifiedTags(..) -> False
    }
  })
}

fn unknown_key(
  file file: SourceFile,
  line line: Int,
  where where: String,
  key key: String,
  fact_keys fact_keys: List(String),
) -> List(Breach) {
  case list.contains(fact_keys, key) {
    True -> []
    False -> [
      at(
        file:,
        line:,
        rule: "a schema field whose evidence is not a key of the fact file: "
          <> where
          <> " names "
          <> key,
      ),
    ]
  }
}

/// Each entry of the allow-list that does not match the schema: one that lists
/// nothing, a name or a tag twice, or an owner or union another entry lists, one
/// whose owner or union no sent message reaches, and each listed field or tag
/// that is absent or is traced now, at the owner's or the union's line.
fn gap_breaches(
  file file: SourceFile,
  lines lines: List(String),
  owners owners: List(Owner),
  sent_unions sent_unions: List(Union),
  gaps gaps: List(Gap),
) -> List(Breach) {
  let listed_owners =
    list.filter_map(gaps, fn(gap) {
      case gap {
        UntracedFields(owner:, ..) -> Ok(owner)
        UnclassifiedTags(..) -> Error(Nil)
      }
    })
  let listed_unions =
    list.filter_map(gaps, fn(gap) {
      case gap {
        UnclassifiedTags(union:, ..) -> Ok(union)
        UntracedFields(..) -> Error(Nil)
      }
    })
  list.flat_map(gaps, fn(gap) {
    case gap {
      UntracedFields(owner: name, fields:, ..) ->
        field_gap_breaches(
          file:,
          line: line_of(lines:, from: 0, text: "name = \"" <> name <> "\""),
          owner: list.find(owners, fn(owner) {
            owner.name == name && owner.sent
          }),
          name:,
          fields:,
          listed: listed_owners,
        )
      UnclassifiedTags(union: name, tags:, ..) ->
        tag_gap_breaches(
          file:,
          line: line_of(lines:, from: 0, text: "name = \"" <> name <> "\""),
          union: list.find(sent_unions, fn(union) { union.name == name }),
          name:,
          tags:,
          listed: listed_unions,
        )
    }
  })
}

fn entry_breach(
  file file: SourceFile,
  line line: Int,
  rule rule: String,
) -> Breach {
  at(file:, line:, rule: "an allow-list entry " <> rule)
}

/// The breaches of one `UntracedFields` entry; `owner` is the sent owner of the
/// entry's name, when there is one, and `listed` the owner of every entry.
fn field_gap_breaches(
  file file: SourceFile,
  line line: Int,
  owner owner: Result(Owner, Nil),
  name name: String,
  fields fields: List(String),
  listed listed: List(String),
) -> List(Breach) {
  let entry = entry_breach(file:, line:, rule: _)
  let own = case fields, list.count(listed, fn(other) { other == name }) {
    [], _ -> [entry("lists no field: " <> name)]
    _, 1 -> []
    _, _ -> [entry("repeats the owner " <> name <> " of another entry")]
  }
  let twice =
    list.map(repeated(fields), fn(field_name) {
      entry("lists " <> name <> "." <> field_name <> " twice")
    })
  let stale = case owner {
    Error(Nil) -> [
      entry("whose owner no message the server sends holds: " <> name),
    ]
    Ok(owner) ->
      list.filter_map(fields, fn(field_name) {
        let where = name <> "." <> field_name
        case list.find(owner.fields, fn(field) { field.name == field_name }) {
          Error(Nil) ->
            Ok(entry("lists " <> where <> ", which the owner lacks"))
          Ok(field) ->
            case is_traced(field) {
              True ->
                Ok(entry("lists " <> where <> ", which is traced or open now"))
              False -> Error(Nil)
            }
        }
      })
  }
  list.flatten([own, twice, stale])
}

/// The breaches of one `UnclassifiedTags` entry; `union` is the sent union of
/// the entry's name, when there is one, and `listed` the union of every entry.
fn tag_gap_breaches(
  file file: SourceFile,
  line line: Int,
  union union: Result(Union, Nil),
  name name: String,
  tags tags: List(Int),
  listed listed: List(String),
) -> List(Breach) {
  let entry = entry_breach(file:, line:, rule: _)
  let own = case tags, list.count(listed, fn(other) { other == name }) {
    [], _ -> [entry("lists no kind: " <> name)]
    _, 1 -> []
    _, _ -> [entry("repeats the union " <> name <> " of another entry")]
  }
  let twice =
    list.map(repeated(tags), fn(tag) {
      entry("lists " <> name <> " kind " <> int.to_string(tag) <> " twice")
    })
  let stale = case union {
    Error(Nil) -> [
      entry("whose union no message the server sends holds: " <> name),
    ]
    Ok(union) ->
      list.filter_map(tags, fn(tag) {
        case list.contains(untraced_tags(union), tag) {
          True -> Error(Nil)
          False ->
            Ok(entry(
              "lists "
              <> name
              <> " kind "
              <> int.to_string(tag)
              <> ", which is traced, never sent, open or refused now",
            ))
        }
      })
  }
  list.flatten([own, twice, stale])
}

/// Each item that an item before it in the list equals, once for each extra
/// appearance.
fn repeated(items: List(a)) -> List(a) {
  list.index_map(items, fn(item, index) { #(item, list.take(items, index)) })
  |> list.filter(fn(item_and_earlier) {
    list.contains(item_and_earlier.1, item_and_earlier.0)
  })
  |> list.map(pair.first)
}

/// The 1-based number of the first line at or after the 0-based `from` that
/// holds the text, or 1 when none does.
fn line_of(
  lines lines: List(String),
  from from: Int,
  text text: String,
) -> Int {
  let found =
    lines
    |> list.index_map(fn(line, index) { #(index, line) })
    |> list.find(fn(numbered) {
      numbered.0 >= from && string.contains(numbered.1, text)
    })
  case found {
    Ok(#(index, _)) -> index + 1
    Error(Nil) -> 1
  }
}
