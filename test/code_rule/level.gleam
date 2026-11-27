//// The levels rule: stub.
////
//// Enforced levels: data platform

import code_rule/source.{type Breach, type SourceFile}

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

pub type Row {
  Row(module: String, level: Level, line: Int)
}

pub const list_path = "test/code_rule/levels.txt"

pub const enforced: List(Level) = []

pub fn all_levels() -> List(Level) {
  panic as "stub"
}

pub fn name(level: Level) -> String {
  let _ = level
  panic as "stub"
}

pub fn parse_rows(text text: String) -> List(Row) {
  let _ = text
  panic as "stub"
}

pub fn imported_levels(level: Level) -> List(Level) {
  let _ = level
  panic as "stub"
}

pub fn message_levels(level: Level) -> List(Level) {
  let _ = level
  panic as "stub"
}

pub fn contract(level: Level) -> List(String) {
  let _ = level
  panic as "stub"
}

pub fn imports_of(file file: SourceFile) -> List(#(Int, String)) {
  let _ = file
  panic as "stub"
}

pub fn table_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
) -> List(Breach) {
  let _ = #(files, rows)
  panic as "stub"
}

pub fn import_breaches(
  files files: List(SourceFile),
  rows rows: List(Row),
  enforced enforced: List(Level),
) -> List(Breach) {
  let _ = #(files, rows, enforced)
  panic as "stub"
}
