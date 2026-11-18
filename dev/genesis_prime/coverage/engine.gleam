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
import genesis_prime/game/objective_kind
import genesis_prime/game/prerequisite as game_prerequisite
import genesis_prime/game/spell_plan
import genesis_prime/game/spend
import genesis_prime/login/auth_connection
import genesis_prime/table/creature2
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite
import genesis_prime/table/quest2_reward
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
    missing: [],
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
    // The handled types are genesis_prime/game/objective_kind `is_counted`, the types a
    // rule advances; the comment below names each rule.
    // Talk (type 3) and use (type 12) objectives count a talk to a creature or a use of
    // one, and kill objectives count a kill: type 2 by the creature, types 8 and 16 by a
    // TargetGroup (genesis_prime/game/objective). Types 15 and 46 need a unit's cluster
    // and rank the server does not hold, so no kill advances them; the issue "Kill
    // objectives count by cluster, rank and a unit's tagged value" closes that. Collect
    // (types 4 and 33) objectives take the held count and visit (type 17) objectives the
    // player's zone chain, both after every change of either. A use of a creature whose
    // row names the objective counts a scripted objective (type 5) or a collectible
    // (type 32), which the partial list states the gaps of. Checklist objectives (types
    // 14 and 18 by a TargetGroup, types 27 and 28 by a PathSoldierActivate row) count a talk to or
    // an activate of a target as the target's bit of the objective's 32-bit mask, and the
    // objective is done at its count of bits
    // (genesis_prime/game/objective; the index of each target is
    // genesis_prime/world_map/checklist_index). A finish (type 24) objective takes the
    // completion of the quest its data names, now or earlier in its repeat period. A cast
    // of the spell of a type 11 objective completes it (objective_test
    // a_cast_of_the_objective_spell_completes_it_test), which the partial list states the
    // gaps of. Types 10 and 13 are not counted. A use of a unit of the TargetGroup of a
    // type 23 objective counts one for each unit, once (the once is the server's choice),
    // and a departures choice objective counts only its own terminal
    // (genesis_prime/game/objective).
    handled: Decoded(is_read: objective_kind.is_counted),
    partial: [
      Missing(
        type_number: 11,
        reason: "a cast of the objective's spell completes it, but the client never ties the spell to the objective's data, so that link is a guess until a retail recording of quest 3915, 4832 or 7618 shows it; 6 rows cannot finish, since the client refuses the press of a spell with no Spell4 row (data 0 in 7378, 8042, 9882, 16525 and 16577; Spell4 46171 in 15816); Spell4 43461 cannot be planned, so its press is refused, behind a target gate whose prerequisite condition of type 12 the server does not read (#818); 11 rows (8389, 9399, 9401, 9768, 9770, 9771, 14966, 15332, 15363, 17880, 17933) have a cast condition the server cannot judge: a caster cast of prerequisite type 16 or 102 (#818), or a target cast of type 4, 71 or 102 that needs the struck creature's own facts (#851 for 4 and 71, #818 for 102)",
        fact_key: "QuestObjective.type.11",
      ),
      Missing(
        type_number: 22,
        reason: "an arrival at a marker completes a place objective of count 1; the 43 with no marker and the 2 with a count above 1 (14205, 14577) are not counted, which the issue \"Place objectives with no marker or a count above one complete (objective type 22)\" closes",
        fact_key: "QuestObjective.type.22",
      ),
      Missing(
        type_number: 5,
        reason: "a use of a creature linked to the objective by its row (a finished activate cast, or a use with no activate spell) counts one, which is a guess; 250 of the 1556 rows have a linked creature, and the rest have no source; the 12 linked creatures whose Collect click sends 0x14f are not counted, and a linked creature with no stored spawn is not placed (the issue \"A click target with no spawn stands at its objective's marker\"); a hidden row (flag 8) with data 0 that no creature links, 91 hidden data 0 rows less the 8 whose slot a creature links, is completed by the server once its quest's other required objectives are done, which is a server choice (the issue \"A hidden scripted objective with no target completes once its quest's other required objectives are done\")",
        fact_key: "QuestObjective.type.5",
      ),
      Missing(
        type_number: 32,
        reason: "a use of a creature linked to the objective by its row (a finished activate cast, or a use with no activate spell) counts one, which is a guess; 293 of the 709 rows have a linked creature, and the 416 others have no source; the 12 linked creatures whose Collect click sends 0x14f are not counted, and a linked creature with no stored spawn is not placed (the issue \"A click target with no spawn stands at its objective's marker\")",
        fact_key: "QuestObjective.type.32.sources",
      ),
    ],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: [],
    starting_abilities: None,
  )
}

