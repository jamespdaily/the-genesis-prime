//// The rows a recorded session starts from, saved beside its recordings as a
//// file of data-only SQL (`INSERT` statements for the account and character
//// tables, no schema), so a replay applies every migration and then the
//// fixture, and the session finds the same account and characters it found
//// live.

import pog

/// Why the fixture could not be written or applied.
pub type FixtureError {
  /// The file could not be read or written.
  FileFailed(path: String, reason: String)
  /// The database refused a statement, naming it.
  StatementFailed(statement: String, reason: String)
}

/// Saves every row of the account and character tables of the database
/// `database` reaches as data-only SQL in the file at `path`, in an order
/// that satisfies each table's references. A file already there is never
/// overwritten. The dev start writes it before it accepts the first
/// connection.
pub fn write(
  database _database: pog.Connection,
  path _path: String,
) -> Result(Nil, FixtureError) {
  panic as "built in the next commit"
}

/// Runs the statements of the fixture file at `path`, in one transaction, on
/// the database `database` reaches, which holds the schema and no rows.
pub fn apply(
  database _database: pog.Connection,
  path _path: String,
) -> Result(Nil, FixtureError) {
  panic as "built in the next commit"
}

/// The name of the fixture's file inside a recording folder.
pub const file_name = "fixture.sql"
