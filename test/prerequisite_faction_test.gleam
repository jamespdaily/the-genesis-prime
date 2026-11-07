//// The faction conditions of the prerequisite rule
//// (`genesis_prime/game/prerequisite`): types 4, 243 and 250. Expected values come
//// from these places, each named at its assertion:
//// - `Prerequisite.prerequisiteTypeId.243`: the client's check of type 243 always
////   fails, whatever the unit, comparison, objectId and value
////   (slot 0x70 of the prerequisite class is `xor eax, eax; ret`).
//// - `Prerequisite.prerequisiteTypeId.250`: the unit's base faction (the faction
////   message 0x262's second faction field) against the value: comparison 1 passes
////   when equal, 2 when not equal, any other fails; a unit with no faction counts
////   as 0; the objectId is not read.
//// - `Prerequisite.prerequisiteTypeId.4`: the same on the unit's current faction (the
////   first faction field).
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite 30100
////   30101`): 30100 is an OR of (243, comparison 1, value 167) and (250, comparison 1,
////   value 167), and 30101 of (243, 1, 166) and (250, 1, 166, objectId 6548); the
////   Faction2 rows 166 and 167 are the Dominion and the Exiles.
//// - `opcode.0x262`: the unit's faction is the first faction field and its base
////   faction the second.
//// A subject's two factions are given different values wherever a test must tell the
//// current faction from the base faction.

import cast_support as support
import character_support
import character_tables
import client_tables
import genesis_prime/game/area.{Point, Pose}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/connection/casting
import genesis_prime/game/prerequisite.{
  type Prerequisite, type Subject, type Verdict, Factions, Fails, NotRead,
  Passes, Subject,
}
import genesis_prime/game/spell_plan.{type Plans, CastGate, Spell}
import genesis_prime/game/world_entry
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/table/id.{PrerequisiteId}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import unitest
import world_entry_support

const dominion = 166

const exiles = 167

/// A subject whose first unit has these two factions.
fn with_factions(current current: Int, base base: Int) -> Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: None),
    factions: Some(Factions(current:, base:)),
  )
}

/// A subject that holds no factions.
fn without_factions() -> Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: None),
    factions: None,
  )
}

/// A row of one condition, as (type, comparison, objectId, value), checked against the
/// subject.
fn checked(
  condition condition: #(Int, Int, Int, Int),
  subject subject: Subject,
) -> Verdict {
  prerequisite_support.check(
    row: prerequisite_support.row(id: 1, flags: 0, conditions: [condition]),
    subject:,
  )
}

// ---- 1: type 243 ----

pub fn type_243_fails_for_every_subject_comparison_and_value_test() -> Nil {
  use <- owned_test.run(5000)
  let origin = Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0)
  let subjects = [
    with_factions(current: exiles, base: exiles),
    with_factions(current: dominion, base: dominion),
    with_factions(current: 0, base: 0),
    without_factions(),
    prerequisite.of_struck(first: None, second: origin),
    prerequisite.of_difficulty(difficulty: 1),
  ]
  list.each(subjects, fn(subject) {
    list.each([0, 1, 2, 3, 4, 5, 6, 7], fn(comparison) {
      list.each([0, dominion, exiles], fn(value) {
        assert checked(condition: #(243, comparison, 0, value), subject:)
          == Fails
          as "the client's slot 0x70 of the prerequisite class is xor eax, eax; ret: type 243 passes for nothing, not even comparison 1 on the unit's own faction"
      })
    })
  })
}

// ---- 2 and 3: types 250 and 4 ----

/// What a faction condition of this type gives for each comparison from 0 to 7 and the
/// values 0, 166, 167 and 168, against a subject of current faction 166 and base
/// faction 167, as (comparison, value, verdict).
fn verdicts_of(type_id type_id: Int) -> List(#(Int, Int, Verdict)) {
  let subject = with_factions(current: dominion, base: exiles)
  list.flat_map([0, 1, 2, 3, 4, 5, 6, 7], fn(comparison) {
    list.map([0, dominion, exiles, 168], fn(value) {
      #(
        comparison,
        value,
        checked(condition: #(type_id, comparison, 0, value), subject:),
      )
    })
  })
}

