//// What each engine declares: its name, the area that builds it, where the
//// client's data names the types it handles, how the types it handles are told,
//// and the types the client's code was read for that it does not handle. The
//// coverage measure reads these declarations.
////
//// A rule that decodes its type once for its dispatch (genesis_prime/game/effect_kind,
//// genesis_prime/game/prerequisite) hands the measure that decode: a type is
//// handled when the decode does not give its unread case, so a rule and the
//// measure cannot disagree. An engine with no such decode lists the ids its rules
//// name.

import genesis_prime/client_connection
import genesis_prime/coverage/sent_message
import genesis_prime/coverage/starting_ability
import genesis_prime/game/connection as game_connection
import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite as game_prerequisite
import genesis_prime/game/spell_plan
import genesis_prime/game/spend
import genesis_prime/login/auth_connection
import genesis_prime/table/creature2
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{type Option, None, Some}

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
  /// The message ids a client sends, one entry for each use of an id.
  Cases(evidence: String, ids: List(Int))
  /// A set of ids the fact file does not record; `needed` says what must be
  /// recorded.
  CasesNotRecorded(evidence: String, needed: String)
}

/// How an engine tells the types it handles.
pub type Handling {
  /// The ids its rules name. Every one must be a type some row uses.
  Listed(ids: List(Int))
  /// The rule's own decode: `is_read` says whether the rule handles a type.
  Decoded(is_read: fn(Int) -> Bool)
}

/// A type the client's code was read for, with what the engine lacks to handle it: in
/// `missing` the engine does not handle the type; in `partial` it handles the type but
/// not every row of it or every part of a row.
pub type Missing {
  Missing(
    type_number: Int,
    /// What the engine lacks to handle it, in plain words.
    reason: String,
    /// The fact file's key of the client's reading of the type.
    fact_key: String,
  )
}

/// One engine's declaration.
pub type EngineDeclaration {
  EngineDeclaration(
    /// What the engine owns, as a heading.
    name: String,
    /// The number of the GitHub issue of the engine's area.
    area_issue: Int,
    source: Source,
    handled: Handling,
    /// The types handled with a stated gap. A type is never both partial and missing,
    /// and each is one the engine handles.
    partial: List(Missing),
    /// How many rows of a partial type no rule of the engine reads, from the tables:
    /// those rows are counted as not handled. `no_unread_rows` for an engine whose
    /// partial types leave no row out whole.
    unread_rows: fn(store.Tables, Int) -> Int,
    /// How many of the starting abilities' rows of a type no rule reads, which the
    /// starting abilities' column counts as not handled.
    unread_starting_rows: fn(store.Tables, Int) ->
      Result(Int, List(starting_ability.MissingRow)),
    /// The types read from the client and not handled. A type is never both.
    missing: List(Missing),
    /// The type values the level-1 abilities' trees use, when the engine's
    /// types are those of spells, or the rows the trees name that the tables lack.
    starting_abilities: Option(
      fn(store.Tables) -> Result(List(Int), List(starting_ability.MissingRow)),
    ),
  )
}

/// No row of a partial type is left out whole.
fn no_unread_rows(_tables: store.Tables, _type_number: Int) -> Int {
  0
}

/// No row of the starting abilities is left out of a handled type.
fn no_unread_starting_rows(
  _tables: store.Tables,
  _type_number: Int,
) -> Result(Int, List(starting_ability.MissingRow)) {
  Ok(0)
}

/// Whether the engine handles the type.
pub fn handles(
  engine engine: EngineDeclaration,
  type_number type_number: Int,
) -> Bool {
  case engine.handled {
    Listed(ids:) -> list.contains(ids, type_number)
    Decoded(is_read:) -> is_read(type_number)
  }
}

