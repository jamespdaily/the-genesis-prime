//// The rule behind the tutorial's four projectors (`genesis_prime/game/projector`): where
//// each puts the player, which links it offers the move on, and the rows of the landing
//// table the load refuses. The expected places are the client's own WorldLocation2 rows
//// (float32 bits of position0 to position2, worldId, worldZoneId) and the expected links
//// the client's Prerequisite rows of each projector.

import cast_support
import character_tables
import genesis_prime/content/refusal.{type Refusal, RowId}
import genesis_prime/game/activate.{type Link, ClosedLink, OpenLink}
import genesis_prime/game/cast
import genesis_prime/game/objective_link
import genesis_prime/game/projector.{NotAProjector, NotOffered, Row}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import gleam/list
import gleam/string
import owned_test
import projector_support
import quest_support

const combat = 73_735

const housing = 73_741

const mission = 73_743

const cryo = 73_745

/// The departures terminal Northern Wilds (Creature2 73606), which casts another spell.
const a_terminal = 73_606

/// Faction2 167, the Exile, and 166, the Dominion (`Creature2` faction of a character).
const exile = 167

const dominion = 166

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

fn landing_of(
  creature_id creature_id: Int,
  faction faction: Int,
  link link: Link,
) -> Result(Place, projector.Refusal) {
  projector.landing(
    landings: projector_support.landings(),
    creature_id: Creature2Id(creature_id),
    faction_id: faction,
    link:,
  )
}

fn assert_place(
  landing landing: Result(Place, projector.Refusal),
  zone zone: Int,
  x x: Float,
  y y: Float,
  z z: Float,
  reason reason: String,
) -> Nil {
  let assert Ok(place) = landing as reason
  assert start_place.world_id(place) == 3460 as reason
  assert start_place.world_zone_id(place) == zone as reason
  assert start_place.x(place) == x as reason
  assert start_place.y(place) == y as reason
  assert start_place.z(place) == z as reason
}

/// The Exile's Combat Simulation quest (Quest2 10527) with the objectives before its
/// last, the use of the projector, done: 21321, 21324 and 21323 (the skipped 21322 is
/// not asked for), so mask 0b1101.
fn exile_before_the_combat_projector() -> QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id: 10_527,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 13,
      progress: [1, 0, 1, 1, 0],
    ),
  ])
}

pub fn each_projector_lands_at_its_row_test() -> Nil {
  use <- owned_test.run(5000)
  assert_place(
    landing: landing_of(creature_id: combat, faction: exile, link: OpenLink),
    zone: 5967,
    x: -50.53350067138672,
    y: -861.4010009765625,
    z: 307.8080139160156,
    reason: "WorldLocation2 51615, Warfare Woods",
  )
  assert_place(
    landing: landing_of(creature_id: housing, faction: exile, link: OpenLink),
    zone: 5969,
    x: 1177.1600341796875,
    y: -493.3890075683594,
    z: 223.45899963378906,
    reason: "WorldLocation2 51617, the housing plot",
  )
  assert_place(
    landing: landing_of(creature_id: mission, faction: exile, link: OpenLink),
    zone: 5968,
    x: 476.4630126953125,
    y: -393.81201171875,
    z: 254.22799682617188,
    reason: "WorldLocation2 51616, the mission hub",
  )
  assert_place(
    landing: landing_of(creature_id: combat, faction: dominion, link: OpenLink),
    zone: 5967,
    x: -50.53350067138672,
    y: -861.4010009765625,
    z: 307.8080139160156,
    reason: "the Dominion's Combat projector lands in the same place: 21356 asks for the same use",
  )
}

