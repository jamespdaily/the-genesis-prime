//// The text of one generated table module: the row type, the schema, the
//// record decoder and the functions that read the table from a load. The text
//// is unformatted; the generator runs `gleam format` over what it writes.

import genesis_prime/table/loader/tbl_file
import genesis_prime/table_generator/column_sign.{type ColumnSign}
import genesis_prime/table_generator/difference
import genesis_prime/table_generator/naming
import genesis_prime/table_generator/reference.{type Table}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Why a table's module could not be written.
pub type ModuleError {
  /// A table or column name has no Gleam name.
  Unnamed(error: naming.NameError)
  /// The first column is not a 32-bit integer named `id`, so the table has no
  /// id to index its rows by.
  NoIdColumn(table: String)
  /// Two columns of a table have the same field name.
  DuplicateField(table: String, field: String)
  /// The placement rule gives another record size than the file's header.
  LayoutDiffers(table: String, placed: Int, header: Int)
  /// The type name is one a generated module already uses.
  ReservedTypeName(table: String)
}

/// Gleam's own type names, which a table's type may not be.
const prelude_types = [
  "BitArray", "Bool", "Float", "Int", "List", "Nil", "Result", "String",
  "UtfCodepoint",
]

/// A column with its Gleam field name and its place in the record.
type NamedField {
  NamedField(position: Int, field: String, placed: tbl_file.Field)
}

/// A function that gives a column's integer as the typed id of the table whose
/// id it holds.
type Reader {
  Reader(field: String, column: String, table: Table)
}

/// A table's module, and the columns of the table that name an id of no
/// loaded table, by the client's column names.
pub type Rendered {
  Rendered(text: String, unmatched: List(String))
}

/// The module for a table: `file` is the name of its file without `.tbl`,
/// `table` is the table's names, and `tables` is every table that is loaded,
/// which the columns that hold their ids are matched against. `signs` gives
/// the 32-bit columns the client reads unsigned.
pub fn render(
  file file: String,
  description description: tbl_file.Description,
  table own: Table,
  tables tables: Dict(String, Table),
  signs signs: List(ColumnSign),
) -> Result(Rendered, ModuleError) {
  let table = description.table
  let type_name = own.type_name
  use <- bool.guard(
    when: list.contains(prelude_types, type_name),
    return: Error(ReservedTypeName(table)),
  )
  use placed <- result.try(
    tbl_file.fields(description)
    |> result.map_error(fn(error) {
      case error {
        tbl_file.NoIdColumn -> NoIdColumn(table)
        tbl_file.NotPlaced(tbl_file.RecordSizeNotPlaced(placed:, header:)) ->
          LayoutDiffers(table:, placed:, header:)
      }
    }),
  )
  use fields <- result.try(name_fields(table, placed))
  let #(readers, unmatched) = readers(fields:, own:, tables:)
  let text =
    string.join(
      [
        header(file, table),
        imports(fields:, own:, readers:),
        row_type(type_name:, table:, fields:),
        schema(file, description),
        entry(type_name, table),
        get(own, table),
        all(type_name, table),
        list.map(readers, reader(type_name, _)) |> string.join("\n"),
        row_id(type_name),
        decoder(type_name:, table:, fields:, signs:),
      ],
      "\n",
    )
  Ok(Rendered(text:, unmatched:))
}

/// The readers of a table: its own `id` column, and each 32-bit integer column
/// whose name follows another table's name with `_id`; and the client names of
/// the 32-bit integer columns that have the word `id` and follow no table's
/// name.
fn readers(
  fields fields: List(NamedField),
  own own: Table,
  tables tables: Dict(String, Table),
) -> #(List(Reader), List(String)) {
  let #(readers, unmatched) =
    list.fold(fields, #([], []), fn(found, named) {
      let #(readers, unmatched) = found
      let column = named.placed.column
      case column.column_type, named.field {
        tbl_file.Integer32, "id" -> #(
          [
            Reader(field: named.field, column: column.name, table: own),
            ..readers
          ],
          unmatched,
        )
        tbl_file.Integer32, field ->
          case reference.referenced_table(column: field, tables:) {
            Ok(table) -> #(
              [Reader(field:, column: column.name, table:), ..readers],
              unmatched,
            )
            Error(Nil) ->
              case reference.names_an_id(field) {
                True -> #(readers, [column.name, ..unmatched])
                False -> #(readers, unmatched)
              }
          }
        _, _ -> found
      }
    })
  #(list.reverse(readers), list.reverse(unmatched))
}

/// The id type of a table, which `genesis_prime/table/id` holds.
fn id_type(table: Table) -> String {
  table.type_name <> "Id"
}

