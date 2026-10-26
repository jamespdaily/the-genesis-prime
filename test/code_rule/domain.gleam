//// The domain rule: every top-level folder or module under `src/genesis_prime/`
//// is a game domain listed under `[tools.code_rules]` in the Gleam project
//// file, each with the reason it exists.

import code_rule/source.{type Breach, type SourceFile}

/// A game domain: the module path of its folder or module, and why it exists.
pub type Domain {
  Domain(module: String, reason: String)
}

/// The domains listed under `domains` in the text of a Gleam project file. A
/// list that is absent is empty, so no domain is allowed.
pub fn domains(project_file: String) -> List(Domain) {
  todo as "read the domains from the project file"
}

/// Each file whose top-level folder or module under `src/genesis_prime/` is
/// not a listed domain. The root module `src/genesis_prime.gleam` is not under
/// a domain and is never a breach.
pub fn unlisted(
  files files: List(SourceFile),
  domains domains: List(Domain),
) -> List(Breach) {
  todo as "find the files outside every listed domain"
}

/// The module of each listed domain whose reason is empty or only spaces.
pub fn unexplained(domains: List(Domain)) -> List(String) {
  todo as "find the domains with no reason"
}
