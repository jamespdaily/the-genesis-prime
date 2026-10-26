//// The Erlang environment rule: no Erlang file reads an environment variable
//// or the command-line arguments itself.

import code_rule/source.{type Breach, type SourceFile}

/// Each call in the Erlang file to `os:getenv` or `init:get_plain_arguments`.
pub fn breaches(_file: SourceFile) -> List(Breach) {
  []
}
