//// The decode of a Creature2 row's `CreationTypeEnum` into one kind
//// (genesis_prime/world_map/creation_type). Expected values and their sources:
//// - The client refuses a creature whose creation type is 26 or higher
////   (`ValidateCreatureRows 0x140485790`, `Creature2.CreationTypeEnum`).
//// - Its chooser `0x140479560` keys behaviour on 4 (door), 8 (collectible) and 12
////   (mailbox); the unit type equals the creation type for 0 to 14.
//// - 18 (bind point) pairs with unit type 19 and 20 with 32: from the world database
////   (wildstar-knowledge world-data), a guess; no client code holds the pairing.
//// - The client's table: no Creature2 row (56,369) has a creation type of 26 or more.

import client_tables
import genesis_prime/table/creature2
import genesis_prime/world_map/creation_type.{
  BindPoint, NonPlayer, Other, Refused, SimpleCollidable, Turret,
}
import gleam/int
import gleam/list
import owned_test
import unitest

pub fn creation_type_decodes_each_value_to_its_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  assert creation_type.kind_of(0) == NonPlayer
    as "0x140479560: creation type 0 is a non-player"
  assert creation_type.kind_of(13) == Turret as "13 is the turret creation type"
  assert creation_type.kind_of(18) == BindPoint
    as "18 is a bind point (world database, guess)"
  assert creation_type.kind_of(20) == SimpleCollidable
    as "20 is a simple collidable (world database, guess)"
  let others =
    list.flatten([
      through(1, 12),
      through(14, 17),
      [19],
      through(21, 25),
    ])
  list.each(others, fn(number) {
    assert creation_type.kind_of(number) == Other(number)
      as "0x140485790: 0 to 25 load, and these have no behaviour of their own here"
  })
  list.each([26, 27, 100], fn(number) {
    assert creation_type.kind_of(number) == Refused(number)
      as "0x140485790: the client refuses 26 and over"
  })
}

pub fn creation_type_pairs_with_its_unit_type_test() -> Nil {
  use <- owned_test.run(10_000)
  assert creation_type.unit_type(creation_type.kind_of(18)) == 19
    as "world database (guess): a bind point stands as unit type 19"
  assert creation_type.unit_type(creation_type.kind_of(20)) == 32
    as "world database (guess): a simple collidable stands as unit type 32"
  list.each([0, 1, 4, 8, 12, 13, 19, 25, 26, 99], fn(number) {
    assert creation_type.unit_type(creation_type.kind_of(number)) == number
      as "0x140479560: the unit type equals the creation type for 0 to 14; elsewhere the server picks its own number (guess), a refused value included"
  })
}

pub fn creation_type_accepts_0_to_25_only_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(through(0, 25), fn(number) {
    assert creation_type.is_accepted(creation_type.kind_of(number))
      as "0x140485790: the client loads a creature below 26"
  })
  list.each([26, 27, 100], fn(number) {
    assert !creation_type.is_accepted(creation_type.kind_of(number))
      as "0x140485790: the client refuses 26 and over"
  })
}

pub fn creation_type_reads_every_row_of_the_real_table_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let rows = creature2.all(client_tables.shared())
  assert list.length(rows) == 56_369 as "Creature2.tbl holds 56,369 rows"
  assert list.filter(rows, fn(row) {
      case creation_type.kind_of(row.creation_type_enum) {
        Refused(_) -> True
        NonPlayer | Turret | BindPoint | SimpleCollidable | Other(_) -> False
      }
    })
    == []
    as "no row is of a creation type the client refuses"
}

/// The numbers from `first` to `last`, both included.
fn through(first: Int, last: Int) -> List(Int) {
  int.range(from: first, to: last + 1, with: [], run: fn(numbers, number) {
    [number, ..numbers]
  })
  |> list.reverse
}
