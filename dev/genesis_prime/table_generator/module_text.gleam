//// The text of one generated table module: the row type, the schema, the
//// record decoder and the functions that read the table from a load. The text
//// is unformatted; the generator runs `gleam format` over what it writes.

import genesis_prime/table/tbl_file
import genesis_prime/table_generator/naming

/// Why a table's module could not be written.
pub type ModuleError {
  /// A table or column name has no Gleam name.
  Unnamed(error: naming.NameError)
  /// The first column is not a 32-bit integer named `id`, so the table has no
  /// id to index its rows by.
  NoIdColumn(table: String)
  /// Two columns of a table have the same field name.
  DuplicateField(table: String, field: String)
  /// The placement rule gives another record size than the file's header.
  LayoutDiffers(table: String, placed: Int, header: Int)
  /// The type name is one a generated module already uses.
  ReservedTypeName(table: String)
}

/// The module for a table: `file` is the name of its file without `.tbl`, and
/// `index` its number among the loaded tables.
pub fn render(
  file file: String,
  index index: Int,
  description description: tbl_file.Description,
) -> Result(String, ModuleError) {
  todo
}
