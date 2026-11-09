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
import genesis_prime/coverage/effect_row
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
import gleam/dict.{type Dict}
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
    /// and each is one the engine handles. A handled type with rows no rule reads and no
    /// entry here stops the measure.
    partial: List(Missing),
    /// How many rows of each type no rule of the engine reads, from the tables: those rows
    /// are counted as not handled. `no_unread_rows` for an engine whose types leave no row
    /// out whole.
    unread_rows: fn(store.Tables) -> Dict(Int, Int),
    /// The same for the starting abilities' rows, which the starting abilities' column
    /// counts as not handled.
    unread_starting_rows: fn(store.Tables) ->
      Result(Dict(Int, Int), List(starting_ability.MissingRow)),
    /// The types read from the client and not handled. A type is never both.
    missing: List(Missing),
    /// The type values the level-1 abilities' trees use, when the engine's
    /// types are those of spells, or the rows the trees name that the tables lack.
    starting_abilities: Option(
      fn(store.Tables) -> Result(List(Int), List(starting_ability.MissingRow)),
    ),
  )
}

/// No row of a type is left out whole.
fn no_unread_rows(_tables: store.Tables) -> Dict(Int, Int) {
  dict.new()
}

/// No row of the starting abilities is left out of a handled type.
fn no_unread_starting_rows(
  _tables: store.Tables,
) -> Result(Dict(Int, Int), List(starting_ability.MissingRow)) {
  Ok(dict.new())
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

/// How many rows of each effect type the plan does not read, by the plan's own decision
/// (genesis_prime/coverage/effect_row).
fn unread_effect_rows(tables: store.Tables) -> Dict(Int, Int) {
  effect_row.unread_by_type(tables:, effects: spell4_effects.all(tables))
}

/// What a type 17 or 18 row the plan does not read leaves out: its go lists no row aimed
/// by flags the plan refuses, and applies none behind a target apply prerequisite.
const lasting_gap =
  "rows aimed by flags the plan refuses or behind a target prerequisite, which no go applies"

/// The same for type 80, whose rows the plan also refuses where the two columns that hold
/// the count of stacks differ or a selector names no row.
const force_remove_gap =
  "rows aimed by flags the plan refuses, behind a target prerequisite, with differing stack counts (dataBits03 and dataBits04) or a selector that names no spell group, Spell4 or Spell4Base, which no go applies or the plan refuses"

/// The same for type 81, whose script the client does not hold either.
const signal_gap =
  "rows aimed by flags the plan refuses or behind a target prerequisite, which no go applies; the script a signal stands for is not in the client"

/// What type 145 reads of a row, whose computation is the server's choice.
const conversion_gap =
  "the share is added to the source's value after the type 11 changes, in start order; whether the source is its base or its total and when the share is recomputed are not read"

/// The spell effect engine: the `effectType` column of Spell4Effects, the
/// client's own column name (`game_table.schema`). No fact records the code that
/// reads the column. A type is handled when the effect rule's decode reads it
/// (genesis_prime/game/effect_kind `is_read`). A row is read when the plan applies it
/// (genesis_prime/coverage/effect_row); a spell the plan refuses for a column of its own
/// (a cost, a requirement, a cycle) is left out of the counts, and each of its rows is
/// counted by its own columns.
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
        type_number: 1,
        reason: "rows aimed at another unit, changing a vital other than 6 and 8, behind a target apply prerequisite or periodic (tickTime), which the plan refuses or holds and no go applies",
        fact_key: "Spell4Effects.effectType.1",
      ),
      Missing(
        type_number: 3,
        reason: "rows, or parts of rows, aimed at another unit (#336); rows behind a target apply prerequisite, which no go applies",
        fact_key: "Spell4Effects.effectType.3",
      ),
      Missing(
        type_number: 4,
        reason: "rows holding a state other than Stun and Knockdown, aimed at the caster or by a flag the plan refuses, or behind an apply prerequisite, which the plan refuses",
        fact_key: "Spell4Effects.effectType.4",
      ),
      Missing(
        type_number: 8,
        reason: "rows with a formula parameter a player's value does not read, aimed by a flag the area load refuses, or with a multiplier that is not a finite number, which the area load refuses",
        fact_key: "0x140566ad0",
      ),
      Missing(
        type_number: 11,
        reason: "rows aimed at another player, which the cast applies to creatures only (#570, under #336); rows behind a target apply prerequisite, which no go applies",
        fact_key: "Spell4Effects.effectType.11",
      ),
      Missing(
        type_number: 14,
        reason: "kinds other than entering and leaving stealth, leaving combat and dying, and rows with a chance, a filter, a gate, another unit or a delay, which the plan refuses",
        fact_key: "Spell4Effects.effectType.14",
      ),
      Missing(
        type_number: 17,
        reason: lasting_gap,
        fact_key: "Spell4Effects.effectType.17",
      ),
      Missing(
        type_number: 18,
        reason: lasting_gap,
        fact_key: "Spell4Effects.effectType.18",
      ),
      Missing(
        type_number: 26,
        reason: "rows whose dataBits00 names no spell (the plan holds no Proxy for them) or that are aimed by a flag the plan refuses",
        fact_key: "Spell4Effects.effectType.26",
      ),
      Missing(
        type_number: 29,
        reason: "rows aimed only at other units, periodic (tickTime), with no lifetime, with a formula parameter the plan refuses, whose amount is 0 for every caster (which of dataBits00 and dataBits01 is the amount when the other is 0 is not read), behind a target apply prerequisite, or aimed at the primary target of a spell a Proxy starts on each struck unit, whose pool the server does not hold",
        fact_key: "Spell4Effects.effectType.29",
      ),
      Missing(
        type_number: 52,
        reason: "rows aimed at the units a go strikes, or at the primary target of a spell started on each struck unit, whose armor the server does not hold",
        fact_key: "Spell4Effects.effectType.52",
      ),
      Missing(
        type_number: 64,
        reason: "rows aimed at the caster or its target, whose shield the server does not hold at 0",
        fact_key: "Spell4Effects.effectType.64",
      ),
      Missing(
        type_number: 73,
        reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite, which no go applies",
        fact_key: "Spell4Effects.effectType.73",
      ),
      Missing(
        type_number: 80,
        reason: force_remove_gap,
        fact_key: "Spell4Effects.effectType.80",
      ),
      Missing(
        type_number: 81,
        reason: signal_gap,
        fact_key: "Spell4Effects.effectType.81",
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
        type_number: 112,
        reason: "rows with an outfit (0x905), no display, aimed at another unit, behind a target prerequisite or with no life, which the plan refuses or no go applies",
        fact_key: "Spell4Effects.effectType.112",
      ),
      Missing(
        type_number: 118,
        reason: "rows aimed at another unit, periodic (tickTime), behind a target apply prerequisite or with a formula parameter the plan refuses",
        fact_key: "Spell4Effects.effectType.118",
      ),
      Missing(
        type_number: 145,
        reason: conversion_gap,
        fact_key: "Spell4Effects.effectType.145",
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
    partial: [
      Missing(
        type_number: 0x012B,
        reason: "type 1, the shared-challenge preference, is not kept, so the server does not know it (#52)",
        fact_key: "opcode.0x12b",
      ),
      Missing(
        type_number: 0x0180,
        reason: "the scanbot unit is not made, so no scanbot appears (#55)",
        fact_key: "opcode.0x180",
      ),
      Missing(
        type_number: 0x018F,
        reason: "the trade it cancels, begun by 0x192, is not built (#58)",
        fact_key: "opcode.0x18f",
      ),
      Missing(
        type_number: 0x0269,
        reason: "the reply 0x26A is not sent, so the CREDD tab shows no price (#58)",
        fact_key: "opcode.0x269",
      ),
      Missing(
        type_number: 0x03EC,
        reason: "the reply 0x64C is not sent, so the player's commodity order list stays empty (#58)",
        fact_key: "opcode.0x3ec",
      ),
      Missing(
        type_number: 0x03ED,
        reason: "the reply 0x64D is not sent, so the player's auction list stays empty (#58)",
        fact_key: "opcode.0x3ed",
      ),
      Missing(
        type_number: 0x0570,
        reason: "the reply 0x56F is not sent, so the player's saved key bindings do not load (#60)",
        fact_key: "opcode.0x570",
      ),
    ],
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
