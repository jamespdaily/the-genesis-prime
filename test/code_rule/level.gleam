//// The levels rule: every hand-written module of `src` has one row in the
//// levels table (`levels.txt`, `module level`), and a module of an
//// enforced level imports only what its level allows. A module's level says
//// which part of the server it belongs to, so a module of one process's
//// state cannot reach into another's.
////
//// Each line below is a level, the levels whose modules it may import, and
//// the levels whose message modules (its `contract`) it may import, since
//// what crosses between processes is a typed message. A level always may
//// import its own modules.
////
//// level data      imports data messages of
//// level platform  imports data platform messages of
//// level shared    imports data platform shared messages of
//// level link      imports data platform shared link messages of character unit
//// level character imports data platform shared character messages of unit map link
//// level unit      imports data platform shared unit messages of character map link
//// level map       imports data platform shared map messages of unit
//// level host      imports data platform shared link character unit map host messages of
////
//// Enforced levels: data platform
////
//// - data: client tables, content tables and readers of world data.
//// - platform: the process model (step, service, store, hand-off, wire
////   recording) and the ids that name a process.
//// - shared: pure vocabulary and rules read by more than one level.
//// - link, character, unit, map: the connection, one character's rows, the
////   body in a map run, and the relations between units.
//// - host: a module that composes the levels, or one whose imports reach
////   across them today. It may import every level and is not checked. The
////   levels that are not enforced are not checked either; a module of the
////   enforced levels may import only the levels the lines above give it.
////
//// A row for a module of `src` outside the generated `message/` and `table/`
//// folders and the generated `sql` modules is required, once, in order; a
//// row for a module that is gone is a breach at the row. An import of a
//// module with no row (a library, a generated module) is not checked.

import code_rule/list_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string

/// A level of the server.
pub type Level {
  Data
  Platform
  Shared
  Link
  Character
  Unit
  Map
  Host
}

/// A row of the levels table: the module's full name, its level and the row's
/// line of the table (from 1).
pub type Row {
  Row(module: String, level: Level, line: Int)
}

/// The levels table.
pub const list_path = "test/code_rule/levels.txt"

/// The levels whose imports are checked. Every other level is read from the
/// table but its imports are not checked.
pub const enforced: List(Level) = [Data, Platform]

/// What one level may import: the levels whose modules it may import, and the
/// levels whose message modules it may import.
type Imports {
  Imports(modules: List(Level), messages: List(Level))
}

/// Every level.
pub fn all_levels() -> List(Level) {
  [Data, Platform, Shared, Link, Character, Unit, Map, Host]
}

/// The level's word in the table and in the diagram.
pub fn name(level: Level) -> String {
  case level {
    Data -> "data"
    Platform -> "platform"
    Shared -> "shared"
    Link -> "link"
    Character -> "character"
    Unit -> "unit"
    Map -> "map"
    Host -> "host"
  }
}

fn imports(level: Level) -> Imports {
  let above = [Data, Platform, Shared]
  case level {
    Data -> Imports([Data], [])
    Platform -> Imports([Data, Platform], [])
    Shared -> Imports(above, [])
    Link -> Imports(list.append(above, [Link]), [Character, Unit])
    Character -> Imports(list.append(above, [Character]), [Unit, Map, Link])
    Unit -> Imports(list.append(above, [Unit]), [Character, Map, Link])
    Map -> Imports(list.append(above, [Map]), [Unit])
    Host -> Imports(all_levels(), [])
  }
}

/// The levels whose modules the level may import, itself among them.
pub fn imported_levels(level: Level) -> List(Level) {
  imports(level).modules
}

/// The levels whose message modules the level may import.
pub fn message_levels(level: Level) -> List(Level) {
  imports(level).messages
}

/// The message modules of a level: the only modules of it that a level
/// talking to it may import.
pub fn contract(level: Level) -> List(String) {
  case level {
    Link -> ["genesis_prime/link/message"]
    Character -> ["genesis_prime/character/message"]
    Unit -> ["genesis_prime/unit/message"]
    Map -> ["genesis_prime/map/message"]
    Data | Platform | Shared | Host -> []
  }
}

fn from_name(word: String) -> Option(Level) {
  list.find(all_levels(), fn(level) { name(level) == word })
  |> option.from_result
}

