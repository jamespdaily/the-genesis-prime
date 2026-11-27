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
import genesis_prime/message/combat_result
import genesis_prime/message/spell_go.{SpellGo}
import genesis_prime/message/spell_position.{SpellPosition}
import genesis_prime/message/spell_target_info.{
  type SpellTargetInfo, SpellTargetInfo,
}
import genesis_prime/shared/spell_plan
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
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
    #(target.unit_id, effect_infos_of(target))
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
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let spell_ids =
    spell4_effects.all(tables)
    |> list.filter(fn(row) { row.delay_time == 1 })
    |> list.map(fn(row) { row.spell_id })
    |> list.unique
  // Each node is one target's effect infos of a go the cast rule makes of the client's
  // spell, with the table's row of each effect. A spell the server refuses to plan alone
  // (a plan error) makes no go.
  let nodes =
    list.flat_map(spell_ids, fn(spell_id) {
      let planned =
        spell_plan.spell_alone(
          tables:,
          sources:,
          spell4_id: spell_id,
          chain: [],
        )
      let told =
        result.map(planned, nodes_told(spell: _, spell_id:))
        |> result.unwrap(or: [])
      list.map(told, fn(node) {
        list.map(node, fn(info) {
          let assert Ok(row) =
            spell4_effects.get(tables:, id: Spell4EffectsId(info.0))
            as "a told effect is a row of the client's table"
          Told(effect_id: info.0, told_ms: info.1, row:)
        })
      })
    })
  let delay_1_nodes =
    list.filter(nodes, fn(node) {
      list.any(node, fn(told) { own_delay_ms(told:) == 1 })
    })
  let tells_2 = fn(node) {
    smallest_delay_ms(node:) == 1 && holds_until_removed(node:)
  }
  assert list.any(delay_1_nodes, tells_2)
    as "the client's spells make nodes whose smallest delay is 1 and that hold an until-removed row"
  assert list.any(delay_1_nodes, fn(node) {
    smallest_delay_ms(node:) == 1 && !holds_until_removed(node:)
  })
    as "the client's spells make nodes whose smallest delay is 1 and that hold no until-removed row"
  assert list.any(delay_1_nodes, fn(node) {
    smallest_delay_ms(node:) != 1 && holds_until_removed(node:)
  })
    as "the client's spells make nodes with a row of delay 1 and an until-removed row whose smallest delay is not 1"
  assert list.any(delay_1_nodes, fn(node) {
    list.any(node, fn(told) { told.effect_id == 74_798 })
    && list.map(node, fn(told) { told.told_ms }) == [1, 0]
  })
    as "Spell4Effects 74798's real node holds the type 80 row 135368 at delay 0, so it is told 1 as in the test of Spell4 36201's go"
  list.each(delay_1_nodes, fn(node) {
    assert list.map(node, fn(told) { told.told_ms })
      == list.map(node, fn(told) {
        case tells_2(node), own_delay_ms(told:) {
          True, 1 -> 2
          _, delay_time -> delay_time
        }
      })
      as {
        "a node whose smallest delay is 1 tells 2 for each delay of 1 when it holds a row with flags bit 2 (a node told 1 builds no buff), else tells every delay as the table has it (opcode.0x7f4.first_start); the node of Spell4Effects "
        <> string.join(
          list.map(node, fn(told) { int.to_string(told.effect_id) }),
          ", ",
        )
      }
  })
}

/// One effect info of a node with the row of the client's table it names.
type Told {
  Told(effect_id: Int, told_ms: Int, row: spell4_effects.Spell4Effects)
}

/// The effect infos (Spell4Effects id and told delay) of each target of each go that a
/// press makes of the client's Spell4 `spell_id`, planted as a spell without a cast time,
/// a cost or a requirement that keeps the client's effect rows (`real`, the plan of the
/// spell alone).
fn nodes_told(
  spell real: spell_plan.Spell,
  spell_id spell_id: Int,
) -> List(List(#(Int, Int))) {
  let planted =
    spell_plan.Spell(
      ..support.child(spell4_id: spell_id, base: 3),
      effects: real.effects,
      longer_of_delay_and_duration: real.longer_of_delay_and_duration,
    )
  let #(_, effects) =
    support.press(
      plans: support.plans_of([planted]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  support.frames_of(message_id: spell_go.message_id, effects:)
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body)
      as "a go the server wrote decodes"
    list.map(go.targets, effect_infos_of)
  })
}