pub fn the_cryo_projector_lands_each_faction_in_its_own_pod_test() -> Nil {
  use <- owned_test.run(5000)
  assert_place(
    landing: landing_of(creature_id: cryo, faction: exile, link: OpenLink),
    zone: 5998,
    x: -4338.9521484375,
    y: -445.60028076171875,
    z: -4104.56787109375,
    reason: "WorldLocation2 51658: Quest2 10520's objective 21298 reaches zone 5998",
  )
  assert_place(
    landing: landing_of(creature_id: cryo, faction: dominion, link: OpenLink),
    zone: 5999,
    x: -3689.68408203125,
    y: -436.7900390625,
    z: -4356.00390625,
    reason: "WorldLocation2 51657: Quest2 10523's objective 21311 reaches zone 5999",
  )
}

pub fn a_closed_link_moves_no_one_test() -> Nil {
  use <- owned_test.run(5000)
  assert landing_of(creature_id: combat, faction: exile, link: ClosedLink)
    == Error(NotOffered(link: ClosedLink))
    as "a closed link is no offer"
  assert landing_of(creature_id: combat, faction: exile, link: activate.NoLink)
    == Error(NotOffered(link: activate.NoLink))
    as "no link is no offer"
  assert list.all([combat, housing, mission, cryo], fn(creature_id) {
    case landing_of(creature_id:, faction: dominion, link: ClosedLink) {
      Error(NotOffered(link: ClosedLink)) -> True
      _ -> False
    }
  })
    as "no projector moves anyone on a closed link"
}

pub fn a_creature_that_is_not_a_projector_moves_no_one_test() -> Nil {
  use <- owned_test.run(5000)
  assert landing_of(creature_id: a_terminal, faction: exile, link: OpenLink)
    == Error(NotAProjector)
    as "the departures terminal 73606 is no projector, open or not"
}

pub fn the_combat_projector_is_closed_without_its_objective_or_quest_test() -> Nil {
  use <- owned_test.run(5000)
  assert link_of(quests: quest_support.log_of(rows: []), creature_id: combat)
    == ClosedLink
    as "Prerequisite 43088 of Creature2 73735: no quest 10527 or 10532 held, so no open objective 4 and no state 2 or 3"
  assert link_of(
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 10_527, progress: [0, 0, 0, 0, 0]),
      ]),
      creature_id: combat,
    )
    == ClosedLink
    as "objective 21325 (flags 3) is reachable only once 21321, 21324 and 21323 are done"
}

pub fn the_combat_projector_opens_on_its_objective_test() -> Nil {
  use <- owned_test.run(5000)
  assert link_of(
      quests: exile_before_the_combat_projector(),
      creature_id: combat,
    )
    == OpenLink
    as "Prerequisite 41950's type 43 condition: objective 4 of Quest2 10527 is open once the others are done"
}

pub fn the_combat_projector_stays_offered_in_state_2_test() -> Nil {
  use <- owned_test.run(5000)
  let log =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_527,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 31,
        progress: [1, 1, 1, 1, 1],
      ),
    ])
  assert link_of(quests: log, creature_id: combat) == OpenLink
    as "Prerequisite 41950's type 6 conditions of comparison 1: the quest in state 2 is offered"
}

pub fn the_housing_projector_is_open_while_its_quest_is_held_test() -> Nil {
  use <- owned_test.run(5000)
  assert link_of(quests: quest_support.log_of(rows: []), creature_id: housing)
    == ClosedLink
    as "Prerequisite 41955: neither quest 10525 nor 10526 is held, so both states are 0"
  assert link_of(
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 10_525, progress: [0, 0, 0, 0, 0, 0]),
      ]),
      creature_id: housing,
    )
    == OpenLink
    as "Prerequisite 41955's type 6 conditions of comparison 2: a held quest's state is not 0"
}

