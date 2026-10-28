//// Writes one Gleam module per client game table, and the module that loads
//// them all, from the headers of the client's extracted `.tbl` files.
////
//// `gleam run -m genesis_prime/table_generator write` regenerates
//// `src/genesis_prime/table/` and `src/genesis_prime/table.gleam` from the
//// folder named by `GENESIS_TABLE_DIR`. `gleam run -m genesis_prime/table_generator check`
//// generates into a scratch folder and fails when the committed code differs;
//// it does nothing where `GENESIS_NO_CLIENT=1`, because there is no client to
//// read. Both format what they write with `gleam format`, and both print the
//// columns that name an id of no loaded table, which stay `Int`.

import argv
import envoy
import genesis_prime/table/loader/tbl_file
import genesis_prime/table_folder
import genesis_prime/table_generator/difference.{type Difference}
import genesis_prime/table_generator/id_text
import genesis_prime/table_generator/module_text
import genesis_prime/table_generator/naming
import genesis_prime/table_generator/reference.{type Table, Table}
import genesis_prime/table_generator/registry_text
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Why the code could not be generated.
pub type GenerateError {
  /// The tables folder is not set or cannot be read.
  NoTables(folder: String)
  /// A table file is not a game table file.
  UnreadableTable(file: String)
  /// A table's module could not be written.
  BadTable(file: String, error: module_text.ModuleError)
  /// Two tables have the same module name.
  DuplicateModule(module: String, first: String, second: String)
  /// A table has the module name of the typed ids.
  ReservedModule(module: String, file: String)
  /// A generated file could not be written.
  Unwritable(path: String)
  /// `gleam format` failed on the generated files.
  FormatFailed(output: String)
}

const table_folder = "genesis_prime/table"

const registry_path = "genesis_prime/table.gleam"

/// A table file read: its file name, its header and its names.
type Named {
  Named(file: String, description: tbl_file.Description, table: Table)
}

/// A column that names an id of a table, when no loaded table has that name:
/// the client's table and column names. Its field stays an `Int`.
pub type IdColumn {
  IdColumn(table: String, column: String)
}

/// The generated code and what the generation found.
pub type Generated {
  Generated(
    /// The code as path to text.
    files: Dict(String, String),
    /// The columns that name an id of no loaded table, in table and column
    /// order.
    unmatched: List(IdColumn),
  )
}

