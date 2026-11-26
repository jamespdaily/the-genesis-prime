//// What the rule does with a visible, marked scripted objective (type 5) that no creature
//// links (`genesis_prime/game/objective`, `settle` and `script_of`): the objectives that
//// ask only to reach a place complete where the player stands, the ones a spell effect or
//// an item names stay open, and every other one completes when it is open. Expected values
//// come from these places.
//// - `QuestObjective.type.5`, `opcode.0x361`: nothing the client sends completes a type 5
////   objective; the server's 0x361 does, and the client then shows it done.
//// - `0x140553890`: the marker of an open objective is its destination whatever its type
////   (the arrow is drawn at it), so a marker alone does not say what the objective asks.
//// - `0x140485fa0` (`IsPlayerAtWorldLocation`): a place is reached when the horizontal
////   distance is within the row's radius and the height within its limit.
//// - `0x140553790`: an objective is open only while reachable: flags 1 and 2 keep it closed
////   behind the objectives before it.
//// - `0x1405fbc40`: the quest is Achieved once every required objective is done.
//// - `Spell4Effects.effectType.42` (QuestAdvanceObjective) and `0x140398cc0` (an item's
////   quest and objective): the client's data that names the action of an objective.
//// - The completion of the other kinds is the server's choice, a guess: the issue "Each
////   kind of scripted quest step that the Tower fix completes on accept gets its real rule".
////
//// The client's rows in the fixture (`table_rows -- Quest2`, `QuestObjective`,
//// `WorldLocation2`):
//// - quest 3667 "The Tower": objective 4770 (type 5, flags 0x10, count 1, marker
////   WorldLocation2 7778 in World 426, centre (4146.54, -721.71, -5729.80), radius 5, no
////   height limit); its receiver is the Master Control Panel, Creature2 11194.
//// - quest 4509 "Urgent Rescue": objective 6150 (type 5, count 6, three markers).
//// - quest 3163: objective 0 is 4120 (type 22, marker 7015), objective 1 is 4202 (type 5,
////   flags 3, marker 7015).
//// - quest 3769 "Up, Up, and Away": objective 4849 (type 5, count 5, marker 48831), named by
////   Spell4Effects 89873; its twin quest 3785 by 89874; Item2 6938 names 3769 objective 0.
//// - quest 4748 "Roan, Roan on the Range": objective 6589 (type 5, count 5, marker 12907),
////   named by Item2 12448 only.
//// - quest 10115 "zTrack: Celestial River Rush": objective 19335 (flags 0x10, marker 50703)
////   then the checkpoints 19336 (marker 50705), 19337 (50709), all of flags 19.
//// - quest 10116: objective 19367 (index 2) has two markers, 50761 and 50787.
//// - quest 9165: objective 18944 (index 4) has four markers, 49550 to 49553.
//// - quest 9282 "Logical Security": objectives 17752 (type 3, flags 2), 18311 (type 5, flags
////   11, hidden), 17753 (type 5, flags 3, marker, 300000 ms) and 18312 (hidden, flags 11).
//// - quest 6433 "Asteroid 3C48": objective 9884 (index 1, type 5, flags 3, marker 21773) of a
////   quest whose Quest2 questContentFinderTypeEnum is 1.

import character_tables
import client_tables
import content_support
import fixture_tables
import genesis_prime/game/arrival_objective
import genesis_prime/game/click_objective
import genesis_prime/game/held_objective
import genesis_prime/game/kill_objective
import genesis_prime/game/objective.{
  type Advanced, type Effect, Advanced, CompleteByServer, ReleaseUnit,
  SendProgress, SendState,
}
import genesis_prime/game/objective_action
import genesis_prime/game/objective_kind
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/start_place.{type Place}
import genesis_prime/store
import genesis_prime/table/id.{QuestObjectiveId, WorldLocation2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4_effects
import genesis_prime/table/world_location2
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set.{type Set}
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import spawn_support
import unitest

/// 2025-04-24 20:26:40 UTC in Unix milliseconds, the time of the connection tests.
const unix_ms = 1_745_526_400_000

const tower = 3667

const tower_objective = 4770

/// A position a recording of the Tower's player holds, inside the radius 5 of the marker
/// WorldLocation2 7778 (4.77 from its centre) in World 426, zone 852.
fn tower_marker() -> Place {
  place_support.at(
    world_id: 426,
    world_zone_id: 852,
    x: 4148.99,
    y: -722.05,
    z: -5733.9,
  )
}

/// The settle of the log with a player at the place and these QuestObjective ids as the
/// arrival objectives and the held ones.
fn settle(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  at place: Place,
  arrivals arrivals: List(Int),
  held held: List(Int),
) -> Advanced {
  settle_sets(
    log:,
    tables:,
    at: place,
    arrivals: set.from_list(arrivals),
    held: set.from_list(held),
    scripts: objective.no_rows(),
  )
}

fn settle_sets(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  at place: Place,
  arrivals arrivals: Set(Int),
  held held: Set(Int),
  scripts scripts: objective.ScriptRows,
) -> Advanced {
  objective.settle(
    log:,
    tables:,
    items: [],
    zones: [],
    place:,
    shown: dict.new(),
    numbers: spawn_support.numbers,
    arrival_objectives: arrivals,
    held_objectives: held,
    unix_ms:,
    now_ms: 0,
    scripts:,
  )
}

/// A player far from every marker: the live character's place, in World 3460.
fn away() -> Place {
  place_support.live_character_place()
}

/// The effects the client is told: progress and state, without the server's own
/// completion of a quest nothing receives.
fn told(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      CompleteByServer(..) | ReleaseUnit(..) -> False
      SendProgress(..) | SendState(..) -> True
    }
  })
}

/// The place at the centre of a WorldLocation2 row, in its world and zone: standing there
/// is at the marker (`0x140485fa0`: distance 0 within every radius, and the height equal).
fn centre_of(tables tables: table_store.Tables, marker marker: Int) -> Place {
  let assert Ok(row) =
    world_location2.get(tables:, id: WorldLocation2Id(marker))
    as "the fixture holds the marker row"
  place_support.at(
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    x: row.position0,
    y: row.position1,
    z: row.position2,
  )
}

/// A log of the quest, accepted, with these objectives (by index) done: each at its count.
fn logged(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  done done: List(Int),
) -> quest_log.QuestLog {
  quest_support.logged(tables:, quest_id:, done:)
}

/// The quest accepted with nothing done.
fn accepted(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> quest_log.QuestLog {
  logged(tables:, quest_id:, done: [])
}

// ---- the place scripts ----

pub fn a_player_at_the_marker_of_the_tower_completes_its_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let settled =
    settle(
      log: accepted(tables:, quest_id: tower),
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
  assert settled.effects
    == [
      SendProgress(quest_id: tower, objective_index: 0, progress: 1),
      SendState(quest_id: tower, state: 2),
    ]
    as "opcode.0x361 sets objective 4770 to its count 1, then 0x35c state 2: the Master Control Panel receives the quest, so the server does not complete it"
  assert quest_log.stored_state(log: settled.log, quest_id: tower) == 2
    as "the quest is Achieved, which is what offers the player its turn-in"
}

pub fn a_position_outside_the_marker_or_in_another_world_completes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log = accepted(tables:, quest_id: tower)
  // 10 east of the marker's centre (4146.54), at its height: outside the radius 5.
  let outside =
    place_support.at(
      world_id: 426,
      world_zone_id: 852,
      x: 4156.54,
      y: -721.71,
      z: -5729.8,
    )
  assert settle(
      log:,
      tables:,
      at: outside,
      arrivals: [tower_objective],
      held: [],
    )
    == Advanced(log:, effects: [])
    as "0x140485fa0: a horizontal distance above the radius is not at the place"
  // The marker's own position, in another world: the row names World 426.
  let elsewhere =
    place_support.at(
      world_id: 3460,
      world_zone_id: 852,
      x: 4146.54,
      y: -721.71,
      z: -5729.8,
    )
  assert settle(
      log:,
      tables:,
      at: elsewhere,
      arrivals: [tower_objective],
      held: [],
    )
    == Advanced(log:, effects: [])
    as "WorldLocation2 7778 is in World 426, so a position of another world is no arrival"
}