/// The rows of the table as its file writes them: `module level` on each
/// line.
pub fn parse_rows(text text: String) -> List(Row) {
  list_file.rows(text)
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let assert [module, word] = string.split(row, " ")
      as list_file.bad_row(line:, what: "is not a module and a level")
    let assert Some(level) = from_name(word)
      as list_file.bad_row(line:, what: "names no level")
    Row(module:, level:, line:)
  })
}

/// The module name of each import of the file and the line of the import
/// (from 1), in the order written.
pub fn imports_of(file file: SourceFile) -> List(#(Int, String)) {
  let imported = syntax.parse(file).imports
  let lines =
    syntax.lines_of(
      text: file.text,
      byte_offsets: list.map(imported, fn(definition) {
        definition.definition.location.start
      }),
    )
  list.zip(
    lines,
    list.map(imported, fn(definition) { definition.definition.module }),
  )
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

/// Whether the path is a module whose row the table must hold: a `.gleam`
/// file of `src/genesis_prime` (or the package's own module) that is not
/// generated message, table or SQL code.
fn needs_row(path: String) -> Bool {
  !string.contains(path, "/message/")
  && !string.contains(path, "/table/")
  && !string.ends_with(path, "/sql.gleam")
}

fn module_of(file: SourceFile) -> String {
  syntax.module_name(file.path)
}

/// A breach for each hand-written module with no row, at the module's first
/// line; each row for a module that is not among the files, at the row's
/// line of the table; and each row out of order or repeated.
pub fn table_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
) -> List(Breach) {
  let modules =
    files
    |> list.filter(fn(file) { needs_row(file.path) })
  let unlisted =
    list.filter_map(modules, fn(file) {
      case list.any(rows, fn(row) { row.module == module_of(file) }) {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: file.path,
            line: 1,
            rule: module_of(file) <> " has no row in the levels table",
          ))
      }
    })
  let gone =
    list.filter_map(rows, fn(row) {
      case list.any(modules, fn(file) { module_of(file) == row.module }) {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: list_path,
            line: row.line,
            rule: row.module <> " is a row for a module that is not in src",
          ))
      }
    })
  let disordered =
    list_file.disordered(
      rows:,
      compare: fn(before, row) { string.compare(before.module, row.module) },
      path: list_path,
      line: fn(row) { row.line },
      name: fn(row) { row.module },
      what: "is out of order or repeated in the levels table",
    )
  list.flatten([unlisted, gone, disordered])
}

/// A breach, at its line, for each import of a module of an enforced level
/// that the matrix forbids: a module that has a row, at a level the importer's
/// level may not import, unless it is a message module of a level the
/// importer talks to.
pub fn import_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
  enforced enforced: List(Level),
) -> List(Breach) {
  list.flat_map(files, fn(file) {
    case list.find(rows, fn(row) { row.module == module_of(file) }) {
      Ok(Row(level: from, ..)) ->
        case list.contains(enforced, from) {
          True ->
            list.filter_map(imports_of(file:), fn(found) {
              breach_of_import(file:, rows:, from:, found:)
            })
          False -> []
        }
      Error(Nil) -> []
    }
  })
}

/// The breach of one import `found` (its line and module) of a file of level
/// `from`, when the imported module has a row and the matrix forbids it.
fn breach_of_import(
  file file: SourceFile,
  rows rows: List(Row),
  from from: Level,
  found found: #(Int, String),
) -> Result(Breach, Nil) {
  let #(line, imported) = found
  use row <- result.try(list.find(rows, fn(row) { row.module == imported }))
  case may_import(from:, to: row.level, module: imported) {
    True -> Error(Nil)
    False ->
      Ok(Breach(
        path: file.path,
        line:,
        rule: name(from)
          <> " module "
          <> module_of(file)
          <> " imports the "
          <> name(row.level)
          <> " module "
          <> imported
          <> ", and a "
          <> name(from)
          <> " module may import "
          <> string.join(list.map(imported_levels(from), name), ", ")
          <> " modules and the message modules of "
          <> string.join(list.map(message_levels(from), name), ", ")
          <> " (listed in contract)",
      ))
  }
}

fn may_import(from from: Level, to to: Level, module module: String) -> Bool {
  list.contains(imported_levels(from), to)
  || {
    list.contains(message_levels(from), to)
    && list.contains(contract(to), module)
  }
}
