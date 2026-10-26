//// What each engine declares: its name, the area that builds it, where the
//// client's data names the types it handles, and the types it handles. The
//// coverage measure reads these declarations.

import genesis_prime/table/loader/store

/// Where the types an engine must handle are found in the client.
pub type Source {
  /// The columns of a client table that hold the engine's type. `values`
  /// gives each of the columns' values for every row.
  TableColumns(
    table: String,
    columns: List(String),
    evidence: String,
    values: fn(store.Tables) -> List(Int),
  )
  /// The message ids that have a case in the client's message dispatcher.
  Cases(evidence: String, ids: List(Int))
  /// The cases of the client's message dispatcher, whose ids the fact file
  /// does not record; `needed` says what must be recorded.
  CasesNotRecorded(evidence: String, needed: String)
}

/// One engine's declaration.
pub type EngineDeclaration {
  EngineDeclaration(
    /// What the engine owns, as a heading.
    name: String,
    /// The number of the GitHub issue of the engine's area.
    area_issue: Int,
    source: Source,
    /// The types the engine handles. Every one must be a type some row uses.
    handled: List(Int),
  )
}

/// The prerequisite engine: the three type columns of the Prerequisite table.
pub fn prerequisites() -> EngineDeclaration {
  todo as "the prerequisite engine's declaration"
}

/// The quest objective engine: the type column of the QuestObjective table.
pub fn quest_objectives() -> EngineDeclaration {
  todo as "the quest objective engine's declaration"
}

/// The spell effect engine: the effect type column of the Spell4Effects table.
pub fn spell_effects() -> EngineDeclaration {
  todo as "the spell effect engine's declaration"
}

/// The unit type engine: the creation type column of the Creature2 table.
pub fn unit_types() -> EngineDeclaration {
  todo as "the unit type engine's declaration"
}

/// The message routing table: the cases of the client's message dispatcher.
pub fn messages() -> EngineDeclaration {
  todo as "the message routing table's declaration"
}

/// Every engine's declaration, in the order of their area issues.
pub fn all() -> List(EngineDeclaration) {
  [
    prerequisites(),
    quest_objectives(),
    spell_effects(),
    unit_types(),
    messages(),
  ]
}
