//// The dash's rows (`genesis_prime/game/dash`): the Spell4 each direction of 0x015C
//// names and what each costs. Expected values come from the client's rows
//// (`gleam run -m genesis_prime/table_rows -- GameFormula 477 478 479 480` and
//// `-- Spell4 28770 28771 28772 28773`) and from the client's own code, which maps the
//// direction to the GameFormula row (`0x14039f590`: 1 Forward, 2 Backward, 3 Left, 4 Right).

import fixture_tables
import genesis_prime/game/dash
import genesis_prime/shared/class_resource
import genesis_prime/shared/spell_plan
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import gleam/list
import owned_test

pub fn each_dash_direction_names_one_dash_spell_and_each_costs_100_of_type_16_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let dashes = dash.dashes(tables:)
  // Direction, its GameFormula row (dataint0 is the Spell4 id), the Spell4 and its
  // description: innateCostType0 16 and innateCost0 100 on each.
  [
    #(1, 479, 28_772, "Dash Forward (Knockdown) - Tier 1"),
    #(2, 480, 28_773, "Dash Backward (Knockdown) - Tier 1"),
    #(3, 477, 28_770, "Dash Left (Knockdown) - Tier 1"),
    #(4, 478, 28_771, "Dash Right (Knockdown) - Tier 1"),
  ]
  |> list.each(fn(row) {
    let #(direction, formula, spell4_id, _description) = row
    let assert Ok(formula_row) =
      game_formula.get(tables:, id: GameFormulaId(formula))
      as "the dash's GameFormula row is in the fixture"
    assert formula_row.dataint0 == spell4_id
      as "the rows as the client's table holds them (table_rows -- GameFormula 477 478 479 480)"
    assert dash.spell4_id_of(dashes:, direction:) == Ok(spell4_id)
      as "the direction's GameFormula row names its Spell4 in dataint0"
    assert dash.costs_of(dashes:, direction:)
      == Ok([
        spell_plan.SlotCost(
          slot: class_resource.dash_slot,
          amount: 100,
          result: 177,
        ),
      ])
      as "innateCostType0 16 reads resource slot 7 (stat 9) and refuses with 177; innateCost0 is 100"
  })
  list.each([0, 5, 7], fn(direction) {
    assert dash.spell4_id_of(dashes:, direction:) == Error(Nil)
      as "the client sends no other direction (0x14039f590 maps only 1 to 4)"
    assert dash.costs_of(dashes:, direction:) == Error(Nil)
  })
}
