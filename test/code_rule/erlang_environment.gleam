//// The Erlang environment rule: no Erlang file reads an environment variable
//// or the command-line arguments itself. Gleam reads them through envoy and
//// argv, packages already in the tree, which come before an Erlang external
//// in the package order of the writing-gleam skill.

import code_rule/erlang_calls.{Target}
import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list

const forbidden = [
  Target("os", "getenv"),
  Target("init", "get_plain_arguments"),
]

/// Each line of the Erlang file that calls or refers to `os:getenv` (of any
/// arity) or `init:get_plain_arguments`, read as the compiler reads it
/// (code_rule/erlang_calls).
pub fn breaches(file: SourceFile) -> List(Breach) {
  erlang_calls.lines(file.text, forbidden)
  |> list.map(fn(line) {
    Breach(
      path: file.path,
      line:,
      rule: "an Erlang file that reads the environment or the arguments; use envoy or argv",
    )
  })
}
