//// A press of a Focus-cost spell checked against and paid from the caster's Focus
//// (`genesis_prime/game/cast` with `genesis_prime/game/class_resource`). Expected
//// values come from these places, each named at its assertion:
//// - The client's check: `CheckInnateCost` 0x1403b3320 case 0xe refuses 167
////   (`Spell4CastResult` 167, `CasterVitalCostFocus`, text 151788 "Insufficient Focus")
////   when the whole points of Focus held are fewer than `(int)(m x cost + 0.5)`, with
////   `m` the cost modifier (property 135 and the intensity fraction, `FUN_140462a90`);
////   `CheckInnateCosts` 0x1403b1de0 checks the first cost, then the second, and gives the
////   first refusal.
//// - The client's rows (`table_rows -- Spell4 32820 32821 58841 33257 30354`): Mind
////   Over Body 32820 costs 22 of type 15, Bolster 32821 costs 70, Emission 58841 costs
////   15, Mental Boon 33257 costs 1 of type 6 (EMM id 7, every point held) and 73 of type
////   15, Shield Surge 30354 costs 2 of type 18 and 86 of type 15.
//// - `Spell4.innateCost0.timing`: the client pays nothing, so when to pay is the
////   server's: reserved at the accept, paid at the first go, and at the accept for a
////   spell that goes at once (`cast_cost_timing_test`).

import cast_support as support
import channel_support.{type Scene}
import class_resource_support
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/class_resource.{type Payment, Payment}
import genesis_prime/game/spell_plan.{type Spell}
import gleam/dict
import gleam/list
import gleam/string
import owned_test
import spell_tables

const esper = 3

const medic = 4

const warrior = 1

const spellslinger = 7

/// Mind Over Body, an Esper's: 22 Focus.
fn mind_over_body() -> Spell {
  spell_tables.client_spell(32_820)
}

/// Bolster, an Esper's, instant: 70 Focus.
fn bolster() -> Spell {
  spell_tables.client_spell(32_821)
}

/// Emission, a Medic's channel: 15 Focus for each of 3 gos.
fn emission() -> Spell {
  spell_tables.client_spell(58_841)
}

/// Healing Salve, a Spellslinger's.
fn healing_salve() -> Spell {
  spell_tables.client_spell(39_121)
}

/// Mental Boon, an Esper's: 1 Psi Point (every point held) and 73 Focus.
fn mental_boon() -> Spell {
  spell_tables.client_spell(33_257)
}

/// Shield Surge, a Medic's: 2 Actuators and 86 Focus.
fn shield_surge() -> Spell {
  spell_tables.client_spell(30_354)
}

