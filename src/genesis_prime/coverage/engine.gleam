//// What each engine declares: its name, the area that builds it, where the
//// client's data names the types it handles, and the types it handles. The
//// coverage measure reads these declarations.

import genesis_prime/table/creature2
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4_effects
import gleam/list

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

/// The prerequisite engine. A Prerequisite row holds up to three conditions,
/// each with its type in `prerequisiteTypeId0` to `2`, so every non-zero value
/// of the three columns is one use of a type. The column names are the client's
/// (`game_table.schema`); each names a PrerequisiteType row, and the client's
/// handler of type 71 is fact 0x1404a4e48. No fact records the code that reads
/// the three columns.
fn prerequisites() -> EngineDeclaration {
  EngineDeclaration(
    name: "Prerequisites",
    area_issue: 47,
    source: TableColumns(
      table: "Prerequisite",
      columns: [
        "prerequisiteTypeId0",
        "prerequisiteTypeId1",
        "prerequisiteTypeId2",
      ],
      evidence: "the client's column names in Prerequisite.tbl (game_table.schema); each value names a PrerequisiteType row, and fact 0x1404a4e48 is the client's handler of type 71",
      values: fn(tables) {
        list.flat_map(prerequisite.all(tables), fn(row) {
          [
            row.prerequisite_type_id0,
            row.prerequisite_type_id1,
            row.prerequisite_type_id2,
          ]
        })
      },
    ),
    handled: [],
  )
}

/// The quest objective engine: the `type` column of QuestObjective, the
/// client's own column name (`game_table.schema`). No fact records the code that
/// reads the column.
fn quest_objectives() -> EngineDeclaration {
  EngineDeclaration(
    name: "Quest objectives",
    area_issue: 48,
    source: TableColumns(
      table: "QuestObjective",
      columns: ["type"],
      evidence: "the client's column name in QuestObjective.tbl (game_table.schema)",
      values: fn(tables) {
        list.map(quest_objective.all(tables), fn(row) { row.type_ })
      },
    ),
    handled: [],
  )
}

/// The spell effect engine: the `effectType` column of Spell4Effects, the
/// client's own column name (`game_table.schema`). No fact records the code that
/// reads the column.
fn spell_effects() -> EngineDeclaration {
  EngineDeclaration(
    name: "Spell effects",
    area_issue: 49,
    source: TableColumns(
      table: "Spell4Effects",
      columns: ["effectType"],
      evidence: "the client's column name in Spell4Effects.tbl (game_table.schema)",
      values: fn(tables) {
        list.map(spell4_effects.all(tables), fn(row) { row.effect_type })
      },
    ),
    handled: [],
  )
}

/// The unit type engine: the `CreationTypeEnum` column of Creature2, the
/// client's own column name (`game_table.schema`). That the column holds the
/// unit type is a guess: only its name says it.
fn unit_types() -> EngineDeclaration {
  EngineDeclaration(
    name: "Unit types",
    area_issue: 50,
    source: TableColumns(
      table: "Creature2",
      columns: ["CreationTypeEnum"],
      evidence: "a guess: the client's column name in Creature2.tbl (game_table.schema) is the only evidence",
      values: fn(tables) {
        list.map(creature2.all(tables), fn(row) { row.creation_type_enum })
      },
    ),
    handled: [],
  )
}

/// The message routing table: the ids that have a case in the client's message
/// dispatcher. The fact file records that 645 of the 2,322 ids from 97 to 2418
/// have a case, not which; so the source is not recorded.
fn messages() -> EngineDeclaration {
  EngineDeclaration(
    name: "Client message routing",
    area_issue: 51,
    source: CasesNotRecorded(
      evidence: "HandleWorldMessage 0x1403ec6a0 switches on ids 97 to 2418 through 2,322 table entries at 0x1403f1344, 1,677 of them the default, so 645 ids have a case (facts 0x1403ec6a0 and 0x1403f1344)",
      needed: "which of the dispatcher's 2,322 ids have a case (the 645 whose table entry at 0x1403f1344 is not the default 0x1403f12d2), and the ids of the auth and character-select readers, each recorded in the fact file",
    ),
    handled: [],
  )
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