/// The verdicts the client gives a unit whose compared faction is 167 (equal passes
/// for comparison 1, not equal for comparison 2, any other comparison fails).
fn verdicts_for_faction_167() -> List(#(Int, Int, Verdict)) {
  [
    #(0, 0, Fails),
    #(0, 166, Fails),
    #(0, 167, Fails),
    #(0, 168, Fails),
    #(1, 0, Fails),
    #(1, 166, Fails),
    #(1, 167, Passes),
    #(1, 168, Fails),
    #(2, 0, Passes),
    #(2, 166, Passes),
    #(2, 167, Fails),
    #(2, 168, Passes),
    #(3, 0, Fails),
    #(3, 166, Fails),
    #(3, 167, Fails),
    #(3, 168, Fails),
    #(4, 0, Fails),
    #(4, 166, Fails),
    #(4, 167, Fails),
    #(4, 168, Fails),
    #(5, 0, Fails),
    #(5, 166, Fails),
    #(5, 167, Fails),
    #(5, 168, Fails),
    #(6, 0, Fails),
    #(6, 166, Fails),
    #(6, 167, Fails),
    #(6, 168, Fails),
    #(7, 0, Fails),
    #(7, 166, Fails),
    #(7, 167, Fails),
    #(7, 168, Fails),
  ]
}

pub fn type_250_compares_the_base_faction_1_equal_2_not_equal_and_any_other_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdicts_of(type_id: 250) == verdicts_for_faction_167()
    as "the unit's current faction is 166 and its base faction 167: type 250 reads the base faction (0x14049c6a0: [rdx+0x110], SetUnitBaseFaction); comparison 1 passes on equal, 2 on not equal, 3 to 7 and 0 fail"
}

pub fn type_250_does_not_read_its_object_id_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = with_factions(current: dominion, base: exiles)
  assert checked(condition: #(250, 1, 6548, exiles), subject:) == Passes
    as "row 30101's second condition holds objectId 6548, which the client's check does not read"
  assert checked(condition: #(250, 1, 0, exiles), subject:) == Passes
    as "the same with no objectId"
}

pub fn type_4_compares_the_current_faction_1_equal_2_not_equal_and_any_other_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = with_factions(current: exiles, base: dominion)
  let expected = verdicts_for_faction_167()
  assert list.map(expected, fn(row) {
      #(row.0, row.1, checked(condition: #(4, row.0, 0, row.1), subject:))
    })
    == expected
    as "the unit's current faction is 167 and its base faction 166: type 4 reads the current faction (0x14049c620: slot 0x58, the unit's 0x118, SetUnitFaction); comparison 1 passes on equal, 2 on not equal, 3 to 7 and 0 fail"
}

// ---- 4: no faction counts as 0 ----