/// The prerequisite engine. A Prerequisite row holds up to three conditions,
/// each with its type in `prerequisiteTypeId0` to `2`, so every non-zero value
/// of the three columns is one use of a type. The column names are the client's
/// (`game_table.schema`); each names a PrerequisiteType row, and the client's
/// handler of type 71 is fact 0x1404a4e48. No fact records the code that reads
/// the three columns. A type is handled when the prerequisite rule's decode reads
/// it (genesis_prime/game/prerequisite `is_read`).
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
    handled: Decoded(is_read: game_prerequisite.is_read),
    partial: [],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: [
      Missing(
        type_number: 43,
        reason: "needs the player's quest log and its done marks",
        fact_key: "Prerequisite.prerequisiteTypeId.43",
      ),
    ],
    starting_abilities: Some(starting_ability.prerequisite_types),
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
    handled: Listed(ids: []),
    partial: [],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: [],
    starting_abilities: None,
  )
}

/// The rows of the effect type that the effect rule does not read
/// (genesis_prime/game/spell_plan `effect_row_read`): the type 3, type 11, type 73, type 83,
/// type 84 and type 14 rows aimed only at other units, the type 118 rows aimed at the area
/// and the type 64 rows aimed at the caster or its target, and the Stealth, RemoveStealth,
/// Proc and HealShields rows the plan refuses, skips or holds, among them a heal aimed at
/// the primary target of a spell a Proxy starts on each struck unit.
fn unread_effect_rows(tables: store.Tables, type_number: Int) -> Int {
  let rows = spell4_effects.all(tables)
  let struck_children = spell_plan.struck_unit_children(effects: rows)
  list.count(rows, fn(row) {
    row.effect_type == type_number
    && !spell_plan.effect_row_read(effect: row, struck_children:)
  })
}

/// The spell effect engine: the `effectType` column of Spell4Effects, the
/// client's own column name (`game_table.schema`). No fact records the code that
/// reads the column. A type is handled when the effect rule's decode reads it
/// (genesis_prime/game/effect_kind `is_read`).
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
    handled: Decoded(is_read: effect_kind.is_read),
    unread_rows: unread_effect_rows,
    unread_starting_rows: starting_ability.unread_effect_rows,
    partial: [
      Missing(
        type_number: 3,
        reason: "rows, or parts of rows, aimed at another unit: the next step",
        fact_key: "Spell4Effects.effectType.3",
      ),
      Missing(
        type_number: 11,
        reason: "rows, or parts of rows, aimed at another unit: the next step",
        fact_key: "Spell4Effects.effectType.11",
      ),
      Missing(
        type_number: 14,
        reason: "kinds other than entering and leaving stealth, leaving combat and dying, and rows with a chance, a filter, a gate, another unit or a delay, which the plan refuses",
        fact_key: "Spell4Effects.effectType.14",
      ),
      Missing(
        type_number: 64,
        reason: "rows aimed at the caster or its target, whose shield the server does not hold at 0",
        fact_key: "Spell4Effects.effectType.64",
      ),
      Missing(
        type_number: 73,
        reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps",
        fact_key: "Spell4Effects.effectType.73",
      ),
      Missing(
        type_number: 83,
        reason: "rows aimed at another unit, behind a target prerequisite or timed (a delayTime or durationTime: timed stealth), which the plan refuses",
        fact_key: "Spell4Effects.effectType.83",
      ),
      Missing(
        type_number: 84,
        reason: "rows aimed at another unit or behind a target prerequisite, which the plan refuses",
        fact_key: "Spell4Effects.effectType.84",
      ),
      Missing(
        type_number: 118,
        reason: "rows aimed at another unit, periodic (tickTime) or with a formula parameter the plan refuses",
        fact_key: "Spell4Effects.effectType.118",
      ),
    ],
    missing: [
      Missing(
        type_number: 90,
        reason: "needs an ability's charges changed and sent (0x0914)",
        fact_key: "Spell4Effects.effectType.90",
      ),
    ],
    starting_abilities: Some(starting_ability.effect_types),
  )
}