pub fn a_place_script_is_not_a_stand_in_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log = accepted(tables:, quest_id: tower)
  assert settle(
      log:,
      tables:,
      at: away(),
      arrivals: [tower_objective],
      held: [],
    )
    == Advanced(log:, effects: [])
    as "the Tower's only objective stays open at accept while the player is away: its trigger is the place"
  // The same objective outside the arrival set is a stand-in on accept.
  let standing_in = settle(log:, tables:, at: away(), arrivals: [], held: [])
  assert told(effects: standing_in.effects)
    == [
      SendProgress(quest_id: tower, objective_index: 0, progress: 1),
      SendState(quest_id: tower, state: 2),
    ]
    as "an objective the table does not list is completed at accept wherever the player is"
}

pub fn a_done_place_script_is_not_counted_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let first =
    settle(
      log: accepted(tables:, quest_id: tower),
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
  assert settle(
      log: first.log,
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
    == Advanced(log: first.log, effects: [])
    as "opcode.0x361 (the done bit): a second settle at the marker sends nothing"
}

pub fn a_place_script_with_a_count_above_one_completes_to_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  // No curated place script has a count above 1, so objective 4770 is given count 3: the
  // rule sets a place script to its count in one message, as every other completion does.
  use tables <- fixture_tables.changed(table: "QuestObjective", id: 4770, with: [
    #("count", Integer(3)),
  ])
  let settled =
    settle(
      log: accepted(tables:, quest_id: tower),
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
  assert told(effects: settled.effects)
    == [
      SendProgress(quest_id: tower, objective_index: 0, progress: 3),
      SendState(quest_id: tower, state: 2),
    ]
    as "opcode.0x361 carries the count in one message"
}

pub fn a_place_script_with_two_markers_completes_at_either_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // Quest 10116: objective 19367 (index 2, flags 19) has the markers 50761 and 50787, in
  // World 22 a long way apart; the objectives before it are done.
  let log = logged(tables:, quest_id: 10_116, done: [0, 1])
  let at_either = fn(marker: Int) {
    settle(
      log:,
      tables:,
      at: centre_of(tables:, marker:),
      arrivals: [19_366, 19_367, 19_368, 19_369, 19_371],
      held: [],
    ).effects
  }
  let expected = [
    SendProgress(quest_id: 10_116, objective_index: 2, progress: 1),
  ]
  assert at_either(50_761) == expected as "the first marker completes it"
  assert at_either(50_787) == expected as "the second marker completes it too"
  // Quest 9165: objective 18944 (index 4) has four markers, 49550 to 49553; the player is at
  // the fourth, and the other four objectives are done.
  let log = logged(tables:, quest_id: 9165, done: [0, 1, 2, 3])
  let settled =
    settle(
      log:,
      tables:,
      at: centre_of(tables:, marker: 49_553),
      arrivals: [18_944],
      held: [],
    )
  assert told(effects: settled.effects)
    == [
      SendProgress(quest_id: 9165, objective_index: 4, progress: 1),
      SendState(quest_id: 9165, state: 2),
    ]
    as "the fourth of four markers completes the last objective and the quest is Achieved"
}

pub fn a_checkpoint_waits_for_the_objective_before_it_and_then_completes_at_its_marker_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // Quest 10115: objective 0 (19335) is the start, objectives 1 and 2 (19336, 19337) are
  // checkpoints of flags 19, which `0x140553790` keeps closed behind every earlier one.
  // The start is held here, so it stays open.
  let checkpoints = [19_336, 19_337, 19_338, 19_340, 19_339]
  let start_open = accepted(tables:, quest_id: 10_115)
  assert settle(
      log: start_open,
      tables:,
      at: centre_of(tables:, marker: 50_705),
      arrivals: checkpoints,
      held: [19_335],
    )
    == Advanced(log: start_open, effects: [])
    as "0x140553790: with the starting objective open checkpoint 1 is closed, so its marker counts for nothing"
  let started = logged(tables:, quest_id: 10_115, done: [0])
  let first =
    settle(
      log: started,
      tables:,
      at: centre_of(tables:, marker: 50_705),
      arrivals: checkpoints,
      held: [],
    )
  assert first.effects
    == [SendProgress(quest_id: 10_115, objective_index: 1, progress: 1)]
    as "once the start is done the settle at checkpoint 1 completes only checkpoint 1"
  let second =
    settle(
      log: first.log,
      tables:,
      at: centre_of(tables:, marker: 50_709),
      arrivals: checkpoints,
      held: [],
    )
  assert second.effects
    == [SendProgress(quest_id: 10_115, objective_index: 2, progress: 1)]
    as "and the settle at checkpoint 2 completes checkpoint 2"
}

pub fn a_stand_in_beside_a_place_script_completes_in_the_same_settle_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296's objective 9658 becomes a visible script with its markers (21383, 21384)
  // that the arrival set lists, objective 9659 an optional one, and objective 16132 is its
  // hidden script: the hidden one stands in once the place script is done.
  use tables <- quest_support.with_objectives(edits: [
    #(9658, "type", 5),
    #(9658, "flags", 0),
    #(9658, "data", 0),
    #(9658, "count", 1),
    #(9659, "flags", 0x20),
  ])
  let log = logged(tables:, quest_id: 6296, done: [])
  assert settle(log:, tables:, at: away(), arrivals: [9658], held: [])
    == Advanced(log:, effects: [])
    as "the hidden stand-in waits for the place script, and the place script for the player"
  let settled =
    settle(
      log:,
      tables:,
      at: centre_of(tables:, marker: 21_383),
      arrivals: [9658],
      held: [],
    )
  assert told(effects: settled.effects)
    == [
      SendProgress(quest_id: 6296, objective_index: 0, progress: 1),
      SendProgress(quest_id: 6296, objective_index: 2, progress: 1),
      SendState(quest_id: 6296, state: 2),
    ]
    as "opcode.0x361 for the place script, then for the hidden stand-in in the same settle, then 0x35c state 2"
}

// ---- the stand-ins on accept ----

