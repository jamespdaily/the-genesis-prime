//// The module-path rules: no folder or module is named by kind, and none is
//// named for another package.

import code_rule/project_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/list
import gleam/pair
import gleam/result
import gleam/string

/// The names that group by kind, which no segment of a module path may be.
pub const kind_names = [
  "type", "types", "util", "utils", "helper", "helpers", "rule", "rules",
  "common", "shared", "misc", "lib", "core", "model", "models",
]

/// The names of the packages in the text of `manifest.toml`.
pub fn packages(manifest: String) -> List(String) {
  list.map(project_file.manifest_packages(manifest), pair.first)
}

/// Each file with a segment of its module path in `kind_names`.
pub fn named_by_kind(files: List(SourceFile)) -> List(Breach) {
  list.filter_map(files, fn(file) {
    first_segment_in(file, kind_names)
    |> result.map(fn(name) {
      Breach(
        path: file.path,
        line: 1,
        rule: "a module path with a folder or module named by kind: " <> name,
      )
    })
  })
}

/// Each file with a segment of its module path equal to the name of a package.
pub fn named_for_a_package(
  files files: List(SourceFile),
  packages packages: List(String),
) -> List(Breach) {
  list.filter_map(files, fn(file) {
    first_segment_in(file, packages)
    |> result.map(fn(name) {
      Breach(
        path: file.path,
        line: 1,
        rule: "a module path with a folder or module named for a package: "
          <> name,
      )
    })
  })
}

fn first_segment_in(
  file: SourceFile,
  names: List(String),
) -> Result(String, Nil) {
  string.split(syntax.module_name(file.path), "/")
  |> list.find(list.contains(names, _))
}
