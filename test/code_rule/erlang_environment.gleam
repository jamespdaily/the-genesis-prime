//// The Erlang environment rule: no Erlang file reads an environment variable
//// or the command-line arguments itself. Gleam reads them through envoy and
//// argv, packages already in the tree, which come before an Erlang external
//// in the package order of the writing-gleam skill.

import code_rule/erlang_text
import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import gleam/string

const forbidden = ["os:getenv", "init:get_plain_arguments"]

/// Each line of the Erlang file that calls or refers to `os:getenv` (of any
/// arity) or `init:get_plain_arguments`. Text in a comment (from `%` to the end
/// of the line), in a string or in a quoted atom is not read, and a longer name
/// that starts or ends with one of them is not a match.
pub fn breaches(file: SourceFile) -> List(Breach) {
  string.split(file.text, "\n")
  |> list.index_map(fn(line, index) { #(index + 1, erlang_text.code_of(line)) })
  |> list.filter(fn(numbered) {
    list.any(forbidden, erlang_text.names(numbered.1, _))
  })
  |> list.map(fn(numbered) {
    Breach(
      path: file.path,
      line: numbered.0,
      rule: "an Erlang file that reads the environment or the arguments; use envoy or argv",
    )
  })
}