pub fn a_unit_with_no_faction_reads_faction_0_in_types_4_and_250_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = with_factions(current: 0, base: 0)
  list.each([4, 250], fn(type_id) {
    assert checked(condition: #(type_id, 1, 0, 0), subject:) == Passes
      as "a unit with no faction counts as faction 0: comparison 1 on value 0 passes"
    assert checked(condition: #(type_id, 2, 0, 0), subject:) == Fails
      as "and comparison 2 on value 0 fails"
    assert checked(condition: #(type_id, 1, 0, exiles), subject:) == Fails
      as "it is not an Exile"
    assert checked(condition: #(type_id, 2, 0, exiles), subject:) == Passes
      as "it differs from an Exile"
  })
}

pub fn a_subject_that_holds_no_factions_leaves_types_4_and_250_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  let origin = Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0)
  let struck = prerequisite.of_struck(first: Some(origin), second: origin)
  list.each(
    [
      without_factions(),
      struck,
      prerequisite.of_difficulty(difficulty: 1),
    ],
    fn(subject) {
      list.each([4, 250], fn(type_id) {
        assert checked(condition: #(type_id, 1, 0, exiles), subject:)
          == NotRead(prerequisite_type: type_id)
          as "a creature known by its place alone, or by its difficulty, holds no factions: the server cannot say what the client would"
      })
    },
  )
}

// ---- 5: the client's rows ----

fn client_row(id id: Int) -> Prerequisite {
  let tables = client_tables.shared()
  let assert Ok(loaded) =
    prerequisite.load(
      id: PrerequisiteId(id),
      rows: prerequisite.table_rows(tables:),
      arcs: prerequisite.table_arcs(tables:),
    )
    as "the client's table holds the row"
  loaded
}

pub fn rows_30100_and_30101_pass_on_the_base_faction_alone_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let exile_gate = client_row(id: 30_100)
  let dominion_gate = client_row(id: 30_101)
  let check = fn(gate, subject) {
    prerequisite.check(prerequisite: gate, subject:)
  }
  assert check(exile_gate, with_factions(current: dominion, base: exiles))
    == Passes
    as "30100 is an OR of 243, which fails, and 250 on 167: it passes for base faction 167 though the current faction is 166"
  assert check(dominion_gate, with_factions(current: dominion, base: exiles))
    == Fails
    as "30101 needs base faction 166"
  assert check(exile_gate, with_factions(current: exiles, base: dominion))
    == Fails
    as "30100 fails for base faction 166 though the current faction is 167"
  assert check(dominion_gate, with_factions(current: exiles, base: dominion))
    == Passes
    as "30101 passes for base faction 166"
  assert check(exile_gate, with_factions(current: 0, base: 0)) == Fails
    && check(dominion_gate, with_factions(current: 0, base: 0)) == Fails
    as "a unit with no faction passes neither"
}

// ---- 6: the caster carries the factions of its 0x262 ----

pub fn the_caster_carries_the_faction_and_base_faction_of_its_0x262_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: character_support.character(number: 1),
    )
  let with_unit_factions = fn(current, base) {
    world_entry.Entered(
      ..entered,
      unit: UnitCreatePlayer(
        ..entered.unit,
        tail: UnitCreateTail(
          ..entered.unit.tail,
          faction_id: current,
          base_faction_id: base,
        ),
      ),
    )
  }
  assert casting.caster_of(entered: with_unit_factions(dominion, exiles)).factions
    == Factions(current: dominion, base: exiles)
    as "the 0x262's first faction field is the current faction and its second the base faction (opcode.0x262)"
  assert casting.caster_of(entered: with_unit_factions(exiles, dominion)).factions
    == Factions(current: exiles, base: dominion)
    as "swapped, they swap"
}

/// A caster of current faction 166 and base faction 167.
fn caster_of_factions() -> Caster {
  cast.Caster(
    ..support.caster(),
    factions: Factions(current: dominion, base: exiles),
  )
}

/// The plans with a spell of base 1 (bag index 8) whose cast condition is this
/// condition, as (type, comparison, objectId, value).
fn plans_gated_on(condition condition: #(Int, Int, Int, Int)) -> Plans {
  support.with_spells(plans: support.plans(), spells: [
    Spell(
      ..support.child(spell4_id: 5001, base: 1),
      caster_cast: CastGate(prerequisite: prerequisite_support.single(
        id: 1,
        condition:,
      )),
    ),
  ])
}

fn refusals_of_press(condition condition: #(Int, Int, Int, Int)) -> List(Int) {
  let #(_, effects): #(State, List(Effect)) =
    support.pressed_in(
      plans: plans_gated_on(condition:),
      state: cast.new(),
      caster: caster_of_factions(),
      bag_index: 8,
      target: 0,
      at: 1000,
    )
  support.refusal_results(effects:)
}

pub fn a_cast_condition_of_type_250_reads_the_casters_base_faction_test() -> Nil {
  use <- owned_test.run(20_000)
  assert refusals_of_press(condition: #(250, 1, 0, exiles)) == []
    as "the caster's base faction is 167: 250 on 167 passes"
  assert refusals_of_press(condition: #(250, 1, 0, dominion)) == [151]
    as "250 on 166, the caster's current faction, fails: CasterCast refuses with 151 (0x1403ace00)"
}

pub fn a_cast_condition_of_type_4_reads_the_casters_current_faction_test() -> Nil {
  use <- owned_test.run(20_000)
  assert refusals_of_press(condition: #(4, 1, 0, dominion)) == []
    as "the caster's current faction is 166: type 4 on 166 passes"
  assert refusals_of_press(condition: #(4, 1, 0, exiles)) == [151]
    as "type 4 on 167, the caster's base faction, fails: CasterCast refuses with 151 (0x1403ace00)"
}
