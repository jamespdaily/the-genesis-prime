//// The decode of a Spell4TargetMechanics row's `targetType` into one kind
//// (genesis_prime/shared/target_mechanic). Expected values and their sources:
//// - The client's picker `0x14055bdc0` (`Spell4TargetMechanics.targetType`, fairly sure)
////   takes the caster for kinds 0, 2, 6 and 7 and a target for 1, 3, 5 and 8; kind 4 is
////   placed on the ground (`CastAbilityBagSpell` sends 0x9b for it). The client names none.
//// - The client's table: all 61 rows are of kinds 0 to 8 (read from the extracted table).

import client_tables
import genesis_prime/shared/target_mechanic.{Caster, Ground, Targeted, Unread}
import genesis_prime/table/spell4_target_mechanics
import gleam/list
import owned_test
import unitest

pub fn target_mechanic_decodes_each_target_type_to_its_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0, 2, 6, 7], fn(target_type) {
    assert target_mechanic.kind_of(target_type:) == Caster
      as "0x14055bdc0: kinds 0, 2, 6 and 7 take the caster"
  })
  list.each([1, 3, 5, 8], fn(target_type) {
    assert target_mechanic.kind_of(target_type:) == Targeted
      as "0x14055bdc0: kinds 1, 3, 5 and 8 take a target"
  })
  assert target_mechanic.kind_of(target_type: 4) == Ground
    as "CastAbilityBagSpell sends 0x9b for kind 4: it is placed on the ground"
  list.each([-1, 9, 10, 100], fn(target_type) {
    assert target_mechanic.kind_of(target_type:) == Unread(target_type)
      as "the client's picker has no case for any other kind"
  })
}

pub fn target_mechanic_reads_every_row_of_the_real_table_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let rows = spell4_target_mechanics.all(client_tables.shared())
  assert list.length(rows) == 61 as "Spell4TargetMechanics.tbl holds 61 rows"
  assert list.filter(rows, fn(row) {
      case target_mechanic.of_row(row) {
        Unread(_) -> True
        Caster | Targeted | Ground -> False
      }
    })
    == []
    as "every row is of a kind the client's picker has a case for (0 to 8)"
}
