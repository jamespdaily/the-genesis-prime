//// The effect infos of a go (`genesis_prime/game/cast/frame`) for effects that last until
//// removed. Expected values come from these places:
//// - `opcode.0x7f4.first_start`: the client builds no buff for a target node whose earliest
////   effect start (the smallest delay of its effects) plus longest effect lifetime is 0 in
////   32 bits, and an effect with flags bit 2 has all bits as its lifetime, so a node whose
////   smallest delay is 1 and that holds one is told 2 where a delay of 1 would be. A node
////   with an effect at delay 0 sums to all bits and is told as it is.
//// - `opcode.0x7f4.target_info`: a go's effect info names the effect row, the result bit,
////   the instance number from 1 and the fourth value 0.
//// - Spell4Effects 74798 (Spell4 36201): type 17, targetFlags 2, delayTime 1, flags 2, and
////   135368 of the same spell: type 80, targetFlags 2, delayTime 0
////   (`table_rows -- Spell4Effects 74798`, `-- Spell4Effects 135368`).

import cast_support as support
import client_tables
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/spell_plan
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/int
import gleam/list
import owned_test
import spell_tables
import unitest

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// The delay of each effect info of the one go the effects write, by the unit each is
/// told on.
fn told_on_units(
  effects effects: List(cast_state.Effect),
) -> List(#(Int, List(#(Int, Int)))) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  list.map(decoded.targets, fn(target) {
    #(
      target.unit_id,
      list.map(target.effects, fn(info) {
        #(info.spell4_effects_id, info.delay_ms)
      }),
    )
  })
}

pub fn a_go_tells_2_for_a_smallest_delay_of_1_on_a_node_with_an_until_removed_effect_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell_36201 =
    spell_plan.Spell(
      ..spell_tables.client_spell(spell4_id: 36_201),
      spell4_base_id: Spell4BaseId(3),
    )
  list.each(
    [
      #(
        "Spell4Effects 74798 (delay 1, flags 2) alone on its node: the node's smallest delay is 1, a node told 1 builds no buff, so it is told 2",
        support.client_lasting(spell4_id: 36_201, base: 3, effect_ids: [74_798]),
        [#(74_798, 2)],
      ),
      #(
        "Spell4 36201's full go: the type 80 row 135368 at delay 0 makes the node's smallest delay 0, so the client builds the buff either way and 74798 is told its own 1",
        spell_36201,
        [#(74_798, 1), #(135_368, 0)],
      ),
    ],
    fn(row) {
      let #(reason, spell, expected) = row
      let #(_, effects) =
        support.press(
          plans: support.plans_of([spell]),
          state: cast_state.new(),
          bag: bag_of_base_3,
          at: 1000,
        )
      let assert [#(unit_id, told)] = told_on_units(effects:)
      assert unit_id == 7
        as "the caster is the primary target of a press with no target"
      assert told == expected as reason
    },
  )
}

pub fn a_node_whose_smallest_delay_is_1_is_told_2_only_when_it_holds_an_until_removed_row_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // A node is the rows of types 17 (Fluff) and 11 (property modifier) that one spell aims
  // at one kind of target, as one unit holds them: a go lists exactly those rows with
  // their delay and flags. The nodes are those with a row of delay 1.
  let nodes =
    spell4_effects.all(client_tables.shared())
    |> list.filter(fn(row) { list.contains([17, 11], row.effect_type) })
    |> list.group(fn(row) { #(row.spell_id, row.target_flags) })
    |> dict.values
    |> list.filter(fn(rows) { list.any(rows, fn(row) { row.delay_time == 1 }) })
  let starts_at_1 = fn(rows) { smallest_delay_ms(rows:) == 1 }
  let tells_2 = fn(rows) { starts_at_1(rows) && holds_until_removed(rows) }
  assert list.any(nodes, fn(rows) {
    tells_2(rows) && list.any(rows, fn(row) { row.id == 74_798 })
  })
    as "Spell4Effects 74798's node has a smallest delay of 1 and holds an until-removed row"
  assert list.any(nodes, fn(rows) {
    starts_at_1(rows) && !holds_until_removed(rows)
  })
    as "the client holds nodes whose smallest delay is 1 and that hold no until-removed row"
  assert list.any(nodes, fn(rows) {
    !starts_at_1(rows) && holds_until_removed(rows)
  })
    as "the client holds nodes with a row of delay 1 and an until-removed row whose smallest delay is not 1"
  list.each(nodes, fn(rows) {
    let go =
      cast_frame.go_message(
        cast_id: 1,
        phase: 0,
        place: support.caster().place,
        struck: [],
        listed: [
          #(
            7,
            list.map(rows, fn(row) {
              cast_state.listed_by_row(
                effect_id: Spell4EffectsId(row.id),
                row: spell_plan.lasting_row_of(effect: row),
              )
            }),
          ),
        ],
      )
    let assert [target] = go.targets
    assert list.map(target.effects, fn(info) { info.delay_ms })
      == list.map(rows, fn(row) {
        case tells_2(rows), row.delay_time {
          True, 1 -> 2
          _, delay_time -> delay_time
        }
      })
      as "a node whose smallest delay is 1 tells 2 for each delay of 1 when it holds a row with flags bit 2 (a node told 1 builds no buff), else tells every delay as it is (opcode.0x7f4.first_start)"
  })
}

fn smallest_delay_ms(rows rows: List(spell4_effects.Spell4Effects)) -> Int {
  list.fold(rows, 1_000_000, fn(smallest, row) {
    int.min(smallest, row.delay_time)
  })
}

fn holds_until_removed(rows: List(spell4_effects.Spell4Effects)) -> Bool {
  list.any(rows, fn(row) { int.bitwise_and(row.flags, 2) != 0 })
}
