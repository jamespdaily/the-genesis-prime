//// The QuestAdvanceObjective rule (`genesis_prime/game/quest_advance`): what a spell's type 42
//// rows do to the player's quest log and what the client is told. Expected values come from
//// these places.
//// - `Spell4Effects.effectType.42`: the row's dataBits00 is a Quest2 id, dataBits01 the
////   objective's index and dataBits02 the amount, and the client holds no effect for it.
//// - `0x140551840` and `0x1405515c0`: an objective's needed count, and the thousandths a
////   percent kind of kill objective stores (an objective of a count above 1 and no flag 0x200).
//// - `opcode.0x361` and `opcode.0x35c`: the progress of one objective, and the quest's state 2
////   once its last open objective is done.
//// - `0x1405510d0` and `0x140553790`: an objective takes progress only while its quest is in
////   the active list and it is not done and not closed behind another.
//// - The client's rows in the fixture (`table_rows -- QuestObjective`):
////   quest 3769 objective 4849 (type 5, count 5); quest 3785 objective 4900 (type 8, count 5,
////   TargetGroup 2124); quest 8262 objectives 15009 (type 14, count 4, flags 128), 15010
////   (type 14, count 2) and 15555 to 15557 (type 5, flags 8, count 3); quest 4982 objective
////   7091 (type 5, count 3, flags 16) which Creature2 19308 links (questAnimStateId 4982,
////   questAnimObjectiveIndex 0); quest 9207 objective 17932 (type 12, Creature2 58487, count
////   1); quest 6805 objective 11577 (type 11, Spell4 35424, count 1, flags 16); quest 3741
////   objective 4813 (type 32, count 6); quest 1823 objective 1915 (type 14, count 3).
//// - A server choice, named in the module doc: a checklist takes no advance, and one count a
////   cast.

import genesis_prime/game/communicator
import genesis_prime/game/objective.{
  type Advanced, type Effect, type Event, Advanced, Cast, CastTarget,
  CompleteByServer, SendProgress, SendState, Used,
}
import genesis_prime/game/quest_advance.{type Advance, Advance}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/id.{Quest2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import quest_support

/// The log after the rows, and what the advances do to it, on the fixture's tables.
fn advanced(
  rows rows: List(QuestRow),
  advances advances: List(Advance),
  with with: Option(Event),
) -> #(QuestLog, Advanced) {
  use tables <- quest_support.with_objectives(edits: [])
  advanced_on(tables:, rows:, advances:, with:)
}

fn advanced_on(
  tables tables: table_store.Tables,
  rows rows: List(QuestRow),
  advances advances: List(Advance),
  with with: Option(Event),
) -> #(QuestLog, Advanced) {
  let log = quest_support.log_of(rows:)
  #(log, quest_advance.advance(log:, tables:, advances:, with:, now_ms: 0))
}

/// The progress each `SendProgress` of the effects carries, in order.
fn progresses(effects effects: List(Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      SendProgress(progress:, ..) -> Ok(progress)
      SendState(..) | CompleteByServer(..) | objective.ReleaseUnit(..) ->
        Error(Nil)
    }
  })
}

fn states(effects effects: List(Effect)) -> List(#(Int, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      SendState(quest_id:, state:) -> Ok(#(quest_id, state))
      SendProgress(..) | CompleteByServer(..) | objective.ReleaseUnit(..) ->
        Error(Nil)
    }
  })
}

/// One advance of one objective.
fn one(
  quest quest: Int,
  index index: Int,
  amount amount: Int,
) -> List(Advance) {
  [Advance(quest_id: quest, objective_index: index, amount:)]
}

/// Quest 8262 with objectives 0 and 1 (checklists) done and these progress values for the
/// hidden type 5 objectives 2 to 4, whose done bits follow their counts of 3.
fn ignite_tower(progress progress: List(Int)) -> QuestRow {
  let done =
    list.index_fold(progress, 0b11, fn(mask, value, place) {
      case value >= 3 {
        True -> int.bitwise_or(mask, int.bitwise_shift_left(1, place + 2))
        False -> mask
      }
    })
  quest_support.active(
    quest_id: 8262,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: done,
    progress: [0b1111, 0b11, ..progress],
  )
}

