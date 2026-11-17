//// The shared check of a creature's spell (`genesis_prime/world_map/creature_attack`
//// `loadable`), on the client's committed rows. Expected values come from these places.
//// - The creature formula reads parameter types 0, 1, 10 and 12 (`damage.creature_unread`).
//// - Spell4 34361 (an Asura auto-attack) has damage rows 185278 (parameter types 1 and 12,
////   caster prerequisite 30526: difficulty at most 6) and 185298 (parameter types 2 and 12,
////   30527: difficulty at least 7) (`table_rows -- Spell4Effects spellId=34361` and
////   `Prerequisite 30526 30527`), so a creature of difficulty 4 strikes with the first
////   and one of difficulty 7 with the second.
//// - The client reads a damage multiplier, dataBits00, as a 32-bit float; a NaN or an
////   infinity has no value (`float32.of_column`).

import fixture_tables
import genesis_prime/world_map/creature_attack.{
  FormulaNotRead, MultiplierNotFinite,
}
import owned_test
import planted_table.{Integer}

pub fn loadable_names_an_unread_formula_for_the_creatures_difficulty_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  assert creature_attack.loadable(tables:, spell4_id: 34_361, difficulty: 4)
    == Ok(Nil)
    as "difficulty 4 takes damage row 185278, whose parameters the creature formula reads"
  assert creature_attack.loadable(tables:, spell4_id: 34_361, difficulty: 7)
    == Error(FormulaNotRead(spell4_effects_id: 185_298, parameter_kind: 2))
    as "difficulty 7 takes row 185298, which reads parameter type 2: the same spell, another difficulty"
  assert creature_attack.loadable(tables:, spell4_id: 6651, difficulty: 2)
    == Error(FormulaNotRead(spell4_effects_id: 185_104, parameter_kind: 2))
    as "Spell4 6651 reads parameter type 2 in both its rows"
}

pub fn loadable_names_a_multiplier_that_is_not_finite_test() -> Nil {
  use <- owned_test.run(60_000)
  // Synthetic: Spell4Effects 184751's dataBits00 is 1065353216, the float 1.0; 2143289344
  // is a NaN.
  use tables <- fixture_tables.changed(
    table: "Spell4Effects",
    id: 184_751,
    with: [#("dataBits00", Integer(2_143_289_344))],
  )
  assert creature_attack.loadable(tables:, spell4_id: 33_251, difficulty: 4)
    == Error(MultiplierNotFinite(
      spell4_effects_id: 184_751,
      bits: 2_143_289_344,
    ))
    as "a multiplier that is not a finite float is refused with the row and its bits"
  assert creature_attack.loadable(tables:, spell4_id: 33_251, difficulty: 7)
    == Ok(Nil)
    as "the other difficulty takes row 184829, which is unchanged"
}
