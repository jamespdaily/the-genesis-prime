//// Every module in `dev/` is used by a check, a test or a CI job, or an
//// allow-list names it with an open issue.

import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import gleam/string

/// Each module of `dev` that is not used and not in `allowed`, and each
/// allow-list entry that names no module of `dev`.
///
/// A module is used when a test imports it, when `runners` (the `check` script
/// and the CI workflow files) run it with `-m`, or when a used module of `dev`
/// imports it. Comment lines of the runners do not count. `allowed` pairs a
/// module with the number of the open issue that decides its fate.
pub fn breaches(
  dev dev: List(SourceFile),
  tests tests: List(SourceFile),
  runners runners: List(SourceFile),
  allowed allowed: List(#(String, Int)),
) -> List(Breach) {
  let modules = list.map(dev, fn(file) { #(module_of(file), file) })
  let names = list.map(modules, fn(module) { module.0 })
  let run_text = list.map(runners, fn(file) { without_comments(file.text) })
  let roots =
    list.filter(names, fn(name) {
      list.any(tests, fn(file) {
        mentions(in: file.text, after: "import ", module: name)
      })
      || list.any(run_text, fn(text) {
        mentions(in: text, after: "-m ", module: name)
      })
    })
  let used = close_over_imports(roots, modules)
  let unused =
    list.filter(modules, fn(module) {
      !list.contains(used, module.0)
      && !list.any(allowed, fn(entry) { entry.0 == module.0 })
    })
  let stale = list.filter(allowed, fn(entry) { !list.contains(names, entry.0) })
  list.append(
    list.map(unused, fn(module) {
      Breach(
        path: { module.1 }.path,
        line: 1,
        rule: "a module in dev/ that no check, test or CI job uses: "
          <> module.0,
      )
    }),
    list.map(stale, fn(entry) {
      Breach(
        path: "test/code_rule/dev_module_test.gleam",
        line: 1,
        rule: "an allow-list entry that names no module in dev/: " <> entry.0,
      )
    }),
  )
}

/// The modules `used` plus every module of `dev` that a used one imports.
fn close_over_imports(
  used: List(String),
  modules: List(#(String, SourceFile)),
) -> List(String) {
  let imported =
    list.filter(modules, fn(candidate) {
      !list.contains(used, candidate.0)
      && list.any(modules, fn(user) {
        list.contains(used, user.0)
        && mentions(in: { user.1 }.text, after: "import ", module: candidate.0)
      })
    })
  case imported {
    [] -> used
    _ ->
      close_over_imports(
        list.append(used, list.map(imported, fn(module) { module.0 })),
        modules,
      )
  }
}

/// `dev/genesis_prime/table_generator/naming.gleam` is the module
/// `genesis_prime/table_generator/naming`.
fn module_of(file: SourceFile) -> String {
  file.path
  |> string.remove_prefix("dev/")
  |> string.remove_suffix(".gleam")
}

/// Whether the text holds `prefix` and then the module's name, which no more
/// letters, digits, underscores or slashes follow.
fn mentions(
  in text: String,
  after prefix: String,
  module module: String,
) -> Bool {
  case string.split(text, prefix <> module) {
    [_, ..following] ->
      list.any(following, fn(rest) { !continues_a_name(rest) })
    [] -> False
  }
}

fn continues_a_name(rest: String) -> Bool {
  case string.first(rest) {
    Ok(character) ->
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_/", character)
    Error(Nil) -> False
  }
}

fn without_comments(text: String) -> String {
  text
  |> string.split("\n")
  |> list.filter(fn(line) { !string.starts_with(string.trim_start(line), "#") })
  |> string.join("\n")
}
