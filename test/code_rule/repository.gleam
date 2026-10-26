//// The repository as the code-rule tests read it: its Gleam source, its
//// tracked paths and its guidance files.

import code_rule/source.{type SourceFile, SourceFile}
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom

@external(erlang, "repository_ffi", "tracked_files")
fn tracked_files() -> String

/// Every `.gleam` file under each directory, which must hold at least one, so
/// a rule checked over the repository cannot pass by finding nothing.
pub fn sources(under directories: List(String)) -> List(SourceFile) {
  let files = list.flat_map(directories, source.files)
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

/// Every tracked `.erl` file, sorted by path, which must hold at least one.
pub fn erlang_sources() -> List(SourceFile) {
  let files =
    tracked_paths()
    |> list.filter(string.ends_with(_, ".erl"))
    |> list.sort(string.compare)
    |> list.map(fn(path) {
      let assert Ok(text) = simplifile.read(path)
        as { "the Erlang file could not be read: " <> path }
      SourceFile(path:, text:)
    })
  let assert [_, ..] = files as "no tracked Erlang file found"
  files
}

/// The guidance files as (path, text): CLAUDE.md, every skill's SKILL.md and
/// every agent file.
pub fn guidance() -> List(#(String, String)) {
  let skills = directory_entries(".claude/skills")
  let skill_files =
    list.map(skills, fn(skill) { ".claude/skills/" <> skill <> "/SKILL.md" })
  let agent_files =
    directory_entries(".claude/agents")
    |> list.filter(string.ends_with(_, ".md"))
    |> list.map(fn(agent) { ".claude/agents/" <> agent })
  let paths = ["CLAUDE.md", ..list.append(skill_files, agent_files)]
  list.map(paths, fn(path) {
    let assert Ok(text) = simplifile.read(path)
      as "a guidance file could not be read"
    #(path, text)
  })
}

fn directory_entries(directory: String) -> List(String) {
  simplifile.read_directory(directory)
  |> result.unwrap([])
  |> list.sort(string.compare)
}

/// Every key of the client's fact file.
pub fn fact_keys() -> List(String) {
  let assert Ok(text) =
    simplifile.read(
      ".claude/skills/decoding-the-client/references/client-facts.toml",
    )
    as "the fact file could not be read"
  let assert Ok(facts) = tom.parse(text) as "the fact file is TOML"
  dict.keys(facts)
}
