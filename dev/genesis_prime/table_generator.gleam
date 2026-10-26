//// Writes one Gleam module per client game table, and the module that loads
//// them all, from the headers of the client's extracted `.tbl` files.
////
//// `gleam run -m genesis_prime/table_generator write` regenerates
//// `src/genesis_prime/table/` and `src/genesis_prime/table.gleam` from the
//// folder named by `GENESIS_TABLE_DIR`. `gleam run -m genesis_prime/table_generator check`
//// generates into a scratch folder and fails when the committed code differs;
//// it does nothing where `GENESIS_NO_CLIENT=1`, because there is no client to
//// read. Both format what they write with `gleam format`.

import genesis_prime/table/loader/tbl_file
import genesis_prime/table_generator/difference.{type Difference}
import genesis_prime/table_generator/module_text
import genesis_prime/table_generator/naming
import genesis_prime/table_generator/registry_text
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
  /// A generated file could not be written.
  Unwritable(path: String)
  /// `gleam format` failed on the generated files.
  FormatFailed(output: String)
}

const table_folder = "genesis_prime/table"

const registry_path = "genesis_prime/table.gleam"

/// The generated code as path to text, one entry per `.tbl` file given as file
/// name without extension and bytes, plus the `genesis_prime/table` module. A
/// path is relative to the source folder: `genesis_prime/table/creature2.gleam`.
/// The text is unformatted.
pub fn generate(
  tables tables: List(#(String, BitArray)),
) -> Result(Dict(String, String), GenerateError) {
  let sorted = list.sort(tables, fn(a, b) { string.compare(a.0, b.0) })
  use modules <- result.try(
    list.try_fold(sorted, [], fn(made, table) {
      let #(file, bytes) = table
      use #(module, text) <- result.try(module_of(file, bytes))
      case
        list.find(made, fn(other: #(String, String, String)) {
          other.0 == module
        })
      {
        Ok(#(_, first, _)) ->
          Error(DuplicateModule(module:, first:, second: file))
        Error(Nil) -> Ok([#(module, file, text), ..made])
      }
    }),
  )
  let modules = list.reverse(modules)
  let registry =
    registry_text.render(list.map(modules, fn(module) { module.0 }))
  list.map(modules, fn(module) {
    #(table_folder <> "/" <> module.0 <> ".gleam", module.2)
  })
  |> list.prepend(#(registry_path, registry))
  |> dict.from_list
  |> Ok
}

fn module_of(
  file: String,
  bytes: BitArray,
) -> Result(#(String, String), GenerateError) {
  use description <- result.try(
    tbl_file.describe(bytes) |> result.replace_error(UnreadableTable(file)),
  )
  use module <- result.try(
    naming.module_name(description.table)
    |> result.map_error(fn(error) { BadTable(file, module_text.Unnamed(error)) }),
  )
  use text <- result.try(
    module_text.render(file:, description:)
    |> result.map_error(BadTable(file, _)),
  )
  Ok(#(module, text))
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

/// The generated code, formatted by `gleam format`, as path to text.
fn generate_formatted(
  folder: String,
) -> Result(Dict(String, String), GenerateError) {
  use tables <- result.try(read_tables(folder))
  use generated <- result.try(generate(tables:))
  let scratch = scratch_folder()
  let formatted = format_in(scratch, generated)
  use _ <- result.try(
    simplifile.delete(scratch) |> result.replace_error(Unwritable(scratch)),
  )
  formatted
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
/// generated file the generator no longer writes is deleted.
pub fn write(
  tables folder: String,
  into source: String,
) -> Result(Nil, GenerateError) {
  use generated <- result.try(generate_formatted(folder))
  let committed = read_committed(source)
  use _ <- result.try(write_files(source, generated))
  difference.between(generated:, committed:)
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
}

/// Generates the code from the `.tbl` files in `folder` and compares it with
/// the generated files under `source`.
pub fn check(
  tables folder: String,
  against source: String,
) -> Result(List(Difference), GenerateError) {
  use generated <- result.try(generate_formatted(folder))
  Ok(difference.between(generated:, committed: read_committed(source)))
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
  case arguments(), getenv("GENESIS_NO_CLIENT") {
    ["check"], Ok("1") ->
      io.println(
        "generated tables not compared: GENESIS_NO_CLIENT=1, no client",
      )
    ["check"], _ ->
      finish(check(tables: tables_folder(), against: "src"), report_check)
    ["write"], _ ->
      finish(write(tables: tables_folder(), into: "src"), report_write)
    _, _ -> {
      io.println(
        "usage: gleam run -m genesis_prime/table_generator write | check",
      )
      halt_with(2)
    }
  }
}

fn tables_folder() -> String {
  case getenv("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      case getenv("GENESIS_HOME"), getenv("HOME") {
        Ok(home), _ -> home <> "/tables"
        Error(Nil), Ok(home) -> home <> "/.genesis-prime/tables"
        Error(Nil), Error(Nil) -> "tables"
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

fn report_write(_written: Nil) -> Nil {
  io.println("generated tables written under src/genesis_prime")
}

fn report_check(differences: List(Difference)) -> Nil {
  case differences {
    [] -> io.println("generated tables match the client's headers")
    _ -> {
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

@external(erlang, "table_generator_ffi", "arguments")
fn arguments() -> List(String)

@external(erlang, "table_generator_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)

@external(erlang, "table_generator_ffi", "scratch_folder")
fn scratch_folder() -> String

@external(erlang, "table_generator_ffi", "run")
fn run(program: String, arguments: List(String)) -> #(Int, String)

@external(erlang, "table_generator_ffi", "halt_with")
fn halt_with(status: Int) -> Nil
