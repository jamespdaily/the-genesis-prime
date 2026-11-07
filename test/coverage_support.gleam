//// What the coverage tests share: a fact file's keys and the engine
//// declarations by name.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import gleam/list
import gleam/string

/// Whether the fact file's text holds a record under `key`.
pub fn has_record(facts facts: String, key key: String) -> Bool {
  string.contains(facts, "[\"" <> key <> "\"]")
}

/// The engine declaration named `name`.
pub fn engine_named(name: String) -> EngineDeclaration {
  let assert Ok(found) =
    list.find(engine.all(), fn(declaration) { declaration.name == name })
    as { "no engine is named " <> name }
  found
}
