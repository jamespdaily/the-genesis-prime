//// The allow-lists under `[tools.code_rules]` in the Gleam project file.

import gleam/list
import tom

/// The strings in one list under `[tools.code_rules]`. A list that is absent
/// is empty, so nothing is allowed.
pub fn strings(
  project_file project_file: String,
  key key: String,
) -> List(String) {
  list.map(entries(project_file, key), fn(entry) {
    let assert Ok(text) = tom.as_string(entry)
      as { "an entry of " <> key <> " is not a string" }
    text
  })
}

/// The `module` of each `{ module, reason }` table in one list under
/// `[tools.code_rules]`. A list that is absent is empty.
pub fn modules(
  project_file project_file: String,
  key key: String,
) -> List(String) {
  list.map(entries(project_file, key), fn(entry) {
    let assert Ok(table) = tom.as_table(entry)
      as { "an entry of " <> key <> " is not a table" }
    let assert Ok(module) = tom.get_string(table, ["module"])
      as { "an entry of " <> key <> " has no module" }
    module
  })
}

/// The `module` and `reason` of each `{ module, reason }` table in one list
/// under `[tools.code_rules]`. A list that is absent is empty.
pub fn listings(
  project_file project_file: String,
  key key: String,
) -> List(#(String, String)) {
  todo as "read each module and its reason"
}

fn entries(project_file: String, key: String) -> List(tom.Toml) {
  let assert Ok(parsed) = tom.parse(project_file)
    as "the project file does not parse"
  case tom.get_array(parsed, ["tools", "code_rules", key]) {
    Ok(entries) -> entries
    Error(tom.NotFound(..)) -> []
    Error(tom.WrongType(..)) -> panic as { key <> " is not a list" }
  }
}
