//// Every repository path that CLAUDE.md, a skill or an agent names exists.

import code_rule/source.{type Breach, Breach}
import gleam/list
import gleam/string

const file_extensions = [
  "gleam", "md", "py", "toml", "sql", "json", "sh", "erl", "yml", "yaml",
]

const characters_of_no_path = [
  " ", "*", "<", ">", ":", "{", "}", "(", ")", "[", "]", "\"", "'", ",", "=",
  "|", "!", "?", "#", "$", "&", ";", "\\",
]

/// Each path the guidance text names that is not in the list of repository paths.
///
/// A path is text between single backticks that has none of the characters a
/// command, glob or placeholder would hold, does not start with `/` or `~`,
/// and either holds a `/` or is a file name with a stem and a known extension.
/// It exists when it or a directory it opens is in the list, read from the
/// repository root or from the folder of the guidance file that names it.
pub fn breaches(
  guidance guidance: List(#(String, String)),
  repository_paths repository_paths: List(String),
) -> List(Breach) {
  list.flat_map(guidance, fn(file) {
    let #(guidance_path, text) = file
    let folder = folder_of(guidance_path)
    named_paths(text)
    |> list.filter(fn(named) {
      !exists(path: named.1, folder:, repository_paths:)
    })
    |> list.map(fn(named) {
      Breach(
        path: guidance_path,
        line: named.0,
        rule: "a guidance path that is not in the repository: " <> named.1,
      )
    })
  })
}

/// The paths a text names between single backticks, with their line numbers.
/// Fenced blocks are not read.
fn named_paths(text: String) -> List(#(Int, String)) {
  let lines = string.split(text, "\n")
  let #(_, found) =
    list.index_fold(lines, #(False, []), fn(state, line, index) {
      let #(in_fence, found) = state
      case string.starts_with(string.trim_start(line), "```"), in_fence {
        True, _ -> #(!in_fence, found)
        False, True -> #(True, found)
        False, False -> {
          let paths =
            spans(line)
            |> list.filter(is_path)
            |> list.map(fn(path) { #(index + 1, path) })
          #(False, list.append(found, paths))
        }
      }
    })
  found
}

/// The text between each pair of single backticks on a line.
fn spans(line: String) -> List(String) {
  let segments = string.split(line, "`")
  let last = list.length(segments) - 1
  segments
  |> list.index_map(fn(segment, index) { #(segment, index) })
  |> list.filter(fn(segment) {
    let #(text, index) = segment
    index % 2 == 1 && index < last && text != ""
  })
  |> list.map(fn(segment) { segment.0 })
}

fn is_path(candidate: String) -> Bool {
  let has_no_excluded_character =
    list.all(characters_of_no_path, fn(character) {
      !string.contains(candidate, character)
    })
  has_no_excluded_character
  && !string.starts_with(candidate, "/")
  && !string.starts_with(candidate, "~")
  && { string.contains(candidate, "/") || is_file_name(candidate) }
}

fn is_file_name(candidate: String) -> Bool {
  case list.reverse(string.split(candidate, ".")) {
    [extension, stem, ..] ->
      stem != "" && list.contains(file_extensions, extension)
    [_] | [] -> False
  }
}

fn folder_of(path: String) -> String {
  case list.reverse(string.split(path, "/")) {
    [_, ..folders] -> string.join(list.reverse(folders), "/")
    [] -> ""
  }
}

fn exists(
  path path: String,
  folder folder: String,
  repository_paths repository_paths: List(String),
) -> Bool {
  let path = string.remove_prefix(path, "./")
  let candidates = case folder {
    "" -> [path]
    folder -> [path, folder <> "/" <> path]
  }
  list.any(candidates, fn(candidate) {
    let candidate = string.remove_suffix(candidate, "/")
    list.any(repository_paths, fn(repository_path) {
      repository_path == candidate
      || string.starts_with(repository_path, candidate <> "/")
    })
  })
}
