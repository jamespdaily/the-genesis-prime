//// What the rule does with a kill script, a visible, required, marked type 5 objective of the
//// kill table (`genesis_prime/game/objective`, `script_of`, `counts` and `settle`): the
//// kill of a creature of its reward pane counts, and nothing completes it when the quest is
//// accepted. Expected values come from these places.
//// - `QuestObjective.type.5`, `opcode.0x361`: nothing the client sends completes a type 5
////   objective; the server's 0x361 does, and the client then shows it done.
//// - `0x140550c50` (`QuestObjectiveCountsUnit`): a unit of the objective's reward pane
////   TargetGroup counts for an objective whatever its type, and the group test reads the
////   unit's Creature2 id for a type 1 group, the groups a type 11 group names for a union.
//// - `0x1405fb830`, `0x1405fbc40`: a 0x361 sets the progress, the done bit is set when it
////   reaches the count, and the quest is Achieved once every objective without flag 0x20 is
////   done. `0x140553790`: flags 1 and 2 keep an objective closed behind the ones before it.
//// - The order of the server's rules is the one `script_of` documents: a spell or an item
////   that names the objective, the arrival table, the kill table, the stand-in.
////
//// The client's rows in the fixture (`table_rows -- QuestObjective`, `TargetGroup`, `Quest2`):
//// - quest 5895: objective 8866 (type 5, count 1, flags 0x14, pane 5256 = Creature2 26037)
////   and 8936 (type 2, Creature2 26042, flags 7); its twin quest 5896 has 8867 on the same
////   pane. Creature2 26206 and 26207 receive them, so the server does not complete them.
//// - quest 5535: 15786 (flags 0) then 8281 (type 5, count 25, flags 7, pane 2539 = Creature2
////   24039, 24040, 24041, 24042 and 54033).
//// - quest 3170: 4324 (type 3) then 15996 (type 5, flags 3, pane 6336 = Creature2 9635).
//// - quest 5444: 8008 (type 3), 8010 (type 5, count 7, flags 531, pane 2451, a type 11 union of
////   groups 2452 and 9152; group 9152 lists Creature2 61532) and 8586 (flags 33, optional).