/// The spell pressed by a caster of the class who holds `focus` points of Focus, whose
/// cost modifier (property 135) is `modifier`.
fn modified_scene(
  spell spell: Spell,
  class_id class_id: Int,
  focus focus: Float,
  modifier modifier: Float,
) -> Scene {
  channel_support.resources_scene(
    spell:,
    resources: class_resource_support.resources_with(
      class_id:,
      changes: [#(5, focus), #(135, modifier)],
      level: 1,
    ),
  )
}

fn scene(
  spell spell: Spell,
  class_id class_id: Int,
  focus focus: Float,
) -> Scene {
  channel_support.focus_scene(spell:, class_id:, focus:)
}

/// What a press ends as: refused with a result, or accepted with what it pays at its
/// first go or accept.
type Outcome {
  Refused(result: Int)
  Pays(payments: List(Payment))
}

/// The press and every timer it leads to, as an outcome: a refusal pays nothing and
/// reserves nothing, an accepted press pays what its first go (or accept) pays.
fn outcome_of(scene scene: Scene) -> Outcome {
  let #(state, pressed, _) = channel_support.pressed(scene:)
  case support.refusal_results(effects: pressed) {
    [result] -> {
      assert support.payments(effects: pressed) == []
        as "a refused press pays nothing"
      assert dict.size(state.casts) == 0
        as "a refused press reserves nothing: no cast is live"
      Refused(result:)
    }
    [] -> {
      let run = channel_support.run_channel(scene:)
      let first_paid =
        list.find(run.steps, fn(step) {
          support.payments(effects: step.effects) != []
        })
      case first_paid {
        Ok(step) -> Pays(payments: support.payments(effects: step.effects))
        Error(Nil) -> Pays(payments: [])
      }
    }
    [_, ..] -> panic as "a press is refused once"
  }
}

pub fn a_focus_cost_is_checked_against_the_whole_points_held_and_refused_167_below_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let focus_points = fn(points) { Pays([Payment(slot: -1, amount: points)]) }
  [
    #(
      "34.1",
      scene(spell: mind_over_body(), class_id: esper, focus: 21.9),
      Refused(167),
      "Mind Over Body costs 22: 21.9 holds 21 whole points (0x1403b3320 case 0xe)",
    ),
    #(
      "34.2",
      scene(spell: mind_over_body(), class_id: esper, focus: 22.0),
      focus_points(22),
      "22.0 holds 22: accepted, and the cast pays the 22",
    ),
    #(
      "34.3",
      scene(spell: bolster(), class_id: esper, focus: 69.9),
      Refused(167),
      "Bolster costs 70: 69.9 holds 69",
    ),
    #(
      "34.4",
      scene(spell: bolster(), class_id: esper, focus: 70.0),
      focus_points(70),
      "70.0 holds 70",
    ),
    #(
      "34.5",
      scene(spell: emission(), class_id: medic, focus: 14.9),
      Refused(167),
      "Emission costs 15: 14.9 holds 14",
    ),
    #(
      "34.6",
      scene(spell: emission(), class_id: medic, focus: 15.0),
      focus_points(15),
      "15.0 holds 15",
    ),
    #(
      "34.7",
      scene(spell: emission(), class_id: warrior, focus: 1000.0),
      Refused(167),
      "a Warrior holds no Focus (the unit's +0x218 is 0, ConstructUnit 0x140454380): refused 167 whatever the table says",
    ),
    #(
      "34.8",
      modified_scene(
        spell: mind_over_body(),
        class_id: esper,
        focus: 16.9,
        modifier: 0.75,
      ),
      Refused(167),
      "a cost modifier of 0.75 on 22 needs int(0.75 x 22 + 0.5) = 17 (FUN_140462a90): 16.9 holds 16",
    ),
    #(
      "34.9",
      modified_scene(
        spell: mind_over_body(),
        class_id: esper,
        focus: 17.0,
        modifier: 0.75,
      ),
      focus_points(17),
      "17.0 meets the 17 the modifier asks, and the cast pays 17, not 22",
    ),
  ]
  |> list.each(fn(row) {
    let #(name, scene, outcome, reason) = row
    assert outcome_of(scene:) == outcome as { name <> ": " <> reason }
  })
}

/// What a press does with a Focus cost: what its accept pays, what the live cast holds
/// reserved, and the time after the press and the payments of the first payment.
type Timing {
  Timing(
    at_press: List(Payment),
    reserved: List(Payment),
    first_paid: #(Int, List(Payment)),
  )
}

fn timing_of(scene scene: Scene) -> Timing {
  let #(state, pressed, _) = channel_support.pressed(scene:)
  let run = channel_support.run_channel(scene:)
  let assert Ok(#(after_ms, first)) = list.first(channel_support.payments(run:))
    as "the press is accepted and its cost is paid"
  Timing(
    at_press: support.payments(effects: pressed),
    reserved: list.flat_map(dict.values(state.casts), fn(live) { live.reserved }),
    first_paid: #(after_ms, [first]),
  )
}

pub fn a_focus_cost_is_reserved_at_the_accept_and_paid_at_the_first_go_and_an_instant_spell_pays_at_its_accept_test() -> Nil {
  use <- owned_test.run(30_000)
  let paid = fn(points) { [Payment(slot: -1, amount: points)] }
  // Name, the spell, its class, and what its press does.
  [
    #(
      "35.1",
      mind_over_body(),
      esper,
      Timing(at_press: [], reserved: paid(22), first_paid: #(1250, paid(22))),
      "Mind Over Body has a cast time of 1250 ms: the accept reserves the 22 and the go pays them (Spell4.innateCost0.timing)",
    ),
    #(
      "35.2",
      bolster(),
      esper,
      Timing(at_press: paid(70), reserved: [], first_paid: #(0, paid(70))),
      "Bolster goes at once: its accept pays the 70 (pays_at_accept) and nothing is left reserved",
    ),
    #(
      "35.3",
      healing_salve(),
      spellslinger,
      Timing(at_press: [], reserved: paid(68), first_paid: #(1000, paid(68))),
      "Healing Salve costs 68 and has a cast time of 1000 ms: reserved at the accept, paid at the go",
    ),
  ]
  |> list.each(fn(row) {
    let #(name, spell, class_id, expected, reason) = row
    assert timing_of(scene: scene(spell:, class_id:, focus: 1000.0)) == expected
      as { name <> ": " <> reason }
  })
}

/// The same caster's second press of a spell that leaves the caster free, which the
/// first press's reservation is checked against.
fn free(spell spell: Spell) -> Spell {
  support.free_while_live(spell:)
}

fn second_press_results(focus focus: Float) -> #(List(Int), List(Int)) {
  let spell = free(spell: mind_over_body())
  let scene = scene(spell:, class_id: esper, focus:)
  let #(state, first, _) = channel_support.pressed(scene:)
  let #(_, second) =
    support.pressed_raw_in(
      plans: scene.plans,
      state:,
      caster: scene.caster,
      bag_index: scene.bag_index,
      target: support.target_the_client_sends(
        caster: scene.caster,
        plans: scene.plans,
        bag_index: scene.bag_index,
      ),
      at: channel_support.pressed_at_ms + 100,
    )
  #(
    support.refusal_results(effects: first),
    support.refusal_results(effects: second),
  )
}