/// The quest reward engine: the `quest2RewardTypeId` column of Quest2Reward, the client's
/// own column name (`game_table.schema`). The client reads the type when it splits a quest's
/// rewards (`0x140551ac0`). Items (type 1) and credits (type 3, currency 1) are given by the
/// turn-in (genesis_prime/game/quest_turn_in).
fn quest_rewards() -> EngineDeclaration {
  let not_given = fn(type_number, reason) {
    Missing(type_number:, reason:, fact_key: "Quest2Reward.quest2RewardTypeId")
  }
  EngineDeclaration(
    name: "Quest rewards",
    area_issue: 334,
    source: TableColumns(
      table: "Quest2Reward",
      columns: ["quest2RewardTypeId"],
      evidence: "the client's column name in Quest2Reward.tbl (game_table.schema); the client reads the type in the reward split of 0x140551ac0",
      values: fn(tables) {
        list.map(quest2_reward.all(tables), fn(row) {
          row.quest2_reward_type_id
        })
      },
    ),
    handled: Listed(ids: [1, 3]),
    partial: [
      not_given(
        3,
        "rows of a currency but credits (objectId other than 1), which no turn-in gives (#675)",
      ),
    ],
    unread_rows: no_unread_rows,
    unread_starting_rows: no_unread_starting_rows,
    missing: [
      not_given(2, "a reputation reward is not given (#674)"),
      not_given(4, "a tradeskill experience reward is not given (#677)"),
      not_given(5, "a new tradeskill is not given (#677)"),
      not_given(7, "an account currency reward is not given (#675)"),
      not_given(10, "a rotation essence reward is not given (#676)"),
    ],
    starting_abilities: None,
  )
}

/// How many rows of each effect type the plan does not read, by the plan's own decision
/// (genesis_prime/coverage/effect_row).
fn unread_effect_rows(tables: store.Tables) -> Dict(Int, Int) {
  effect_row.unread_by_type(tables:, effects: spell4_effects.all(tables))
}

/// What a type 17 or 18 row the plan does not read leaves out: its go lists no row aimed
/// by flags the plan refuses, and none behind a target apply prerequisite the plan cannot
/// check.
const lasting_gap =
  "rows aimed by a flag with bit 8 (#336) or by 3, 5 or 7 in a spell that hits no foes (#834) or behind an apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses"

/// The same for type 76, whose rows with a delayTime the client does not apply from the
/// go: the server lists them with their delay and the measure counts them not read.
const item_visual_swap_gap =
  "rows aimed by flags the plan refuses or behind an apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses; rows with a delayTime, which the go lists and the measure counts not read: an effect with a start delay shows on the client when its delay ends (#827, 0x1405d6880.delayed_apply)"

/// The same for type 80, whose rows the plan also refuses where the two columns that hold
/// the count of stacks differ or a selector names no row.
const force_remove_gap =
  "rows aimed by a flag with bit 8 (#336) or by 3, 5 or 7 in a spell that hits no foes (#834), behind an apply prerequisite whose conditions the plan cannot check (#817, #818), with differing stack counts (dataBits03 and dataBits04) or a selector that names no spell group, Spell4 or Spell4Base, which the plan refuses"

