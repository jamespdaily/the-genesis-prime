//// The licence rule: every package the project uses carries a licence the
//// project accepts, and the project's own licence is Apache-2.0.

/// A package the rule refuses.
pub type Refusal {
  /// Every licence the package declares is off the accepted list.
  Unaccepted(package: String, licences: List(String))
  /// No licence was found for the package.
  NoLicence(package: String)
}

/// The accepted licences, read from `accepted` under `[tools.licences]` in the
/// text of a Gleam project file.
pub fn accepted(_project_file: String) -> List(String) {
  panic as "the licence rule is not built"
}

/// The licences declared by the text of a Gleam project file, under
/// `licences` or, as glexer writes it, `licenses`. A file that declares none
/// gives an empty list.
pub fn gleam_licences(_project_file: String) -> List(String) {
  panic as "the licence rule is not built"
}

/// The licences declared by the text of an Erlang package's `.app.src`, in its
/// `{licenses, [...]}` entry. A file that declares none gives an empty list.
pub fn erlang_licences(_app_source: String) -> List(String) {
  panic as "the licence rule is not built"
}

/// Each (package, licences) pair the rule refuses: a package whose licences
/// are all off the accepted list, or that has none. A package with any
/// accepted licence passes.
pub fn refusals(
  _packages: List(#(String, List(String))),
  _accepted: List(String),
) -> List(Refusal) {
  panic as "the licence rule is not built"
}

/// A refusal in words, naming the package and its licences.
pub fn describe(_refusal: Refusal) -> String {
  panic as "the licence rule is not built"
}

/// Every package in the text of `manifest.toml` as (name, licences), the
/// licences read from `<directory>/<name>/gleam.toml` for a Gleam package or
/// `<directory>/<name>/src/<name>.app.src` for an Erlang one. A package whose
/// file is missing has no licences.
pub fn installed(
  _manifest: String,
  _packages_directory: String,
) -> List(#(String, List(String))) {
  panic as "the licence rule is not built"
}
