//// Writes the Gleam codec of every message and record in the schema: one
//// module for each under `src/genesis_prime/message/`, with its type, and for
//// a message `encode` and `decode`, for a record `write` and `read`. The text
//// is already in `gleam format`'s layout, so a regenerated file equals the
//// committed one byte for byte, and `mismatches` names each file that does not.

import genesis_prime/message_schema.{type Schema}

/// One generated file: its path from the repository root and its text.
pub type GeneratedFile {
  GeneratedFile(path: String, text: String)
}

/// How a committed file differs from the generated one.
pub type Mismatch {
  /// The committed text differs from what the schema generates.
  Edited(path: String)
  /// The schema generates a file that is not committed.
  Missing(path: String)
  /// A committed generated file is not in what the schema generates.
  Stale(path: String)
}

/// The first line every generated file starts with, which marks a file as
/// generated and so as one that `mismatches` compares.
pub const generated_marker = "//// Generated"

/// The files the schema generates.
pub fn generate(schema: Schema) -> List(GeneratedFile) {
  todo
}

/// Each way the committed files differ from the generated ones. A committed
/// file counts only when it holds the generated marker, so the hand-written
/// bit stream module is never stale.
pub fn mismatches(
  generated generated: List(GeneratedFile),
  committed committed: List(GeneratedFile),
) -> List(Mismatch) {
  todo
}
