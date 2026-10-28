//// Every field of the message schema names its evidence: a key of the client's
//// fact file that gives its width, and, when its name is more than its
//// position, a key that says what it is. So does every message and record, and
//// every named value of a field, which names the key that shows the client
//// gives the value that meaning (the schema reader refuses a number or a name
//// listed twice).
//// A field of a message the server sends that has no name must carry a
//// `safe_by` key of the fact file, which shows the value the server sends is
//// safe. A message is sent when it travels to the client, or both ways, and a
//// module outside `src/genesis_prime/message/` imports its module; a record is
//// sent when a message that is sent holds it, directly or inside another
//// record that is sent.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import genesis_prime/message_schema.{
  type Field, type Record, type Schema, ArrayOfFloat32, ArrayOfRecord,
  ArrayOfUnsigned, ArrayOfWideText, ClientToServer, Constant, CountedWideText,
  Endpoint, Float32, Guid, RawBytes, Unsigned, UnsignedArrayCountedBy,
  UnsignedBelow, WholeFrame, WideText,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// The names of the message modules the given source files import, from the
/// files outside `src/genesis_prime/message/`, sorted and each once.
pub fn sent_messages(sources sources: List(SourceFile)) -> List(String) {
  sources
  |> list.filter(fn(file) {
    !string.starts_with(file.path, "src/genesis_prime/message/")
  })
  |> list.flat_map(syntax.imported_modules)
  |> list.filter(string.starts_with(_, "genesis_prime/message/"))
  |> list.map(string.remove_prefix(_, "genesis_prime/message/"))
  |> list.unique
  |> list.sort(string.compare)
}

/// Each field, message or record of the schema that names no evidence or
/// names a key the fact file does not hold, at the line of the field; each
/// `safe_by` key the fact file does not hold; and each unnamed field with no
/// `safe_by` in a message the server sends, which is one named in
/// `sent_messages` that does not travel only from the client.
pub fn breaches(
  file file: SourceFile,
  fact_keys fact_keys: List(String),
  sent_messages sent_messages: List(String),
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
    Ok(schema) -> owners_breaches(file:, schema:, fact_keys:, sent_messages:)
  }
}

type Owner {
  Owner(name: String, evidence: String, fields: List(Field), sent: Bool)
}

fn owners(schema: Schema, sent_messages: List(String)) -> List(Owner) {
  let sent =
    list.filter(schema.messages, fn(message) {
      message.direction != ClientToServer
      && list.contains(sent_messages, message.name)
    })
  let sent_records =
    records_reached(
      records: schema.records,
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

/// The names of the records the fields hold in arrays, and the records those
/// hold in turn, each once.
fn records_reached(
  records records: List(Record),
  from fields: List(Field),
  found found: List(String),
) -> List(String) {
  let named =
    list.filter_map(fields, fn(field) {
      case field.kind {
        ArrayOfRecord(record:, ..) ->
          case list.contains(found, record) {
            True -> Error(Nil)
            False -> Ok(record)
          }
        Unsigned(..)
        | UnsignedBelow(..)
        | Float32
        | WideText
        | CountedWideText(..)
        | Guid
        | Endpoint
        | RawBytes(..)
        | WholeFrame
        | ArrayOfWideText(..)
        | ArrayOfUnsigned(..)
        | ArrayOfFloat32(..)
        | UnsignedArrayCountedBy(..)
        | Constant(..) -> Error(Nil)
      }
    })
    |> list.unique
  case named {
    [] -> found
    _ ->
      records_reached(
        records:,
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

fn owners_breaches(
  file file: SourceFile,
  schema schema: Schema,
  fact_keys fact_keys: List(String),
  sent_messages sent_messages: List(String),
) -> List(Breach) {
  let lines = string.split(file.text, "\n")
  list.flat_map(owners(schema, sent_messages), fn(owner) {
    let owner_line =
      line_of(lines:, from: 0, text: "name = \"" <> owner.name <> "\"")
    let own = case list.contains(fact_keys, owner.evidence) {
      True -> []
      False -> [
        Breach(
          path: file.path,
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
        field_breaches(file:, owner:, field:, line:, fact_keys:)
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
) -> List(Breach) {
  let where = owner.name <> "." <> field.name
  let evidence = case field.evidence {
    None -> [
      Breach(
        path: file.path,
        line:,
        rule: "a schema field that names no evidence: " <> where,
      ),
    ]
    Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
  }
  let named_by = case field.named_by {
    None -> []
    Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
  }
  let safe_by = case field.safe_by, field.named_by {
    Some(key), _ -> unknown_key(file:, line:, where:, key:, fact_keys:)
    None, None if owner.sent -> [
      Breach(
        path: file.path,
        line:,
        rule: "a field of a message the server sends that has no name and no safe_by key: "
          <> where,
      ),
    ]
    None, _ -> []
  }
  let values = case field.named_values {
    None -> []
    Some(named_values) ->
      list.flat_map(named_values.values, fn(value) {
        let where = where <> " value " <> value.name
        case value.evidence {
          None -> [
            Breach(
              path: file.path,
              line:,
              rule: "a schema value that names no evidence: " <> where,
            ),
          ]
          Some(key) -> unknown_key(file:, line:, where:, key:, fact_keys:)
        }
      })
  }
  list.flatten([evidence, named_by, safe_by, values])
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
      Breach(
        path: file.path,
        line:,
        rule: "a schema field whose evidence is not a key of the fact file: "
          <> where
          <> " names "
          <> key,
      ),
    ]
  }
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
