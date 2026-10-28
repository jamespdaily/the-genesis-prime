//// What the code rules read from the Gleam project file, and from the build's
//// manifest: the allow-lists under `[tools.code_rules]`, the licences, and the
//// packages the build holds.

import gleam/list
import gleam/string
import tom

/// The strings in the list at `path` in the text of a Gleam project file. A
/// list that is absent is empty, so nothing is allowed.
pub fn strings(
  project_file project_file: String,
  path path: List(String),
) -> List(String) {
  list.map(entries(project_file:, path:), fn(entry) {
    let assert Ok(text) = tom.as_string(entry)
      as { "an entry of " <> string.join(path, ".") <> " is not a string" }
    text
  })
}

/// Every package in the text of `manifest.toml` as its name and the build
/// tools it is built with.
pub fn manifest_packages(manifest: String) -> List(#(String, List(String))) {
  let assert Ok(parsed) = tom.parse(manifest) as "the manifest does not parse"
  let assert Ok(packages) = tom.get_array(parsed, ["packages"])
    as "the manifest lists no packages"
  list.map(packages, fn(package) {
    let assert Ok(table) = tom.as_table(package)
      as "a manifest package is not a table"
    let assert Ok(name) = tom.get_string(table, ["name"])
      as "a manifest package has no name"
    let assert Ok(build_tools) = tom.get_array(table, ["build_tools"])
      as "a manifest package has no build tools"
    #(
      name,
      list.map(build_tools, fn(tool) {
        let assert Ok(tool) = tom.as_string(tool)
          as "a build tool is not a string"
        tool
      }),
    )
  })
}

/// The `module` of each `{ module, reason }` table in one list under
/// `[tools.code_rules]`. A list that is absent is empty.
pub fn modules(
  project_file project_file: String,
  key key: String,
) -> List(String) {
  list.map(
    entries(project_file:, path: ["tools", "code_rules", key]),
    fn(entry) {
      let assert Ok(table) = tom.as_table(entry)
        as { "an entry of " <> key <> " is not a table" }
      let assert Ok(module) = tom.get_string(table, ["module"])
        as { "an entry of " <> key <> " has no module" }
      module
    },
  )
}

/// The `module` and `reason` of each `{ module, reason }` table in one list
/// under `[tools.code_rules]`. A list that is absent is empty.
pub fn listings(
  project_file project_file: String,
  key key: String,
) -> List(#(String, String)) {
  list.map(
    entries(project_file:, path: ["tools", "code_rules", key]),
    fn(entry) {
      let assert Ok(table) = tom.as_table(entry)
        as { "an entry of " <> key <> " is not a table" }
      let assert Ok(module) = tom.get_string(table, ["module"])
        as { "an entry of " <> key <> " has no module" }
      let assert Ok(reason) = tom.get_string(table, ["reason"])
        as { "an entry of " <> key <> " has no reason" }
      #(module, reason)
    },
  )
}

/// The entries of the list at `path`; a list that is absent is empty.
pub fn entries(
  project_file project_file: String,
  path path: List(String),
) -> List(tom.Toml) {
  let assert Ok(parsed) = tom.parse(project_file)
    as "the project file does not parse"
  case tom.get_array(parsed, path) {
    Ok(entries) -> entries
    Error(tom.NotFound(..)) -> []
    Error(tom.WrongType(..)) ->
      panic as { string.join(path, ".") <> " is not a list" }
  }
}
