//// No atom is made from a string, and no term is read from bytes, outside
//// the modules allowed it under `[tools.code_rules]`, so client input can
//// neither fill the atom table nor build terms.

import code_rule/source.{type Breach, type SourceFile}

/// Reads the modules allowed atoms or terms from the text of a Gleam project file.
pub fn allowed(project_file: String) -> List(String) {
  todo as "body in the build commit"
}

/// Each call in the file that makes an atom from a string or a term from bytes.
pub fn breaches(file: SourceFile, allowed: List(String)) -> List(Breach) {
  todo as "body in the build commit"
}
