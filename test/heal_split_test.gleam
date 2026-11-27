//// What a heal comes to (`genesis_prime/game/heal_split`), for every amount, share and
//// room. The expected values are the rule's own, not a client row's.
//// - A heal gives each vital a part of 0 or more and never more than the heal's amount;
////   a vital's part is at most its room, and the parts and the overheal add up to the
////   amount (`spell.heal_result_log`: the overheal is what the shield and the health did
////   not take).
////   Shares run from 0 to 2, so the property covers a share above 1.

import genesis_prime/game/heal_split.{Scaling}
import genesis_prime/shared/effect_kind
import gleam/list
import owned_test
import qcheck

pub fn a_heal_split_never_gives_a_negative_part_or_more_than_its_amount_test() -> Nil {
  use <- owned_test.run(60_000)
  qcheck.given(
    qcheck.tuple4(
      qcheck.bounded_int(from: 0, to: 2000),
      qcheck.bounded_float(from: 0.0, to: 2.0),
      qcheck.bounded_int(from: 0, to: 2000),
      qcheck.bounded_int(from: 0, to: 2000),
    ),
    fn(drawn) {
      let #(amount, share, health_room, shield_room) = drawn
      list.each([effect_kind.Health, effect_kind.Shield], fn(vital) {
        let split =
          heal_split.split(
            vital:,
            amount:,
            scaling: Scaling(outgoing: 1.0, incoming: 1.0, to_shield: share),
            health_room:,
            shield_room:,
          )
        assert split.amount == amount
          as "unscaled, the heal is its formula's amount"
        assert split.shield >= 0 && split.health >= 0 && split.overheal >= 0
          as "no part is negative"
        assert split.shield + split.health + split.overheal == amount
          as "the parts and the overheal are the amount"
        assert split.shield <= shield_room && split.health <= health_room
          as "a vital rises by no more than its room"
      })
    },
  )
}
