//// The domain rule: every top-level folder or module under `src/genesis_prime/`
//// is a game domain listed under `[tools.code_rules]` in the Gleam project
//// file, each with the reason it exists.

import code_rule/project_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/list
import gleam/string

/// A game domain: the module path of its folder or module, and why it exists.
pub type Domain {
  Domain(module: String, reason: String)
}

/// The domains listed under `domains` in the text of a Gleam project file. A
/// list that is absent is empty, so no domain is allowed.
pub fn domains(project_file: String) -> List(Domain) {
  project_file.listings(project_file, "domains")
  |> list.map(fn(listing) { Domain(module: listing.0, reason: listing.1) })
}

/// Each file whose top-level folder or module under `src/genesis_prime/` is
/// not a listed domain. The root module `src/genesis_prime.gleam` is not under
/// a domain and is never a breach.
pub fn unlisted(
  files files: List(SourceFile),
  domains domains: List(Domain),
) -> List(Breach) {
  let listed = list.map(domains, fn(domain) { domain.module })
  list.filter_map(files, fn(file) {
    case string.split(syntax.module_name(file.path), "/") {
      ["genesis_prime", top, ..] -> {
        let module = "genesis_prime/" <> top
        case list.contains(listed, module) {
          True -> Error(Nil)
          False ->
            Ok(Breach(
              path: file.path,
              line: 1,
              rule: "a top-level folder or module that is not a listed domain: "
                <> module,
            ))
        }
      }
      _ -> Error(Nil)
    }
  })
}

/// The module of each listed domain whose reason is empty or only spaces.
pub fn unexplained(domains: List(Domain)) -> List(String) {
  domains
  |> list.filter(fn(domain) { string.trim(domain.reason) == "" })
  |> list.map(fn(domain) { domain.module })
}