type AmountCase {
  AmountCase(
    why: String,
    rows: List(QuestRow),
    advances: List(Advance),
    progress: List(Int),
    state: List(#(Int, Int)),
  )
}

pub fn a_spell_advance_adds_its_amount_capped_at_the_count_for_each_objective_kind_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      AmountCase(
        "a count objective takes the amount: quest 3769's type 5 of count 5, 0 and 1",
        [quest_support.accepted(quest_id: 3769, progress: [0])],
        one(quest: 3769, index: 0, amount: 1),
        [1],
        [],
      ),
      AmountCase(
        "an amount of 2 adds 2: 1 and 2 are 3",
        [quest_support.accepted(quest_id: 3769, progress: [1])],
        one(quest: 3769, index: 0, amount: 2),
        [3],
        [],
      ),
      AmountCase(
        "the sum is capped at the count: 4 and 2 are 5, which finishes the quest",
        [quest_support.accepted(quest_id: 3769, progress: [4])],
        one(quest: 3769, index: 0, amount: 2),
        [5],
        [#(3769, 2)],
      ),
      AmountCase(
        "a done objective takes nothing more",
        [
          quest_support.active(
            quest_id: 3769,
            state: 2,
            placeholder: 0,
            tracked: False,
            done_mask: 0b1,
            progress: [5],
          ),
        ],
        one(quest: 3769, index: 0, amount: 1),
        [],
        [],
      ),
      AmountCase(
        "quest 8262's hidden type 5 objective of count 3: an amount of 2 on 1 completes it, and its siblings still wait",
        [ignite_tower(progress: [1, 0, 0])],
        one(quest: 8262, index: 2, amount: 2),
        [3],
        [],
      ),
      AmountCase(
        "the last of the quest's objectives to complete, and the quest is Achieved",
        [ignite_tower(progress: [1, 3, 3])],
        one(quest: 8262, index: 2, amount: 2),
        [3],
        [#(8262, 2)],
      ),
      AmountCase(
        "a type 32 objective of count 6 takes 2 as a count",
        [quest_support.accepted(quest_id: 3741, progress: [5])],
        one(quest: 3741, index: 0, amount: 2),
        [6],
        [#(3741, 2)],
      ),
    ],
    fn(row) {
      let #(log, advanced) =
        advanced(rows: row.rows, advances: row.advances, with: None)
      assert progresses(effects: advanced.effects) == row.progress as row.why
      assert states(effects: advanced.effects) == row.state as row.why
      assert row.progress != [] || advanced.log == log as row.why
    },
  )
}

pub fn a_percent_kill_objective_stores_thousandths_of_its_count_for_each_amount_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 3785's objective 4900 is a type 8 of count 5 and no flag 0x200: a percent kind
  // (`0x1405515c0`), so an amount of 1 is one kill, 200 of 1000.
  let advance = one(quest: 3785, index: 0, amount: 1)
  use tables <- quest_support.with_objectives(edits: [])
  let #(log, effects) =
    list.fold(
      [200, 400, 600, 800, 1000],
      #(
        quest_support.log_of(rows: [
          quest_support.accepted(quest_id: 3785, progress: [0]),
        ]),
        [],
      ),
      fn(so_far, _) {
        let advanced =
          quest_advance.advance(
            log: so_far.0,
            tables:,
            advances: advance,
            with: None,
            now_ms: 0,
          )
        #(advanced.log, list.append(so_far.1, advanced.effects))
      },
    )
  assert progresses(effects:) == [200, 400, 600, 800, 1000]
    as "each amount of 1 is a fifth of 1000"
  assert states(effects:) == [#(3785, 2)] as "the fifth kill finishes the quest"
  let again =
    quest_advance.advance(
      log:,
      tables:,
      advances: advance,
      with: None,
      now_ms: 0,
    )
  assert again.effects == [] && again.log == log
    as "a done objective takes nothing"
}

