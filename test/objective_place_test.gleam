//// What a position does to the open objectives of a quest log
//// (`genesis_prime/game/objective.settle`): a type 22 objective completes when the
//// player's position reaches its marker, and a checklist objective of Primal
//// Manifestations counts the unit under the place reached. Expected values come from
//// these places.
//// - `0x140485fa0` (`IsPlayerAtWorldLocation`): a place is reached when its row exists,
////   the height is within `maxVerticalDistance` of the row's (a limit of 0 tests no
////   height) and the horizontal distance (x and z) is at most the row's radius.
//// - `QuestObjective.type.22`: the client sends nothing for a place and the server tells
////   it the objective's progress (`opcode.0x361`); the marker is the objective's
////   worldLocationsIdIndicator00 to 03 (`QuestObjective.21294.places` for the checklist's
////   places, `Quest2.10527.finish_line` for the finish line).
//// - `0x140553790`: an objective takes progress only while it is open.
//// - `opcode.0x361`: a checklist's progress is the whole mask of counted targets.
////
//// The client's rows in the fixture (`table_rows -- QuestObjective`, `WorldLocation2`):
//// - quest 10513: objectives 21271 (index 0, type 22, flags 0, marker 51735), 21279
////   (index 1, flags 3, marker 51736, data 8542), 21280 (index 2, flags 0x21, marker
////   51736, data 8542), 21272 and 21289 (markers 51737). WorldLocation2 51735: World
////   3460, centre (32.5895, -854.5823, -544.8400), radius 1.0, no vertical limit; 51736:
////   centre (54.0913, -854.5638, -540.1770), radius 1.0.
//// - quest 10527: objectives 21321 (index 0, flags 0), 21322 (index 1, flags 0x21),
////   21324 (index 2, a type 12), 21323 (index 3, type 22, flags 3, marker 51734) and
////   21325. WorldLocation2 51734: World 3460, centre (48.0406, -830.3301, 156.4670),
////   radius 1.0.
//// - quest 7426: objective 13674 (index 0, type 22, marker 28530): World 1061, centre
////   (1455.2638, -851.6394, 2992.7693), radius 42.6053, maxVerticalDistance 35. Quest
////   7413: objective 13907 (index 0, type 22, marker 44761): World 1061, centre
////   (1867.0724, -390.3604, 3167.8726), radius 30.0, maxVerticalDistance 8.
//// - quest 7667: objectives 14204 (index 0, type 5, count 1), 14205 (index 1, type 22,
////   flags 0x14, count 10, marker 30725) and 14376 (index 2, type 18). WorldLocation2
////   30725: World 1061, centre (3124.9680, -968.2173, 720.1985), radius 9.0219, no
////   vertical limit.
//// - quest 10520: objective 21294 (index 0, type 14, count 3, TargetGroup 14425, which
////   is Creature2 73500, questDirection 2488 whose places are WorldLocation2 51698,
////   51699 and 51700, each of radius 1.0 in World 3460: 51699 at (482.6148, -416.2688,
////   296.1966), 51700 at (465.2186, -405.4728, 280.6568)).
//// - the world database's spawns of Creature2 73500, in World 3460: 29338 at (464.81,
////   -410.57, 280.38), 29339 at (482.72, -420.95, 296.00) and 29340 at (508.63,
////   -429.19, 293.90) (wildstar-knowledge `world-data/spawn.tsv`); they hold the checklist
////   indexes 0, 1 and 2 (`checklist_index_test`).

import fixture_tables
import genesis_prime/game/objective.{Advanced, SendProgress}
import genesis_prime/game/quest_log
import genesis_prime/game/shown.{ShownObject}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{Hostile}
import gleam/dict
import gleam/list
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import spawn_support