/// The generated code as path to text, one entry per `.tbl` file given as file
/// name without extension and bytes, plus the `genesis_prime/table` module and
/// the typed ids of `genesis_prime/table/id`, and the columns that name an id
/// of no loaded table. A path is relative to the source folder:
/// `genesis_prime/table/creature2.gleam`. The text is unformatted.
pub fn generate(
  tables tables: List(#(String, BitArray)),
) -> Result(Generated, GenerateError) {
  use named <- result.try(named_tables(tables))
  let known = list.map(named, fn(table) { table.table })
  let index = reference.index(known)
  use modules <- result.try(
    list.try_map(named, fn(table) {
      module_text.render(
        file: table.file,
        description: table.description,
        table: table.table,
        tables: index,
      )
      |> result.map(fn(rendered) { #(table, rendered) })
      |> result.map_error(BadTable(table.file, _))
    }),
  )
  let registry =
    registry_text.render(list.map(named, fn(table) { table.table.snake }))
  let files =
    list.map(modules, fn(module) {
      #(
        table_folder <> "/" <> { module.0 }.table.snake <> ".gleam",
        { module.1 }.text,
      )
    })
    |> list.prepend(#(
      table_folder <> "/" <> id_text.module_name <> ".gleam",
      id_text.render(known),
    ))
    |> list.prepend(#(registry_path, registry))
    |> dict.from_list
  let unmatched =
    list.flat_map(modules, fn(module) {
      list.map({ module.1 }.unmatched, IdColumn(
        { module.0 }.description.table,
        _,
      ))
    })
  Ok(Generated(files:, unmatched:))
}

/// Reads each file's header and names its table, in file-name order, refusing
/// two tables with one module name and a table named as the typed ids' module.
fn named_tables(
  tables: List(#(String, BitArray)),
) -> Result(List(Named), GenerateError) {
  let sorted = list.sort(tables, fn(a, b) { string.compare(a.0, b.0) })
  list.try_fold(sorted, [], fn(made, table) {
    let #(file, bytes) = table
    use named <- result.try(name_table(file, bytes))
    let module = named.table.snake
    use <- bool.guard(
      when: module == id_text.module_name,
      return: Error(ReservedModule(module:, file:)),
    )
    case list.find(made, fn(other: Named) { other.table.snake == module }) {
      Ok(other) ->
        Error(DuplicateModule(module:, first: other.file, second: file))
      Error(Nil) -> Ok([named, ..made])
    }
  })
  |> result.map(list.reverse)
}

fn name_table(file: String, bytes: BitArray) -> Result(Named, GenerateError) {
  use description <- result.try(
    tbl_file.describe(bytes) |> result.replace_error(UnreadableTable(file)),
  )
  let unnamed = fn(error) { BadTable(file, module_text.Unnamed(error)) }
  use snake <- result.try(
    naming.module_name(description.table) |> result.map_error(unnamed),
  )
  use type_name <- result.try(
    naming.type_name(description.table) |> result.map_error(unnamed),
  )
  Ok(Named(file:, description:, table: Table(snake:, type_name:)))
}

/// The `.tbl` files in the folder, as file name without extension and bytes.
fn read_tables(
  folder: String,
) -> Result(List(#(String, BitArray)), GenerateError) {
  use names <- result.try(
    simplifile.read_directory(folder) |> result.replace_error(NoTables(folder)),
  )
  names
  |> list.filter(string.ends_with(_, ".tbl"))
  |> list.map(string.remove_suffix(_, ".tbl"))
  |> list.try_map(fn(file) {
    simplifile.read_bits(folder <> "/" <> file <> ".tbl")
    |> result.map(fn(bytes) { #(file, bytes) })
    |> result.replace_error(UnreadableTable(file))
  })
}

/// The generated code, formatted by `gleam format`, with what the generation
/// found. The folder is read once.
fn generate_formatted(folder: String) -> Result(Generated, GenerateError) {
  use tables <- result.try(read_tables(folder))
  use generated <- result.try(generate(tables:))
  let scratch = scratch_folder(temporary_folder())
  let formatted = format_in(scratch, generated.files)
  use _ <- result.try(
    simplifile.delete(scratch) |> result.replace_error(Unwritable(scratch)),
  )
  result.map(formatted, fn(files) { Generated(..generated, files:) })
}

fn format_in(
  scratch: String,
  generated: Dict(String, String),
) -> Result(Dict(String, String), GenerateError) {
  let paths = dict.keys(generated)
  use _ <- result.try(write_files(scratch, generated))
  let #(status, output) =
    run("gleam", [
      "format",
      ..list.map(paths, fn(path) { scratch <> "/" <> path })
    ])
  case status {
    0 ->
      list.try_map(paths, fn(path) {
        simplifile.read(scratch <> "/" <> path)
        |> result.map(fn(text) { #(path, text) })
        |> result.replace_error(Unwritable(path))
      })
      |> result.map(dict.from_list)
    _ -> Error(FormatFailed(output))
  }
}

fn write_files(
  root: String,
  files: Dict(String, String),
) -> Result(Nil, GenerateError) {
  list.try_each(dict.to_list(files), fn(file) {
    let path = root <> "/" <> file.0
    let folder = parent(path)
    use _ <- result.try(
      simplifile.create_directory_all(folder)
      |> result.replace_error(Unwritable(file.0)),
    )
    simplifile.write(path, file.1) |> result.replace_error(Unwritable(file.0))
  })
}

/// The folder a path is in.
fn parent(path: String) -> String {
  string.split(path, "/")
  |> list.reverse
  |> list.drop(1)
  |> list.reverse
  |> string.join("/")
}

/// The Gleam files of the table folder and the registry under `source`, as
/// path to text.
fn read_committed(source: String) -> Dict(String, String) {
  let folder = source <> "/" <> table_folder
  let names =
    simplifile.read_directory(folder)
    |> result.unwrap([])
    |> list.filter(string.ends_with(_, ".gleam"))
  let paths =
    list.map(names, fn(name) { table_folder <> "/" <> name })
    |> list.prepend(registry_path)
  list.filter_map(paths, fn(path) {
    simplifile.read(source <> "/" <> path)
    |> result.map(fn(text) { #(path, text) })
  })
  |> dict.from_list
}

/// Generates the code from the `.tbl` files in `folder`, writes it under
/// `source` (the folder that holds `genesis_prime/`) and formats it. A
/// generated file the generator no longer writes is deleted. It gives the
/// columns that name an id of no loaded table.
pub fn write(
  tables folder: String,
  into source: String,
) -> Result(List(IdColumn), GenerateError) {
  use generated <- result.try(generate_formatted(folder))
  let committed = read_committed(source)
  use _ <- result.try(write_files(source, generated.files))
  difference.between(generated: generated.files, committed:)
  |> list.filter_map(fn(difference) {
    case difference {
      difference.Extra(path:) -> Ok(path)
      difference.Changed(..) | difference.Missing(..) -> Error(Nil)
    }
  })
  |> list.try_each(fn(path) {
    simplifile.delete(source <> "/" <> path)
    |> result.replace_error(Unwritable(path))
  })
  |> result.replace(generated.unmatched)
}

/// What a check found: how the committed code differs from the generated, and
/// the columns that name an id of no loaded table.
pub type Checked {
  Checked(differences: List(Difference), unmatched: List(IdColumn))
}

/// Generates the code from the `.tbl` files in `folder` and compares it with
/// the generated files under `source`.
pub fn check(
  tables folder: String,
  against source: String,
) -> Result(Checked, GenerateError) {
  use generated <- result.try(generate_formatted(folder))
  Ok(Checked(
    differences: difference.between(
      generated: generated.files,
      committed: read_committed(source),
    ),
    unmatched: generated.unmatched,
  ))
}

/// The differences a check found, for printing.
fn report(differences: List(Difference)) -> String {
  list.map(differences, fn(found) {
    case found {
      difference.Changed(path:) ->
        path <> " differs from what the generator writes"
      difference.Missing(path:) -> path <> " is not in the repository"
      difference.Extra(path:) ->
        path <> " is generated but the generator no longer writes it"
    }
  })
  |> string.join("\n")
}

/// Runs `write` or `check` as the first argument says, on the folder named by
/// `GENESIS_TABLE_DIR` and the `src` folder. Prints what differs and stops with
/// an error status when the check fails.
pub fn main() -> Nil {
  case argv.load().arguments, envoy.get("GENESIS_NO_CLIENT") {
    ["check"], Ok("1") ->
      io.println(
        "generated tables not compared: GENESIS_NO_CLIENT=1, no client",
      )
    ["check"], _ ->
      finish(check(tables: table_folder.path(), against: "src"), report_check)
    ["write"], _ ->
      finish(write(tables: table_folder.path(), into: "src"), report_write)
    _, _ -> {
      io.println(
        "usage: gleam run -m genesis_prime/table_generator write | check",
      )
      halt_with(2)
    }
  }
}

fn finish(
  outcome: Result(a, GenerateError),
  report_success: fn(a) -> Nil,
) -> Nil {
  case outcome {
    Ok(value) -> report_success(value)
    Error(error) -> {
      io.println("the tables could not be generated: " <> describe(error))
      halt_with(1)
    }
  }
}

/// Prints the columns that name an id of no loaded table.
fn report_unmatched(columns: List(IdColumn)) -> Nil {
  io.println(
    int.to_string(list.length(columns))
    <> " columns name an id of no loaded table and stay Int:",
  )
  list.each(columns, fn(column) {
    io.println("  " <> column.table <> "." <> column.column)
  })
}

fn report_write(unmatched: List(IdColumn)) -> Nil {
  io.println("generated tables written under src/genesis_prime")
  report_unmatched(unmatched)
}

fn report_check(checked: Checked) -> Nil {
  report_unmatched(checked.unmatched)
  case checked.differences {
    [] -> io.println("generated tables match the client's headers")
    differences -> {
      io.println(report(differences))
      io.println(
        "regenerate with: gleam run -m genesis_prime/table_generator write",
      )
      halt_with(1)
    }
  }
}

fn describe(error: GenerateError) -> String {
  case error {
    NoTables(folder:) ->
      "no tables in "
      <> folder
      <> "; run python3.13 -I setup_check/extract_tables.py"
    UnreadableTable(file:) -> file <> ".tbl is not a game table file"
    BadTable(file:, error:) -> file <> ".tbl: " <> describe_module(error)
    DuplicateModule(module:, first:, second:) ->
      first <> ".tbl and " <> second <> ".tbl are both the module " <> module
    ReservedModule(module:, file:) ->
      file <> ".tbl is the module " <> module <> ", which holds the typed ids"
    Unwritable(path:) -> path <> " could not be written"
    FormatFailed(output:) -> "gleam format failed: " <> output
  }
}

fn describe_module(error: module_text.ModuleError) -> String {
  case error {
    module_text.Unnamed(naming.NotAName(client_name:)) ->
      "`" <> client_name <> "` has no Gleam name"
    module_text.NoIdColumn(table:) ->
      table <> " has no 32-bit integer id as its first column"
    module_text.DuplicateField(table:, field:) ->
      table <> " has two columns named " <> field
    module_text.LayoutDiffers(table:, placed:, header:) ->
      table
      <> " places its columns in "
      <> int.to_string(placed)
      <> " bytes, the header says "
      <> int.to_string(header)
    module_text.ReservedTypeName(table:) ->
      table <> " is a type name Gleam or the generated modules use"
  }
}

fn temporary_folder() -> String {
  result.unwrap(envoy.get("TMPDIR"), "/tmp")
}

@external(erlang, "table_generator_ffi", "scratch_folder")
fn scratch_folder(base: String) -> String

@external(erlang, "table_generator_ffi", "run")
fn run(program: String, arguments: List(String)) -> #(Int, String)

@external(erlang, "table_generator_ffi", "halt_with")
fn halt_with(status: Int) -> Nil
