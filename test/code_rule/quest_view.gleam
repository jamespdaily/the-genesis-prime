//// The quest view rules: the read-only snapshot of a quest log
//// (genesis_prime/shared/quest_view) is built only by the log's own module, and
//// the modules of the units and the map, and the shared modules, never import the
//// log, so none of them can read it, change it or make a view.
////
//// - A module whose row in the levels table is unit, map or shared and that
////   imports `genesis_prime/game/quest_log` is a breach at the import.
//// - A call of `quest_view.of` (by the module's name, its alias or an unqualified
////   import) in any module but the quest log is a breach at the call.

import code_rule/level.{type Level, type Row, Map, Shared, Unit}
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list

/// The module that owns the log and builds its view.
pub const quest_log_module = "genesis_prime/game/quest_log"

/// The module that holds the view.
pub const quest_view_module = "genesis_prime/shared/quest_view"

/// The levels whose modules never import the quest log.
const reading_levels: List(Level) = [Unit, Map, Shared]

/// A breach, at its line, for each import of the quest log by a module whose row
/// says unit, map or shared.
pub fn log_import_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
) -> List(Breach) {
  level.import_breaches_by(files:, rows:, check: fn(file, from, found) {
    case list.contains(reading_levels, from), found.1 == quest_log_module {
      True, True ->
        Ok(Breach(
          path: file.path,
          line: found.0,
          rule: level.name(from)
            <> " module "
            <> syntax.module_name(file.path)
            <> " imports the quest log; it reads quests through a quest view",
        ))
      _, _ -> Error(Nil)
    }
  })
  |> list.map(fn(found) { found.2 })
}

/// A breach, at its line, for each call of the view's constructor `of` in a module
/// other than the quest log and the view's own.
pub fn view_builder_breaches(files files: List(SourceFile)) -> List(Breach) {
  list.flat_map(files, fn(file) {
    let module = syntax.module_name(file.path)
    case module == quest_log_module || module == quest_view_module {
      True -> []
      False ->
        syntax.references_to(
          module: syntax.parse(file),
          from: [quest_view_module],
          named: ["of"],
        )
        |> list.map(fn(reference) {
          let glance.Span(start:, ..) = syntax.location_of(reference)
          Breach(
            path: file.path,
            line: syntax.line_of(text: file.text, byte_offset: start),
            rule: "quest_view.of is called outside the quest log, which alone builds a view",
          )
        })
    }
  })
}
