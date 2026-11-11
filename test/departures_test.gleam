//// The departures terminals (`genesis_prime/game/departures`): which log opens each
//// terminal's link (read by `objective_link.of` from the creature's own columns), where
//// each lands the player, and which choice objective is whose. Expected values come from
//// these places.
//// - Prerequisite 41793 (Exile) and 42982 (Dominion), the terminals' prerequisiteIdAnimState:
////   any of three conditions, flags 1: type 43 (objective 1 of the quest is open), type 6 with
////   value 2 (the quest is Achieved) or value 3 (Completed). The offer is open in those three
////   states of the faction's quest and closed otherwise.
//// - Quest2 10528 (Exile) and 10530 (Dominion): "Bon Voyage". Their objectives, in slot
////   order: the talk (type 3, 21326 / 21347), the travel (type 23, flags 3, 21327 /
////   21348), a choice per terminal (type 23, flags 33, 21328 and 21329 / 21349 and
////   21350) and an optional type 14 (flags 41). The travel's flag 2 makes it reachable
////   once the talk, the one earlier objective without flag 0x20, is done.
//// - The landings are the client's WorldLocation2 rows: 42074 (world 426, zone 648),
////   41641 (990, 1417), 42148 (1387, 1411) and 8223 (870, 1236), each matched to its
////   terminal by the names of the terminal, its spell and the choice objective
////   (Northern Wilds, Everstar Grove, Levian Bay, Crimson Isle).

import cast_support
import character_tables
import fixture_tables
import genesis_prime/game/activate.{type Link, ClosedLink, OpenLink}
import genesis_prime/game/cast
import genesis_prime/game/departures.{NotATerminal, TravelClosed}
import genesis_prime/game/objective_link
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}
import quest_support

const northern_wilds = 73_606

const everstar_grove = 73_605

const levian_bay = 74_773

const crimson_isle = 74_772

/// The Exile's log after the talk (objective 0 of Quest2 10528).
fn exile_after_the_talk() -> QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id: 10_528,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 1,
      progress: [1, 0, 0, 0, 0],
    ),
  ])
}

/// The Dominion's log after the talk (objective 0 of Quest2 10530).
fn dominion_after_the_talk() -> QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id: 10_530,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 1,
      progress: [1, 0, 0, 0, 0],
    ),
  ])
}

/// The link of a creature's right-click for a player holding this log, as the rule that
/// reads it gives it (`objective_link.of`).
fn link_of(quests quests: QuestLog, creature_id creature_id: Int) -> Link {
  let tables = character_tables.shared()
  let assert Ok(row) = creature2.get(tables:, id: Creature2Id(creature_id))
    as "the creature is a root of the fixture"
  objective_link.of(
    tables:,
    activations: activate.activations(tables:),
    subject: cast.subject_for_use(
      cast: cast.new(),
      caster: cast.Caster(..cast_support.caster(), quests:),
      unit_id: 5000,
      checklist_index: 0,
    ),
    quests:,
    row:,
    checklist_index: 0,
  )
}

fn assert_place(
  landing landing: Result(Place, departures.Refusal),
  world world: Int,
  zone zone: Int,
  x x: Float,
  y y: Float,
  z z: Float,
  reason reason: String,
) -> Nil {
  let assert Ok(place) = landing as reason
  assert start_place.world_id(place) == world as reason
  assert start_place.world_zone_id(place) == zone as reason
  assert start_place.x(place) == x as reason
  assert start_place.y(place) == y as reason
  assert start_place.z(place) == z as reason
}

pub fn each_terminal_lands_at_its_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let exile = exile_after_the_talk()
  let dominion = dominion_after_the_talk()
  assert_place(
    landing: departures.landing(
      tables:,
      quests: exile,
      creature_id: Creature2Id(northern_wilds),
    ),
    world: 426,
    zone: 648,
    x: 4098.16015625,
    y: -665.9780883789062,
    z: -5165.10009765625,
    reason: "WorldLocation2 42074, the Northern Wilds landing",
  )
  assert_place(
    landing: departures.landing(
      tables:,
      quests: exile,
      creature_id: Creature2Id(everstar_grove),
    ),
    world: 990,
    zone: 1417,
    x: -768.36572265625,
    y: -904.805419921875,
    z: -2275.0791015625,
    reason: "WorldLocation2 41641, the Everstar Grove landing",
  )
  assert_place(
    landing: departures.landing(
      tables:,
      quests: dominion,
      creature_id: Creature2Id(levian_bay),
    ),
    world: 1387,
    zone: 1411,
    x: -3835.7451171875,
    y: -980.21728515625,
    z: -6053.263671875,
    reason: "WorldLocation2 42148, the Levian Bay landing",
  )
  assert_place(
    landing: departures.landing(
      tables:,
      quests: dominion,
      creature_id: Creature2Id(crimson_isle),
    ),
    world: 870,
    zone: 1236,
    x: -8260.708984375,
    y: -995.0770263671875,
    z: -239.0409393310547,
    reason: "WorldLocation2 8223, the Crimson Isle landing",
  )
}

