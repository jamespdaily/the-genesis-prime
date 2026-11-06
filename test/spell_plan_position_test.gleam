//// The plan's Proxies behind a target apply prerequisite (`genesis_prime/game/spell_plan`
//// `GatedOnCasterAndTarget`), read from the client's tables where the client is present.
//// Expected values come from these places:
//// - The client's rows (`table_rows -- Spell4Effects 83818 83819 85673 85682`): Impale's
////   four Proxies, effect type 26, targetFlags 4 (the area): 83818 starts 39426 behind
////   caster apply 38587 and target apply 5735, 83819 starts 39427 behind 38585 and 5735,
////   85673 starts 39427 behind 38587 and 5734, and 85682 starts 39427 behind 38585 and 5734.
//// - `-- Prerequisite 38585 38587 5734 5735`: 38585 is (116, 1) or (15, 1 on 39407), 38587 is
////   (116, 2) and (50, 2 on 39407), 5734 is (108, 1, row 53) and 5735 the same with
////   comparison 2; `-- PositionalRequirement 53`: 180, 140, flags 0.
//// - `-- Spell4Effects spellId=39426` and `spellId=39427`: each child holds one damage effect,
////   86304 and 86308, aimed at the primary target (targetFlags 2) in phase 1, and no area row
////   of its own, so each strikes the unit it is made on.
//// - `Spell4Effects.effectType.1` and the design of issue 418: a gain of a child started at
////   each struck unit is given once for each go of its parent; the plan moves it onto the
////   Proxy, and a Proxy that may start no child on some unit has none to give.

import client_tables
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  type Proxy, type Spell, GatedOnCasterAndTarget,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table.{Integer}
import prerequisite_support
import spell_tables
import unitest

/// Impale's Spell4Base (the Spell4 38779's `spell4BaseIdBaseSpell`).
const impale_base = 23_161

fn impale() -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_plan.plans(client_tables.shared()),
      base: Spell4BaseId(impale_base),
    )
    as "the client's plans hold Impale"
  spell
}

/// Every Proxy in the tree of every level-1 ability and innate.
fn level_1_proxies() -> List(Proxy) {
  dict.values(spell_plan.plans(client_tables.shared()))
  |> list.flat_map(fn(ability) {
    list.flat_map(
      spell_plan.tree(spell: ability, started: fn(_) { True }),
      fn(spell) { spell.proxies },
    )
  })
}

pub fn impales_four_proxies_keep_their_caster_gate_and_their_target_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let behind = prerequisite_support.behind_arc()
  let target = fn(id, comparison) {
    prerequisite_support.prerequisite_of_arcs(
      row: prerequisite_support.row(id:, flags: 0, conditions: [
        #(108, comparison, 53, 0),
      ]),
      arcs: [behind],
    )
  }
  let stealthed =
    prerequisite_support.prerequisite_of(
      row: prerequisite_support.row(id: 38_585, flags: 1, conditions: [
        #(116, 1, 0, 28_455),
        #(15, 1, 0, 39_407),
      ]),
    )
  let not_stealthed =
    prerequisite_support.prerequisite_of(
      row: prerequisite_support.row(id: 38_587, flags: 0, conditions: [
        #(116, 2, 0, 28_455),
        #(50, 2, 0, 39_407),
      ]),
    )
  let expected = [
    #(83_818, 39_426, not_stealthed, target(5735, 2)),
    #(83_819, 39_427, stealthed, target(5735, 2)),
    #(85_673, 39_427, not_stealthed, target(5734, 1)),
    #(85_682, 39_427, stealthed, target(5734, 1)),
  ]
  list.each(expected, fn(row) {
    let #(effect_id, child, caster_gate, target_gate) = row
    let assert Ok(found) =
      list.find(impale().proxies, fn(proxy) {
        proxy.effect_id == Spell4EffectsId(effect_id)
      })
      as "Impale holds the Proxy"
    assert found.spell.spell4_id == Spell4Id(child)
    assert found.target == spell_plan.OnEachStruck
      as "targetFlags 4: a child on each struck unit"
    assert found.condition
      == GatedOnCasterAndTarget(caster: [caster_gate], target: target_gate)
      as "the caster apply prerequisite and the target apply prerequisite, each as the rows hold them"
  })
}

pub fn the_areas_hold_impales_two_children_each_striking_the_unit_it_is_made_on_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  list.each([#(39_426, 86_304), #(39_427, 86_308)], fn(child) {
    let assert Ok(area) =
      spell_area.of_spell(areas:, spell4_id: Spell4Id(child.0))
      as "the areas hold the child of a target-gated Proxy"
    assert area.row == None
      as "no area row: the child strikes the unit it is made on"
    let assert Ok(phase) = spell_area.phase(spell: area, phase: 0, spent: None)
      as "the child has a phase"
    assert phase.strikes_primary_target
    assert !phase.selects_area
    assert list.map(phase.damage, fn(damage) { damage.effect_id })
      == [Spell4EffectsId(child.1)]
      as "one damage effect"
  })
}

pub fn the_only_level_1_proxies_behind_a_target_gate_are_impales_four_and_hold_no_lifted_gains_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let gated =
    list.filter(level_1_proxies(), fn(proxy) {
      case proxy.condition {
        GatedOnCasterAndTarget(..) -> True
        spell_plan.Always
        | spell_plan.GatedOnCaster(..)
        | spell_plan.GatedOnTarget(..) -> False
      }
    })
  assert list.sort(
      list.unique(list.map(gated, fn(proxy) { proxy.effect_id.value })),
      int.compare,
    )
    == [83_818, 83_819, 85_673, 85_682]
    as "no other Proxy of a level-1 ability or innate tree has a target apply prerequisite"
  list.each(gated, fn(proxy) {
    assert proxy.gains == []
      as "a gain lifted onto such a Proxy would be given once for a go whose children may not all start"
  })
}

pub fn a_proxys_target_gate_naming_a_positional_requirement_the_table_lacks_fails_the_plan_test() -> Nil {
  use <- owned_test.run(60_000)
  // A Proxy of Telekinetic Strike to 30900 at the area, behind the planted Prerequisite
  // 99901 of one type 108 condition (comparison 1) naming PositionalRequirement 999, a row
  // the planted table lacks.
  let proxy =
    planted_table.row(spell4_effects.schema, [
      #("ID", Integer(99_900)),
      #("spellId", Integer(32_893)),
      #("targetFlags", Integer(4)),
      #("effectType", Integer(26)),
      #("phaseFlags", Integer(-1)),
      #("dataBits00", Integer(30_900)),
      #("prerequisiteIdTargetApply", Integer(99_901)),
      #("orderIndex", Integer(9)),
    ])
  let rows = spell_tables.rows_with_effect(effect: proxy)
  let rows =
    spell_tables.Rows(
      ..rows,
      prerequisites: spell_tables.sorted_by_id([
        spell_tables.prerequisite_row(id: 99_901, flags: 0, conditions: [
          #(108, 1, 999, 0),
        ]),
        ..rows.prerequisites
      ]),
    )
  assert spell_tables.planned_strike(rows:)
    == Error(spell_plan.NoRow(table: "PositionalRequirement", id: 999))
    as "the load refuses it, as it refuses any table row that is missing"
}