import character_tables
import genesis_prime/game/objective.{Advanced, Killed, SendProgress, SendState}
import genesis_prime/game/quest_log
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_group
import genesis_prime/table/id.{Creature2Id, Faction2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/list
import gleam/set
import owned_test
import place_support
import quest_support
import spawn_support

/// 2025-04-24 20:26:40 UTC in Unix milliseconds, the time of the connection tests.
const unix_ms = 1_745_526_400_000

const the_scientist = 26_037

/// A unit of this creature, of the faction and race of the Creature2 row of 26037 (the
/// scientist): a type 1 pane reads only the creature, so these must not count anything.
fn killed(creature creature: Int) -> objective.Event {
  Killed(target_group.Unit(
    creature_id: Creature2Id(creature),
    faction_id: Faction2Id(340),
    unit_race_id: UnitRaceId(129),
  ))
}

/// The rows of the kill table these tests use: every kill objective of the table that
/// the tests name.
fn kill_rows(objectives objectives: List(Int)) -> objective.ScriptRows {
  objective.ScriptRows(..objective.no_rows(), kills: set.from_list(objectives))
}

/// The quest as the log reads it, with the objective at `index`.
fn objective_at(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> quest_log.Objective {
  let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
    as "the fixture holds the quest"
  let assert Ok(found) = list.drop(quest.objectives, index) |> list.first
    as "the quest has an objective at the index"
  found
}

/// What `script_of` says of the objective at `index` of a quest, over the fixture with
/// these QuestObjective cells edited (objective, column, value).
type ScriptCase {
  ScriptCase(
    why: String,
    quest_id: Int,
    index: Int,
    edits: List(#(Int, String, Int)),
    arrivals: List(Int),
    kills: List(Int),
    script: objective.Script,
  )
}

pub fn a_type_5_row_in_the_kill_table_is_the_kill_script_and_never_a_stand_in_test() -> Nil {
  use <- owned_test.run(60_000)
  let base =
    ScriptCase(
      why: "a visible, required, marked, unlinked row in the table",
      quest_id: 3170,
      index: 1,
      edits: [],
      arrivals: [],
      kills: [15_996],
      script: objective.KillScript,
    )
  let cases = [
    base,
    ScriptCase(
      ..base,
      why: "the same row not in the table is the stand-in",
      kills: [],
      script: objective.StandInOnAccept,
    ),
    ScriptCase(
      ..base,
      why: "a row Spell4Effects 89873 names is the cast's, whatever else lists it",
      quest_id: 3769,
      index: 0,
      kills: [4849],
      script: objective.NamedAction,
    ),
    ScriptCase(
      ..base,
      why: "a row in the arrival table is a place: the arrival table is read first",
      quest_id: 3667,
      index: 0,
      arrivals: [4770],
      kills: [4770],
      script: objective.PlaceScript,
    ),
    ScriptCase(
      ..base,
      why: "a hidden row (flag 0x8) waits for its quest, in the table or not",
      edits: [#(15_996, "flags", 3 + 8)],
      script: objective.StandInWithQuest,
    ),
    ScriptCase(
      ..base,
      why: "objective 9659 of quest 6296, a row Creature2 27768 links and here made type 5, is its creature's",
      quest_id: 6296,
      index: 1,
      edits: [#(9659, "type", 5), #(9659, "flags", 0)],
      kills: [9659],
      script: objective.UsedByCreature,
    ),
  ]
  list.each(cases, fn(row) {
    use tables <- quest_support.with_objectives(edits: row.edits)
    assert objective.script_of(
        tables:,
        quest_id: row.quest_id,
        index: row.index,
        objective: objective_at(
          tables:,
          quest_id: row.quest_id,
          index: row.index,
        ),
        arrival_objectives: set.from_list(row.arrivals),
        scripts: kill_rows(objectives: row.kills),
      )
      == row.script
      as row.why
  })
}

/// Whether the kill of a unit counts for the objective at `index` of a quest, with the
/// kill table holding these objectives.
type CountCase {
  CountCase(
    why: String,
    quest_id: Int,
    index: Int,
    kills: List(Int),
    killed: objective.Event,
    counts: Bool,
  )
}

pub fn a_kill_of_a_pane_creature_counts_the_kill_script_and_no_other_kill_does_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let base =
    CountCase(
      why: "the creature of pane 5256",
      quest_id: 5895,
      index: 0,
      kills: [8866],
      killed: killed(creature: the_scientist),
      counts: True,
    )
  let cases = [
    base,
    CountCase(
      ..base,
      why: "a creature of no pane",
      killed: killed(creature: 73_464),
      counts: False,
    ),
    CountCase(
      ..base,
      why: "the creature of the second group (9152) of the union pane 2451",
      quest_id: 5444,
      index: 1,
      kills: [8010],
      killed: killed(creature: 61_532),
    ),
    CountCase(
      ..base,
      why: "a creature of the first group (2452) of the union pane",
      quest_id: 5444,
      index: 1,
      kills: [8010],
      killed: killed(creature: 9633),
    ),
    CountCase(
      ..base,
      why: "a creature of another objective's pane (6336 lists 9635, not 26037)",
      quest_id: 3170,
      index: 1,
      kills: [15_996],
      counts: False,
    ),
    CountCase(
      ..base,
      why: "a type 5 row not in the table counts nothing",
      kills: [],
      counts: False,
    ),
  ]
  list.each(cases, fn(row) {
    assert objective.counts(
        tables:,
        event: row.killed,
        quest_id: row.quest_id,
        index: row.index,
        objective: objective_at(
          tables:,
          quest_id: row.quest_id,
          index: row.index,
        ),
        scripts: kill_rows(objectives: row.kills),
      )
      == row.counts
      as row.why
  })
}

/// The effects of the kill on the log, and the log after it.
fn slain(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  creature creature: Int,
  kills kills: List(Int),
) -> objective.Advanced {
  objective.advance(
    log:,
    tables:,
    event: killed(creature:),
    reused: set.new(),
    scripts: kill_rows(objectives: kills),
    now_ms: 0,
  )
}

pub fn kills_bring_a_kill_script_to_its_count_and_achieve_its_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // Count 1: quest 5895's 8866, with its second objective 8936 done.
  let one = quest_support.logged(tables:, quest_id: 5895, done: [1])
  let first = slain(log: one, tables:, creature: the_scientist, kills: [8866])
  assert first.effects
    == [
      SendProgress(quest_id: 5895, objective_index: 0, progress: 1),
      SendState(quest_id: 5895, state: 2),
    ]
    as "opcode.0x361 sets the count 1, and the quest is Achieved: its other objective is done and Creature2 26206 receives it"
  assert slain(log: first.log, tables:, creature: the_scientist, kills: [8866])
    == Advanced(log: first.log, effects: [])
    as "a done objective counts nothing"

  // Count 7: quest 5444's 8010 (pane 2451, eight creatures) after its talk objective.
  let seven = quest_support.logged(tables:, quest_id: 5444, done: [0])
  let #(_, told) =
    list.fold(one_to(last: 7), #(seven, []), fn(so_far, _) {
      let advanced =
        slain(log: so_far.0, tables:, creature: 61_532, kills: [8010])
      #(advanced.log, list.append(so_far.1, [advanced.effects]))
    })
  assert told
    == list.append(
      list.map(one_to(last: 6), fn(progress) {
        [SendProgress(quest_id: 5444, objective_index: 1, progress:)]
      }),
      [
        [
          SendProgress(quest_id: 5444, objective_index: 1, progress: 7),
          SendState(quest_id: 5444, state: 2),
        ],
      ],
    )
    as "each kill adds one, and only the seventh, the count, achieves the quest: objective 8586 of the quest is optional (flag 0x20)"

  // Count 25: quest 5535's 8281 after its first objective, over the five creatures of pane 2539.
  let twenty_five = quest_support.logged(tables:, quest_id: 5535, done: [0])
  let creatures = [24_039, 24_040, 24_041, 24_042, 54_033]
  let #(_, effects) =
    list.fold(one_to(last: 25), #(twenty_five, []), fn(so_far, number) {
      let advanced =
        slain(
          log: so_far.0,
          tables:,
          creature: pick(from: creatures, number:),
          kills: [
            8281,
          ],
        )
      #(advanced.log, list.append(so_far.1, advanced.effects))
    })
  assert effects
    == list.append(
      list.map(one_to(last: 25), fn(progress) {
        SendProgress(quest_id: 5535, objective_index: 1, progress:)
      }),
      [SendState(quest_id: 5535, state: 2)],
    )
    as "25 kills of any of the pane's creatures: one 0x361 each, and the 25th achieves the quest"

  // Closed behind an earlier objective: quest 3170's 15996 has flags 3 and objective 4324
  // (type 3) before it is not done.
  let closed = quest_support.logged(tables:, quest_id: 3170, done: [])
  assert slain(log: closed, tables:, creature: 9635, kills: [15_996])
    == Advanced(log: closed, effects: [])
    as "0x140553790: an objective of flags 3 counts nothing while the one before it is open"

  // Two quests open on the same pane.
  let twins =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 5895,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b10,
        progress: [0, 1],
      ),
      quest_support.active(
        quest_id: 5896,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b10,
        progress: [0, 1],
      ),
    ])
  assert slain(log: twins, tables:, creature: the_scientist, kills: [8866, 8867]).effects
    == [
      SendProgress(quest_id: 5895, objective_index: 0, progress: 1),
      SendState(quest_id: 5895, state: 2),
      SendProgress(quest_id: 5896, objective_index: 0, progress: 1),
      SendState(quest_id: 5896, state: 2),
    ]
    as "each quest open on pane 5256 counts the one kill, in quest id order"
}

