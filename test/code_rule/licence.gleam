//// The licence rule: every package the project uses carries a licence the
//// project accepts, and the project's own licence is Apache-2.0.

import code_rule/project_file
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom

/// A package the rule refuses.
pub type Refusal {
  /// Every licence the package declares is off the accepted list.
  Unaccepted(package: String, licences: List(String))
  /// No licence was found for the package.
  NoLicence(package: String)
}

/// The accepted licences, read from `accepted` under `[tools.licences]` in the
/// text of a Gleam project file. A list that is absent is empty, so every
/// package is refused.
pub fn accepted(project_file: String) -> List(String) {
  project_file.strings(project_file, ["tools", "licences", "accepted"])
}

/// The licences declared by the text of a Gleam project file, under
/// `licences` or, as glexer writes it, `licenses`. A file that declares none
/// gives an empty list.
pub fn gleam_licences(project_file: String) -> List(String) {
  case project_file.strings(project_file, ["licences"]) {
    [] -> project_file.strings(project_file, ["licenses"])
    licences -> licences
  }
}

/// The licences declared by the text of an Erlang package's `.app.src`, in its
/// `{licenses, [...]}` entry. A file that declares none gives an empty list.
pub fn erlang_licences(app_source: String) -> List(String) {
  let found = {
    use #(_, after_key) <- result.try(string.split_once(app_source, "{licenses"))
    use #(_, after_open) <- result.try(string.split_once(after_key, "["))
    use #(entries, _) <- result.map(string.split_once(after_open, "]"))
    quoted(entries)
  }
  result.unwrap(found, [])
}

/// The licences named under `declared` in `[tools.licences]` of the text of
/// a Gleam project file, as (package, licence): each for a package that
/// declares no licence where `installed` reads it, checked by hand and
/// written with where it was checked (`evidence`).
pub fn declared(project_file: String) -> List(#(String, String)) {
  list.map(
    project_file.entries(project_file, path: ["tools", "licences", "declared"]),
    fn(entry) {
      let assert Ok(fields) = tom.as_table(entry)
        as "an entry of tools.licences.declared is not a table"
      let assert Ok(package) = tom.get_string(fields, ["package"])
        as "a declared licence names no package"
      let assert Ok(named) = tom.get_string(fields, ["licence"])
        as "a declared licence names no licence"
      let assert Ok(_evidence) = tom.get_string(fields, ["evidence"])
        as "a declared licence says not where it was checked"
      #(package, named)
    },
  )
}

/// The packages with each one that declares no licence given its declared
/// one, when `declared` names it. A package that declares its own licences
/// keeps them.
pub fn with_declared(
  packages packages: List(#(String, List(String))),
  declared declared: List(#(String, String)),
) -> List(#(String, List(String))) {
  list.map(packages, fn(package) {
    case package.1, list.key_find(declared, package.0) {
      [], Ok(named) -> #(package.0, [named])
      [], Error(Nil) | [_, ..], _ -> package
    }
  })
}

/// Each (package, licences) pair the rule refuses: a package whose licences
/// are all off the accepted list, or that has none. A package with any
/// accepted licence passes.
pub fn refusals(
  packages packages: List(#(String, List(String))),
  accepted accepted: List(String),
) -> List(Refusal) {
  list.filter_map(packages, fn(package) {
    let #(name, licences) = package
    case licences {
      [] -> Ok(NoLicence(name))
      _ ->
        case list.any(licences, list.contains(accepted, _)) {
          True -> Error(Nil)
          False -> Ok(Unaccepted(name, licences))
        }
    }
  })
}

/// A refusal in words, naming the package and its licences.
pub fn describe(refusal: Refusal) -> String {
  case refusal {
    Unaccepted(package:, licences:) ->
      "package "
      <> package
      <> " is refused: every licence it declares is off the accepted list ("
      <> string.join(licences, ", ")
      <> ")"
    NoLicence(package:) ->
      "package " <> package <> " is refused: no licence was found"
  }
}

/// Every package in the text of `manifest.toml` as (name, licences), the
/// licences read from `<directory>/<name>/gleam.toml` for a Gleam package or
/// `<directory>/<name>/src/<name>.app.src` for an Erlang one. A package whose
/// file is missing has no licences.
pub fn installed(
  manifest manifest: String,
  packages_directory packages_directory: String,
) -> List(#(String, List(String))) {
  list.map(project_file.manifest_packages(manifest), fn(package) {
    let #(name, build_tools) = package
    let directory = packages_directory <> "/" <> name
    let licences = case list.contains(build_tools, "gleam") {
      True -> list.map(read(directory <> "/gleam.toml"), gleam_licences)
      False ->
        list.map(
          read(directory <> "/src/" <> name <> ".app.src"),
          erlang_licences,
        )
    }
    #(name, list.flatten(licences))
  })
}

fn read(path: String) -> List(String) {
  case simplifile.read(path) {
    Ok(text) -> [text]
    Error(simplifile.Enoent) -> []
    Error(error) ->
      panic as {
        "a package file could not be read: "
        <> path
        <> " ("
        <> simplifile.describe_error(error)
        <> ")"
      }
  }
}

fn quoted(text: String) -> List(String) {
  string.split(text, "\"")
  |> list.index_map(fn(segment, index) { #(segment, index) })
  |> list.filter(fn(segment) { segment.1 % 2 == 1 })
  |> list.map(fn(segment) { segment.0 })
}