pub fn a_terminal_with_travel_open_is_an_open_link_test() -> Nil {
  use <- owned_test.run(60_000)
  assert link_of(quests: exile_after_the_talk(), creature_id: northern_wilds)
    == OpenLink
    as "Quest2 10528's travel objective 21327 is open once the talk is done: Prerequisite 41793's type 43 condition passes and the Northern Wilds terminal is offered"
  assert link_of(quests: exile_after_the_talk(), creature_id: everstar_grove)
    == OpenLink
    as "either terminal of the faction is offered while its travel is open"
  assert link_of(quests: dominion_after_the_talk(), creature_id: crimson_isle)
    == OpenLink
    as "Quest2 10530's travel objective 21348 is open once the talk is done: Prerequisite 42982 passes and the Crimson Isle terminal is offered"
}

pub fn a_player_without_bon_voyage_meets_a_closed_terminal_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log = quest_support.log_of(rows: [])
  assert link_of(quests: log, creature_id: northern_wilds) == ClosedLink
    as "Prerequisite 41793: a log without the quest has no open objective and no state 2 or 3"
  assert departures.landing(
      tables:,
      quests: log,
      creature_id: Creature2Id(northern_wilds),
    )
    == Error(TravelClosed)
    as "no landing for a player without the quest"
}

pub fn the_talk_not_done_closes_the_terminal_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 10_528, progress: [0, 0, 0, 0, 0]),
    ])
  assert link_of(quests: log, creature_id: northern_wilds) == ClosedLink
    as "flag 2 of objective 21327: it is reachable only once the talk 21326 is done, so it is not open, and the quest is in state 1"
  assert departures.landing(
      tables:,
      quests: log,
      creature_id: Creature2Id(northern_wilds),
    )
    == Error(TravelClosed)
    as "no landing before the talk"
}

pub fn travel_already_done_keeps_the_terminal_offered_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // The talk, the travel and the Northern Wilds choice done: mask 0b111, state 2.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_528,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 7,
        progress: [1, 1, 1, 0, 0],
      ),
    ])
  assert link_of(quests: log, creature_id: everstar_grove) == OpenLink
    as "Prerequisite 41793's type 6 condition with value 2: the client offers the terminal to a player whose quest is Achieved, so the server does too"
  let assert Ok(place) =
    departures.landing(
      tables:,
      quests: log,
      creature_id: Creature2Id(everstar_grove),
    )
    as "the yes of a player whose quest is Achieved lands, so a player stranded before the move can press again"
  assert start_place.world_id(place) == 990
    as "WorldLocation2 41641, the Everstar Grove landing, is in world 990"
}

pub fn a_completed_quest_keeps_the_terminal_offered_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.completed(quest_id: 10_530, at: 7),
    ])
  assert link_of(quests: log, creature_id: levian_bay) == OpenLink
    as "Prerequisite 42982's type 6 condition with value 3: the client offers the terminal to a player whose quest is Completed"
  let assert Ok(place) =
    departures.landing(
      tables:,
      quests: log,
      creature_id: Creature2Id(levian_bay),
    )
    as "the yes of a player whose quest is Completed lands too"
  assert start_place.world_id(place) == 1387
    as "WorldLocation2 42148, the Levian Bay landing, is in world 1387"
}

pub fn the_other_factions_quest_opens_no_terminal_test() -> Nil {
  use <- owned_test.run(60_000)
  assert link_of(quests: exile_after_the_talk(), creature_id: crimson_isle)
    == ClosedLink
    as "Quest2 10528 is the Exile's: the Dominion's Crimson Isle terminal needs Quest2 10530 (Prerequisite 42982)"
  assert link_of(quests: dominion_after_the_talk(), creature_id: northern_wilds)
    == ClosedLink
    as "Quest2 10530 is the Dominion's: the Exile's Northern Wilds terminal needs Quest2 10528 (Prerequisite 41793)"
}

