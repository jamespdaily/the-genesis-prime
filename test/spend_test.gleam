//// How a spell with an innate cost EMM id chooses its effects and which EMM ids the
//// server reads (`genesis_prime/game/spend`). Expected values come from the fact
//// file's records:
//// - `Spell4Effects.emmComparison`: with n the points spent above the base cost,
////   comparison 0 applies the effect when n equals emmValue and comparison 1 when n
////   is at least emmValue, so (1, 0) always applies; a spell with no EMM id has no n
////   and every effect applies.
//// - `Spell4.innateCostEMMId0`: the ids on the rows are 4 (45 rows), 7 (46), 10, 5, 9,
////   2 and 11; 4 and 7 both mark Psi Point spenders with the same effect layout
////   (emmValue 0 to 4), and the meaning of any other id is not in the client.

import genesis_prime/game/spend.{AllHeld, Unread}
import gleam/list
import gleam/option.{None, Some}
import owned_test

pub fn a_spell_with_no_n_applies_every_tag_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      spend.tag_of(comparison: 0, value: 4),
      spend.tag_of(comparison: 1, value: 2),
      spend.tag_of(comparison: 0, value: 0),
      spend.tag_of(comparison: 2, value: 9),
    ],
    fn(tag) {
      assert spend.applies(tag:, spent: None)
        as "Spell4Effects.emmComparison: a spell with no EMM id has no n and keeps every effect (Crush's stray (0, 4))"
    },
  )
}

pub fn comparison_0_applies_only_when_n_equals_the_value_test() -> Nil {
  use <- owned_test.run(5000)
  let tag = spend.tag_of(comparison: 0, value: 2)
  assert !spend.applies(tag:, spent: Some(1))
  assert spend.applies(tag:, spent: Some(2))
    as "Spell4Effects.emmComparison 0: n equals emmValue"
  assert !spend.applies(tag:, spent: Some(3))
}

pub fn comparison_1_applies_at_the_value_and_above_test() -> Nil {
  use <- owned_test.run(5000)
  let tag = spend.tag_of(comparison: 1, value: 2)
  assert !spend.applies(tag:, spent: Some(1))
    as "Spell4Effects.emmComparison 1: n is at least emmValue, so 1 is below 2"
  assert spend.applies(tag:, spent: Some(2))
  assert spend.applies(tag:, spent: Some(3))
  assert spend.applies(tag:, spent: Some(4))
}

pub fn comparison_1_with_value_0_applies_at_every_n_test() -> Nil {
  use <- owned_test.run(5000)
  let tag = spend.tag_of(comparison: 1, value: 0)
  list.each([0, 1, 2, 3, 4], fn(spent) {
    assert spend.applies(tag:, spent: Some(spent))
      as "Spell4Effects.emmComparison: (1, 0) is n >= 0, which every n holds (the Proxy 62590 of 32999 runs at every point count)"
  })
  assert tag == spend.always
}

pub fn only_ids_4_and_7_are_read_as_a_spend_of_every_point_held_test() -> Nil {
  use <- owned_test.run(5000)
  assert spend.spend_of(emm_id: 4) == Some(AllHeld)
  assert spend.spend_of(emm_id: 7) == Some(AllHeld)
    as "Spell4.innateCostEMMId0: 4 and 7 are the Psi Point spenders whose rows hold emmValue 0 to 4"
  list.each([2, 5, 9, 10, 11], fn(emm_id) {
    assert spend.spend_of(emm_id:) == Some(Unread(emm_id:))
      as "Spell4.innateCostEMMId0: the client does not say what any other id means"
    assert !spend.is_read(emm_id:)
  })
  assert spend.is_read(emm_id: 4) && spend.is_read(emm_id: 7)
  assert spend.spend_of(emm_id: 0) == None
    as "Spell4.innateCostEMMId0 0 is no EMM id: the cost is the base cost alone"
}