/// Runs the body on the fixture's tables with these QuestObjective cells changed (the
/// objective's id, the column and its new value), built on the body's heap.
fn with_objectives(
  edits edits: List(#(Int, String, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(edits, fixture_tables.rows(), fn(rows, edit) {
      case
        fixture_tables.change(rows:, table: "QuestObjective", id: edit.0, with: [
          #(edit.1, Integer(edit.2)),
        ])
      {
        Ok(changed) -> changed
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The log settled for a player standing at the position of a world and zone, with no
/// unit in sight.
fn settled_at(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  world world_id: Int,
  zone world_zone_id: Int,
  at position: #(Float, Float, Float),
) -> objective.Advanced {
  settled_among(
    log:,
    tables:,
    world: world_id,
    zone: world_zone_id,
    at: position,
    units: [],
  )
}

/// A static object of a creature standing at the position in World 3460, zone 5968.
fn object_at(
  creature creature: Int,
  index checklist_index: Int,
  at position: #(Float, Float, Float),
) -> shown.Shown {
  ShownObject(
    creature_id: Creature2Id(creature),
    faction_id: 0,
    checklist_index:,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 5968,
      x: position.0,
      y: position.1,
      z: position.2,
    ),
    hit_radius: 0.0,
    hostile_to: Hostile(exile: False, dominion: False),
  )
}

/// The log settled for a player standing at the position, among these units (their unit
/// ids are their positions in the list).
fn settled_among(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  world world_id: Int,
  zone world_zone_id: Int,
  at position: #(Float, Float, Float),
  units units: List(shown.Shown),
) -> objective.Advanced {
  objective.settle(
    log:,
    tables:,
    items: [],
    zones: [],
    place: place_support.at(
      world_id:,
      world_zone_id:,
      x: position.0,
      y: position.1,
      z: position.2,
    ),
    shown: dict.from_list(
      list.index_map(units, fn(unit, number) { #(number, unit) }),
    ),
    now_ms: 0,
    numbers: spawn_support.numbers,
    unix_ms: 0,
  )
}

/// Quest 10513 accepted with nothing done.
fn first_ring() -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id: 10_513, progress: [0, 0, 0, 0, 0]),
  ])
}

pub fn a_position_inside_the_marker_completes_a_type_22_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // 0.4 east of WorldLocation2 51735's centre and 40 above it: inside the radius 1.0, and
  // its maxVerticalDistance of 0 tests no height (0x140485fa0).
  let log = first_ring()
  let reached =
    settled_at(log:, tables:, world: 3460, zone: 6009, at: #(
      32.9895,
      -854.5823 +. 40.0,
      -544.84,
    ))
  assert reached.effects
    == [SendProgress(quest_id: 10_513, objective_index: 0, progress: 1)]
    as "opcode.0x361: the ring's objective 21271 is done (count 1); objective 21279 waits for 21271 and its marker 51736 is not reached"
  assert quest_log.stored_state(log: reached.log, quest_id: 10_513) == 1
    as "the quest stays Accepted: its other objectives are open"
  assert settled_at(log: reached.log, tables:, world: 3460, zone: 6009, at: #(
      32.9895,
      -854.5823,
      -544.84,
    ))
    == Advanced(log: reached.log, effects: [])
    as "a done objective takes nothing from a second visit"
}

pub fn a_position_just_outside_the_marker_completes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // 1.01 east of 51735's centre, at its height: outside the radius 1.0.
  let log = first_ring()
  assert settled_at(log:, tables:, world: 3460, zone: 6009, at: #(
      32.5895 +. 1.01,
      -854.5823,
      -544.84,
    ))
    == Advanced(log:, effects: [])
    as "0x140485fa0: a horizontal distance above the radius is not at the place"
  assert settled_at(log:, tables:, world: 3460, zone: 6009, at: #(
      32.5895,
      -854.5823,
      -544.84 -. 1.01,
    ))
    == Advanced(log:, effects: [])
    as "the distance is horizontal in x and z, whichever way the player stands"
}

pub fn a_marker_in_another_world_is_not_reached_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // The client's test names no world, so the server holds the player to the marker's
  // World row: a position in another world with the same numbers is no arrival.
  let log = first_ring()
  assert settled_at(log:, tables:, world: 1061, zone: 6009, at: #(
      32.9895,
      -854.5823,
      -544.84,
    ))
    == Advanced(log:, effects: [])
    as "WorldLocation2 51735 is in World 3460"
}