pub fn a_creature_outside_the_table_keeps_its_own_link_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // Creature2 4989's questAnim columns name quest 2020, objective index 1 (flags 1).
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 2020, progress: [0, 0, 0, 0, 0, 0]),
    ])
  assert link_of(quests: log, creature_id: 4989) == OpenLink
    as "a creature that is no terminal has the link its own columns decide"
  assert departures.landing(
      tables:,
      quests: log,
      creature_id: Creature2Id(4989),
    )
    == Error(NotATerminal)
    as "and no landing"
}

pub fn a_landing_is_refused_once_the_quest_is_gone_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // The window was opened with the quest open; the quest is abandoned before the yes.
  let abandoned = quest_support.log_of(rows: [])
  assert departures.landing(
      tables:,
      quests: abandoned,
      creature_id: Creature2Id(crimson_isle),
    )
    == Error(TravelClosed)
    as "the landing is asked of the log as it is at the yes, not at the press"
}

pub fn each_choice_objective_names_its_terminal_test() -> Nil {
  use <- owned_test.run(60_000)
  assert departures.choice_terminal(21_328) == Some(Creature2Id(northern_wilds))
    as "QuestObjective 21328 is the Northern Wilds choice"
  assert departures.choice_terminal(21_329) == Some(Creature2Id(everstar_grove))
    as "QuestObjective 21329 is the Everstar Grove choice"
  assert departures.choice_terminal(21_349) == Some(Creature2Id(levian_bay))
    as "QuestObjective 21349 is the Levian Bay choice"
  assert departures.choice_terminal(21_350) == Some(Creature2Id(crimson_isle))
    as "QuestObjective 21350 is the Crimson Isle choice"
  assert departures.choice_terminal(21_327) == None
    as "the travel objective is counted by either terminal of the faction, so it names none"
  assert departures.choice_terminal(21_342) == None
    as "an objective of another type is no choice"
}

pub fn the_load_fails_without_a_landing_row_test() -> Nil {
  use <- owned_test.run(60_000)
  assert list.flat_map(departures.requirements(), fn(requirement) {
      requirement.missing(character_tables.shared())
    })
    == []
    as "the client's tables hold every landing and choice objective the terminals name"
  let assert Ok(rows) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "WorldLocation2",
      id: 8223,
    )
    as "the client's table holds row 8223"
  assert fixture_tables.load(rows:)
    == Error(table_store.RowMissing(
      from_table: "the server's departures terminals",
      column: "WorldLocation2 id",
      to_table: "WorldLocation2",
      id: 8223,
    ))
    as "the Crimson Isle terminal lands at WorldLocation2 8223, so a load without it fails"
}

pub fn the_load_fails_without_a_choice_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(without) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "QuestObjective",
      id: 21_329,
    )
    as "the client's table holds row 21329"
  let missing =
    Error(table_store.RowMissing(
      from_table: "the server's departures terminals",
      column: "QuestObjective id",
      to_table: "QuestObjective",
      id: 21_329,
    ))
  assert fixture_tables.load(rows: without) == missing
    as "the Everstar Grove terminal counts QuestObjective 21329, so a load without it fails"
  let assert Ok(retyped) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "QuestObjective",
      id: 21_329,
      with: [#("type", Integer(2))],
    )
    as "the client's table holds row 21329 with a type column"
  assert fixture_tables.load(rows: retyped) == missing
    as "a row that is no longer a use-a-unit objective (type 23) is no choice to count: the load fails as for a missing one"
}

pub fn the_load_fails_for_a_group_without_the_terminal_test() -> Nil {
  use <- owned_test.run(60_000)
  // TargetGroup 14367 (type 1) lists Creature2 73605 and 73606, the Exile terminals, in
  // data0 and data1: the group of QuestObjective 21327, 21328 and 21329.
  let assert Ok(without) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "TargetGroup",
      id: 14_367,
      with: [#("data0", Integer(0))],
    )
    as "the client's table holds row 14367 with a data0 column"
  assert fixture_tables.load(rows: without)
    == Error(table_store.RowMissing(
      from_table: "the server's departures terminals",
      column: "QuestObjective id",
      to_table: "QuestObjective",
      id: 21_327,
    ))
    as "the Everstar Grove terminal (73605) is no longer in its objectives' group, so its use would not count: the load fails at the first objective the group no longer holds it for"
}
