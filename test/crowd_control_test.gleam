//// The instance id of a crowd-control effect (`genesis_prime/game/crowd_control`).
//// Expected values come from `cc_state.instance_id`: the client finds the effect a 0x87f
//// waits for by instance id alone among every effect held on the unit, from any caster,
//// and 0 matches the first effect found, so an id is non-zero and no two effects on a
//// unit share one; the id is 32 bits on the wire (`opcode.0x87f`); a unit id is below
//// 2^20, the bound the cast ids already hold (`cast.cast_id`).

import genesis_prime/game/cast
import genesis_prime/game/crowd_control
import owned_test
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
