//// The text of the generated `genesis_prime/table` module: one entry per
//// generated table module, in file-name order, and the load of all of them.

import genesis_prime/table_generator/difference
import gleam/list
import gleam/string

/// The module `genesis_prime/table` for the table modules named, each by its
/// module name (`creature2`), in the order given.
pub fn render(modules modules: List(String)) -> String {
  let imports =
    modules
    |> list.map(fn(module) { "import genesis_prime/table/" <> module })
    |> list.append([
      "import genesis_prime/table/loader/requirement",
      "import genesis_prime/table/loader/store",
      "import gleam/erlang/reference.{type Reference}",
    ])
    |> list.sort(string.compare)
  let entries =
    list.map(modules, fn(module) { "    " <> module <> ".entry()," })
  string.join(
    [
      difference.generated_marker <> ".",
      "//// Every game table of the client, loaded together: one entry per table file",
      "//// and the load that reads them all.",
      "",
      string.join(imports, "\n"),
      "",
      "/// The entry of every table in the client, in file-name order.",
      "pub fn entries() -> List(store.Entry) {",
      "  [",
      string.join(entries, "\n"),
      "  ]",
      "}",
      "",
      "/// Loads every table from the folder that holds the client's extracted `.tbl`",
      "/// files under `key`, checking each against its generated schema and the rows",
      "/// the server requires.",
      "pub fn load(",
      "  under key: Reference,",
      "  from folder: String,",
      ") -> Result(store.Tables, store.LoadError) {",
      "  store.load(",
      "    under: key,",
      "    from: folder,",
      "    entries: entries(),",
      "    requirements: requirement.all(),",
      "  )",
      "}",
      "",
    ],
    "\n",
  )
}
