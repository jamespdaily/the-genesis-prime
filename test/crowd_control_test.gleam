//// The instance id of a crowd-control effect (`genesis_prime/game/crowd_control`).
//// Expected values come from `cc_state.instance_id`: the client finds the effect a 0x87f
//// waits for by instance id alone among every effect held on the unit, from any caster,
//// and 0 matches the first effect found, so an id is non-zero and no two effects on a
//// unit share one; the id is 32 bits on the wire (`opcode.0x87f`); a unit id is below
//// 2^20, the bound the cast ids already hold (`cast.cast_id`).

import fixture_tables
import genesis_prime/game/cast
import genesis_prime/game/crowd_control
import genesis_prime/message/crowd_control_state
import genesis_prime/table/cc_states
import genesis_prime/table/loader/store
import genesis_prime/table/spell4_cc_conditions
import gleam/int
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import qcheck

pub fn a_casters_first_ids_are_its_unit_id_times_4096_plus_the_count_test() -> Nil {
  use <- owned_test.run(5000)
  assert crowd_control.instance_id(caster_unit_id: 7, count: 1) == 28_673
  assert crowd_control.instance_id(caster_unit_id: 7, count: 2) == 28_674
  assert crowd_control.instance_id(caster_unit_id: 7, count: 4095) == 32_767
    as "the last number of unit 7's range"
  assert crowd_control.instance_id(caster_unit_id: 7, count: 4096) == 28_673
    as "the count wraps within the caster's range, which stays below the next unit's"
}

pub fn every_id_is_non_zero_within_32_bits_and_two_casters_never_share_one_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(first, second, first_count, second_count) <- qcheck.given(qcheck.tuple4(
    qcheck.bounded_int(1, 1_048_575),
    qcheck.bounded_int(1, 1_048_575),
    qcheck.bounded_int(1, 100_000),
    qcheck.bounded_int(1, 100_000),
  ))
  let one = crowd_control.instance_id(caster_unit_id: first, count: first_count)
  let other =
    crowd_control.instance_id(caster_unit_id: second, count: second_count)
  assert one >= 1 && one < 4_294_967_296
    as "non-zero, and within the 32 bits of 0x87f"
  assert one >= 4096
    as "never equal to the small ids a go numbers its damage and Fluff effects with"
  assert first == second || one != other
    as "two casters' effects on one creature differ"
}

pub fn one_casters_ids_within_4095_counts_differ_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(unit, count, apart) <- qcheck.given(qcheck.tuple3(
    qcheck.bounded_int(1, 1_048_575),
    qcheck.bounded_int(1, 100_000),
    qcheck.bounded_int(1, 4094),
  ))
  assert crowd_control.instance_id(caster_unit_id: unit, count:)
    != crowd_control.instance_id(caster_unit_id: unit, count: count + apart)
    as "a state is gone long before its caster tells 4095 more"
}

pub fn the_bound_on_unit_ids_is_the_cast_ids_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast.cast_id(unit_id: 1_048_575, number: 2047) < 4_294_967_296
    as "a unit id of 2^20 - 1 is the largest whose cast ids fit 32 bits, so the largest the instance ids need"
}

/// The results `CheckSpellCCConditions` (`0x1403b2c40`) gives for each state, as the
/// client's names for them (`Spell.CodeEnumCastResult`, `0x140c2f290`): the state, its
/// Caster_CannotBe result and its Target_CannotBe result.
fn client_results() -> List(#(Int, Int, Int)) {
  [
    #(0, 73, 122),
    #(1, 75, 124),
    #(2, 77, 126),
    #(3, 79, 128),
    #(4, 81, 130),
    #(5, 200, 201),
    #(6, 85, 134),
    #(7, 204, 205),
    #(8, 158, 161),
    #(9, 159, 160),
    #(10, 159, 160),
    #(11, 208, 209),
    #(12, 212, 213),
    #(13, 216, 217),
    #(14, 220, 221),
    #(15, 224, 225),
    #(16, 228, 229),
    #(17, 232, 233),
    #(18, 236, 237),
    #(19, 240, 241),
    #(20, 244, 245),
    #(21, 248, 249),
    #(22, 260, 261),
    #(23, 266, 267),
    #(24, 271, 272),
    #(25, 292, 293),
    #(26, 297, 298),
    #(27, 302, 303),
  ]
}

pub fn cc_condition_results_match_the_client_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.length(client_results()) == 28
    as "Unit.CodeEnumCCState names 28 states"
  list.each(client_results(), fn(row) {
    let #(state, caster, target) = row
    let held = crowd_control_state.from_value(state)
    assert crowd_control.caster_result(held) == caster
      as {
        "0x1403b2c40: a held state "
        <> int.to_string(state)
        <> " on the caster gives "
        <> int.to_string(caster)
      }
    assert crowd_control.target_result(held) == target
      as {
        "0x1403b2c40: a held state "
        <> int.to_string(state)
        <> " on the target gives "
        <> int.to_string(target)
      }
  })
  assert crowd_control.target_result(crowd_control_state.VulnerabilityWithAct)
    == crowd_control.target_result(crowd_control_state.Vulnerability)
    as "0x1403b2c40: state 10 gives state 9's results, as the client does"
}

/// The client's Spell4CCConditions row 1 with ccStateFlagsRequired changed, loaded with
/// the crowd-control requirements.
fn load_with_flags_required(
  value value: Int,
) -> Result(store.Tables, store.LoadError) {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4CCConditions",
      id: 1,
      with: [#("ccStateFlagsRequired", Integer(value))],
    )
    as "the client's table holds Spell4CCConditions row 1"
  fixture_tables.edited(
    rows:,
    entries: [spell4_cc_conditions.entry()],
    requirements: crowd_control.requirements(),
    derivations: [],
  )
}

pub fn a_condition_row_asking_for_a_state_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(_) = load_with_flags_required(value: 0)
    as "the client's 12 rows hold ccStateFlagsRequired 0 (an own count over the table's dump), which load"
  let assert Error(error) = load_with_flags_required(value: 4)
    as "0x1403b2c40: a row whose ccStateFlagsRequired asks for a state gives a Caster_MustBe or Target_MustBe result, which the server does not read, so the load fails"
  let assert store.RowMissing(id: 1, column:, ..) = error
    as "the failure names the row, 1"
  assert string.contains(column, "ccStateFlagsRequired")
    as "the failure names the column"
  assert string.contains(store.describe(error), "MustBe")
    as "the failure says what the server does not read"
}

pub fn a_missing_state_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(rows) =
    fixture_tables.remove(rows: fixture_tables.rows(), table: "CCStates", id: 5)
    as "the client's table holds CCStates row 5, Polymorph"
  let assert Error(error) =
    fixture_tables.edited(
      rows:,
      entries: [cc_states.entry()],
      requirements: crowd_control.requirements(),
      derivations: [],
    )
    as "the server names states 0 to 27 and reads each one's row (stopping_mask, hard_held), so a table without one fails the load"
  let assert store.RowMissing(to_table:, id:, ..) = error
    as "the load's failure is a missing row"
  assert to_table == "CCStates" && id == 5
    as "the failure names the table and the missing row, 5"
}

pub fn the_clients_condition_rows_all_ask_for_no_state_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  assert list.flat_map(crowd_control.requirements(), fn(requirement) {
      requirement.missing(tables)
    })
    == []
    as "all 12 Spell4CCConditions rows hold ccStateFlagsRequired 0, and the client's CCStates holds a row for each state 0 to 27"
}
