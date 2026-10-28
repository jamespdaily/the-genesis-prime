//// The text of the generated `genesis_prime/table/id` module: one typed id for
//// each table, so one table's id cannot pass as another's. They are all in one
//// module because tables name each other's ids, and Gleam refuses modules that
//// import each other.

import genesis_prime/table_generator/difference
import genesis_prime/table_generator/reference.{type Table}
import gleam/list
import gleam/string

/// The module name of the typed ids, under `genesis_prime/table/`.
pub const module_name = "id"

/// The module `genesis_prime/table/id` for the tables given, in the order
/// given.
pub fn render(tables tables: List(Table)) -> String {
  let ids =
    list.map(tables, fn(table) {
      string.join(
        [
          "/// An id of a row of the client's " <> table.type_name <> " table.",
          "pub type " <> table.type_name <> "Id {",
          "  " <> table.type_name <> "Id(value: Int)",
          "}",
          "",
        ],
        "\n",
      )
    })
  string.join(
    [
      difference.generated_marker <> ".",
      "//// The typed id of every game table of the client.",
      "//// A table's rows keep plain `Int` ids: typed ids in the client's 26,362,088 id cells would add about 603 MB (measured); a table's `get` and the readers of its id columns give these.",
      "",
      string.join(ids, "\n"),
    ],
    "\n",
  )
}