pub fn a_marker_with_a_vertical_limit_refuses_a_far_height_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // 13674's marker 28530 has maxVerticalDistance 35: a height difference above it is not
  // at the place, whatever the horizontal distance; 13907's marker 44761 has 8.
  let broken = quest_support.accepted(quest_id: 7426, progress: [0, 0, 0, 0])
  let log = quest_support.log_of(rows: [broken])
  let centre = #(1455.2638, -851.6394, 2992.7693)
  assert settled_at(log:, tables:, world: 1061, zone: 1929, at: #(
      centre.0,
      centre.1 +. 36.0,
      centre.2,
    ))
    == Advanced(log:, effects: [])
    as "36 above the centre is past the limit of 35"
  assert settled_at(log:, tables:, world: 1061, zone: 1929, at: #(
      centre.0,
      centre.1 -. 36.0,
      centre.2,
    ))
    == Advanced(log:, effects: [])
    as "36 below it is past the limit too"
  assert settled_at(log:, tables:, world: 1061, zone: 1929, at: #(
      centre.0 +. 40.0,
      centre.1 +. 34.0,
      centre.2,
    )).effects
    == [SendProgress(quest_id: 7426, objective_index: 0, progress: 1)]
    as "34 above the centre and 40 across, inside the radius 42.6, is at the place"

  let hunt =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 7413, progress: [0, 0]),
    ])
  let hill = #(1867.0724, -390.3604, 3167.8726)
  assert settled_at(log: hunt, tables:, world: 1061, zone: 1936, at: #(
      hill.0,
      hill.1 +. 9.0,
      hill.2,
    ))
    == Advanced(log: hunt, effects: [])
    as "9 above 44761's centre is past its limit of 8"
  assert settled_at(log: hunt, tables:, world: 1061, zone: 1936, at: #(
      hill.0,
      hill.1 +. 7.0,
      hill.2,
    )).effects
    == [SendProgress(quest_id: 7413, objective_index: 0, progress: 1)]
    as "7 above it is at the place"
}

pub fn a_type_22_objective_not_yet_open_does_not_complete_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // The finish line, objective 21323 (index 3 of quest 10527, flags 3): it waits for every
  // earlier objective that is not optional (0x140553790), and 21321 and 21324 are not done.
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 10_527, progress: [0, 0, 0, 0, 0]),
    ])
  assert settled_at(log:, tables:, world: 3460, zone: 6010, at: #(
      48.0406,
      -830.3301,
      156.467,
    ))
    == Advanced(log:, effects: [])
    as "the finish line's marker 51734 is reached and its objective is not open"
}

pub fn an_optional_objective_completes_with_its_required_sibling_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objective 21279 (index 1, flags 3) and 21280 (index 2, flags 0x21, optional) share
  // data 8542 and marker 51736; objective 21271 is done.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_513,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0, 0, 0],
      ),
    ])
  let at_51736 = #(54.0913, -854.5638, -540.177)
  use tables <- with_objectives(edits: [])
  assert settled_at(log:, tables:, world: 3460, zone: 6009, at: at_51736).effects
    == [
      SendProgress(quest_id: 10_513, objective_index: 1, progress: 1),
      SendProgress(quest_id: 10_513, objective_index: 2, progress: 1),
    ]
    as "reaching 51736 completes the required objective and its optional one"

  // The optional objective with no marker of its own still completes with its sibling:
  // the two share data 8542, the server's trigger for the place.
  use unmarked <- with_objectives(edits: [
    #(21_280, "worldLocationsIdIndicator00", 0),
  ])
  assert settled_at(
      log:,
      tables: unmarked,
      world: 3460,
      zone: 6009,
      at: at_51736,
    ).effects
    == [
      SendProgress(quest_id: 10_513, objective_index: 1, progress: 1),
      SendProgress(quest_id: 10_513, objective_index: 2, progress: 1),
    ]
    as "the optional objective follows its required sibling of the same data, with or without a marker"

  // And it completes alone when only its own marker is reached.
  use sibling_unmarked <- with_objectives(edits: [
    #(21_279, "worldLocationsIdIndicator00", 0),
  ])
  assert settled_at(
      log:,
      tables: sibling_unmarked,
      world: 3460,
      zone: 6009,
      at: at_51736,
    ).effects
    == [SendProgress(quest_id: 10_513, objective_index: 2, progress: 1)]
    as "the optional objective's own marker completes it when its sibling has none"
}

pub fn the_finish_line_completes_on_entering_its_marker_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // Quest 10527's objectives 0 to 2 are done; objective 21323 is index 3, type 22, marker
  // 51734. No ring unit is in sight: the arrival alone counts.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_527,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b111,
        progress: [1, 1, 1, 0, 0],
      ),
    ])
  assert settled_at(log:, tables:, world: 3460, zone: 6010, at: #(
      48.0406 +. 0.5,
      -830.3301,
      156.467,
    )).effects
    == [SendProgress(quest_id: 10_527, objective_index: 3, progress: 1)]
    as "opcode.0x361 (10527, 3, 1): entering 51734 completes the finish line"
}

/// Quest 10520 accepted with nothing done: objective 21294 is index 0.
fn manifestations() -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id: 10_520, progress: [0, 0, 0, 0, 0]),
  ])
}