pub fn the_mission_projector_opens_on_its_store_objective_test() -> Nil {
  use <- owned_test.run(5000)
  assert link_of(
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 10_540, progress: [0, 0, 0]),
      ]),
      creature_id: mission,
    )
    == OpenLink
    as "Prerequisite 41956's type 43 condition: objective 2 of Quest2 10540 (21372, flags 0x28) is open and reachable"
  assert link_of(
      quests: quest_support.log_of(rows: [
        quest_support.active(
          quest_id: 10_540,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 4,
          progress: [0, 0, 1],
        ),
      ]),
      creature_id: mission,
    )
    == ClosedLink
    as "with objective 2 done, the quest is in state 1, not 2 or 3: closed"
  assert link_of(quests: quest_support.log_of(rows: []), creature_id: mission)
    == ClosedLink
    as "no quest held"
}

/// The refusals the rows give over the client's committed tables.
fn refused(rows rows: List(projector.Row)) -> List(Refusal) {
  let assert Error(refusals) =
    projector.select(rows:, tables: character_tables.content_tables())
    as "the rows are refused"
  refusals
}

/// The eight rows with the row of `objective_id` replaced by `row`.
fn with_row(row row: projector.Row) -> List(projector.Row) {
  list.map(projector_support.rows(), fn(seeded) {
    case seeded.objective_id == row.objective_id {
      True -> row
      False -> seeded
    }
  })
}

pub fn a_landing_outside_the_training_world_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(
      rows: with_row(row: Row(
        creature_id: combat,
        faction_enum: 0,
        objective_id: 21_325,
        world_location2_id: 42_074,
      )),
    )
    as "one refusal: the row of objective 21325, whose landing is in world 426"
  assert table == "projector_landing"
  assert row == RowId(21_325)
  assert string.contains(rule, "426")
    as "the rule names the world the landing is in"
  assert string.contains(rule, "3460") as "the rule names the training world"
}

pub fn a_landing_with_no_world_location2_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(
      rows: with_row(row: Row(
        creature_id: housing,
        faction_enum: 0,
        objective_id: 21_344,
        world_location2_id: 1,
      )),
    )
    as "one refusal: the row of objective 21344, whose landing the client's table lacks"
  assert table == "projector_landing"
  assert row == RowId(21_344)
  assert string.contains(rule, "WorldLocation2")
}

pub fn a_creature_that_does_not_cast_the_projector_spell_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(
      rows: with_row(row: Row(
        creature_id: a_terminal,
        faction_enum: 0,
        objective_id: 21_325,
        world_location2_id: 51_615,
      )),
    )
    as "one refusal: Creature2 73606 casts Spell4 34680 when used"
  assert table == "projector_landing"
  assert row == RowId(21_325)
  assert string.contains(rule, "34680")
    as "the rule names the spell the creature casts"
  assert string.contains(rule, "87061") as "the rule names the projector spell"
}

pub fn a_zone_objective_the_landing_does_not_reach_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(
      rows: with_row(row: Row(
        creature_id: mission,
        faction_enum: 0,
        objective_id: 21_373,
        world_location2_id: 51_617,
      )),
    )
    as "one refusal: objective 21373 reaches zone 4964, which the housing plot's zone 5969 is not in"
  assert table == "projector_landing"
  assert row == RowId(21_373)
  assert string.contains(rule, "4964")
    as "the rule names the zone the objective reaches"
}

pub fn a_use_objective_of_another_creature_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(
      rows: with_row(row: Row(
        creature_id: housing,
        faction_enum: 0,
        objective_id: 21_325,
        world_location2_id: 51_617,
      )),
    )
    as "one refusal: objective 21325 is a use of Creature2 73735, not of 73741"
  assert table == "projector_landing"
  assert row == RowId(21_325)
  assert string.contains(rule, "73735")
    as "the rule names the creature the objective is a use of"
}

pub fn an_objective_of_the_other_faction_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(
      rows: with_row(row: Row(
        creature_id: combat,
        faction_enum: 0,
        objective_id: 21_356,
        world_location2_id: 51_615,
      )),
    )
    as "one refusal: objective 21356 is in Quest2 10532, which is the Dominion's"
  assert table == "projector_landing"
  assert row == RowId(21_356)
  assert string.contains(rule, "10532")
    as "the rule names the quest that holds the objective"
}
