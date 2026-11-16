//// The decode of a TargetGroup row's `type` into one kind (genesis_prime/game/target_group_kind).
//// Expected values and their sources:
//// - The client's tester `0x1403b4a20` switches on the type: 1 and 2 test the unit's
////   Creature2 id, 3 and 4 its current Faction2 id, 5 and 6 its race, 7 and 8 its class,
////   12 and 13 its UnitRace id, 9 the 18-bit value of the third tagged entry of its 0x262
////   (`TargetGroup.type.9`), 10 and 11 the sub-groups its words name; any other type is
////   never a member. The odd type of each pair is the member test and the even type its
////   negation.
//// - The client's table: all 9,644 rows are of types 1 to 13 (counted from the extracted
////   table: type 1 7,980 rows, 2 39, 3 224, 4 18, 5 11, 7 7, 9 314, 10 22, 11 853, 12 173
////   and 13 3).

import client_tables
import genesis_prime/game/target_group_kind.{
  AllOf, AnyOf, ByClass, ByCreature, ByFaction, ByRace, BySet, ByUnitRace,
  NotClass, NotCreature, NotFaction, NotRace, NotUnitRace, Unread,
}
import genesis_prime/table/target_group
import gleam/list
import owned_test
import unitest

pub fn target_group_kind_decodes_types_1_to_13_to_their_variants_test() -> Nil {
  use <- owned_test.run(10_000)
  let expected = [
    #(1, ByCreature),
    #(2, NotCreature),
    #(3, ByFaction),
    #(4, NotFaction),
    #(5, ByRace),
    #(6, NotRace),
    #(7, ByClass),
    #(8, NotClass),
    #(9, BySet),
    #(10, AllOf),
    #(11, AnyOf),
    #(12, ByUnitRace),
    #(13, NotUnitRace),
  ]
  list.each(expected, fn(entry) {
    let #(type_number, kind) = entry
    assert target_group_kind.kind_of(type_number:) == kind
      as "0x1403b4a20: the type picks the test"
  })
}

pub fn target_group_kind_gives_unread_the_number_of_any_other_type_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([0, 14, 15, 100, -1], fn(type_number) {
    assert target_group_kind.kind_of(type_number:) == Unread(type_number)
      as "0x1403b4a20: any other type is never a member"
  })
}

pub fn target_group_kind_reads_every_row_of_the_real_table_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let rows = target_group.all(client_tables.shared())
  assert list.length(rows) == 9644 as "TargetGroup.tbl holds 9,644 rows"
  assert list.filter(rows, fn(row) {
      case target_group_kind.of_row(row) {
        Unread(_) -> True
        ByCreature
        | NotCreature
        | ByFaction
        | NotFaction
        | ByRace
        | NotRace
        | ByClass
        | NotClass
        | BySet
        | AllOf
        | AnyOf
        | ByUnitRace
        | NotUnitRace -> False
      }
    })
    == []
    as "every row is of a type the client's tester has a case for"
}