pub fn a_marked_action_script_completes_as_a_stand_in_with_the_rest_of_its_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // Quest 4509 "Urgent Rescue": objective 6150 (count 6, three markers) is the only
  // objective and no arrival objective.
  let rescued =
    settle(
      log: accepted(tables:, quest_id: 4509),
      tables:,
      at: away(),
      arrivals: [],
      held: [],
    )
  assert told(effects: rescued.effects)
    == [
      SendProgress(quest_id: 4509, objective_index: 0, progress: 6),
      SendState(quest_id: 4509, state: 2),
    ]
    as "opcode.0x361 sets the count 6 in one message at accept, then state 2"
  // Quest 3163: objective 4202 (flags 3) is closed behind objective 4120 (a place at marker
  // 7015), so it is not open at accept; the place completes 4120 and the stand-in follows in
  // the same settle (`0x140553790`).
  let log = accepted(tables:, quest_id: 3163)
  assert settle(log:, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log:, effects: [])
    as "a stand-in closed behind an open objective stays closed at accept"
  let there =
    settle(
      log:,
      tables:,
      at: centre_of(tables:, marker: 7015),
      arrivals: [],
      held: [],
    )
  assert told(effects: there.effects)
    == [
      SendProgress(quest_id: 3163, objective_index: 0, progress: 1),
      SendProgress(quest_id: 3163, objective_index: 1, progress: 1),
      SendState(quest_id: 3163, state: 2),
    ]
    as "the place completes 4120 and 4202 opens and completes in the same settle"
}

pub fn a_stand_in_on_accept_does_not_wait_for_another_open_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296: objective 9658 becomes a marked script (markers 21383, 21384 kept); objective
  // 9659 (a use of a creature, count 4) stays open and required.
  use tables <- quest_support.with_objectives(edits: [
    #(9658, "type", 5),
    #(9658, "flags", 0),
    #(9658, "data", 0),
    #(9658, "count", 1),
  ])
  let settled =
    settle(
      log: logged(tables:, quest_id: 6296, done: []),
      tables:,
      at: away(),
      arrivals: [],
      held: [],
    )
  assert told(effects: settled.effects)
    == [SendProgress(quest_id: 6296, objective_index: 0, progress: 1)]
    as "the stand-in completes at accept with objective 1 open, and the quest stays Accepted (0x1405fbc40)"
  assert quest_log.stored_state(log: settled.log, quest_id: 6296) == 1
    as "another required objective is open"
}

pub fn a_marked_script_with_no_text_completes_like_one_with_text_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 6150 with neither its Full nor its Short text (the 73 objectives of no
  // text): the rule reads no text, so it stands in as the textual ones do.
  use tables <- quest_support.with_objectives(edits: [
    #(6150, "localizedTextIdFull", 0),
    #(6150, "localizedTextIdShort", 0),
  ])
  let settled =
    settle(
      log: accepted(tables:, quest_id: 4509),
      tables:,
      at: away(),
      arrivals: [],
      held: [],
    )
  assert told(effects: settled.effects)
    == [
      SendProgress(quest_id: 4509, objective_index: 0, progress: 6),
      SendState(quest_id: 4509, state: 2),
    ]
    as "an objective with no text completes at accept like the others"
}

pub fn a_marker_naming_no_table_row_completes_as_a_stand_in_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296's objective 9658 becomes a visible script whose markers name rows
  // WorldLocation2 lacks (the real objectives 3737, 3811 and 3933 are in the tables test
  // below): no position can be at it (`0x140485fa0` returns false without the row), so it
  // is no place and no destination, and it waits for the quest like an unmarked script.
  use tables <- quest_support.with_objectives(edits: [
    #(9658, "type", 5),
    #(9658, "flags", 0),
    #(9658, "data", 0),
    #(9658, "count", 1),
    #(9658, "worldLocationsIdIndicator00", 4_000_000),
    #(9658, "worldLocationsIdIndicator01", 0),
  ])
  let waiting = logged(tables:, quest_id: 6296, done: [])
  assert settle(log: waiting, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log: waiting, effects: [])
    as "it waits for the quest's other required objectives, which are open"
  let ready = logged(tables:, quest_id: 6296, done: [1, 2])
  assert told(
      effects: settle(log: ready, tables:, at: away(), arrivals: [], held: []).effects,
    )
    == [
      SendProgress(quest_id: 6296, objective_index: 0, progress: 1),
      SendState(quest_id: 6296, state: 2),
    ]
    as "once they are done it completes as the unmarked scripts do"
}

pub fn a_timed_stand_in_completes_before_its_deadline_and_not_after_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(quest) = quest_log.quest_of(tables:, id: 9282)
    as "the fixture holds quest 9282"
  // Accepted at 0 ms; the talk (index 0) and the hidden stand-in (index 1) done at 1000 ms
  // start the timer of 17753 (index 2, 300000 ms): its deadline is 301000 ms.
  let accepted =
    quest_log.accept(
      log: quest_support.log_of(rows: []),
      quest:,
      max_time_ms: 0,
      now_ms: 0,
    )
  let assert Ok(first) =
    quest_log.counted(log: accepted, quest:, index: 0, value: 1, now_ms: 1000)
  let assert Ok(second) =
    quest_log.counted(log: first.log, quest:, index: 1, value: 1, now_ms: 1000)
  assert quest_log.next_deadline(log: second.log) == Some(301_000)
    as "the timed objective's 300000 ms from the moment it opened"
  let before =
    objective.settle(
      log: second.log,
      tables:,
      items: [],
      zones: [],
      place: away(),
      shown: dict.new(),
      numbers: spawn_support.numbers,
      arrival_objectives: set.new(),
      held_objectives: set.new(),
      unix_ms:,
      now_ms: 200_000,
      scripts: objective.no_rows(),
    )
  assert told(effects: before.effects)
    == [
      SendProgress(quest_id: 9282, objective_index: 2, progress: 1),
      SendProgress(quest_id: 9282, objective_index: 3, progress: 1),
      SendState(quest_id: 9282, state: 2),
    ]
    as "the stand-in completes before the deadline, then the hidden one behind it, and the quest is Achieved, not botched"
  assert quest_log.expire(log: before.log, now_ms: 400_000).1 == []
    as "an Achieved quest is never botched"
  // The same objective not done when the time runs out: the server botches the quest, and a
  // botched quest takes nothing.
  let #(botched, due) = quest_log.expire(log: second.log, now_ms: 400_000)
  assert due == [9282] as "the quest runs out with its timed objective open"
  assert settle(log: botched, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log: botched, effects: [])
    as "a botched quest is not in the active list, so nothing counts"
}

// ---- the objectives that stay open ----

pub fn an_objective_a_spell_effect_advances_stays_open_at_its_marker_and_at_accept_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert objective_action.by_effect(tables:, quest_id: 3769, index: 0)
    as "Spell4Effects 89873 (type 42) names quest 3769 objective 0"
  assert objective_action.by_effect(tables:, quest_id: 3785, index: 0)
    as "Spell4Effects 89874 names the other faction's twin"
  let log = accepted(tables:, quest_id: 3769)
  assert settle(log:, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log:, effects: [])
    as "at accept the objective stays open"
  let at_marker = centre_of(tables:, marker: 48_831)
  assert settle(log:, tables:, at: at_marker, arrivals: [], held: [])
    == Advanced(log:, effects: [])
    as "at its marker 48831 it stays open: a walk into the shards is not five railgun hits"
  assert settle(log:, tables:, at: at_marker, arrivals: [4849], held: [])
    == Advanced(log:, effects: [])
    as "a listed arrival objective that a spell effect names is still the cast's"
  assert settle(
      log: logged(tables:, quest_id: 3769, done: []),
      tables:,
      at: at_marker,
      arrivals: [],
      held: [4849],
    )
    == Advanced(log:, effects: [])
    as "held or not it stays open"
}

