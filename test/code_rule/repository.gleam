//// The repository as the code-rule tests read it: its Gleam source, its
//// tracked paths and the client's fact file.

import code_rule/source.{type SourceFile, SourceFile}
import database_support
import gleam/dict
import gleam/list
import gleam/string
import simplifile
import tom

@external(erlang, "repository_ffi", "tracked_files")
fn tracked_files() -> String

/// The directories whose Gleam source the rules read.
const tree_directories = ["src", "test", "dev"]

/// Every `.gleam` file under each directory, which must hold at least one, so
/// a rule checked over the repository cannot pass by finding nothing. The
/// directories are `src`, `test` and `dev`, read from disk once per run and shared by
/// every rule; a directory outside them holds nothing.
pub fn sources(under directories: List(String)) -> List(SourceFile) {
  let tree =
    database_support.once("source_tree", fn() {
      list.flat_map(tree_directories, source.files)
    })
  let files =
    list.flat_map(directories, fn(directory) {
      list.filter(tree, fn(file) {
        string.starts_with(file.path, directory <> "/")
      })
    })
  let assert [_, ..] = files as "no Gleam source found under the directories"
  files
}

/// Every path `git ls-files` lists from the repository root.
pub fn tracked_paths() -> List(String) {
  let paths =
    tracked_files()
    |> string.split("\n")
    |> list.filter(fn(path) { path != "" })
  let assert [_, ..] = paths as "git ls-files listed no path"
  paths
}

/// Every tracked `.erl` file under the directories, sorted by path, which
/// must hold at least one.
pub fn erlang_sources(under directories: List(String)) -> List(SourceFile) {
  tracked_sources(suffix: ".erl", under: directories)
}

fn tracked_sources(
  suffix suffix: String,
  under directories: List(String),
) -> List(SourceFile) {
  let files =
    tracked_paths()
    |> list.filter(string.ends_with(_, suffix))
    |> list.filter(fn(path) {
      list.any(directories, fn(directory) {
        string.starts_with(path, directory <> "/")
      })
    })
    |> list.sort(string.compare)
    |> list.map(fn(path) {
      let assert Ok(text) = simplifile.read(path)
        as { "the tracked file could not be read: " <> path }
      SourceFile(path:, text:)
    })
  let assert [_, ..] = files as { "no tracked " <> suffix <> " file found" }
  files
}

/// Every key of the client's fact file, read once for the run: the first caller
/// parses the file and the others take the stored keys.
pub fn fact_keys() -> List(String) {
  database_support.once("fact_keys", fn() {
    let assert Ok(text) =
      simplifile.read(
        ".claude/skills/decoding-the-client/references/client-facts.toml",
      )
      as "the fact file could not be read"
    let assert Ok(facts) = tom.parse(text) as "the fact file is TOML"
    dict.keys(facts)
  })
}
