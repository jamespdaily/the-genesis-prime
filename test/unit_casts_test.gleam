//// The casts a unit create lists (`genesis_prime/game/unit_casts`). Expected
//// values come from `opcode.0x262.casts` (the entry's fields and the 9-bit
//// count), `cast.state` (the entry's bit is state 2 for 1 and state 3 for 0),
//// and `CreateCast 0x140561780` (a cast id 0 is a pending cast, which makes
//// `ApplyUnitCreateCasts 0x140458fe0` fail and skip the rest of the list).

import genesis_prime/game/unit_casts.{type CastView, CastView}
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/table/id.{Spell4Id}
import gleam/int
import gleam/list
import gleam/result
import owned_test

fn view(cast_id cast_id: Int) -> CastView {
  CastView(
    caster_unit_id: 21,
    cast_id:,
    spell4_id: Spell4Id(32_893),
    primary_target: 22,
    gone: False,
    current: True,
  )
}

fn entry(cast_id cast_id: Int, started started: Int) -> UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: 21,
    primary_target_unit_id: 22,
    cast_id:,
    spell4_id: 32_893,
    started:,
    targets: [],
    initial_positions: [],
    telegraph_positions: [],
  )
}

pub fn an_entry_names_its_cast_and_state_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "a cast whose first go has not gone is started (bit 1)",
        view(cast_id: 7),
        entry(cast_id: 7, started: 1),
      ),
      #(
        "a cast whose first go has gone is gone (bit 0)",
        CastView(..view(cast_id: 7), gone: True),
        entry(cast_id: 7, started: 0),
      ),
      #(
        "the caster, the primary target and the Spell4 id are the cast's",
        CastView(
          caster_unit_id: 5,
          cast_id: 9,
          spell4_id: Spell4Id(100),
          primary_target: 6,
          gone: False,
          current: True,
        ),
        UnitCreateCast(
          ..entry(cast_id: 9, started: 1),
          caster_unit_id: 5,
          primary_target_unit_id: 6,
          spell4_id: 100,
        ),
      ),
    ],
    fn(row) {
      assert unit_casts.entry_of(row.1) == Ok(row.2) as row.0
    },
  )
}

pub fn entries_come_in_cast_id_order_stop_at_511_and_never_carry_id_0_test() -> Nil {
  use <- owned_test.run(5000)
  let ids = fn(views) {
    list.map(unit_casts.entries_of(views), fn(entry) { entry.cast_id })
  }
  assert ids([view(cast_id: 30), view(cast_id: 10), view(cast_id: 20)])
    == [10, 20, 30]
    as "entries are in cast id order"
  let many =
    list.index_map(list.repeat(Nil, 600), fn(_, index) {
      view(cast_id: 600 - index)
    })
  assert list.length(ids(many)) == 511
    as "a list holds 511 entries at most (its count is 9 bits)"
  assert ids(many) == list.sort(ids(many), int.compare)
    as "the entries are sorted by cast id"
  assert list.first(ids(many)) == Ok(1) as "the 511 are the lowest cast ids"
  assert list.last(ids(many)) == Ok(511) as "the 511 are the lowest cast ids"
  assert ids([view(cast_id: 0), view(cast_id: 4)]) == [4]
    as "a view with cast id 0 gives no entry"
  assert result.is_error(unit_casts.entry_of(view(cast_id: 0)))
    as "a cast id 0 is refused by name"
  assert ids([CastView(..view(cast_id: 5), current: False), view(cast_id: 6)])
    == [6]
    as "a view that is not the current cast and holds no target is left out"
}