pub fn an_objective_an_item_names_stays_open_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert objective_action.by_item(tables:, quest_id: 4748, index: 0)
    as "Item2 12448 names quest 4748 objective 0"
  assert !objective_action.by_effect(tables:, quest_id: 4748, index: 0)
    as "no type 42 row names it: this is the item's, apart from the spell effect's"
  let log = accepted(tables:, quest_id: 4748)
  assert settle(log:, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log:, effects: [])
    as "at accept it stays open"
  assert settle(
      log:,
      tables:,
      at: centre_of(tables:, marker: 12_907),
      arrivals: [],
      held: [],
    )
    == Advanced(log:, effects: [])
    as "at its marker 12907 it stays open"
}

pub fn a_held_marked_script_stays_open_at_its_marker_and_at_accept_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // The held rows of the instance quests: a place script (quest 10132, objective 19357,
  // marker 39638), a stand-in on accept (quest 6433, objective 9884, flags 3, behind the
  // visit 10204) and a named action (quest 10130, objective 19351).
  let place = accepted(tables:, quest_id: 10_132)
  assert settle(
      log: place,
      tables:,
      at: centre_of(tables:, marker: 39_638),
      arrivals: [19_357],
      held: [19_357, 19_358],
    )
    == Advanced(log: place, effects: [])
    as "a held place script stays open at its marker, and so does its held neighbour"
  let asteroid = logged(tables:, quest_id: 6433, done: [0])
  assert settle(log: asteroid, tables:, at: away(), arrivals: [], held: [9884])
    == Advanced(log: asteroid, effects: [])
    as "a held stand-in stays open once it is reachable"
  assert told(
      effects: settle(
        log: asteroid,
        tables:,
        at: away(),
        arrivals: [],
        held: [],
      ).effects,
    )
    == [
      SendProgress(quest_id: 6433, objective_index: 1, progress: 1),
      SendState(quest_id: 6433, state: 2),
    ]
    as "the same objective not held completes, which shows the hold is what kept it"
  let spell = accepted(tables:, quest_id: 10_130)
  assert settle(
      log: spell,
      tables:,
      at: centre_of(tables:, marker: 39_638),
      arrivals: [],
      held: [19_351],
    ).effects
    == []
    as "a held named action stays open"
}

// ---- a creature-linked, optional and hidden script ----

pub fn a_linked_marked_script_is_left_to_its_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296's objective 9659 is linked by Creature2 27768 (its questAnim columns): made a
  // marked type 5 objective, neither the stand-in nor arrival takes it.
  use tables <- quest_support.with_objectives(edits: [
    #(9659, "type", 5),
    #(9659, "flags", 0),
    #(9659, "data", 0),
    #(9659, "count", 1),
    #(9659, "worldLocationsIdIndicator00", 21_383),
    #(9658, "flags", 0x20),
    #(16_132, "type", 2),
    #(16_132, "data", 73_464),
    #(16_132, "flags", 0x20),
  ])
  let log = logged(tables:, quest_id: 6296, done: [])
  assert settle(log:, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log:, effects: [])
    as "a creature links it, so a use of that creature completes it"
  assert settle(
      log:,
      tables:,
      at: centre_of(tables:, marker: 21_383),
      arrivals: [9659],
      held: [],
    )
    == Advanced(log:, effects: [])
    as "nor does arrival"
}

pub fn an_optional_marked_script_is_untouched_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 9658 made an optional (flag 0x20) marked type 5 objective, markers kept; the
  // others optional too, so it is the quest's only candidate.
  use tables <- quest_support.with_objectives(edits: [
    #(9658, "type", 5),
    #(9658, "flags", 0x20),
    #(9658, "data", 0),
    #(9658, "count", 1),
    #(9659, "flags", 0x20),
    #(16_132, "type", 2),
    #(16_132, "data", 73_464),
    #(16_132, "flags", 0x20),
  ])
  let log = logged(tables:, quest_id: 6296, done: [])
  assert settle(log:, tables:, at: away(), arrivals: [], held: [])
    == Advanced(log:, effects: [])
    as "0x1405fbc40 skips an optional objective, so no quest waits for it and nothing completes it"
  assert settle(
      log:,
      tables:,
      at: centre_of(tables:, marker: 21_383),
      arrivals: [],
      held: [],
    )
    == Advanced(log:, effects: [])
    as "nor does its marker"
}

pub fn a_hidden_marked_script_completes_as_a_stand_in_not_by_place_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296's hidden objective 16132 (flag 8) given marker 21383 and listed as an
  // arrival objective: a hidden objective shows no marker (`QuestObjective.flags.8`), so
  // the place does not complete it; it waits for the quest as a hidden script does.
  use tables <- quest_support.with_objectives(edits: [
    #(16_132, "worldLocationsIdIndicator00", 21_383),
  ])
  let waiting = logged(tables:, quest_id: 6296, done: [])
  assert settle(
      log: waiting,
      tables:,
      at: centre_of(tables:, marker: 21_383),
      arrivals: [16_132],
      held: [],
    )
    == Advanced(log: waiting, effects: [])
    as "standing at its marker completes nothing while the quest's other objectives are open"
  let ready = logged(tables:, quest_id: 6296, done: [0, 1])
  assert told(
      effects: settle(log: ready, tables:, at: away(), arrivals: [], held: []).effects,
    )
    == [
      SendProgress(quest_id: 6296, objective_index: 2, progress: 1),
      SendState(quest_id: 6296, state: 2),
    ]
    as "it completes once the other required objectives are done"
}

// ---- lifecycle ----

pub fn a_completed_place_script_survives_a_relog_without_a_second_message_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let done =
    settle(
      log: accepted(tables:, quest_id: tower),
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
  let rows = quest_log.rows(log: done.log, now_ms: 0)
  let assert Ok(relogged) = quest_log.from_rows(rows:, tables:)
    as "the saved rows are ones the client takes"
  assert settle(
      log: relogged,
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
    == Advanced(log: relogged, effects: [])
    as "the saved done bit and the Achieved state are kept: a relog at the marker sends no progress again"
  assert quest_log.stored_state(log: relogged, quest_id: tower) == 2
}

pub fn an_abandoned_and_retaken_quest_starts_its_place_script_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let done =
    settle(
      log: accepted(tables:, quest_id: tower),
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
  let assert Ok(quest) = quest_log.quest_of(tables:, id: tower)
    as "the fixture holds the quest"
  let abandoned =
    quest_log.hold(log: done.log, quest_id: tower, state: store.Abandoned)
  assert quest_log.stored_state(log: abandoned, quest_id: tower) != 2
    as "an abandoned quest is not Achieved"
  let retaken =
    quest_log.accept(log: abandoned, quest:, max_time_ms: 0, now_ms: 0)
  let again =
    settle(
      log: retaken,
      tables:,
      at: tower_marker(),
      arrivals: [tower_objective],
      held: [],
    )
  assert told(effects: again.effects)
    == [
      SendProgress(quest_id: tower, objective_index: 0, progress: 1),
      SendState(quest_id: tower, state: 2),
    ]
    as "the retaken quest starts from nothing: the objective completes again at the marker"
}

// ---- the client's tables ----

/// The QuestObjective ids the migrated database holds in the arrival table.
fn arrival_ids() -> Set(Int) {
  content_support.objective_ids(table: arrival_objective.table)
}

/// Every type 5 objective of the client's quests: the quest as the log reads it, the index,
/// and the objective.
fn type_5_places(
  tables tables: table_store.Tables,
) -> List(#(quest_log.Quest, Int, quest_log.Objective)) {
  quest2.all(tables)
  |> list.flat_map(fn(row) {
    let assert Ok(quest) = quest_log.quest_of(tables:, id: row.id)
      as "the Quest2 row's objectives are rows of the table"
    list.index_map(quest.objectives, fn(objective, index) {
      #(quest, index, objective)
    })
    |> list.filter(fn(place) { { place.2 }.kind == objective_kind.Scripted })
  })
}

/// The (quest, objective index) pairs the Item2 rows name: a quest and a non-negative index
/// (`0x140398cc0`: -1 names the whole quest).
fn item2_pairs(tables tables: table_store.Tables) -> List(#(Int, Int)) {
  item2.all(tables)
  |> list.filter(fn(row) {
    row.quest2_id_activation_required != 0
    && row.quest_objective_activation_required >= 0
  })
  |> list.map(fn(row) {
    #(
      row.quest2_id_activation_required,
      row.quest_objective_activation_required,
    )
  })
  |> list.unique
}

