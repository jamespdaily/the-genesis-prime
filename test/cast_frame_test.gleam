//// The effect infos of a go (`genesis_prime/game/cast/frame`) for effects that last until
//// removed. Expected values come from these places:
//// - `opcode.0x7f4.first_start`: the client builds no buff for a target node whose earliest
////   effect start plus longest effect lifetime is 0 in 32 bits, and an effect with flags
////   bit 2 has all bits as its lifetime, so a node holding one is told 2 where a delay of
////   1 would be.
//// - `opcode.0x7f4.target_info`: a go's effect info names the effect row, the result bit,
////   the instance number from 1 and the fourth value 0.
//// - Spell4Effects 74798 (Spell4 36201): type 17, targetFlags 2, delayTime 1, flags 2
////   (`table_rows -- Spell4Effects 74798`).

import cast_support as support
import client_tables
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/spell_plan
import genesis_prime/message/spell_effect_info.{type SpellEffectInfo}
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import owned_test
import unitest

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// The effect infos of the one go the effects write, by the unit each is told on.
fn told_on_units(
  effects effects: List(cast_state.Effect),
) -> List(#(Int, List(SpellEffectInfo))) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  list.map(decoded.targets, fn(target) { #(target.unit_id, target.effects) })
}

pub fn a_go_tells_an_until_removed_effect_with_its_own_delay_of_1_as_2_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    support.plans_of([
      support.client_lasting(spell4_id: 36_201, base: 3, effect_ids: [74_798]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let assert [#(unit_id, [info])] = told_on_units(effects:)
  assert unit_id == 7
    as "the caster is the primary target of a press with no target"
  assert info
    == support.listed_effect_info(
      effect_id: 74_798,
      instance_id: 1,
      delay_ms: 2,
      lifetime_ms: 0,
    )
    as "row 74798 has delay 1 and flags 2: the client builds no buff for a node told 1, so it is told 2 (opcode.0x7f4.first_start)"
}

pub fn every_until_removed_row_with_a_delay_of_1_is_told_2_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // The rows a go lists as a Fluff row (type 17) or a property modifier (type 11), each
  // alone on a unit: the node holds that one effect.
  let rows =
    spell4_effects.all(client_tables.shared())
    |> list.filter(fn(row) {
      row.delay_time == 1 && list.contains([17, 11], row.effect_type)
    })
  let until_removed =
    list.filter(rows, fn(row) { int.bitwise_and(row.flags, 2) != 0 })
  assert list.contains(list.map(until_removed, fn(row) { row.id }), 74_798)
    as "Spell4Effects 74798 is one of the rows of a delay of 1 and flags bit 2"
  assert list.length(until_removed) < list.length(rows)
    as "the client holds rows of a delay of 1 and no flags bit 2 as well"
  list.each(rows, fn(row) {
    let go =
      cast_frame.go_message(
        cast_id: 1,
        phase: 0,
        place: support.caster().place,
        struck: [],
        listed: [
          #(7, [
            cast_state.listed_by_row(
              effect_id: Spell4EffectsId(row.id),
              row: spell_plan.lasting_row_of(effect: row),
            ),
          ]),
        ],
      )
    let assert [target] = go.targets
    let assert [info] = target.effects
    assert info.spell4_effects_id == row.id
    assert info.delay_ms
      == case int.bitwise_and(row.flags, 2) != 0 {
        True -> 2
        False -> 1
      }
      as "Spell4Effects row with a delay of 1: told 2 with flags bit 2 (a node holding it builds no buff when told 1), else told 1 (opcode.0x7f4.first_start)"
  })
}