pub fn a_second_press_cannot_spend_the_focus_a_live_cast_has_reserved_and_two_the_pool_meets_are_both_accepted_test() -> Nil {
  use <- owned_test.run(30_000)
  assert second_press_results(focus: 30.0) == #([], [167])
    as "30 held, 22 reserved by the first cast: the second needs 22 of the 8 left, refused 167 as an unreserved press is"
  assert second_press_results(focus: 60.0) == #([], [])
    as "60 held meets 22 and 22: the reservation holds back only what the first cast needs"
}

/// A caster of the class holding `slot_points` in its class slot and `focus` points of
/// Focus.
fn holding_both(
  class_id class_id: Int,
  slot_points slot_points: Float,
  focus focus: Float,
) -> class_resource.Resources {
  support.holding_changing(class_id:, value: slot_points, changes: [
    #(5, focus),
  ])
}

fn both_scene(
  spell spell: Spell,
  class_id class_id: Int,
  slot_points slot_points: Float,
  focus focus: Float,
) -> Scene {
  channel_support.resources_scene(
    spell:,
    resources: holding_both(class_id:, slot_points:, focus:),
  )
}

pub fn a_spell_with_a_class_cost_and_a_focus_cost_pays_both_and_is_refused_with_the_first_cost_that_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  [
    #(
      "37.1",
      both_scene(
        spell: mental_boon(),
        class_id: esper,
        slot_points: 0.0,
        focus: 100.0,
      ),
      Refused(51),
      "no Psi Point: the first cost (6, 1) fails and gives its 51 before Focus is looked at (CheckInnateCosts 0x1403b1de0)",
    ),
    #(
      "37.2",
      both_scene(
        spell: mental_boon(),
        class_id: esper,
        slot_points: 1.0,
        focus: 72.9,
      ),
      Refused(167),
      "1 Psi Point meets the first cost; 72.9 holds 72 of the 73 Focus: the second fails, 167",
    ),
    #(
      "37.3",
      both_scene(
        spell: mental_boon(),
        class_id: esper,
        slot_points: 1.0,
        focus: 100.0,
      ),
      Pays([
        Payment(slot: 1, amount: 1),
        Payment(slot: -1, amount: 73),
      ]),
      "both met: the Psi Point (every point held, EMM id 7) and the 73 Focus, in the order of the cost columns",
    ),
    #(
      "37.4",
      both_scene(
        spell: shield_surge(),
        class_id: medic,
        slot_points: 1.0,
        focus: 100.0,
      ),
      Refused(55),
      "1 Actuator of the 2: the class cost (18, 2) fails first, 55 (CasterVitalCostResource5, the Medic's last slot)",
    ),
    #(
      "37.5",
      both_scene(
        spell: shield_surge(),
        class_id: medic,
        slot_points: 2.0,
        focus: 85.0,
      ),
      Refused(167),
      "2 Actuators meet the first cost; 85 of the 86 Focus fails the second",
    ),
    #(
      "37.6",
      both_scene(
        spell: shield_surge(),
        class_id: medic,
        slot_points: 2.0,
        focus: 86.0,
      ),
      Pays([
        Payment(slot: 1, amount: 2),
        Payment(slot: -1, amount: 86),
      ]),
      "both met: the 2 Actuators and the 86 Focus",
    ),
  ]
  |> list.each(fn(row) {
    let #(name, scene, outcome, reason) = row
    assert outcome_of(scene:) == outcome as { name <> ": " <> reason }
  })
}

