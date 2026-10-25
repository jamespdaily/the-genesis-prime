//// Every repository path that CLAUDE.md, a skill or an agent names exists.

import code_rule/source.{type Breach}

/// Each path the guidance text names that is not in the list of repository paths.
pub fn breaches(
  guidance: List(#(String, String)),
  repository_paths: List(String),
) -> List(Breach) {
  todo as "body in the build commit"
}
