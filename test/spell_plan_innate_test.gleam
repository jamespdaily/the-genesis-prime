//// The trees of the class innates in the plans (`genesis_prime/game/spell_plan`),
//// on the client's tables. Expected values come from these places.
//// - `Class.spell4IdInnateAbilityActive00` and `Passive00`: the six slot-0
////   actives (Spell4Base 30828, 31779, 38012, 46615, 30075, 31213) and the three
////   slot-0 passives (29035, 29076, 29131), each keyed by its Spell4Base.
//// - `Class.spell4IdInnateAbilityActive00.trees`: the spells each innate reaches,
////   its stages and every Proxy child, gated or not: Warrior 46867, 42908, 60915,
////   79875 and passive 44926 alone; Engineer 47866, 47860, 79697, 57443, 70599,
////   52371 and passive 45000, 46297; Esper 58586, 70369, 76766, 78078; Medic
////   69450, 60718, 60796; Stalker 46073, 38784, 83850, 38783 and passive 45057,
////   60724, 60868; Spellslinger 47273, 47439, 78307.

import client_tables
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{Spell4BaseId}
import gleam/int
import gleam/list
import owned_test
import unitest

/// The Spell4 ids of the tree a base's plan holds, once each, in id order.
fn tree_of(base base: Int) -> List(Int) {
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(spell) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
    as { "the plans hold the innate with Spell4Base " <> int.to_string(base) }
  spell_plan.tree(spell:, started: fn(_) { True })
  |> list.map(fn(member) { member.spell4_id.value })
  |> list.unique
  |> list.sort(int.compare)
}

pub fn the_plans_hold_the_six_active_innates_and_the_three_passives_by_their_spell4_base_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(client_tables.shared())
  list.each(
    [30_828, 31_779, 38_012, 46_615, 30_075, 31_213, 29_035, 29_076, 29_131],
    fn(base) {
      assert spell_plan.in_plans(plans:, base: Spell4BaseId(base)) != Error(Nil)
        as {
          "Class.spell4IdInnateAbilityActive00 and Passive00: Spell4Base "
          <> int.to_string(base)
          <> " is a slot-0 innate"
        }
    },
  )
}

pub fn each_innates_tree_holds_the_spells_the_trace_found_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert tree_of(base: 30_828) == [42_908, 46_867, 60_915, 79_875]
    as "Warrior's Stance: Onslaught"
  assert tree_of(base: 29_035) == [44_926] as "its passive: 44926 alone"
  assert tree_of(base: 31_779)
    == [47_860, 47_866, 52_371, 57_443, 70_599, 79_697]
    as "Engineer's Mode: Eradicate"
  assert tree_of(base: 29_076) == [45_000, 46_297] as "its passive"
  assert tree_of(base: 38_012) == [58_586, 70_369, 76_766, 78_078]
    as "Esper's Spectral Form"
  assert tree_of(base: 46_615) == [60_718, 60_796, 69_450] as "Medic's Energize"
  assert tree_of(base: 30_075) == [38_783, 38_784, 46_073, 83_850]
    as "Stalker's Nano Skin: Lethal"
  assert tree_of(base: 29_131) == [45_057, 60_724, 60_868] as "its passive"
  assert tree_of(base: 31_213) == [47_273, 47_439, 78_307]
    as "Spellslinger's Spell Surge"
}
