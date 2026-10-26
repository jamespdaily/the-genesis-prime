//// Writes one Gleam module per client game table, and the module that loads
//// them all, from the headers of the client's extracted `.tbl` files.
////
//// `gleam run -m genesis_prime/table_generator write` regenerates
//// `src/genesis_prime/table/` and `src/genesis_prime/table.gleam` from the
//// folder named by `GENESIS_TABLE_DIR`. `gleam run -m genesis_prime/table_generator check`
//// generates into a scratch folder and fails when the committed code differs;
//// it does nothing where `GENESIS_NO_CLIENT=1`, because there is no client to
//// read. Both format what they write with `gleam format`.

import genesis_prime/table_generator/difference.{type Difference}
import genesis_prime/table_generator/module_text
import gleam/dict.{type Dict}

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

/// The generated code as path to text, one entry per `.tbl` file given as file
/// name without extension and bytes, plus the `genesis_prime/table` module. A
/// path is relative to the source folder: `genesis_prime/table/creature2.gleam`.
/// The text is unformatted.
pub fn generate(
  tables tables: List(#(String, BitArray)),
) -> Result(Dict(String, String), GenerateError) {
  todo
}

/// Generates the code from the `.tbl` files in `folder`, writes it under
/// `source` (the folder that holds `genesis_prime/`) and formats it.
pub fn write(
  tables folder: String,
  into source: String,
) -> Result(Nil, GenerateError) {
  todo
}

/// Generates the code from the `.tbl` files in `folder` and compares it with
/// the generated files under `source`.
pub fn check(
  tables folder: String,
  against source: String,
) -> Result(List(Difference), GenerateError) {
  todo
}

/// Runs `write` or `check` as the first argument says, on the folder named by
/// `GENESIS_TABLE_DIR` and the `src` folder. Prints what differs and stops with
/// an error status when the check fails.
pub fn main() -> Nil {
  todo
}

/// The differences a check found, for printing.
pub fn report(differences: List(Difference)) -> String {
  todo
}
