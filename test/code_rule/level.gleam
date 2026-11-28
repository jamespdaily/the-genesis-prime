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
//// level root      imports data platform shared link character unit map host root messages of
////
//// Enforced levels: data platform shared map
////
//// - data: client tables, content tables and readers of world data, and the
////   vocabulary a table row decodes into.
//// - platform: the process model (step, service, store, hand-off, wire
////   recording), the ids that name a process, and the connection modules
////   the STS, auth and game listeners share.
//// - shared: pure vocabulary and rules read by more than one level. Its
////   modules live in `genesis_prime/shared/` and no module outside that folder
////   has this level (`shared_folder_breaches`).
//// - link, character, unit: the game connection, one character's rows and the
////   body in a map run.
//// - map: the relations between units, spawns, respawn and unit ids. It imports
////   only data, platform, shared and its own modules, and the message modules of
////   the levels it talks to.
//// - host: the level of the rule that composes the levels. No module has it.
//// - root: the modules that start the server and its tables and import every
////   level. No module of another level imports a root module, enforced or
////   not (`root_breaches`).
////
//// The levels that are not enforced are not checked; a module of the
//// enforced levels may import only the levels the lines above give it, except
//// the imports listed in `level_imports.txt` (`importer imported`). The list
//// can only shrink: a listed import that the matrix allows or that is gone is
//// a breach at its row, and a forbidden import not listed is a breach at the
//// import.
////
//// A module of `src` needs one row, in order, unless its first line says it
//// is generated (`generated_markers`); a row for a module that is gone is a
//// breach at the row. An import of a module with no row (a library, a
//// generated module) is not checked.

import code_rule/list_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
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
  Root
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
pub const enforced: List(Level) = [Data, Platform, Shared, Map]

/// What one level may import: the levels whose modules it may import, and the
/// levels whose message modules it may import.
type Imports {
  Imports(modules: List(Level), messages: List(Level))
}

/// Every level.
pub fn all_levels() -> List(Level) {
  [Data, Platform, Shared, Link, Character, Unit, Map, Host, Root]
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
    Root -> "root"
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
    Host -> Imports(list.filter(all_levels(), fn(each) { each != Root }), [])
    Root -> Imports(all_levels(), [])
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
    Data | Platform | Shared | Host | Root -> []
  }
}

fn from_name(word: String) -> Option(Level) {
  list.find(all_levels(), fn(level) { name(level) == word })
  |> option.from_result
}

/// The rows of the table as its file writes them: `module level` on each
/// line.
pub fn parse_rows(text text: String) -> List(Row) {
  list_file.pairs(text:, what: "is not a module and a level")
  |> list.map(fn(entry) {
    let #(module, word, line) = entry
    let assert Some(level) = from_name(word)
      as list_file.bad_row(line:, what: "names no level")
    Row(module:, level:, line:)
  })
}

/// The module name of each import of the file and the line of the import
/// (from 1), in the order written.
pub fn imports_of(file file: SourceFile) -> List(#(Int, String)) {
  let imported = syntax.import_offsets(file)
  let lines =
    syntax.lines_of(
      text: file.text,
      byte_offsets: list.map(imported, fn(found) { found.0 }),
    )
  list.zip(lines, list.map(imported, fn(found) { found.1 }))
}

/// A forbidden import that stays: the importing module, the module it
/// imports, and the line of the list's row (from 1).
pub type Allowed {
  Allowed(importer: String, imported: String, line: Int)
}

/// The forbidden imports the list allows.
pub const allowed_path = "test/code_rule/level_imports.txt"

/// The rows of the list of allowed imports as its file writes them:
/// `importer imported` on each line.
pub fn parse_allowed(text text: String) -> List(Allowed) {
  list_file.pairs(text:, what: "is not an importer and an import")
  |> list.map(fn(entry) {
    let #(importer, imported, line) = entry
    Allowed(importer:, imported:, line:)
  })
}

/// The first line of a generated module names its generator or says it holds
/// the code of its queries; no row is kept for such a module.
pub const generated_markers = [
  "//// Generated", "//// This module contains the code to run the sql queries",
]