pub fn a_type_12_objective_of_a_count_above_1_takes_the_amount_test() -> Nil {
  use <- owned_test.run(60_000)
  // No real quest holds a type 12 objective of a count above 1 that the fixture has, so
  // objective 17932 of quest 9207 (type 12, count 1) is given a count of 3.
  use tables <- quest_support.with_objectives(edits: [#(17_932, "count", 3)])
  let #(_, advanced) =
    advanced_on(
      tables:,
      rows: [quest_support.accepted(quest_id: 9207, progress: [0])],
      advances: one(quest: 9207, index: 0, amount: 2),
      with: None,
    )
  assert advanced.effects
    == [SendProgress(quest_id: 9207, objective_index: 0, progress: 2)]
    as "2 of 3 and no state"
}

type NothingCase {
  NothingCase(why: String, rows: List(QuestRow), advances: List(Advance))
}

pub fn a_spell_advance_changes_nothing_for_an_objective_that_takes_no_progress_test() -> Nil {
  use <- owned_test.run(60_000)
  let gated_chain = 3668
  list.each(
    [
      NothingCase(
        "a quest that is not in the log",
        [],
        one(quest: 3769, index: 0, amount: 1),
      ),
      NothingCase(
        "a quest the player finished",
        [quest_support.completed(quest_id: 3769, at: 1)],
        one(quest: 3769, index: 0, amount: 1),
      ),
      NothingCase(
        "a quest the client holds only as Botched (state 4)",
        [quest_support.known(quest_id: 3769, state: 4)],
        one(quest: 3769, index: 0, amount: 1),
      ),
      NothingCase(
        "an index past the quest's objectives",
        [quest_support.accepted(quest_id: 3769, progress: [0])],
        one(quest: 3769, index: 4, amount: 1),
      ),
      NothingCase(
        "a negative index",
        [quest_support.accepted(quest_id: 3769, progress: [0])],
        one(quest: 3769, index: -1, amount: 1),
      ),
      NothingCase(
        "an objective closed behind an earlier one: quest 3668's objective 1 (flags 7) waits for objective 0",
        [quest_support.accepted(quest_id: gated_chain, progress: [0, 0, 0])],
        one(quest: gated_chain, index: 1, amount: 1),
      ),
      NothingCase(
        "a quest id the tables have no row for",
        [quest_support.accepted(quest_id: 3769, progress: [0])],
        one(quest: 32_000, index: 0, amount: 1),
      ),
      NothingCase(
        "a checklist, whose stored value is a mask of units: quest 1823's type 14",
        [quest_support.accepted(quest_id: 1823, progress: [0])],
        one(quest: 1823, index: 0, amount: 1),
      ),
      NothingCase(
        "a checklist of a quest with other objectives: quest 8262's objective 1, type 14",
        [
          ignite_tower(progress: [0, 0, 0]),
          quest_support.accepted(quest_id: 1823, progress: [0]),
        ],
        one(quest: 8262, index: 1, amount: 1),
      ),
    ],
    fn(row) {
      let #(log, advanced) =
        advanced(rows: row.rows, advances: row.advances, with: None)
      assert advanced == Advanced(log:, effects: []) as row.why
    },
  )
}

fn used(creature creature: Int, by_item by_item: Bool) -> Option(Event) {
  Some(Used(
    target: quest_support.unit_of(creature:),
    checklist_index: 0,
    unit: Some(quest_support.unit_ref(unit_id: creature)),
    by_item:,
  ))
}

type EventCase {
  EventCase(
    why: String,
    quest: Int,
    index: Int,
    event: Option(Event),
    progress: List(Int),
  )
}

pub fn a_spell_advance_skips_the_objective_its_own_cast_event_counts_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      EventCase(
        "a use of the creature a type 5 objective links counts it (Creature2 19308 links quest 4982's objective 0), so the row skips it",
        4982,
        0,
        used(creature: 19_308, by_item: False),
        [],
      ),
      EventCase(
        "the same use by an item counts no linked objective, so the row counts it",
        4982,
        0,
        used(creature: 19_308, by_item: True),
        [1],
      ),
      EventCase(
        "a use of the creature a type 12 objective names counts it: quest 9207's data is Creature2 58487",
        9207,
        0,
        used(creature: 58_487, by_item: False),
        [],
      ),
      EventCase(
        "a use of another creature counts no type 12 objective of that data, so the row counts it",
        9207,
        0,
        used(creature: 12_484, by_item: False),
        [1],
      ),
      EventCase(
        "a cast of the spell a type 11 objective names counts it (quest 6805's objective 11577 names Spell4 35424)",
        6805,
        0,
        Some(Cast(spell4_id: Spell4Id(35_424), target: None)),
        [],
      ),
      EventCase(
        "a cast of another spell counts no type 11 objective of that spell, so the row counts it",
        6805,
        0,
        Some(Cast(spell4_id: Spell4Id(1), target: None)),
        [1],
      ),
      EventCase(
        "a use counts no kill objective (type 8), so the row advances quest 3785's objective by a fifth",
        3785,
        0,
        used(creature: 19_308, by_item: False),
        [200],
      ),
      EventCase(
        "no event of the cast's own counts nothing, so the row counts it",
        4982,
        0,
        None,
        [1],
      ),
    ],
    fn(row) {
      let #(_, advanced) =
        advanced(
          rows: [quest_support.untouched(quest_id: row.quest)],
          advances: one(quest: row.quest, index: row.index, amount: 1),
          with: row.event,
        )
      assert progresses(effects: advanced.effects) == row.progress as row.why
    },
  )
  // A cast at a unit counts a unit of the objective's reward pane only, and this one has none,
  // so any unit counts it.
  let at_a_unit =
    Some(Cast(
      spell4_id: Spell4Id(35_424),
      target: Some(CastTarget(
        unit: quest_support.unit_of(creature: 31_734),
        ref: quest_support.unit_ref(unit_id: 5),
      )),
    ))
  let #(_, advanced) =
    advanced(
      rows: [quest_support.untouched(quest_id: 6805)],
      advances: one(quest: 6805, index: 0, amount: 1),
      with: at_a_unit,
    )
  assert progresses(effects: advanced.effects) == []
    as "a cast of the named spell at a unit counts the objective, so the row skips it"
}