/// The numbers 1 to `last`.
fn one_to(last last: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, last), fn(_, index) { index + 1 })
}

/// The `number`th element, counting from 1 and cycling.
fn pick(from from: List(Int), number number: Int) -> Int {
  let assert Ok(found) =
    list.drop(from, { number - 1 } % list.length(from))
    |> list.first
    as "the list is not empty"
  found
}

/// A place away from every marker, in the world of the quest's marker.
fn away() -> Place {
  place_support.at(world_id: 51, world_zone_id: 1, x: 0.0, y: 0.0, z: 0.0)
}

fn settle(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  kills kills: List(Int),
) -> objective.Advanced {
  objective.settle(
    log:,
    tables:,
    items: [],
    zones: [],
    place: away(),
    shown: dict.new(),
    numbers: spawn_support.numbers,
    arrival_objectives: set.new(),
    held_objectives: set.new(),
    unix_ms:,
    now_ms: 0,
    scripts: kill_rows(objectives: kills),
  )
}

pub fn settling_leaves_a_kill_script_open_and_completes_the_stand_ins_around_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 5895's second objective, 8936, made a hidden type 5 stand-in (flags 8, data 0):
  // it waits for every other required objective of its quest.
  use tables <- quest_support.with_objectives(edits: [
    #(8936, "type", 5),
    #(8936, "flags", 8),
    #(8936, "data", 0),
  ])
  let accepted = quest_support.logged(tables:, quest_id: 5895, done: [])
  assert settle(log: accepted, tables:, kills: [8866])
    == Advanced(log: accepted, effects: [])
    as "at accept the kill script has no progress, and the hidden stand-in waits for it"
  assert settle(log: accepted, tables:, kills: []).effects != []
    as "without the kill table the same objective is a stand-in on accept: the rule this step replaces"
  let killed =
    slain(log: accepted, tables:, creature: the_scientist, kills: [8866])
  assert killed.effects
    == [SendProgress(quest_id: 5895, objective_index: 0, progress: 1)]
    as "the kill counts the kill script"
  let settled = settle(log: killed.log, tables:, kills: [8866])
  assert settled.effects
    == [
      SendProgress(quest_id: 5895, objective_index: 1, progress: 1),
      SendState(quest_id: 5895, state: 2),
    ]
    as "once the kill is done the hidden stand-in completes with the quest"
}