/// Whether the module's first line marks it as generated.
pub fn is_generated(file: SourceFile) -> Bool {
  let first = case string.split_once(file.text, "\n") {
    Ok(#(first, _)) -> first
    Error(Nil) -> file.text
  }
  list.any(generated_markers, string.starts_with(first, _))
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
    |> list.filter(fn(file) { !is_generated(file) })
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
/// that the matrix forbids and the list does not allow: a module that has a
/// row, at a level the importer's level may not import, unless it is a
/// message module of a level the importer talks to. An allowed import that
/// the matrix permits or that is gone is a breach at its row of the list, and
/// so is a row out of order or repeated.
pub fn import_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
  enforced enforced: List(Level),
  allowed allowed: List(Allowed),
) -> List(Breach) {
  let forbidden = forbidden_imports(files:, rows:, enforced:)
  let unlisted =
    list.filter_map(forbidden, fn(found) {
      let #(importer, imported, breach) = found
      case
        list.any(allowed, fn(each) {
          each.importer == importer && each.imported == imported
        })
      {
        True -> Error(Nil)
        False -> Ok(breach)
      }
    })
  let gone =
    list.filter_map(allowed, fn(each) {
      case
        list.any(forbidden, fn(found) {
          found.0 == each.importer && found.1 == each.imported
        })
      {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: allowed_path,
            line: each.line,
            rule: each.importer
              <> " does not import "
              <> each.imported
              <> " against the matrix, so its row is gone from the list",
          ))
      }
    })
  let disordered =
    list_file.disordered(
      rows: allowed,
      compare: fn(before, each) {
        string.compare(
          before.importer <> " " <> before.imported,
          each.importer <> " " <> each.imported,
        )
      },
      path: allowed_path,
      line: fn(each) { each.line },
      name: fn(each) { each.importer <> " " <> each.imported },
      what: "is out of order or repeated in the list of allowed imports",
    )
  list.flatten([unlisted, gone, disordered])
}

/// The shared per-file import scan: for each file whose module has a row, each
/// import `check` turns into a breach. `check` gets the importer's file and level
/// and the import (its line and module); a file with no row has no breach. Gives
/// the importer's module, the imported module and the breach.
pub fn import_breaches_by(
  files files: List(SourceFile),
  rows rows: List(Row),
  check check: fn(SourceFile, Level, #(Int, String)) -> Result(Breach, Nil),
) -> List(#(String, String, Breach)) {
  list.flat_map(files, fn(file) {
    case level_of(rows:, module: module_of(file)) {
      Ok(from) ->
        list.filter_map(imports_of(file:), fn(found) {
          check(file, from, found)
          |> result.map(fn(breach) { #(module_of(file), found.1, breach) })
        })
      Error(Nil) -> []
    }
  })
}

/// Each import of a module of an enforced level that the matrix forbids:
/// the importer, the imported module and the breach.
fn forbidden_imports(
  files files: List(SourceFile),
  rows rows: List(Row),
  enforced enforced: List(Level),
) -> List(#(String, String, Breach)) {
  import_breaches_by(files:, rows:, check: fn(file, from, found) {
    case list.contains(enforced, from) {
      True -> breach_of_import(file:, rows:, from:, found:)
      False -> Error(Nil)
    }
  })
}

/// A breach, at its line, for each import of a root module by a module of
/// another level, whether or not that level is enforced.
pub fn root_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
) -> List(Breach) {
  import_breaches_by(files:, rows:, check: fn(file, from, found) {
    case from {
      Root -> Error(Nil)
      _ -> root_import_breach(file:, rows:, from:, found:)
    }
  })
  |> list.map(fn(found) { found.2 })
}

/// The level of a module's row, when it has one.
pub fn level_of(
  rows rows: List(Row),
  module module: String,
) -> Result(Level, Nil) {
  list.find(rows, fn(row) { row.module == module })
  |> result.map(fn(row) { row.level })
}

/// The breach of one import `found` (its line and module) of a file of level
/// `from`, when the imported module is a root module.
fn root_import_breach(
  file file: SourceFile,
  rows rows: List(Row),
  from from: Level,
  found found: #(Int, String),
) -> Result(Breach, Nil) {
  let #(line, imported) = found
  use level <- result.try(level_of(rows:, module: imported))
  case level {
    Root ->
      Ok(Breach(
        path: file.path,
        line:,
        rule: name(from)
          <> " module "
          <> module_of(file)
          <> " imports the root module "
          <> imported
          <> ", which only root modules may import",
      ))
    _ -> Error(Nil)
  }
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

/// The folder every shared module lives in.
pub const shared_folder = "genesis_prime/shared/"

/// A breach for each row at level shared whose module is outside the shared
/// folder (at the row's line of the table), and for each file inside the
/// shared folder whose row names another level (at the file's first line).
pub fn shared_folder_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
) -> List(Breach) {
  let misplaced =
    list.filter_map(rows, fn(row) {
      case
        row.level == Shared && !string.starts_with(row.module, shared_folder)
      {
        True ->
          Ok(Breach(
            path: list_path,
            line: row.line,
            rule: row.module
              <> " is a shared row for a module outside "
              <> shared_folder,
          ))
        False -> Error(Nil)
      }
    })
  let stray =
    list.filter_map(files, fn(file) {
      let module = module_of(file)
      case string.starts_with(module, shared_folder), level_of(rows:, module:) {
        True, Ok(found) if found != Shared ->
          Ok(Breach(
            path: file.path,
            line: 1,
            rule: module
              <> " is under "
              <> shared_folder
              <> " and its row says "
              <> name(found),
          ))
        _, _ -> Error(Nil)
      }
    })
  list.append(misplaced, stray)
}