pub fn a_spell_advance_sends_progress_in_objective_order_then_the_state_and_completion_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_objectives(edits: [])
  // The advances name objective 3 before objective 2 of quest 8262, whose objective 4 is done.
  let advanced =
    quest_advance.advance(
      log: quest_support.log_of(rows: [ignite_tower(progress: [1, 1, 3])]),
      tables:,
      advances: [
        Advance(quest_id: 8262, objective_index: 3, amount: 2),
        Advance(quest_id: 8262, objective_index: 2, amount: 2),
      ],
      with: None,
      now_ms: 0,
    )
  let assert Ok(quest) = quest2.get(tables:, id: Quest2Id(8262))
    as "quest 8262 is in the fixture"
  assert advanced.effects
    == list.flatten([
      [
        SendProgress(quest_id: 8262, objective_index: 2, progress: 3),
        SendProgress(quest_id: 8262, objective_index: 3, progress: 3),
        SendState(quest_id: 8262, state: 2),
      ],
      case communicator.completed_by_server(tables:, quest:) {
        True -> [CompleteByServer(quest_id: 8262)]
        False -> []
      },
    ])
    as "opcode.0x361 in objective order, then one 0x35c state 2, then the server's completion exactly when no creature receives the quest"
  // Two quests: each one's effects in quest id order, whatever the order of the advances.
  let two =
    quest_advance.advance(
      log: quest_support.log_of(rows: [
        ignite_tower(progress: [1, 3, 3]),
        quest_support.accepted(quest_id: 3769, progress: [0]),
      ]),
      tables:,
      advances: [
        Advance(quest_id: 8262, objective_index: 2, amount: 2),
        Advance(quest_id: 3769, objective_index: 0, amount: 1),
      ],
      with: None,
      now_ms: 0,
    )
  assert list.filter_map(two.effects, fn(effect) {
      case effect {
        SendProgress(quest_id:, ..) -> Ok(quest_id)
        SendState(..) | CompleteByServer(..) | objective.ReleaseUnit(..) ->
          Error(Nil)
      }
    })
    == [3769, 8262]
    as "quest 3769's progress comes before quest 8262's"
  // The completion follows the state only for a quest no creature receives, which
  // `communicator.completed_by_server` tells.
  let finishing = [
    #(3769, [4], 0, 1),
    #(3785, [800], 0, 1),
    #(3741, [5], 0, 1),
    #(9207, [0], 0, 1),
  ]
  let completed =
    list.map(finishing, fn(finish) {
      let #(quest_id, progress, index, amount) = finish
      let finished =
        quest_advance.advance(
          log: quest_support.log_of(rows: [
            quest_support.accepted(quest_id:, progress:),
          ]),
          tables:,
          advances: one(quest: quest_id, index:, amount:),
          with: None,
          now_ms: 0,
        )
      let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
        as "the quest is in the fixture"
      let completes = communicator.completed_by_server(tables:, quest: row)
      assert list.drop(finished.effects, 1)
        == [
          SendState(quest_id:, state: 2),
          ..case completes {
            True -> [CompleteByServer(quest_id:)]
            False -> []
          }
        ]
        as "the progress, then state 2, then the completion only for a quest no creature receives"
      completes
    })
  assert list.contains(completed, True) && list.contains(completed, False)
    as "the quests the test finishes include one the server completes and one a creature receives"
}