/// The spend-scaled cost engine: the `innateCostEMMId0` and `innateCostEMMId1`
/// columns of Spell4, the client's own column names (`game_table.schema`). Each
/// column holds the EMM id of the cost beside it, so every non-zero value of the two
/// is one use of an id, except one beside no cost. The client reads neither column (`Spell4.innateCostEMMId0`),
/// so the id's meaning is the server's. An id is handled when the spend rule's decode
/// reads it (genesis_prime/game/spend `is_read`).
fn spend_scaled_costs() -> EngineDeclaration {
  let unread = fn(type_number) {
    Missing(
      type_number:,
      reason: "the id's meaning is not in the client; only 4 and 7 have the Psi Point layout",
      fact_key: "Spell4.innateCostEMMId0",
    )
  }
  EngineDeclaration(
    name: "Spend-scaled costs",
    area_issue: 437,
    source: TableColumns(
      table: "Spell4",
      columns: ["innateCostEMMId0", "innateCostEMMId1"],
      evidence: "the client's column names in Spell4.tbl (game_table.schema); the client reads neither column (fact Spell4.innateCostEMMId0). An id beside no cost (Spell4 45155 and 48782 with id 4, 42075 with id 7) is no use of an id: every press of those spells is refused 285, so each is counted as an empty slot",
      values: fn(tables) {
        list.flat_map(spell4.all(tables), fn(row) {
          spell_plan.spent_emm_ids(row:)
        })
      },
    ),
    handled: Decoded(is_read: spend.is_read),
    partial: [],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: list.map([2, 5, 9, 10, 11], unread),
    starting_abilities: Some(starting_ability.spend_ids),
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
    handled: Listed(ids: []),
    partial: [],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: [],
    starting_abilities: None,
  )
}

/// The message routing table: the ids of the messages the client sends, which
/// the server must route. An id is one row. The fact file gives each send
/// path's ids and its number of send sites, not the sites of each id, so the
/// ids weigh the same; an id listed once for each of its sites would weigh by
/// sites. The messages the client only receives are not this engine's.
///
/// An id is handled when a rule names it: the auth rule
/// (genesis_prime/login/auth_connection), the game rule
/// (genesis_prime/game/connection), or the shared connection code, for the
/// network layer's ids and the wrapper 0x244 (genesis_prime/client_connection).
/// Each names its ids in the one table its dispatch reads. The STS rule names
/// no id: its requests are text paths (genesis_prime/login/sts_connection).
fn messages() -> EngineDeclaration {
  EngineDeclaration(
    name: "Client message routing",
    area_issue: 51,
    source: Cases(
      evidence: "the messages the client sends, from the facts of its send paths: SendWorldMessage 0x1403f4900 (245 ids), 0x1403f4740 (58), 0x140016010 (7), 0x1400161d0 (23), the 14 ids serialised directly (0x140332920), 0x244, 0x38c and the network layer's ids 0, 1 and 2 (0x140332580): 352 ids (RegisterMessage 0x1403309a0). Each id is one row: the facts give each path's ids and send sites, not the sites of each id",
      ids: sent_message.all(),
    ),
    handled: Listed(ids: handled_client_message_ids()),
    partial: [],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: [],
    starting_abilities: None,
  )
}

/// The ids of the client's messages a rule names: the shared connection code's
/// (the network layer's and the wrapper 0x244), the auth rule's and the game
/// rule's. A message of any other id is logged as unhandled.
pub fn handled_client_message_ids() -> List(Int) {
  list.flatten([
    client_connection.shared_message_ids(),
    auth_connection.taken_message_ids(),
    game_connection.taken_message_ids(),
  ])
}

/// Every engine's declaration, in the order of their area issues.
pub fn all() -> List(EngineDeclaration) {
  [
    prerequisites(),
    quest_objectives(),
    spell_effects(),
    unit_types(),
    messages(),
    spend_scaled_costs(),
  ]
}
