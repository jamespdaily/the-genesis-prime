//// Whether the communicator may turn a quest in (`genesis_prime/game/communicator`): the
//// conditions of a CommunicatorMessages row that delivers it. Expected values come from
//// these places, and never from the helpers that build the input.
//// - `0x14043d1f0` (mode 1: some row of the quest, flags bit 0 clear, whose conditions
////   hold) and `0x14043d3d0` (a row's conditions, each with the code it returns:
////   2 World, 3 zone, 5 class, 6 race, 7 base faction, 8 reputation, 10 maxLevel, 9
////   minLevel, 0xb quest states, 0xc prerequisite), then `0x14043d650` (the row's
////   creature: 0x10 when it does not receive the quest, 0x11 when the quest is held
////   Accepted).
//// - `0x14043d870` (a quest state a row wants, read against the log).
//// - The fixture's rows: CommunicatorMessages 1281 (creature 11063, World 426, quest00
////   3673 wanted at state 2, delivers 3673), 2081 (the same creature and World, flags 1,
////   delivers 3673), 1907 (creature 11066, World 51, zone 13, quest00 3741 at state 2,
////   delivers 3741); Quest2 3673 and 3741 have flags 0x10000.

import character_tables
import genesis_prime/game/communicator.{
  NoDeliveringRow, ReputationCondition, Unread,
}
import genesis_prime/game/prerequisite
import genesis_prime/game/vendor_trade.{Log}
import genesis_prime/table/id.{Quest2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import gleam/dict
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import quest_support
import quest_turn_in_support as support

fn tables() -> table_store.Tables {
  character_tables.shared()
}

/// The scene of a quest held Achieved, in this World.
fn in_world(quest_id quest_id: Int, world_id world_id: Int) -> support.Scene {
  support.Scene(..support.scene(quest_id:), world_id:)
}

/// The communicator's verdict for the scene's quest and player.
fn asked(
  scene scene: support.Scene,
  tables tables: table_store.Tables,
) -> Result(Nil, communicator.Refusal) {
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(scene.quest_id))
    as "the fixture holds the quest"
  communicator.turn_in(quest: row, asker: support.asker(scene:), tables:)
}

/// A change of CommunicatorMessages row `id`.
fn row_with(
  id id: Int,
  cells cells: List(#(String, planted_table.Cell)),
) -> #(String, Int, List(#(String, planted_table.Cell))) {
  #("CommunicatorMessages", id, cells)
}

/// The refusal that only the first row fails, with its code.
fn failed_with(code code: Int) -> Result(Nil, communicator.Refusal) {
  Error(NoDeliveringRow(failed: [#(1281, code)]))
}

pub fn delivering_row_holds_only_in_its_world_test() -> Nil {
  use <- owned_test.run(10_000)
  // Row 1281 has worldId 426; `0x14043d3d0` returns 2 for another World. Row 2081 has
  // flags bit 0 set, so it is not read.
  assert asked(scene: in_world(quest_id: 3673, world_id: 426), tables: tables())
    == Ok(Nil)
  assert asked(scene: in_world(quest_id: 3673, world_id: 870), tables: tables())
    == failed_with(code: 2)
}

pub fn delivering_row_with_flags_bit_1_is_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043d1f0` mode 1 tests flags bit 0 of each row of the quest. With row 1281's
  // state00 changed to 3 (the quest held Achieved is not Completed), only row 2081
  // (flags 1, World 426, creature 11063, no conditions) would deliver it, and it is
  // not read, so the refusal names row 1281 and code 0xb alone.
  use tables <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("state00", Integer(3))]),
  ])
  assert asked(scene: in_world(quest_id: 3673, world_id: 426), tables:)
    == failed_with(code: 0xb)
}

pub fn delivering_row_zone_is_the_player_zone_or_a_parent_test() -> Nil {
  use <- owned_test.run(10_000)
  // Row 1907 has worldId 51 and worldZoneId 13; `0x14043d3d0` returns 3 when the zone
  // is not the player's or one above it (`Player.zones`: the zone, then each parent).
  let scene = fn(zones) {
    support.Scene(..in_world(quest_id: 3741, world_id: 51), zones:)
  }
  assert asked(scene: scene([13]), tables: tables()) == Ok(Nil)
  assert asked(scene: scene([999, 13]), tables: tables()) == Ok(Nil)
  assert asked(scene: scene([999, 998]), tables: tables())
    == Error(NoDeliveringRow(failed: [#(1907, 3)]))
}

pub fn delivering_row_level_bounds_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043d3d0`: 10 when the level is above maxLevel, 9 when below minLevel, and a
  // bound of 0 is none.
  use tables <- support.with_changes(changes: [
    row_with(id: 1281, cells: [
      #("minLevel", Integer(10)),
      #("maxLevel", Integer(15)),
    ]),
  ])
  let at = fn(level) {
    asked(
      scene: support.Scene(..in_world(quest_id: 3673, world_id: 426), level:),
      tables:,
    )
  }
  assert at(9) == failed_with(code: 9)
  assert at(16) == failed_with(code: 10)
  assert at(10) == Ok(Nil)
  assert at(15) == Ok(Nil)
  use unbounded <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("minLevel", Integer(10))]),
  ])
  assert asked(
      scene: support.Scene(..in_world(quest_id: 3673, world_id: 426), level: 50),
      tables: unbounded,
    )
    == Ok(Nil)
    as "a maxLevel of 0 sets no upper bound"
  use no_floor <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("maxLevel", Integer(15))]),
  ])
  assert asked(
      scene: support.Scene(..in_world(quest_id: 3673, world_id: 426), level: 1),
      tables: no_floor,
    )
    == Ok(Nil)
    as "a minLevel of 0 sets no lower bound"
}