pub fn the_spell_advanced_set_names_every_type_42_and_item_objective_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let by_effect =
    spell4_effects.all(tables)
    |> list.filter(fn(row) { row.effect_type == 42 })
    |> list.map(fn(row) { #(row.data_bits00, row.data_bits01) })
    |> list.unique
  assert list.length(by_effect) == 221
    as "the Spell4Effects rows of effect type 42 name 221 distinct (quest, index) pairs"
  assert list.all(by_effect, fn(pair) {
    objective_action.by_effect(tables:, quest_id: pair.0, index: pair.1)
  })
    as "every pair of a type 42 row is in the set"
  let by_item = item2_pairs(tables:)
  assert list.length(by_item) == 235
    as "the Item2 rows that name a quest and a non-negative objective name 235 pairs"
  assert list.all(by_item, fn(pair) {
    objective_action.by_item(tables:, quest_id: pair.0, index: pair.1)
  })
    as "every pair an item names is in the set"
  // Of the visible, required, marked, unlinked type 5 objectives, 70 are named by an effect
  // or an item: 53 by an effect and 17 only by an item.
  let named =
    type_5_places(tables:)
    |> list.filter(fn(place) {
      objective.script_of(
        tables:,
        quest_id: { place.0 }.id,
        index: place.1,
        objective: place.2,
        arrival_objectives: set.new(),
        scripts: objective.no_rows(),
      )
      == objective.NamedAction
    })
  assert list.length(named) == 70
    as "70 of the marked unlinked rows are in the set"
  assert list.count(named, fn(place) {
      objective_action.by_effect(
        tables:,
        quest_id: { place.0 }.id,
        index: place.1,
      )
    })
    == 53
    as "53 are advanced by a spell effect"
}

/// The script tables the migrated database holds: the kill and click tables' rows.
fn script_rows() -> objective.ScriptRows {
  objective.ScriptRows(
    kills: content_support.objective_ids(table: kill_objective.table),
    clicks: content_support.objective_ids(table: click_objective.table),
  )
}

/// How many of the places `script_of` gives each class, in the order of `classes`.
fn counted_classes(
  tables tables: table_store.Tables,
  arrivals arrivals: Set(Int),
  rows rows: objective.ScriptRows,
) -> List(#(objective.Script, Int)) {
  let scripts =
    list.map(type_5_places(tables:), fn(place) {
      objective.script_of(
        tables:,
        quest_id: { place.0 }.id,
        index: place.1,
        objective: place.2,
        arrival_objectives: arrivals,
        scripts: rows,
      )
    })
  list.map(classes(), fn(class) {
    #(class, list.count(scripts, fn(script) { script == class }))
  })
}

fn classes() -> List(objective.Script) {
  [
    objective.UsedByCreature,
    objective.Optional,
    objective.NamedAction,
    objective.PlaceScript,
    objective.KillScript,
    objective.ClickScript,
    objective.StandInOnAccept,
    objective.StandInWithQuest,
  ]
}

/// The log of the quest accepted with these objective indexes done, or the place a unit
/// of test needs; the sweeps below build one per objective.
fn others_done(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  except except: Int,
) -> quest_log.QuestLog {
  let done =
    list.index_map(quest.objectives, fn(_, index) { index })
    |> list.filter(fn(index) { index != except })
  logged(tables:, quest_id: quest.id, done:)
}

/// Whether the settle of the objective's quest, with every other objective done and the
/// player at the place, leaves the objective done.
fn done_after(
  tables tables: table_store.Tables,
  place place: #(quest_log.Quest, Int, quest_log.Objective),
  at at: Place,
  arrivals arrivals: Set(Int),
  held held: Set(Int),
  scripts scripts: objective.ScriptRows,
) -> Bool {
  let #(quest, index, _) = place
  let settled =
    settle_sets(
      log: others_done(tables:, quest:, except: index),
      tables:,
      at:,
      arrivals:,
      held:,
      scripts:,
    )
  quest_log.objective_done(log: settled.log, quest:, index:)
}

/// The place at the first marker row of the objective's row, or the same place a long way
/// off in its world.
fn first_marker(
  tables tables: table_store.Tables,
  objective_id objective_id: Int,
  far far: Bool,
) -> Place {
  let assert Ok(row) =
    quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
    as "the objective's row"
  let assert [location, ..] = place_objective.markers(tables:, objective: row)
    as "an objective with a marker has a marker row"
  place_support.at(
    world_id: location.world_id,
    world_zone_id: location.world_zone_id,
    x: location.position0
      +. case far {
      True -> 100_000.0
      False -> 0.0
    },
    y: location.position1,
    z: location.position2,
  )
}

pub fn every_place_script_completes_at_its_marker_and_no_spell_advanced_one_completes_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arrivals = arrival_ids()
  let held = content_support.objective_ids(table: held_objective.table)
  let rows = script_rows()
  let none = set.new()
  let scripted =
    list.map(type_5_places(tables:), fn(place) {
      #(
        place,
        objective.script_of(
          tables:,
          quest_id: { place.0 }.id,
          index: place.1,
          objective: place.2,
          arrival_objectives: arrivals,
          scripts: rows,
        ),
      )
    })
  let wrong =
    list.filter_map(scripted, fn(entry) {
      let #(place, class) = entry
      let id = { place.2 }.objective_id
      let is_held = set.contains(held, id)
      let at_marker = fn() {
        first_marker(tables:, objective_id: id, far: False)
      }
      let far_away = fn() { first_marker(tables:, objective_id: id, far: True) }
      let problem = case class, is_held {
        objective.PlaceScript, False ->
          case
            done_after(
              tables:,
              place:,
              at: at_marker(),
              arrivals:,
              held: none,
              scripts: rows,
            ),
            done_after(
              tables:,
              place:,
              at: far_away(),
              arrivals:,
              held: none,
              scripts: rows,
            )
          {
            True, False -> Ok(Nil)
            True, True -> Error("done a long way from its marker")
            False, _ -> Error("not done at its first marker")
          }
        objective.PlaceScript, True ->
          case
            done_after(
              tables:,
              place:,
              at: at_marker(),
              arrivals:,
              held:,
              scripts: rows,
            )
          {
            False -> Ok(Nil)
            True -> Error("a held place done at its marker")
          }
        objective.NamedAction, _ ->
          case
            done_after(
              tables:,
              place:,
              at: at_marker(),
              arrivals:,
              held: none,
              scripts: rows,
            )
          {
            False -> Ok(Nil)
            True -> Error("a spell or item objective done at its marker")
          }
        objective.NotScripted, _
        | objective.UsedByCreature, _
        | objective.Optional, _
        | objective.KillScript, _
        | objective.ClickScript, _
        | objective.StandInOnAccept, _
        | objective.StandInWithQuest, _
        -> Ok(Nil)
      }
      case problem {
        Ok(Nil) -> Error(Nil)
        Error(why) -> Ok(#({ place.0 }.id, id, why))
      }
    })
  assert wrong == []
    as "the place scripts complete at the first marker row and nowhere far from it; the held ones and the ones a spell effect or an item names stay open at their markers"
}

