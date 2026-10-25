//// A rule module is pure: it imports no process, OTP, database or logging
//// module, and its externals call only Erlang functions on the allow-list.
//// Modules with effects are listed under `[tools.code_rules]` in gleam.toml.

import code_rule/source.{type Breach, type SourceFile}

/// The modules allowed effects and the Erlang functions a rule may call,
/// read from the Gleam project file.
pub type Allowed {
  Allowed(effectful_modules: List(String), pure_erlang: List(String))
}

/// Reads the allow-lists from the text of a Gleam project file.
pub fn allowed(project_file: String) -> Allowed {
  todo as "body in the build commit"
}

/// Each import or external in the file that breaks the rule.
pub fn breaches(file: SourceFile, allowed: Allowed) -> List(Breach) {
  todo as "body in the build commit"
}