pub fn delivering_row_class_race_and_base_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043d3d0` returns 5 for another class, 6 for another race and 7 for another
  // faction, which it reads from the unit's base faction (unit word 0x110), not the
  // current one. The scene is class 5, race 3, Exile (167) as both.
  let scene = in_world(quest_id: 3673, world_id: 426)
  use class_row <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("classId", Integer(5))]),
  ])
  assert asked(scene:, tables: class_row) == Ok(Nil)
  use other_class <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("classId", Integer(1))]),
  ])
  assert asked(scene:, tables: other_class) == failed_with(code: 5)
  use race_row <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("raceId", Integer(3))]),
  ])
  assert asked(scene:, tables: race_row) == Ok(Nil)
  use other_race <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("raceId", Integer(4))]),
  ])
  assert asked(scene:, tables: other_race) == failed_with(code: 6)
  use faction_row <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("factionId", Integer(167))]),
  ])
  assert asked(scene:, tables: faction_row) == Ok(Nil)
  let current_only =
    support.Scene(
      ..scene,
      factions: prerequisite.Factions(current: 166, base: 167),
    )
  assert asked(scene: current_only, tables: faction_row) == Ok(Nil)
    as "a current faction of 166 does not fail a row of base faction 167"
  let base_other =
    support.Scene(
      ..scene,
      factions: prerequisite.Factions(current: 167, base: 166),
    )
  assert asked(scene: base_other, tables: faction_row) == failed_with(code: 7)
    as "a base faction of 166 fails it"
}

pub fn delivering_row_reputation_condition_is_not_read_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043d3d0` code 8 measures the standing with factionIdReputation, which the
  // server does not keep (the open issue 674 gives it). The row is not read: a row that
  // fails an earlier code still fails with that code.
  use tables <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("factionIdReputation", Integer(167))]),
  ])
  let scene = in_world(quest_id: 3673, world_id: 426)
  assert asked(scene:, tables:)
    == Error(Unread(gap: ReputationCondition(row_id: 1281, faction_id: 167)))
  assert asked(scene: in_world(quest_id: 3673, world_id: 870), tables:)
    == failed_with(code: 2)
    as "the World is tested before the reputation"
  // Through the turn-in the refusal is one log line naming the issue.
  let by_communicator =
    support.Scene(..scene, by_communicator: 1, picture: dict.new())
  let #(effects, _) = support.refused(scene: by_communicator, tables:)
  let assert [Log(text:, ..)] = effects as "one log line"
  assert string.contains(text, "#674")
    as "the log line names the issue that will close the gap"
}

pub fn delivering_row_prerequisite_test() -> Nil {
  use <- owned_test.run(10_000)
  // Prerequisite 3 is one condition of type 3 (the unit's class), comparison 1 (equal),
  // value 1. `0x14043d3d0` returns 0xc when the evaluator (slot 0x18) fails it, and
  // fails an id with no row (`0x1404a1ca0`, as `quest.prerequisite_met` notes).
  let scene = fn(class_id) {
    support.Scene(..in_world(quest_id: 3673, world_id: 426), class_id:)
  }
  use named <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("prerequisiteId", Integer(3))]),
  ])
  assert asked(scene: scene(1), tables: named) == Ok(Nil)
  assert asked(scene: scene(5), tables: named) == failed_with(code: 0xc)
  use missing <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("prerequisiteId", Integer(99_999))]),
  ])
  assert asked(scene: scene(1), tables: missing) == failed_with(code: 0xc)
    as "a prerequisite id with no row fails"
}