pub fn every_marked_stand_in_completes_on_accept_and_every_held_one_stays_open_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arrivals = arrival_ids()
  let held = content_support.objective_ids(table: held_objective.table)
  let rows = script_rows()
  let wrong =
    list.filter_map(type_5_places(tables:), fn(place) {
      let id = { place.2 }.objective_id
      let class =
        objective.script_of(
          tables:,
          quest_id: { place.0 }.id,
          index: place.1,
          objective: place.2,
          arrival_objectives: arrivals,
          scripts: rows,
        )
      let #(quest, index, _) = place
      // The objectives before it done, the ones after it not: it is reachable, and the
      // quest's other required objectives are open.
      let log =
        logged(
          tables:,
          quest_id: quest.id,
          done: list.index_map(quest.objectives, fn(_, before) { before })
            |> list.filter(fn(before) { before < index }),
        )
      let settled =
        settle_sets(log:, tables:, at: away(), arrivals:, held:, scripts: rows)
      let done = quest_log.objective_done(log: settled.log, quest:, index:)
      // A collected or crafted objective before it is counted from the items held, so a
      // log that marks it done without the item loses the mark at the settle: the three
      // stand-ins behind one wait for the player's work, which this log cannot do.
      let behind_a_held_item =
        list.take(quest.objectives, index)
        |> list.any(fn(before) {
          result.is_ok(objective_kind.collected_item(before.kind))
          || result.is_ok(objective_kind.crafted_schematic(before.kind))
        })
      case class {
        objective.StandInOnAccept ->
          case set.contains(held, id), done {
            False, False if !behind_a_held_item ->
              Ok(#(quest.id, id, "not done at accept"))
            True, True -> Ok(#(quest.id, id, "a held stand-in done"))
            False, False | False, True | True, False -> Error(Nil)
          }
        objective.NotScripted
        | objective.UsedByCreature
        | objective.Optional
        | objective.NamedAction
        | objective.PlaceScript
        | objective.KillScript
        | objective.ClickScript
        | objective.StandInWithQuest -> Error(Nil)
      }
    })
  assert wrong == []
    as "a marked stand-in is done as soon as it is open whatever else the quest holds, and a held one never is"
}

pub fn every_type_5_objective_in_a_quest_has_one_completing_rule_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arrivals = arrival_ids()
  let held = content_support.objective_ids(table: held_objective.table)
  let rows = script_rows()
  let places = type_5_places(tables:)
  assert list.length(places) == 1498
    as "1556 QuestObjective rows of type 5, 58 of them in no quest, the others in one quest each"
  assert quest_objective.all(tables)
    |> list.filter(fn(row) { row.type_ == 5 })
    |> list.count(fn(row) {
      !list.any(places, fn(place) { { place.2 }.objective_id == row.id })
    })
    == 58
    as "the objectives no quest lists are none of the rules'"
  // The class counts come from the client's rows (the objective's flags, the marker rows,
  // the creatures' links, the type 42 rows and the items) and the arrival table's 50 rows.
  assert counted_classes(tables:, arrivals:, rows:)
    == [
      #(objective.UsedByCreature, 267),
      #(objective.Optional, 59),
      #(objective.NamedAction, 70),
      #(objective.PlaceScript, 50),
      #(objective.KillScript, 9),
      #(objective.ClickScript, 5),
      #(objective.StandInOnAccept, 432),
      #(objective.StandInWithQuest, 606),
    ]
    as "each type 5 objective in a quest has exactly one class: 259 linked required and 8 linked optional, 59 visible optional, 70 a spell or an item names, 50 places, 9 kills, 5 clicks, 432 stand-ins on accept (454 less the 8 places, the 9 kills and the 5 clicks moved), and 606 that wait for the quest (87 hidden, 519 visible with no marker)"
  assert set.size(arrivals) == 50
    as "the arrival table's rows: the 42 of migration 0038 and the 8 of 0043"
  assert set.size(held) == 146
    as "the held table's rows: the 130 of the unmarked scripts, the 15 of the instance quests and the store purchase 21267"
  // The hold is an override: of the 146, the 15 marked rows of the instance quests are of
  // two classes named by a spell, four places (the other two of the six the text reads as
  // places are stand-ins), and nine stand-ins on accept.
  let held_places =
    list.filter(places, fn(place) {
      set.contains(held, { place.2 }.objective_id)
    })
  let held_class = fn(wanted: objective.Script) {
    list.count(held_places, fn(place) {
      objective.script_of(
        tables:,
        quest_id: { place.0 }.id,
        index: place.1,
        objective: place.2,
        arrival_objectives: arrivals,
        scripts: rows,
      )
      == wanted
    })
  }
  assert held_class(objective.NamedAction) == 2
    as "the instance quests 10130 and 10131 each hold one objective a spell names"
  assert held_class(objective.PlaceScript) == 4
    as "four held places: 18629, 18630, 19346 and 19357"
  assert held_class(objective.StandInOnAccept) == 9
    as "nine held stand-ins on accept"
  assert held_class(objective.StandInWithQuest) == 131
    as "the 130 of migration 0034 and 21267 of migration 0041"
}

// ---- the places and equips that left the stand-in ----

