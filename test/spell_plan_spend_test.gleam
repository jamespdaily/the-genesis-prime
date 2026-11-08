//// The spend of a spell with an innate cost EMM id, as the plan holds it
//// (`genesis_prime/game/spell_plan`). Expected values come from the client's rows,
//// which the fact file records and `table_rows` prints, each named at its
//// assertion:
//// - `Spell4.32809`: Mind Burst's cost is type 6 of 1 with innateCostEMMId0 4, so it
////   spends every Psi Point held; its Proxy 135961 holds emmComparison 0 and emmValue
////   4 and its Proxy 230116 emmComparison 1 and emmValue 2.
//// - `Spell4.innateCostEMMId0`: ids other than 4 and 7 are not read, and three rows
////   hold an id with no cost.
//// - `Spell4Effects.emmComparison`: every row of a spell with an EMM id holds 0 or 1.
//// - `Spell4CastResult.vital_cost` and `0x1403b3320`: the result of each cost type.

import fixture_tables
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/game/spend.{AtLeast, EqualTo}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/loader/store
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables

fn mind_burst_of(plans plans: Plans) -> Spell {
  let assert Ok(spell) = spell_plan.in_plans(plans:, base: Spell4BaseId(19_019))
    as "the planted Esper holds Mind Burst"
  spell
}

/// The plans built from the client's rows with Mind Burst's Spell4 row changed in
/// these columns.
fn built_changing_spell(
  with changes: List(#(String, planted_table.Cell)),
) -> Result(Plans, spell_plan.PlanError) {
  fixture_tables.changed(
    table: "Spell4",
    id: 32_809,
    with: changes,
    body: fn(tables) { spell_plan.build(tables:) },
  )
}

pub fn mind_burst_spends_every_psi_point_over_a_base_of_1_and_tags_its_two_proxies_test() -> Nil {
  use <- owned_test.run(60_000)
  let mind_burst = mind_burst_of(plans: spell_tables.fixture_plans())
  assert mind_burst.costs
    == [spell_plan.SpendAllCost(slot: 1, amount: 1, result: 51)]
    as "Spell4.32809: type 6 (slot 1) of 1 with innateCostEMMId0 4, so the base is 1 and every point held is spent; 51 is the slot's result (0x1403b3320)"
  let tags =
    list.map(mind_burst.proxies, fn(proxy) { #(proxy.effect_id, proxy.tag) })
  assert tags
    == [
      #(Spell4EffectsId(135_961), EqualTo(value: 4)),
      #(Spell4EffectsId(230_116), AtLeast(value: 2)),
    ]
    as "Spell4Effects 135961 (emmComparison 0, emmValue 4: n equals 4) and 230116 (emmComparison 1, emmValue 2: n at least 2)"
}

pub fn an_emm_id_of_7_is_a_spend_of_every_point_held_too_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's rows with 7 are other spells (46 rows); Mind Burst's own is 4.
  let assert Ok(plans) =
    built_changing_spell(with: [#("innateCostEMMId0", Integer(7))])
  assert mind_burst_of(plans:).costs
    == [spell_plan.SpendAllCost(slot: 1, amount: 1, result: 51)]
    as "Spell4.innateCostEMMId0: 7 marks Psi Point spenders with the same layout as 4 (46 rows)"
}

pub fn an_unread_emm_id_gives_an_unread_spend_with_the_costs_result_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client row holds an id of 5 on a cost (the test's own subject).
  let assert Ok(plans) =
    built_changing_spell(with: [#("innateCostEMMId0", Integer(5))])
  assert mind_burst_of(plans:).costs
    == [spell_plan.UnreadSpendCost(result: 51, emm_id: 5)]
    as "Spell4.innateCostEMMId0: the meaning of 5 is not in the client; the cost is type 6, whose result is 51"
}

pub fn an_emm_id_on_a_cost_that_is_not_a_slot_is_an_unread_spend_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client row holds the id 4 on a cost of type 1 (health).
  let assert Ok(plans) =
    built_changing_spell(with: [
      #("innateCostType0", Integer(1)),
      #("innateCost0", Integer(20)),
    ])
  assert mind_burst_of(plans:).costs
    == [spell_plan.UnreadSpendCost(result: 44, emm_id: 4)]
    as "Spell4.innateCostEMMId0: the Psi Point layout belongs to a resource slot; a cost of type 1 (health) is refused 44 by the client's check (0x1403b3320)"
}

pub fn an_emm_id_with_no_cost_is_an_unread_spend_refused_285_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's rows with an id and no cost are 45155, 48782 and 42075; Mind Burst's
  // own cost is 6 of 1.
  let assert Ok(plans) =
    built_changing_spell(with: [
      #("innateCostType0", Integer(0)),
      #("innateCost0", Integer(0)),
    ])
  assert mind_burst_of(plans:).costs
    == [spell_plan.UnreadSpendCost(result: 285, emm_id: 4)]
    as "Spell4.innateCostEMMId0: three rows hold an id with no cost (45155, 48782, 42075); no cost has no result of its own, so the press gets the one of a spell the server does not build, 285 (Spell4CastResult 285, 'Illegal spell cast')"
}

pub fn a_comparison_other_than_0_or_1_on_a_spend_spell_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client row holds an emmComparison of 2 (the test's own subject): Mind Burst's
  // damage effect 61993 is changed from 0.
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4Effects",
      id: 61_993,
      with: [#("emmComparison", Integer(2))],
    )
  let assert Error(error) = fixture_tables.read(rows:)
    as "the server's load refuses the row"
  assert string.contains(
    store.describe(error),
    spell_plan.describe(spell_plan.SpendComparisonNotRead(
      spell4_id: 32_809,
      effect_id: 61_993,
      comparison: 2,
    )),
  )
    as "Spell4Effects.emmComparison: every row holds 0 or 1; a 2 would be a choice no rule makes, so the load names the spell, the effect and the value"
}

pub fn a_comparison_other_than_0_or_1_on_a_spell_with_no_emm_id_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mind Burst with no EMM id and the same effect 61993 of comparison 2: two edits no
  // client row holds.
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4",
      id: 32_809,
      with: [#("innateCostEMMId0", Integer(0))],
    )
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "Spell4Effects", id: 61_993, with: [
      #("emmComparison", Integer(2)),
    ])
  let assert Ok(plans) =
    fixture_tables.on_rows(rows:, reaching: [], body: fn(tables) {
      spell_plan.build(tables:)
    })
  assert mind_burst_of(plans:).costs
    == [spell_plan.SlotCost(slot: 1, amount: 1, result: 51)]
    as "Spell4Effects.emmComparison: a spell with no EMM id has no n, so its tags choose nothing and none is refused"
  assert list.map(mind_burst_of(plans:).proxies, fn(proxy) { proxy.tag })
    == [EqualTo(value: 4), AtLeast(value: 2)]
}