pub fn the_unread_focus_uses_are_listed_as_gaps_test() -> Nil {
  use <- owned_test.run(5000)
  let listed =
    list.map(cast_cost.gaps(), fn(entry) { string.lowercase(entry.missing) })
  // What each gap names, and why the server leaves it.
  [
    #("threshold row", "a Focus cost on a stage's threshold row"),
    #("152", "Proc kind 152"),
    #("103", "Proc kind 103"),
    #("focusfinalmultiplier", "FocusFinalMultiplier"),
    #("group member", "a group member's Focus"),
    #("share above 1.0", "a Focus share above 1.0"),
    #("not saved", "Focus is not saved"),
    #("requirement of type 18", "a caster requirement of type 18"),
  ]
  |> list.each(fn(row) {
    let #(needle, name) = row
    assert list.any(listed, string.contains(_, needle))
      as { name <> " is stated as a gap where the cost rule enforces it" }
  })
}

/// Ignite S1 Test, a Spellslinger's: a caster requirement of Focus at least 5 (eval 2).
fn ignite() -> Spell {
  spell_tables.client_spell(45_420)
}

/// The Stimpack, a deprecated potion: a caster requirement of Focus below 100 percent
/// of its maximum (eval 8, value 100).
fn stimpack() -> Spell {
  spell_tables.client_spell(26_636)
}

/// A Medic whose Focus maximum an item raised to 1250 (property 5), holding `held` of it.
fn raised_pool_scene(spell spell: Spell, held held: Int) -> Scene {
  let resources =
    class_resource_support.resources_with(
      class_id: medic,
      changes: [#(5, 1250.0)],
      level: 1,
    )
  channel_support.resources_scene(
    spell:,
    resources: class_resource.paid(resources:, payments: [
      Payment(slot: -1, amount: 1250 - held),
    ]),
  )
}

pub fn a_caster_requirement_of_focus_refuses_167_below_it_and_passes_at_it_a_percent_eval_reads_property_5_and_a_class_with_none_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  // Spell4.casterInnateRequirement.15: the failed test gives 167 (Spell4CastResult.167);
  // evals 0 to 4 compare the Focus held, 5 to 9 compare Focus x 100 / property 5's value,
  // and a maximum of 0 is no number, which fails every comparison.
  [
    #(
      "7.1",
      scene(spell: ignite(), class_id: spellslinger, focus: 4.9),
      Refused(167),
      "45420 needs at least 5 of the Focus held (eval 2): 4.9 fails",
    ),
    #(
      "7.2",
      scene(spell: ignite(), class_id: spellslinger, focus: 5.0),
      Pays([]),
      "5.0 meets it, and the requirement pays nothing",
    ),
    #(
      "7.3",
      raised_pool_scene(spell: stimpack(), held: 1250),
      Refused(167),
      "26636 needs less than 100 percent (eval 8) of the 1250 maximum: a full pool is 100 percent",
    ),
    #(
      "7.4",
      raised_pool_scene(spell: stimpack(), held: 1238),
      Pays([]),
      "1238 of 1250 is 99.04 percent of property 5's value: it passes, though it is above 1000 (the base pool, which is not the maximum)",
    ),
    #(
      "7.5",
      raised_pool_scene(spell: stimpack(), held: 1000),
      Pays([]),
      "1000 of 1250 is 80 percent",
    ),
    #(
      "7.6",
      scene(spell: ignite(), class_id: warrior, focus: 1000.0),
      Refused(167),
      "a Warrior holds no Focus (0 held): the amount 0 is below 5",
    ),
    #(
      "7.7",
      scene(spell: stimpack(), class_id: warrior, focus: 1000.0),
      Refused(167),
      "a Warrior's 0 of a maximum of 0 is no number: the percentage fails the comparison",
    ),
  ]
  |> list.each(fn(row) {
    let #(name, scene, outcome, reason) = row
    assert outcome_of(scene:) == outcome as { name <> ": " <> reason }
  })
}