pub fn delivering_row_creature_must_receive_the_quest_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043d650` on the row's creature: 0x10 when the creature does not receive the
  // quest (Creature2 74812 receives 10520 and not 3673), 0x11 when the quest is held
  // Accepted (state 1).
  let scene = in_world(quest_id: 3673, world_id: 426)
  use other_creature <- support.with_changes(changes: [
    row_with(id: 1281, cells: [#("creatureId", Integer(74_812))]),
  ])
  assert asked(scene:, tables: other_creature) == failed_with(code: 0x10)
  // State 0 wanted of quest 0 passes the state test, leaving the creature's check.
  use no_state <- support.with_changes(changes: [
    row_with(id: 1281, cells: [
      #("quest00", Integer(0)),
      #("state00", Integer(0)),
    ]),
  ])
  let accepted =
    support.Scene(..scene, log: [
      quest_support.accepted(
        quest_id: 3673,
        progress: list.repeat(0, quest_support.objective_count(quest_id: 3673)),
      ),
    ])
  assert asked(scene: accepted, tables: no_state) == failed_with(code: 0x11)
  assert asked(scene:, tables: no_state) == Ok(Nil)
}

pub fn row_quest_state_reads_as_the_client_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043d870`: quest 0 passes; a quest with no Quest2 row fails; a held state of 5
  // to 7 reads as 0; 0xb is held 0 or 4, or 3 of a repeatable quest (flags 0x20); 0xc
  // is held 1 or 2; 0xd is held 2 or 3; any other wanted state equals the held one; of
  // a quest in the active list, 5 to 10 is objective (n - 5) done and 0xe to 0x13 is
  // objective (n - 0xe) not done.
  let holds = fn(tables, rows, quest_id, wanted) {
    communicator.quest_state_holds(
      log: quest_support.log_of(rows:),
      quest_id:,
      wanted:,
      tables:,
    )
  }
  let none = []
  assert holds(tables(), none, 0, 7) as "quest 0 passes"
  assert !holds(tables(), none, 99_999_999, 0) as "no Quest2 row fails"
  assert holds(tables(), none, 3673, 0) as "held 0 is wanted 0"
  assert !holds(tables(), none, 3673, 2)
  assert holds(
    tables(),
    [quest_support.known(quest_id: 3673, state: 5)],
    3673,
    0,
  )
    as "held 5 reads as 0"
  assert holds(
    tables(),
    [quest_support.known(quest_id: 3673, state: 7)],
    3673,
    0xb,
  )
    as "held 7 reads as 0, which 0xb takes"
  assert holds(
    tables(),
    [quest_support.known(quest_id: 3673, state: 4)],
    3673,
    0xb,
  )
  assert holds(tables(), none, 3673, 0xb)
  let completed = [quest_support.completed(quest_id: 3673, at: 1)]
  assert !holds(tables(), completed, 3673, 0xb)
    as "held 3 is not 0xb for a quest that is not repeatable"
  assert holds(tables(), completed, 3673, 3)
  assert holds(tables(), completed, 3673, 0xd)
  use repeatable <- support.with_changes(changes: [
    #("Quest2", 3673, [#("flags", Integer(0x10020))]),
  ])
  assert holds(repeatable, completed, 3673, 0xb)
    as "held 3 is 0xb for a quest of flags 0x20"
  let achieved = [support.achieved(quest_id: 3673)]
  assert holds(tables(), achieved, 3673, 2)
  assert holds(tables(), achieved, 3673, 0xc)
  assert holds(tables(), achieved, 3673, 0xd)
  assert !holds(tables(), achieved, 3673, 0xb)
  assert !holds(tables(), achieved, 3673, 1)
  let accepted = [
    quest_support.accepted(
      quest_id: 3673,
      progress: list.repeat(0, quest_support.objective_count(quest_id: 3673)),
    ),
  ]
  assert holds(tables(), accepted, 3673, 0xc)
  assert !holds(tables(), accepted, 3673, 0xd)
  // Quest 10520 has five objectives. Objectives 0 and 2 are done.
  let partly = [
    quest_support.active(
      quest_id: 10_520,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 5,
      progress: [1, 0, 1, 0, 0],
    ),
  ]
  assert holds(tables(), partly, 10_520, 5) as "5 is objective 0 done"
  assert !holds(tables(), partly, 10_520, 6) as "6 is objective 1 done"
  assert holds(tables(), partly, 10_520, 7) as "7 is objective 2 done"
  assert !holds(tables(), partly, 10_520, 0xe)
    as "0xe wants objective 0 not done, and it is done"
  assert holds(tables(), partly, 10_520, 0xf) as "0xf is objective 1 not done"
  assert !holds(tables(), partly, 10_520, 0x10)
    as "0x10 wants objective 2 not done, and it is done"
  Nil
}
