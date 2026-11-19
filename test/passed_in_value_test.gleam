//// The passed-in value of an effect (`genesis_prime/game/passed_in_value`). Expected values
//// come from these places.
//// - The client's family-33 budget curve (`0x14041f1b0`, GameFormula 991, 65 and 253),
////   emulated: level 1 gives 5.3 (0x40a9999a), 20 gives 11.0, 50 gives 20.0 and 130 gives
////   47.2 (0x423ccccd) (fact `0x14041f1b0`).
//// - The value of the spell of an item is the curve at its level, which is Item2.powerLevel
////   (`0x14040d060`, fact `opcode.0x7ff.caster_item_level`): Basic Medishot 14838 has power
////   level 5, and its 60 sibling 49372 has 60.

import client_tables
import fixture_tables
import genesis_prime/game/item_property
import genesis_prime/game/passed_in_value
import genesis_prime/message/float32
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/item_special
import genesis_prime/table/spell4_effects
import gleam/float
import gleam/int
import gleam/list
import gleam/set
import owned_test
import unitest

pub fn the_curve_holds_the_clients_values_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(
    [
      #(1, float32.rounded(5.3)),
      #(20, 11.0),
      #(50, 20.0),
      #(130, float32.rounded(47.2)),
    ],
    fn(row) {
      assert passed_in_value.of_level(tables:, level: row.0) == row.1
        as "the emulated value of 0x14041f1b0 at the level"
    },
  )
  int.range(
    from: 0,
    to: passed_in_value.highest_level + 1,
    with: Nil,
    run: fn(_, level) {
      let assert Ok(curve) = item_property.rune_budget_curve(tables:, level:)
      assert passed_in_value.of_level(tables:, level:) == curve
        as "the derived curve is the client's curve at every level"
    },
  )
}

pub fn an_items_value_is_the_curve_at_its_power_level_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(
    [
      #(14_838, 5, float32.rounded(6.5)),
      // GameFormula 65 at 60 less its dataint0 (50): between 20.0 at 50 and 47.2 at 130.
      #(49_372, 60, passed_in_value.of_level(tables:, level: 60)),
    ],
    fn(row) {
      let assert Ok(item) = item2.get(tables:, id: Item2Id(row.0))
      assert item.power_level == row.1
        as "the item's power level, which is its level"
      assert float.loosely_equals(
        passed_in_value.of_item(tables:, item2_id: Item2Id(row.0)),
        with: row.2,
        tolerating: 0.0001,
      )
    },
  )
  assert passed_in_value.of_level(tables:, level: 60) >. 20.0
    as "the curve rises past its value at 50"
  assert passed_in_value.of_level(tables:, level: 60) <. 47.2
    as "and is below its value at 130"
}

pub fn no_item_whose_spell_holds_a_type_18_row_has_the_level_1_flag_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let passed_in_spells =
    spell4_effects.all(tables)
    |> list.filter(fn(effect) {
      list.any(
        [
          #(effect.parameter_type00, effect.parameter_value00),
          #(effect.parameter_type01, effect.parameter_value01),
          #(effect.parameter_type02, effect.parameter_value02),
          #(effect.parameter_type03, effect.parameter_value03),
        ],
        fn(parameter) { parameter.0 == 18 && parameter.1 != 0.0 },
      )
    })
    |> list.map(fn(effect) { effect.spell_id })
    |> set.from_list
  let with_type_18 =
    list.filter(item2.all(tables), fn(item) {
      let special = item2.item_special_id00(item)
      case item_special.get(tables:, id: special) {
        Ok(row) -> set.contains(passed_in_spells, row.spell4_id_on_activate)
        Error(Nil) -> False
      }
    })
  assert with_type_18 != []
    as "the client has items whose spell holds a type 18 row"
  list.each(with_type_18, fn(item) {
    assert int.bitwise_and(item.flags, 8) == 0
      as "Item2.flags bit 3 builds the item at level 1 (0x14040d060), which of_item does not model"
  })
  list.each(item2.all(tables), fn(item) {
    assert item.power_level <= passed_in_value.highest_level
      as "no item's power level is above the curve's end"
  })
}
