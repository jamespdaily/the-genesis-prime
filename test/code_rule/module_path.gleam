//// The module-path rules: no folder or module is named by kind, and none is
//// named for another package.

import code_rule/source.{type Breach, type SourceFile}

/// The names that group by kind, which no segment of a module path may be.
pub const kind_names = [
  "type", "types", "util", "utils", "helper", "helpers", "rule", "rules",
  "common", "shared", "misc", "lib", "core", "model", "models",
]

/// The names of the packages in the text of `manifest.toml`.
pub fn packages(manifest: String) -> List(String) {
  todo as "read the package names from the manifest"
}

/// Each file with a segment of its module path in `kind_names`.
pub fn named_by_kind(files: List(SourceFile)) -> List(Breach) {
  todo as "find the module paths named by kind"
}

/// Each file with a segment of its module path equal to the name of a package.
pub fn named_for_a_package(
  files files: List(SourceFile),
  packages packages: List(String),
) -> List(Breach) {
  todo as "find the module paths named for a package"
}