/// The same for type 81, whose script the client does not hold either.
const signal_gap =
  "rows aimed by a flag with bit 8 (#336) or by 3, 5 or 7 in a spell that hits no foes (#834) or behind an apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses; the script a signal stands for is not in the client"

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
        reason: "rows aimed at another unit behind a target apply prerequisite, which the plan refuses (#815); rows behind a prerequisite whose conditions the plan cannot check (#817, #818)",
        fact_key: "Spell4Effects.effectType.3",
      ),
      Missing(
        type_number: 4,
        reason: "rows behind an apply prerequisite (#787); rows aimed at another unit that last until removed (#803) or hold a persistence prerequisite (#787); rows aimed by 9, 10 or 12, which hold bit 8 (#336); rows with a phaseFlags of 0, which no phase selects",
        fact_key: "Spell4Effects.effectType.4",
      ),
      Missing(
        type_number: 8,
        reason: "rows with a formula parameter a player's value does not read (the weapon types 6 and 9, the passed-in value 18), aimed by a flag the area load refuses, or with a multiplier that is not a finite number, which the area load refuses; periodic rows that last until removed (flags bit 2, #803), which the area load leaves out; rows aimed at their caster alone, which load and strike nobody (#831)",
        fact_key: "0x140566ad0",
      ),
      Missing(
        type_number: 10,
        reason: "rows aimed only at other units or behind an apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses; periodic rows that last until removed (flags bit 2, #803), which the plan leaves out; rows with a formula parameter the plan refuses; rows of a spell a Proxy starts on each struck unit, whose heal on that unit is not built (#570)",
        fact_key: "spell.heal_result_log",
      ),
      Missing(
        type_number: 11,
        reason: "rows aimed at another player, which the cast applies to creatures only (#570, under #336); rows behind an apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses",
        fact_key: "Spell4Effects.effectType.11",
      ),
      Missing(
        type_number: 14,
        reason: "kinds other than entering and leaving stealth, leaving combat, dying, the hits, criticals, kills and heals the holder lands, and using an ability, spending or changing the class resource, receiving a heal, a deflect, a finisher critical, a taunt landed, starting to move, and the damage, critical, deflect and depleted shield a creature's blow deals the holder (the other kinds the texts name wait on their own issues), and rows held by another unit, behind a persistence or target apply prerequisite, with a group and no filter kind, with an aim of 32 or above, with no life or naming a Spell4 the tables lack, which the plan leaves out or refuses",
        fact_key: "Spell4Effects.effectType.14",
      ),
      Missing(
        type_number: 15,
        reason: "rows aimed at the caster alone, which need a creature that casts, or a creature's strike on a player, to read (#801); rows that last until removed (flags bit 2, #803); rows behind a persistence prerequisite and rows with a dataBits01 to dataBits09 that is not 0, which no client code reads (#925); rows behind a target apply prerequisite that reads the casts a struck creature holds, which the plan refuses (#569); and the rows the plan applies that refuse nothing: those of a state with no reading (0, 1, 2, 10 and 23), which a creature holds and which refuse nothing since the client does not say what they do (#925), those with a durationTime of 0, which a creature never holds (#925), and those of a spell with no Spell4 row, which no cast reaches (#925)",
        fact_key: "Spell4Effects.effectType.15",
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
        reason: "rows whose dataBits00 names no spell (the plan holds no Proxy for them) or that are aimed by a flag with bit 8 (#336) or by 3, 5 or 7 in a spell that hits no foes (#834)",
        fact_key: "Spell4Effects.effectType.26",
      ),
      Missing(
        type_number: 29,
        reason: "rows aimed only at other units, periodic (tickTime), with no lifetime, with a formula parameter the plan refuses, whose amount is 0 for every caster (which of dataBits00 and dataBits01 is the amount when the other is 0 is not read), behind an apply prerequisite whose conditions the plan cannot check (#817, #818), or aimed at the primary target of a spell a Proxy starts on each struck unit, whose pool the server does not hold",
        fact_key: "Spell4Effects.effectType.29",
      ),
      Missing(
        type_number: 35,
        reason: "rows aimed at another unit (19 at the target, 5 at the area), which no creature rule holds still; rows with no durationTime, which hold their caster for nothing; rows with a phaseFlags of 0, which no phase selects; rows behind a prerequisite, which the plan does not read for a delay and the creature special load refuses; what a row does is the server's reading, since the client has no case for the type",
        fact_key: "Spell4Effects.effectType.35",
      ),
      Missing(
        type_number: 42,
        reason: "rows aimed at the area (4, 6) or with no aim (0, 8 and above without bit 1), which reach no quest log; rows with a column the client does not read that is not 0 (a tick, a duration, a damage type, flags, dataBits03 to dataBits09, a parameter, a persistence or suspend prerequisite) or an amount below 1, which the plan leaves out; rows aimed at the primary target alone in a spell the activate cast names (a creature's activate column, the default spell or an item's use), which the activate cast drops since the unit it activates holds no quest log; rows behind an apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses",
        fact_key: "Spell4Effects.effectType.42",
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
        reason: "rows, or parts of rows, aimed at another unit, whose cooldowns no server rule keeps; rows behind a target apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses",
        fact_key: "Spell4Effects.effectType.73",
      ),
      Missing(
        type_number: 76,
        reason: item_visual_swap_gap,
        fact_key: "Spell4Effects.effectType.76",
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
        reason: "rows aimed at another unit, behind a target prerequisite whose conditions the plan cannot check (#818) or timed (a delayTime or durationTime: timed stealth), which the plan refuses",
        fact_key: "Spell4Effects.effectType.83",
      ),
      Missing(
        type_number: 84,
        reason: "rows aimed at another unit or behind a target prerequisite whose conditions the plan cannot check (#818), which the plan refuses",
        fact_key: "Spell4Effects.effectType.84",
      ),
      Missing(
        type_number: 95,
        reason: "rows aimed only at another unit or at the area (targetFlags 2 and 4), which the client draws no full-screen effect for: it draws one for the player's own unit alone",
        fact_key: "Spell4Effects.effectType.95",
      ),
      Missing(
        type_number: 97,
        reason: "rows aimed at the caster alone, which only a creature caster could remove (#921); rows with a dataBits00 or dataBits01 that is not 0, which no client code reads (#921); rows in a spell the activate cast names (a creature's activate column, the default spell or an item's use) that no Proxy or Proc names as its child, which the activate cast drops since it strikes no unit (#921); rows behind a target apply prerequisite whose conditions the plan cannot check (#817, #818), which the plan refuses",
        fact_key: "Spell4Effects.effectType.97",
      ),
      Missing(
        type_number: 112,
        reason: "rows with an outfit (0x905), no display, aimed at another unit, behind a target prerequisite or with no life, which the plan refuses or no go applies",
        fact_key: "Spell4Effects.effectType.112",
      ),
      Missing(
        type_number: 118,
        reason: "rows aimed at another unit, periodic rows that last until removed (flags bit 2, #803), rows behind an apply prerequisite whose conditions the plan cannot check (#817, #818) or with a formula parameter the plan refuses",
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
/// client's own column name (`game_table.schema`). The client keys a unit's
/// interaction kind on it (Door for 4, Collect for 8, Mail for 12,
/// `0x140479560`), with the numbers message 0x262 gives the unit types
/// (`opcode.0x262.type_data`). The two enums are not one: the bind points' rows
/// hold 18 where the unit type is 19, and the rows spawned as type 32
/// (SimpleCollidable) hold 20 (`Creature2.CreationTypeEnum`, from the world
/// database). So only the types whose two numbers agree are handled, those the
/// server creates and sends (genesis_prime/world_map/static_object): 4, 8, 10,
/// 11, 12, 13 and 14. Type 32's rows are counted under 20, which no rule
/// names, so 20 stays unhandled until the client's own code pairs the two.
fn unit_types() -> EngineDeclaration {
  EngineDeclaration(
    name: "Unit types",
    area_issue: 50,
    source: TableColumns(
      table: "Creature2",
      columns: ["CreationTypeEnum"],
      evidence: "the client's column name in Creature2.tbl (game_table.schema); that its values are the unit types is shown for 4, 8 and 12 by the chooser 0x140479560, which keys Door (creature word 1 == 4), Collect (8) and Mail (12) on it, and is a guess for the others (Creature2.CreationTypeEnum)",
      values: fn(tables) {
        list.map(creature2.all(tables), fn(row) { row.creation_type_enum })
      },
    ),
    handled: Listed(ids: [4, 8, 10, 11, 12, 13, 14]),
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
    quest_rewards(),
    spell_effects(),
    unit_types(),
    messages(),
    spend_scaled_costs(),
  ]
}
