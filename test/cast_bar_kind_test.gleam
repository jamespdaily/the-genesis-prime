//// The decode of a Spell4Base castBarType number (genesis_prime/game/cast_bar_kind).
//// Expected values and their sources:
//// - `Spell4Base.castBarType`: the client reads the number as zero or not (SpellShowsCastBar
////   `0x1407a1820`, IsUnitCastBarShown `0x140469530`, ApplySpellGo `0x14053e5a0`).

import genesis_prime/game/cast_bar_kind.{Bar, NoBar}
import gleam/list
import owned_test

pub fn a_cast_bar_type_of_zero_is_no_bar_and_any_other_number_is_a_bar_test() -> Nil {
  use <- owned_test.run(10_000)
  assert cast_bar_kind.kind_of(number: 0) == NoBar
    as "0x1407a1820: a record word 0x2c of zero is no cast bar"
  let bars = [1, 2, 7, 99, -1]
  assert list.map(bars, fn(number) { cast_bar_kind.kind_of(number:) })
    == list.map(bars, fn(number) { Bar(number:) })
    as "Spell4Base.castBarType: every non-zero number is a cast bar, and the number is kept as stored"
}
