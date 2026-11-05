//// The types the starting abilities use: the effect types and the prerequisite
//// types of the spells the 18 level-1 abilities' trees reach, which the coverage
//// measure shows beside each type's weight in the whole game.
////
//// ```
//// plans (genesis_prime/game/spell_plan) ─▶ every spell of every tree, once each,
////   a Proxy's child behind a gate and a stage included
////   ─▶ its Spell4Effects rows ─▶ their effect types
////   ─▶ the Prerequisite ids of the Spell4 row's columns, of each effect's
////      columns and of each Proxy's dataBits06 ─▶ each kept condition's type
//// ```
////
//// A prerequisite reached by several columns counts once; a type counts once for
//// each condition that holds it (`0x1404a5190`: the conditions before the first of
//// type 0).

import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict
import gleam/list
import gleam/result
import gleam/set

/// The effect type of each Spell4Effects row of the spells the starting abilities'
/// trees reach, one value for each row.
pub fn effect_types(tables: store.Tables) -> List(Int) {
  effects_of(tables:)
  |> list.map(fn(effect) { effect.effect_type })
}

/// The type of each condition of the prerequisites the starting abilities' trees
/// reach, one value for each condition.
pub fn prerequisite_types(tables: store.Tables) -> List(Int) {
  let from_spells =
    spells(tables:)
    |> list.flat_map(fn(spell) {
      case spell4.get(tables:, id: Spell4Id(spell.spell4_id.value)) {
        Ok(row) -> [
          row.prerequisite_id_runner00,
          row.prerequisite_id_runner01,
          row.prerequisite_id_caster_cast,
          row.prerequisite_id_target_cast,
          row.prerequisite_id_caster_persistence,
          row.prerequisite_id_target_persistence,
          row.prerequisite_id_aoe_target,
          row.prerequisite_id_aoe_preferred_target,
        ]
        Error(Nil) -> []
      }
    })
  let from_effects =
    list.flat_map(effects_of(tables:), fn(effect) {
      let gate = case effect_kind.kind_of(effect.effect_type) {
        effect_kind.Proxy -> [effect.data_bits06]
        effect_kind.Damage
        | effect_kind.VitalModifier
        | effect_kind.Unread(..) -> []
      }
      [
        effect.prerequisite_id_caster_apply,
        effect.prerequisite_id_target_apply,
        effect.prerequisite_id_caster_persistence,
        effect.prerequisite_id_target_persistence,
        effect.prerequisite_id_target_suspend,
        ..gate
      ]
    })
  list.append(from_spells, from_effects)
  |> list.filter(fn(prerequisite_id) { prerequisite_id != 0 })
  |> set.from_list
  |> set.to_list
  |> list.flat_map(fn(prerequisite_id) {
    prerequisite_table.get(tables:, id: PrerequisiteId(prerequisite_id))
    |> result.map(fn(row) { prerequisite.condition_types(row:) })
    |> result.unwrap([])
  })
}

/// The Spell4Effects rows of every spell reached, in no order.
fn effects_of(tables tables: store.Tables) -> List(Spell4Effects) {
  let by_spell = spell_plan.effects_by_spell(tables:)
  list.flat_map(spells(tables:), fn(spell) {
    dict.get(by_spell, spell.spell4_id.value) |> result.unwrap([])
  })
}

/// Every spell of every starting ability's tree, once each: the ability, the
/// spells of its stages and the child of each Proxy, whatever the Proxy's gate.
pub fn spells(tables tables: store.Tables) -> List(Spell) {
  dict.values(spell_plan.plans(tables:))
  |> list.flat_map(tree)
  |> list.fold(dict.new(), fn(found, spell) {
    dict.insert(found, spell.spell4_id.value, spell)
  })
  |> dict.values
}

fn tree(spell: Spell) -> List(Spell) {
  let below =
    list.append(
      list.map(spell.stages, fn(stage) { stage.spell }),
      list.map(spell.proxies, fn(proxy) { proxy.spell }),
    )
  [spell, ..list.flat_map(below, tree)]
}