fn reader(type_name: String, reader: Reader) -> String {
  let description = case reader.field {
    "id" -> "/// The row's own id, as the typed id of its table."
    _ ->
      "/// The id in the "
      <> reader.column
      <> " column, as the typed id of the "
      <> reader.table.type_name
      <> " table."
  }
  string.join(
    [
      description,
      "pub fn "
        <> reader.field
        <> "(row: "
        <> type_name
        <> ") -> "
        <> id_type(reader.table)
        <> " {",
      "  " <> id_type(reader.table) <> "(row." <> reader.field <> ")",
      "}",
      "",
    ],
    "\n",
  )
}

/// Names every field, refusing two with one name.
fn name_fields(
  table: String,
  placed: List(tbl_file.Field),
) -> Result(List(NamedField), ModuleError) {
  list.try_fold(
    list.index_map(placed, fn(field, position) { #(position, field) }),
    [],
    fn(named, entry) {
      let #(position, field) = entry
      use name <- result.try(
        naming.field_name(field.column.name) |> result.map_error(Unnamed),
      )
      case list.any(named, fn(other: NamedField) { other.field == name }) {
        True -> Error(DuplicateField(table:, field: name))
        False ->
          Ok([NamedField(position:, field: name, placed: field), ..named])
      }
    },
  )
  |> result.map(list.reverse)
}

fn header(file: String, table: String) -> String {
  string.join(
    [
      difference.generated_marker <> " from the client's DB/" <> file <> ".tbl.",
      "//// The client's "
        <> table
        <> " table: its row type, its schema and the decoder",
      "//// of its records. The layout is the client's (game_table.file, game_table.schema",
      "//// and game_table.column_type in the fact file); the table loads only when its",
      "//// file's header equals `schema`. Rows keep plain `Int` ids; `get` and the readers give the typed ids of `genesis_prime/table/id`, whose doc says why.",
      "",
    ],
    "\n",
  )
}

fn imports(
  fields fields: List(NamedField),
  own own: Table,
  readers readers: List(Reader),
) -> String {
  let converts = list.any(fields, fn(named) { converted(named.placed.column) })
  let id_items =
    [own, ..list.map(readers, fn(reader) { reader.table })]
    |> list.map(id_type)
    |> list.unique
    |> list.sort(string.compare)
    |> list.flat_map(fn(name) { ["type " <> name, name] })
  string.join(
    [
      "import genesis_prime/table/id.{" <> string.join(id_items, ", ") <> "}",
      "import genesis_prime/table/loader/store",
      "import genesis_prime/table/loader/tbl_file",
      ..case converts {
        True -> ["import gleam/result"]
        False -> []
      }
    ],
    "\n",
  )
  <> "\n"
}

/// Whether a column's value is converted after the record is matched.
fn converted(column: tbl_file.Column) -> Bool {
  case column.column_type {
    tbl_file.Boolean32 | tbl_file.Utf16Text -> True
    tbl_file.Integer32 | tbl_file.Float32 | tbl_file.Integer64 -> False
  }
}

fn gleam_type(column: tbl_file.Column) -> String {
  case column.column_type {
    tbl_file.Integer32 | tbl_file.Integer64 -> "Int"
    tbl_file.Float32 -> "Float"
    tbl_file.Boolean32 -> "Bool"
    tbl_file.Utf16Text -> "String"
  }
}

fn row_type(
  type_name type_name: String,
  table table: String,
  fields fields: List(NamedField),
) -> String {
  let labels =
    list.map(fields, fn(named) {
      "    " <> named.field <> ": " <> gleam_type(named.placed.column) <> ","
    })
  string.join(
    [
      "/// One row of the client's " <> table <> " table.",
      "pub type " <> type_name <> " {",
      "  " <> type_name <> "(",
      string.join(labels, "\n"),
      "  )",
      "}",
      "",
    ],
    "\n",
  )
}

fn column_type_name(column: tbl_file.Column) -> String {
  case column.column_type {
    tbl_file.Integer32 -> "Integer32"
    tbl_file.Float32 -> "Float32"
    tbl_file.Boolean32 -> "Boolean32"
    tbl_file.Integer64 -> "Integer64"
    tbl_file.Utf16Text -> "Utf16Text"
  }
}

fn schema(file: String, description: tbl_file.Description) -> String {
  let columns =
    list.map(description.columns, fn(column) {
      "    tbl_file.Column(name: \""
      <> column.name
      <> "\", column_type: tbl_file."
      <> column_type_name(column)
      <> "),"
    })
  string.join(
    [
      "/// The layout of the client's "
        <> description.table
        <> " table: its name, record size and",
      "/// columns, which a file must equal to be loaded.",
      "pub const schema = tbl_file.Schema(",
      "  table: \"" <> description.table <> "\",",
      "  file: \"" <> file <> "\",",
      "  record_size: " <> int.to_string(description.record_size) <> ",",
      "  columns: [",
      string.join(columns, "\n"),
      "  ],",
      ")",
      "",
    ],
    "\n",
  )
}

fn entry(type_name: String, table: String) -> String {
  string.join(
    [
      "/// The key of the " <> table <> " table's rows in the store.",
      "const key: store.TableKey("
        <> type_name
        <> ") = store.TableKey(\""
        <> table
        <> "\")",
      "",
      "/// The entry that loads the " <> table <> " table.",
      "pub fn entry() -> store.Entry {",
      "  store.entry(key:, schema:, decode: decode_record, id: row_id)",
      "}",
      "",
    ],
    "\n",
  )
}

fn get(own: Table, table: String) -> String {
  string.join(
    [
      "/// The row of the "
        <> table
        <> " table with the id, or an error when it has none.",
      "pub fn get(",
      "  tables tables: store.Tables,",
      "  id id: " <> id_type(own) <> ",",
      ") -> Result(" <> own.type_name <> ", Nil) {",
      "  store.row(tables, key, id.value)",
      "}",
      "",
    ],
    "\n",
  )
}

fn all(type_name: String, table: String) -> String {
  string.join(
    [
      "/// Every row of the " <> table <> " table, in id order.",
      "pub fn all(tables: store.Tables) -> List(" <> type_name <> ") {",
      "  store.rows(tables, key)",
      "}",
      "",
    ],
    "\n",
  )
}

fn row_id(type_name: String) -> String {
  string.join(
    [
      "fn row_id(row: " <> type_name <> ") -> Int {",
      "  row.id",
      "}",
      "",
    ],
    "\n",
  )
}

/// The record decoder: one pattern over the record's bytes, a segment for each
/// field and a skip for each padding gap, then the conversions of booleans and
/// strings, then the row. Matched values are `c0`, `c1`, and so on, by column.
fn decoder(
  type_name type_name: String,
  table table: String,
  fields fields: List(NamedField),
  signs signs: List(ColumnSign),
) -> String {
  let segments = segments(fields:, table:, signs:, position: 0, made: [])
  let conversions =
    list.filter_map(fields, fn(named) {
      let variable = variable(named)
      let column = named.placed.column
      case column.column_type {
        tbl_file.Boolean32 ->
          Ok(
            "      use "
            <> variable
            <> " <- result.try(tbl_file.boolean("
            <> variable
            <> ", \""
            <> column.name
            <> "\"))",
          )
        tbl_file.Utf16Text ->
          Ok(
            "      use "
            <> variable
            <> " <- result.try(tbl_file.text(strings, "
            <> variable
            <> ", \""
            <> column.name
            <> "\"))",
          )
        tbl_file.Integer32 | tbl_file.Float32 | tbl_file.Integer64 -> Error(Nil)
      }
    })
  let strings_parameter = case
    list.any(fields, fn(named) {
      named.placed.column.column_type == tbl_file.Utf16Text
    })
  {
    True -> "strings"
    False -> "_strings"
  }
  let arguments =
    list.map(fields, fn(named) {
      "        " <> named.field <> ": " <> variable(named) <> ","
    })
  string.join(
    [
      "fn decode_record(",
      "  record record: BitArray,",
      "  strings " <> strings_parameter <> ": tbl_file.Strings,",
      ") -> Result(" <> type_name <> ", tbl_file.RecordError) {",
      "  case record {",
      "    <<",
      string.join(segments, "\n"),
      "      _:bits,",
      "    >> -> {",
      string.join(conversions, "\n"),
      "      Ok(" <> type_name <> "(",
      string.join(arguments, "\n"),
      "      ))",
      "    }",
      "    _ -> Error(tbl_file.NotARecord)",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn variable(named: NamedField) -> String {
  "c" <> int.to_string(named.position)
}

/// The pattern segments of the fields in record order, each preceded by a skip
/// over any padding before it. A 32-bit integer column is unsigned when `signs`
/// lists it so for the client's `table`, signed otherwise.
fn segments(
  fields fields: List(NamedField),
  table table: String,
  signs signs: List(ColumnSign),
  position position: Int,
  made made: List(String),
) -> List(String) {
  case fields {
    [] -> list.reverse(made)
    [named, ..rest] -> {
      let offset = named.placed.offset
      let skip = case offset > position {
        True -> [
          "      _:size(" <> int.to_string({ offset - position } * 8) <> "),",
        ]
        False -> []
      }
      let #(size, options) = case named.placed.column.column_type {
        tbl_file.Integer32 ->
          case
            column_sign.is_unsigned(
              signs:,
              table:,
              column: named.placed.column.name,
            )
          {
            True -> #(4, "size(32)-little")
            False -> #(4, "size(32)-little-signed")
          }
        tbl_file.Float32 -> #(4, "size(32)-little-float")
        tbl_file.Boolean32 -> #(4, "size(32)-little")
        tbl_file.Integer64 -> #(8, "size(64)-little-signed")
        tbl_file.Utf16Text -> #(8, "size(64)-little")
      }
      let segment = "      " <> variable(named) <> ":" <> options <> ","
      segments(
        fields: rest,
        table:,
        signs:,
        position: offset + size,
        made: list.append([segment, ..skip], made),
      )
    }
  }
}
