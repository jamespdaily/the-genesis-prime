//// Every field of the message schema names its evidence: a key of the client's
//// fact file that gives its width, and, when its name is more than its
//// position, a key that says what it is. So does every message and record.

import code_rule/source.{type Breach, type SourceFile, Breach}
import genesis_prime/message_schema.{type Field, type Schema}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Each field, message or record of the schema that names no evidence or
/// names a key the fact file does not hold, at the line of the field.
pub fn breaches(
  file file: SourceFile,
  fact_keys fact_keys: List(String),
) -> List(Breach) {
  case message_schema.parse(file.text) {
    Error(error) -> [
      Breach(
        path: file.path,
        line: 1,
        rule: "a schema file that is not a schema: " <> describe(error),
      ),
    ]
    Ok(schema) -> owners_breaches(file:, schema:, fact_keys:)
  }
}

fn describe(error: message_schema.SchemaError) -> String {
  case error {
    message_schema.NotToml -> "it is not TOML"
    message_schema.MissingKey(table:, key:) -> table <> " has no " <> key
    message_schema.WrongTypeOfKey(table:, key:) ->
      table <> " has a " <> key <> " of the wrong type"
    message_schema.UnknownKind(field:, kind:) ->
      field <> " has the unknown kind " <> kind
    message_schema.UnknownDirection(message:, direction:) ->
      message <> " has the unknown direction " <> direction
    message_schema.UnknownRecord(field:, record:) ->
      field <> " names the unknown record " <> record
  }
}

type Owner {
  Owner(name: String, evidence: String, fields: List(Field))
}

fn owners(schema: Schema) -> List(Owner) {
  list.append(
    list.map(schema.messages, fn(message) {
      Owner(message.name, message.evidence, message.fields)
    }),
    list.map(schema.records, fn(record) {
      Owner(record.name, record.evidence, record.fields)
    }),
  )
}

fn owners_breaches(
  file file: SourceFile,
  schema schema: Schema,
  fact_keys fact_keys: List(String),
) -> List(Breach) {
  let lines = string.split(file.text, "\n")
  list.flat_map(owners(schema), fn(owner) {
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
  list.append(evidence, named_by)
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
