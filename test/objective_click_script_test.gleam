//// What the rule does with a click script, a visible, required, marked type 5 objective of the
//// click table (`genesis_prime/game/objective`, `script_of`, `counts` and `advance`): the
//// activation of a creature of its reward pane counts, and nothing completes it when the quest
//// is accepted. Expected values come from these places.
//// - `QuestObjective.type.5`, `opcode.0x361`: nothing the client sends completes a type 5
////   objective; the server's 0x361 does, and the client then shows it done.
//// - `0x140550c50` (`QuestObjectiveCountsUnit`): a unit of the objective's reward pane
////   TargetGroup counts for an objective whatever its type, and the group test reads the
////   unit's Creature2 id for a type 1 group.
//// - `0x140553790`: flags 1 and 2 keep an objective closed behind the ones before it.
//// - The activation of a creature is the client's 0x97 cast of its own activate spell
////   (`opcode.0x97`); a use by an item's spell is not that cast (`objective.Event` `by_item`).
//// - The order of the server's rules is the one `script_of` documents: a spell or an item
////   that names the objective, the arrival table, the kill table, the click table, the
////   stand-in.
////
//// The client's rows in the fixture (`table_rows -- QuestObjective`, `TargetGroup`, `Quest2`):
//// - quest 6591: objective 16165 (type 22, flags 0), 16170 (type 5, count 1, flags 3, pane 6299
////   = Creature2 51440), 10523 (type 3, flags 57) and 10256 (type 2, flags 7).
//// - quest 5918: objective 8903 (type 12, flags 0), 9002 (type 5, count 1, flags 3, pane 7874 =
////   Creature2 26436) and 9003.

import character_tables
import genesis_prime/game/objective.{
  Advanced, Killed, ReleaseUnit, SendProgress, TalkedTo, Used,
}
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/id.{Creature2Id, Faction2Id, UnitRaceId}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/set
import owned_test
import quest_support

/// The creature of pane 6299, quest 6591's.
const pyrius = 51_440

/// The creature of pane 7874, quest 5918's.
const the_augmentor = 26_436

/// A creature of no pane of these quests.
const a_beast = 73_464

/// A unit of this creature, of faction 0 and race 0: a type 1 pane reads only the creature.
fn unit_of(creature creature: Int) -> target_group.Unit {
  target_group.Unit(
    creature_id: Creature2Id(creature),
    faction_id: Faction2Id(0),
    unit_race_id: UnitRaceId(0),
  )
}

/// The activation of a creature as unit `unit_id`, by the creature's own activate spell or by
/// an item's.
fn activated(
  creature creature: Int,
  unit_id unit_id: Int,
  by_item by_item: Bool,
) -> objective.Event {
  Used(
    target: unit_of(creature:),
    checklist_index: 0,
    unit: quest_support.unit_ref(unit_id:),
    by_item:,
  )
}

/// The rows of the click table these tests use: every objective they name.
fn click_rows(objectives objectives: List(Int)) -> objective.ScriptRows {
  objective.ScriptRows(..objective.no_rows(), clicks: set.from_list(objectives))
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
    clicks: List(Int),
    script: objective.Script,
  )
}