/// Every type 5 objective of the client's quests, the 31 sized as places by the issue
/// "Each kind of scripted quest step that the Tower fix completes on accept gets its real
/// rule", with what `script_of` gives it and why. The 8 that ask only to reach a place the
/// marker shows, whose quest's giver is spawned in the marker's world, are `PlaceScript`; the
/// others stay `StandInOnAccept` for the reason stated (the 16 of them that ask for more than a
/// position need a trigger the position does not show; the 7 that ask only to reach a place
/// have no giver the server spawns, so no player can accept their quest).
fn sized_places() -> List(#(Int, objective.Script, String)) {
  let place = objective.PlaceScript
  let stays = objective.StandInOnAccept
  [
    #(7342, place, "Find the musical voice of the Wise One (1 m point)"),
    #(8074, place, "Travel to the last known position (1 m point)"),
    #(8204, place, "Find the wedding party caravan (1 m point)"),
    #(9043, place, "Search for survey data at the camp (20 m)"),
    #(11_479, place, "Locate the origin of the relic (36 m)"),
    #(
      14_378,
      place,
      "Find the brother in Ghostwind Hollow (two markers of 160 m)",
    ),
    #(
      14_544,
      place,
      "Find the lover in Ghostwind Hollow (two markers of 160 m)",
    ),
    #(18_099, place, "Find a way down from the Keeper's Sanctuary (1 m point)"),
    #(
      7217,
      stays,
      "Locate the first clue (57 m): quest 5079's giver, Creature2 19935, has no spawn",
    ),
    #(
      7423,
      stays,
      "Locate the second clue (65 m): quest 5079's giver, Creature2 19935, has no spawn",
    ),
    #(
      7424,
      stays,
      "Locate the third clue (64 m): quest 5079's giver, Creature2 19935, has no spawn",
    ),
    #(
      12_933,
      stays,
      "Escape the blast (1 m point, a 60 s limit): quest 6901's giver, Creature2 33806, has no spawn",
    ),
    #(
      16_621,
      stays,
      "Search for Trinette (1 m point): quest 9180 has no giver creature",
    ),
    #(
      17_877,
      stays,
      "Find Stephanus (1 m point): quest 9186 has no giver creature",
    ),
    #(
      18_072,
      stays,
      "Reach the creature on the opposite tower (1 m point): quest 9315 has no giver creature",
    ),
    #(
      6474,
      stays,
      "Clear the drop zone: its marker lies inside the earlier objective's and the giver's circles, and clearing asks to defeat",
    ),
    #(7965, stays, "Complete the Rite of Passage Event: a public event"),
    #(
      8307,
      stays,
      "count 4 beside four hidden talk objectives: not one arrival",
    ),
    #(
      8219,
      stays,
      "Search the creature for a treasure map: a click, sibling of a type 14 objective",
    ),
    #(
      13_691,
      stays,
      "Escape from the Terraformer: its 175 m marker holds the markers before it",
    ),
    #(
      8994,
      stays,
      "Remain in the circle until the ritual is complete: a timed stay held by an aura",
    ),
    #(
      9468,
      stays,
      "Move a safe distance away: a distance from the distillery, one of four 1 m markers lies inside its 95 m circle",
    ),
    #(
      10_195,
      stays,
      "Escape the trap: its marker is the speeder of the three objectives before it",
    ),
    #(
      12_591,
      stays,
      "Find the creature in the Webwood: its second marker is 2 m from the previous objective's",
    ),
    #(12_891, stays, "count 10 deliver energy: not one arrival"),
    #(
      16_168,
      stays,
      "Find and listen to the Final Datalog: a duplicate click of a type 12 objective",
    ),
    #(
      16_181,
      stays,
      "Leave the Phagelabs: its marker is at the earlier boss and the giver",
    ),
    #(21_389, stays, "count 100 Intercept encoded data: a percent progress"),
    #(21_402, stays, "count 100 Intercept encoded data: a percent progress"),
    #(21_406, stays, "count 100 Intercept encoded data: a percent progress"),
    #(21_407, stays, "count 100 Intercept encoded data: a percent progress"),
  ]
}

/// The place (quest, index, objective) the objective is listed at: the first quest that
/// lists it.
fn place_of(
  tables tables: table_store.Tables,
  objective_id objective_id: Int,
) -> #(quest_log.Quest, Int, quest_log.Objective) {
  let assert Ok(place) =
    list.find(type_5_places(tables:), fn(place) {
      { place.2 }.objective_id == objective_id
    })
    as "the objective is a type 5 objective of a quest in the tables"
  place
}

pub fn the_place_rows_are_the_listed_eight_and_the_twenty_three_others_stay_stand_ins_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arrivals = arrival_ids()
  let wrong =
    list.filter_map(sized_places(), fn(row) {
      let #(objective_id, wanted, reason) = row
      let #(quest, index, listed) = place_of(tables:, objective_id:)
      let got =
        objective.script_of(
          tables:,
          quest_id: quest.id,
          index:,
          objective: listed,
          arrival_objectives: arrivals,
          scripts: objective.no_rows(),
        )
      case got == wanted {
        True -> Error(Nil)
        False -> Ok(#(objective_id, reason))
      }
    })
  assert wrong == []
    as "the 8 rows that only ask to reach a place and have a spawned giver are place scripts and the 23 others stay stand-ins on accept"
  assert list.length(sized_places()) == 31
    as "the sizing's 31 go-to-a-place stand-ins"
  assert list.count(sized_places(), fn(row) { row.1 == objective.PlaceScript })
    == 8
    as "8 of them are places"
}

/// How far to put the player east of a marker's centre, in the marker's own radii plus 2 m:
/// 0 is its centre, 1 is 2 m beyond its radius.
type Offset {
  Centre
  BeyondTheRadius(towards_east: Bool)
}

/// The place the offset puts the player at, in the marker's world or in another one.
fn at_marker(
  tables tables: table_store.Tables,
  marker marker: Int,
  offset offset: Offset,
  world_id world_id: option.Option(Int),
) -> Place {
  let assert Ok(row) =
    world_location2.get(tables:, id: WorldLocation2Id(marker))
    as "the fixture holds the marker row"
  let shift = case offset {
    Centre -> 0.0
    BeyondTheRadius(towards_east: True) -> row.radius +. 2.0
    BeyondTheRadius(towards_east: False) -> 0.0 -. { row.radius +. 2.0 }
  }
  place_support.at(
    world_id: option.unwrap(world_id, row.world_id),
    world_zone_id: row.world_zone_id,
    x: row.position0 +. shift,
    y: row.position1,
    z: row.position2,
  )
}