/// The three spawns of Creature2 73500 with the indexes the checklist assignment gives
/// them.
fn the_three() -> List(shown.Shown) {
  [
    object_at(creature: 73_500, index: 0, at: #(464.81, -410.57, 280.38)),
    object_at(creature: 73_500, index: 1, at: #(482.72, -420.95, 296.0)),
    object_at(creature: 73_500, index: 2, at: #(508.63, -429.19, 293.9)),
  ]
}

pub fn a_manifestation_place_reached_sets_the_bit_of_the_unit_under_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // 0.3 from 51699's centre: spawn 29339 (index 1) stands 0.23 from the centre, the other
  // two stand elsewhere.
  let first =
    settled_among(
      log: manifestations(),
      tables:,
      world: 3460,
      zone: 5968,
      at: #(482.9, -416.2688, 296.1966),
      units: the_three(),
    )
  assert first.effects
    == [SendProgress(quest_id: 10_520, objective_index: 0, progress: 0b10)]
    as "opcode.0x361: the mask holds the bit of index 1 and no other"
  assert settled_among(
      log: first.log,
      tables:,
      world: 3460,
      zone: 5968,
      at: #(482.7, -416.2688, 296.1966),
      units: the_three(),
    )
    == Advanced(log: first.log, effects: [])
    as "a second visit to the same place adds nothing"
  let second =
    settled_among(
      log: first.log,
      tables:,
      world: 3460,
      zone: 5968,
      at: #(465.2186, -405.4728, 280.6568),
      units: the_three(),
    )
  assert second.effects
    == [SendProgress(quest_id: 10_520, objective_index: 0, progress: 0b11)]
    as "51700 is under spawn 29338 (index 0), which joins the mask"

  // Two units of the group inside the place: the one nearest its centre counts.
  let crowded =
    settled_among(
      log: manifestations(),
      tables:,
      world: 3460,
      zone: 5968,
      at: #(482.6148, -416.2688, 296.1966),
      units: [
        object_at(creature: 73_500, index: 5, at: #(483.4, -420.0, 296.19)),
        object_at(creature: 73_500, index: 1, at: #(482.72, -420.95, 296.0)),
      ],
    )
  assert crowded.effects
    == [SendProgress(quest_id: 10_520, objective_index: 0, progress: 0b10)]
    as "the unit 0.23 from the centre counts, not the one 0.79 from it"
}

pub fn a_place_with_no_unit_of_the_group_counts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  let log = manifestations()
  let at_51699 = #(482.6148, -416.2688, 296.1966)
  assert settled_among(
      log:,
      tables:,
      world: 3460,
      zone: 5968,
      at: at_51699,
      units: [],
    )
    == Advanced(log:, effects: [])
    as "no unit in sight: the place counts nothing"
  assert settled_among(
      log:,
      tables:,
      world: 3460,
      zone: 5968,
      at: at_51699,
      units: [
        object_at(creature: 73_500, index: 0, at: #(464.81, -410.57, 280.38)),
        object_at(creature: 73_500, index: 2, at: #(508.63, -429.19, 293.9)),
      ],
    )
    == Advanced(log:, effects: [])
    as "units of the group stand only at the other two places, outside 51699's radius 1.0"
  assert settled_among(
      log:,
      tables:,
      world: 3460,
      zone: 5968,
      at: at_51699,
      units: [
        object_at(creature: 12_484, index: 3, at: #(482.72, -420.95, 296.0)),
      ],
    )
    == Advanced(log:, effects: [])
    as "a unit that is not in TargetGroup 14425 (Creature2 73500) counts nothing"
}

pub fn a_place_objective_with_a_count_above_one_is_not_done_by_one_arrival_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_objectives(edits: [])
  // Quest 7667: objective 14204 (index 0, type 5) is done, so 14205 (index 1, type 22,
  // flags 0x14, count 10, marker 30725) is open. WorldLocation2 30725: World 1061, centre
  // (3124.968, -968.2173, 720.1985), radius 9.0219, no vertical limit. The client sends
  // nothing for a place (`QuestObjective.type.22`) and nothing tells how its count of 10
  // is reached, so one arrival leaves it at 0.
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 7667,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [1, 0, 0],
      ),
    ])
  assert settled_at(log:, tables:, world: 1061, zone: 2117, at: #(
      3124.968,
      -968.2173,
      720.1985,
    ))
    == Advanced(log:, effects: [])
    as "objective 14205 has count 10: the arrival at its marker 30725 leaves it at 0"
}