pub fn a_type_5_row_in_the_click_table_is_the_click_script_and_never_a_stand_in_test() -> Nil {
  use <- owned_test.run(60_000)
  let base =
    ScriptCase(
      why: "a visible, required, marked, unlinked row in the table",
      quest_id: 6591,
      index: 1,
      edits: [],
      arrivals: [],
      clicks: [16_170],
      script: objective.ClickScript,
    )
  let cases = [
    base,
    ScriptCase(
      ..base,
      why: "the same row not in the table is the stand-in",
      clicks: [],
      script: objective.StandInOnAccept,
    ),
    ScriptCase(
      ..base,
      why: "a row Spell4Effects 89873 names is the cast's, whatever else lists it",
      quest_id: 3769,
      index: 0,
      clicks: [4849],
      script: objective.NamedAction,
    ),
    ScriptCase(
      ..base,
      why: "a row in the arrival table is a place: the arrival table is read first",
      quest_id: 3667,
      index: 0,
      arrivals: [4770],
      clicks: [4770],
      script: objective.PlaceScript,
    ),
    ScriptCase(
      ..base,
      why: "a hidden row (flag 0x8) waits for its quest, in the table or not",
      edits: [#(16_170, "flags", 3 + 8)],
      script: objective.StandInWithQuest,
    ),
    ScriptCase(
      ..base,
      why: "objective 9659 of quest 6296, a row Creature2 27768 links and here made type 5, is its creature's",
      quest_id: 6296,
      index: 1,
      edits: [#(9659, "type", 5), #(9659, "flags", 0)],
      clicks: [9659],
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
        scripts: click_rows(objectives: row.clicks),
      )
      == row.script
      as row.why
  })
}

/// The log and effects after the event, with the click table holding these objectives.
fn advanced(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  event event: objective.Event,
  clicks clicks: List(Int),
) -> objective.Advanced {
  objective.advance(
    log:,
    tables:,
    event:,
    reused: set.new(),
    scripts: click_rows(objectives: clicks),
    now_ms: 0,
  )
}

/// Whether the event counts for the objective at `index` of a quest, with the click table
/// holding these objectives.
type CountCase {
  CountCase(
    why: String,
    quest_id: Int,
    index: Int,
    clicks: List(Int),
    event: objective.Event,
    counts: Bool,
  )
}

pub fn an_activation_of_a_pane_creature_counts_the_click_script_and_nothing_else_does_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let base =
    CountCase(
      why: "the activation of the creature of pane 6299",
      quest_id: 6591,
      index: 1,
      clicks: [16_170],
      event: activated(creature: pyrius, unit_id: 7, by_item: False),
      counts: True,
    )
  let cases = [
    base,
    CountCase(
      ..base,
      why: "the activation of a creature of no pane",
      event: activated(creature: a_beast, unit_id: 7, by_item: False),
      counts: False,
    ),
    CountCase(
      ..base,
      why: "the activation of quest 5918's creature, which is of another objective's pane",
      event: activated(creature: the_augmentor, unit_id: 7, by_item: False),
      counts: False,
    ),
    CountCase(
      ..base,
      why: "the use of the creature by an item's spell is not its own activate cast",
      event: activated(creature: pyrius, unit_id: 7, by_item: True),
      counts: False,
    ),
    CountCase(
      ..base,
      why: "a talk to the pane creature",
      event: TalkedTo(target: unit_of(creature: pyrius), checklist_index: 0),
      counts: False,
    ),
    CountCase(
      ..base,
      why: "a kill of the pane creature",
      event: Killed(target: unit_of(creature: pyrius)),
      counts: False,
    ),
    CountCase(
      ..base,
      why: "a type 5 row not in the table counts no activation",
      clicks: [],
      counts: False,
    ),
    CountCase(
      ..base,
      why: "quest 5918's objective 9002 counts the activation of the creature of its pane 7874",
      quest_id: 5918,
      index: 1,
      clicks: [9002],
      event: activated(creature: the_augmentor, unit_id: 7, by_item: False),
    ),
  ]
  list.each(cases, fn(row) {
    assert objective.counts(
        tables:,
        event: row.event,
        quest_id: row.quest_id,
        index: row.index,
        objective: objective_at(
          tables:,
          quest_id: row.quest_id,
          index: row.index,
        ),
        scripts: click_rows(objectives: row.clicks),
      )
      == row.counts
      as row.why
  })

  // Quest 6591 with its place objective (16165) done: the click opens, counts, and releases
  // the unit once; the same unit counts nothing again, and nor does another unit of the
  // creature once the count 1 is reached.
  let open = quest_support.logged(tables:, quest_id: 6591, done: [0])
  let first =
    advanced(
      log: open,
      tables:,
      event: activated(creature: pyrius, unit_id: 7, by_item: False),
      clicks: [16_170],
    )
  assert first.effects
    == [
      SendProgress(quest_id: 6591, objective_index: 1, progress: 1),
      ReleaseUnit(unit_id: 7),
    ]
    as "opcode.0x361 sets the count 1; the kill objective 10256 behind it keeps the quest Accepted; the used unit is released once"
  assert advanced(
      log: first.log,
      tables:,
      event: activated(creature: pyrius, unit_id: 7, by_item: False),
      clicks: [16_170],
    )
    == Advanced(log: first.log, effects: [])
    as "the same unit counts once"
  assert advanced(
      log: first.log,
      tables:,
      event: activated(creature: pyrius, unit_id: 8, by_item: False),
      clicks: [16_170],
    )
    == Advanced(log: first.log, effects: [])
    as "a done objective counts nothing for another unit"

  // The server offers a use of the creature only while an open objective counts it
  // (`use_targets`): the click row's pane creature, and only with the click table.
  let offered = fn(clicks) {
    objective.use_targets(
      log: open,
      tables:,
      scripts: click_rows(objectives: clicks),
    )(unit_of(creature: pyrius), 0, quest_support.unit_ref(unit_id: 7))
  }
  assert offered([16_170])
    as "an open click row offers a use of its pane creature"
  assert !offered([]) as "a type 5 row not in the click table offers none"

  // Closed behind an earlier objective: 16170's flags 3 keep it closed while 16165 is open.
  let closed = quest_support.logged(tables:, quest_id: 6591, done: [])
  assert advanced(
      log: closed,
      tables:,
      event: activated(creature: pyrius, unit_id: 7, by_item: False),
      clicks: [16_170],
    )
    == Advanced(log: closed, effects: [])
    as "0x140553790: an objective of flags 3 counts nothing while the one before it is open"
}
