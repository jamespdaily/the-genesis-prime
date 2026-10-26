//// Gleam names for the client's table and column names. A table `Creature2`
//// is the module `creature2` and the type `Creature2`; a column
//// `donutDrawDistance` is the field `donut_draw_distance`. A name that is a
//// Gleam keyword gets a trailing underscore.

/// Why a client name has no Gleam name.
pub type NameError {
  /// The name is empty, or has a character other than letters, digits and
  /// underscores, or starts with a digit.
  NotAName(client_name: String)
}

/// The snake-case form of a client name: a word starts at an upper-case letter
/// that follows a lower-case letter or digit, and at the last upper-case letter
/// of a run that a lower-case letter follows.
pub fn snake_case(client_name: String) -> Result(String, NameError) {
  todo
}

/// The module name of a table: its snake-case name.
pub fn module_name(table: String) -> Result(String, NameError) {
  todo
}

/// The type and constructor name of a table: the client's name, which is
/// already in upper camel case.
pub fn type_name(table: String) -> Result(String, NameError) {
  todo
}

/// The field name of a column: its snake-case name, with a trailing
/// underscore when that is a Gleam keyword.
pub fn field_name(column: String) -> Result(String, NameError) {
  todo
}