fn effect_infos_of(target: SpellTargetInfo) -> List(#(Int, Int)) {
  list.map(target.effects, fn(info) { #(info.spell4_effects_id, info.delay_ms) })
}

/// The delay the go tells an effect before the rule of a node's smallest delay: the row's
/// delayTime, but 0 for a SpellForceRemove row (type 80), whose removal the server tells at
/// the go (`cast.reached_listed`).
fn own_delay_ms(told told: Told) -> Int {
  case told.row.effect_type {
    80 -> 0
    _ -> told.row.delay_time
  }
}

fn smallest_delay_ms(node node: List(Told)) -> Int {
  list.fold(node, 1_000_000, fn(smallest, told) {
    int.min(smallest, own_delay_ms(told:))
  })
}

fn holds_until_removed(node node: List(Told)) -> Bool {
  list.any(node, fn(told) { int.bitwise_and(told.row.flags, 2) != 0 })
}

/// The most units one go names: an area row's 200 (`no_area_row_selects_more_than_200_units_test`),
/// the primary target the area did not select and the caster.
const most_struck_units = 202

pub fn a_go_of_202_struck_units_encodes_with_a_count_of_202_test() -> Nil {
  use <- owned_test.run(5000)
  let targets =
    list.index_map(list.repeat(Nil, most_struck_units), fn(_, index) {
      let unit_id = index + 1
      SpellTargetInfo(
        unit_id:,
        index: 0,
        flags: 0,
        instance_count: 1,
        combat_result: combat_result.Hit,
        effects: [],
      )
    })
  let frame =
    cast_frame.went_frame(go: SpellGo(
      cast_id: 9,
      ignore_cooldown: 0,
      destination: SpellPosition(x: 0, y: 0, z: 0),
      targets:,
      initial_positions: [],
      telegraph_positions: [],
      missiles: [],
      phase: 0,
    ))
  let assert Ok(decoded) = spell_go.decode(frame.body)
    as "the frame is a 0x7f4 the client's reader takes"
  assert list.length(decoded.targets) == 202
    as "schema spell_go.targets: an 8-bit count holds 202 units, 200 of the area, the primary target and the caster"
}

pub fn no_area_row_selects_more_than_200_units_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let rows = spell4_aoe_target_constraints.all(client_tables.shared())
  assert rows != [] as "the client's table has rows"
  let most =
    list.fold(rows, 0, fn(most, row) { int.max(most, row.target_count) })
  assert most <= 200
    as "Spell4AoeTargetConstraints.targetCount: no row selects more than 200 units, which with the primary target and the caster is the 202 a go names"
}

pub fn no_spell_has_more_than_85_effect_rows_or_81_telegraph_rows_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let most_rows_of = fn(spell4_ids: List(Int)) {
    list.group(spell4_ids, by: fn(spell4_id) { spell4_id })
    |> dict.values
    |> list.map(list.length)
    |> list.fold(0, int.max)
  }
  let effects =
    most_rows_of(list.map(spell4_effects.all(tables), fn(row) { row.spell_id }))
  let telegraphs =
    most_rows_of(
      list.filter_map(spell4_telegraph.all(tables), fn(row) {
        case row.spell4_id {
          // Spell4 has no row 0, so no cast draws the rows with spell4Id 0.
          0 -> Error(Nil)
          spell4_id -> Ok(spell4_id)
        }
      }),
    )
  assert effects <= 85 as "Spell4Effects: no Spell4 has more than 85 rows"
  assert telegraphs <= 81
    as "Spell4Telegraph: no Spell4 has more than 81 rows, the rows of spell4Id 0 left out (Spell4 holds no row 0, so no cast draws them)"
  assert 2 * telegraphs <= 255
    as "the started frame's telegraph positions, one for each drawn row on the caster and one on the target (`telegraph_entries.opening_of`), stay within an 8-bit count"
}
