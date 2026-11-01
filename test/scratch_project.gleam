//// What the tests that build a scratch Gleam project share: the project's
//// `gleam.toml` with path dependencies on the project's own copies of the
//// packages it needs (`build/packages`), so no package is fetched; the files
//// written into it; and a run of `gleam` in it.

import filepath
import gleam/list
import gleam/string
import shellout
import simplifile

/// A scratch project called `name` in `folder`, which depends on each of
/// `packages` by path, and its path. The folder is the test's own, from
/// `recording_support.in_folder`.
pub fn create(
  folder folder: String,
  name name: String,
  packages packages: List(String),
) -> String {
  let assert Ok(root) = simplifile.current_directory()
    as "the working directory is known"
  let project = root <> "/" <> folder
  let dependencies =
    list.map(packages, fn(package) {
      package
      <> " = { path = \""
      <> root
      <> "/build/packages/"
      <> package
      <> "\" }"
    })
  write_file(
    project:,
    path: "gleam.toml",
    text: "name = \""
      <> name
      <> "\"\nversion = \"0.1.0\"\n\n[dependencies]\n"
      <> string.join(dependencies, "\n")
      <> "\n",
  )
  project
}

/// Writes `text` to `path` in `project`, made with its folders; a file already
/// there is replaced.
pub fn write_file(
  project project: String,
  path path: String,
  text text: String,
) -> Nil {
  let full = project <> "/" <> path
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.directory_name(full))
    as "the project's folder was made"
  let assert Ok(Nil) = simplifile.write(full, text)
    as "the project's file was written"
  Nil
}

/// Runs `gleam` with `arguments` in `project`: its output, or its exit status
/// and output when it fails.
pub fn gleam(
  project project: String,
  arguments arguments: List(String),
) -> Result(String, #(Int, String)) {
  shellout.command(run: "gleam", with: arguments, in: project, opt: [])
}
