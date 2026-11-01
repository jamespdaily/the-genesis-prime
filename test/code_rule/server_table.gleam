//// The server's table list: the tables the server loads are the tables its
//// rules read. The list is the generated table modules that
//// `genesis_prime/table/loader/server_table` imports; a table is read by a
//// module of `src/` outside `genesis_prime/table/` that imports its module.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/list
import gleam/set
import gleam/string

/// The path of the module that lists the server's tables.
pub const list_path = "src/genesis_prime/table/loader/server_table.gleam"

/// The path of the generated module that imports every table module of the
/// client.
pub const registry_path = "src/genesis_prime/table.gleam"

const table_folder = "genesis_prime/table/"

/// Each import of a table module in `src/` outside `genesis_prime/table/`
/// whose table the list does not hold, and each table the list holds that no
/// such module imports. A table module is one the registry imports, outside
/// the loader's folder. The registry and the list are among `files`; when
/// either is missing, the breach says so.
pub fn breaches(files files: List(SourceFile)) -> List(Breach) {
  case find(files, registry_path), find(files, list_path) {
    Ok(registry), Ok(listing) -> {
      let tables = set.from_list(table_modules(registry))
      let listed = set.from_list(table_modules(listing))
      let reads = reads(files:, tables:)
      let unlisted =
        list.filter_map(reads, fn(read) {
          case set.contains(listed, read.module) {
            True -> Error(Nil)
            False ->
              Ok(Breach(
                path: read.path,
                line: read.line,
                rule: "a module reads the table "
                  <> read.module
                  <> ", which the server's table list does not hold",
              ))
          }
        })
      let read_modules =
        set.from_list(list.map(reads, fn(read) { read.module }))
      let unread =
        set.to_list(listed)
        |> list.sort(string.compare)
        |> list.filter(fn(module) { !set.contains(read_modules, module) })
        |> list.map(fn(module) {
          Breach(
            path: list_path,
            line: 1,
            rule: "the server's table list holds the table "
              <> module
              <> ", which no module outside the table folder reads",
          )
        })
      list.append(unlisted, unread)
    }
    Error(Nil), _ -> [not_found(registry_path)]
    Ok(_), Error(Nil) -> [not_found(list_path)]
  }
}

fn find(files: List(SourceFile), path: String) -> Result(SourceFile, Nil) {
  list.find(files, fn(file) { file.path == path })
}

fn not_found(path: String) -> Breach {
  Breach(path:, line: 1, rule: "the file is not among the sources")
}

/// The table modules a file imports, as written in its imports: everything
/// under `genesis_prime/table/` outside the loader's folder.
fn table_modules(file: SourceFile) -> List(String) {
  list.filter(syntax.imported_modules(file), fn(module) {
    string.starts_with(module, table_folder)
    && !string.starts_with(module, table_folder <> "loader/")
  })
}

type Read {
  Read(path: String, line: Int, module: String)
}

/// Every import of a table module by a file of `src/` outside the table
/// folder and the registry.
fn reads(
  files files: List(SourceFile),
  tables tables: set.Set(String),
) -> List(Read) {
  files
  |> list.filter(fn(file) {
    string.starts_with(file.path, "src/")
    && !string.starts_with(file.path, "src/" <> table_folder)
    && file.path != registry_path
  })
  |> list.flat_map(fn(file) {
    list.filter_map(syntax.parse(file).imports, fn(definition) {
      let import_ = definition.definition
      case set.contains(tables, import_.module) {
        False -> Error(Nil)
        True ->
          Ok(Read(
            path: file.path,
            line: syntax.line_of(file.text, import_.location.start),
            module: import_.module,
          ))
      }
    })
  })
}