pub fn a_new_place_row_completes_at_its_markers_and_nowhere_else_test() -> Nil {
  use <- owned_test.run(120_000)
  let tables = character_tables.shared()
  let arrivals = arrival_ids()
  // Each case: the objective, one of its markers and the side the 2 m beyond its radius lies
  // on, so that it is outside the objective's other marker as well (0x140485fa0: the
  // horizontal distance within the row's radius). Objective 14378 has two markers of 160 m
  // that are 238 m apart, and either completes it.
  let cases = [
    #(7342, 14_792, True),
    #(9043, 20_075, True),
    #(8074, 17_073, True),
    #(14_378, 30_943, True),
    #(14_378, 30_942, False),
    #(18_099, 45_330, True),
  ]
  let wrong =
    list.filter_map(cases, fn(row) {
      let #(objective_id, marker, east) = row
      let place = place_of(tables:, objective_id:)
      let done_at = fn(at) {
        done_after(
          tables:,
          place:,
          at:,
          arrivals:,
          held: set.new(),
          scripts: objective.no_rows(),
        )
      }
      case
        done_at(at_marker(
          tables:,
          marker:,
          offset: Centre,
          world_id: option.None,
        )),
        done_at(at_marker(
          tables:,
          marker:,
          offset: BeyondTheRadius(towards_east: east),
          world_id: option.None,
        )),
        done_at(at_marker(
          tables:,
          marker:,
          offset: Centre,
          world_id: option.Some(3460),
        ))
      {
        True, False, False -> Error(Nil)
        False, _, _ -> Ok(#(objective_id, marker, "not done at its marker"))
        True, True, _ ->
          Ok(#(objective_id, marker, "done 2 m beyond its radius"))
        True, False, True ->
          Ok(#(objective_id, marker, "done in another world"))
      }
    })
  assert wrong == []
    as "each completes inside a marker's radius, not 2 m beyond it and not in another world"
}

pub fn a_new_place_row_behind_other_objectives_waits_for_them_test() -> Nil {
  use <- owned_test.run(120_000)
  let tables = character_tables.shared()
  let arrivals = arrival_ids()
  // Quest 9068's objective 18099 (index 2, flags 3) is closed until the two objectives before
  // it (16347 and 16348) are done (`0x140553790`); its marker is WorldLocation2 45330.
  let at_the_marker = centre_of(tables:, marker: 45_330)
  let waiting = logged(tables:, quest_id: 9068, done: [])
  assert settle_sets(
      log: waiting,
      tables:,
      at: at_the_marker,
      arrivals:,
      held: set.new(),
      scripts: objective.no_rows(),
    )
    == Advanced(log: waiting, effects: [])
    as "with the objectives before it open, its marker counts for nothing"
  let opened = logged(tables:, quest_id: 9068, done: [0, 1])
  assert told(
      effects: settle_sets(
        log: opened,
        tables:,
        at: at_the_marker,
        arrivals:,
        held: set.new(),
        scripts: objective.no_rows(),
      ).effects,
    )
    == [
      SendProgress(quest_id: 9068, objective_index: 2, progress: 1),
      SendState(quest_id: 9068, state: 2),
    ]
    as "once they are done the marker completes it, the quest's last objective, and the quest is Achieved"
  assert settle_sets(
      log: opened,
      tables:,
      at: at_the_marker,
      arrivals:,
      held: set.from_list([18_099]),
      scripts: objective.no_rows(),
    )
    == Advanced(log: opened, effects: [])
    as "a held place stays open at its marker"
}

// ---- the equips and buys stay stand-ins on accept ----
//
// Quest 9058 "Algoroc Mining Expedition": objective 16311 (type 5, count 1, the text "Equip
// the $(item=12631)"); quest 9077 the same for Item2 17978; quest 9448 "Vouchers": objective
// 18069 (type 5, count 1, "Buy a $(item=54409) from $(creature=47172) in Thayd"), quest 9449
// the same from $(creature=47413). The client holds nothing for either kind
// (`QuestObjective.type.5`), and neither rule can fire in this server: the two items carry a
// tradeskill-tier prerequisite the server refuses with 144, and the two vendors have no
// `vendor` rows.

pub fn the_four_equip_and_buy_quests_still_complete_on_accept_test() -> Nil {
  use <- owned_test.run(120_000)
  let tables = character_tables.shared()
  let arrivals = arrival_ids()
  let held = content_support.objective_ids(table: held_objective.table)
  let rows = script_rows()
  // (quest, objective, why its real rule cannot fire): the two items need a prerequisite of
  // type 19 (a tradeskill tier) that the server does not read, so wearing them is refused
  // with 144; the two vendors have no `vendor` rows, so nothing is bought from them. Each
  // objective stays a stand-in on accept until its rule can fire.
  let cases = [
    #(9058, 16_311, "item 12631 needs prerequisite 40040, which is refused"),
    #(9077, 16_379, "item 17978 needs prerequisite 40044, which is refused"),
    #(9448, 18_069, "creature 47172 has no vendor rows"),
    #(9449, 18_070, "creature 47413 has no vendor rows"),
  ]
  let wrong =
    list.filter_map(cases, fn(row) {
      let #(quest_id, objective_id, reason) = row
      let #(quest, index, _) = place_of(tables:, objective_id:)
      // The objectives before it done, so that it is open.
      let log =
        logged(
          tables:,
          quest_id:,
          done: list.index_map(quest.objectives, fn(_, before) { before })
            |> list.take(index),
        )
      let settled =
        settle_sets(log:, tables:, at: away(), arrivals:, held:, scripts: rows)
      case
        quest.id == quest_id
        && quest_log.objective_done(log: settled.log, quest:, index:)
      {
        True -> Error(Nil)
        False -> Ok(#(quest_id, objective_id, reason))
      }
    })
  assert wrong == []
    as "quests 9058, 9077, 9448 and 9449 complete their equip or buy objective as soon as it is open"
}

pub fn the_equip_and_buy_objectives_are_stand_ins_on_accept_over_every_client_quest_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arrivals = arrival_ids()
  let script_of = fn(objective_id) {
    let #(quest, index, listed) = place_of(tables:, objective_id:)
    objective.script_of(
      tables:,
      quest_id: quest.id,
      index:,
      objective: listed,
      arrival_objectives: arrivals,
      scripts: objective.no_rows(),
    )
  }
  // The ids of the objective texts: 487701 "Equip the $(item=12631)", 492421 "Equip the
  // $(item=17978)", 563643 "Buy a $(item=54409) from $(creature=47172) in Thayd" and 563647
  // "... $(creature=47413) in Illium" (`client_files.py text`); 16407 is quest 7012's
  // "right-click on the new shield", which names no item.
  assert list.map([16_311, 16_379, 18_069, 18_070, 16_407], script_of)
    == list.repeat(objective.StandInOnAccept, 5)
    as "the four equip and buy objectives and the shield's stay stand-ins on accept"
}

// ---- the cast steps stay stand-ins on accept ----
//
// The seven support-training quests (10037, 10069, 10070, 10071, 10043, 10072 and 10074: the
// second objective of each, a type 5 of count 3) and quest 6346's objective 9724 (count 1) are
// named by spell columns: `Spell4.prerequisiteIdRunner00` and `01`, and
// `prerequisiteIdCasterCast` of Spell4 32897. The training room (world 3406) has no stored
// spawn, so no creature stands there to be cast at, and the Detonator's counting rule is
// open; each objective is a stand-in on accept.

pub fn the_eight_cast_quests_still_complete_on_accept_over_every_client_quest_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let arrivals = arrival_ids()
  let held = content_support.objective_ids(table: held_objective.table)
  let rows = script_rows()
  let cases = [
    #(10_037, 19_138),
    #(10_069, 19_168),
    #(10_070, 19_170),
    #(10_071, 19_172),
    #(10_043, 19_143),
    #(10_072, 19_174),
    #(10_074, 19_178),
    #(6346, 9724),
  ]
  let wrong =
    list.filter_map(cases, fn(row) {
      let #(quest_id, objective_id) = row
      let #(quest, index, listed) = place_of(tables:, objective_id:)
      let script =
        objective.script_of(
          tables:,
          quest_id:,
          index:,
          objective: listed,
          arrival_objectives: arrivals,
          scripts: rows,
        )
      // The objectives before it done, so that it is open.
      let log =
        logged(
          tables:,
          quest_id:,
          done: list.index_map(quest.objectives, fn(_, before) { before })
            |> list.take(index),
        )
      let settled =
        settle_sets(log:, tables:, at: away(), arrivals:, held:, scripts: rows)
      case
        quest.id == quest_id
        && script == objective.StandInOnAccept
        && quest_log.objective_done(log: settled.log, quest:, index:)
      {
        True -> Error(Nil)
        False -> Ok(#(quest_id, objective_id))
      }
    })
  assert wrong == []
    as "the seven training-room quests and quest 6346 are stand-ins on accept and complete their cast objective as soon as it is open"
}
