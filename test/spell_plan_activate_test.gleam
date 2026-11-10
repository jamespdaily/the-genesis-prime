//// The plans of the activate spells (genesis_prime/game/activate) from the client's own
//// tables: every spell a Creature2 row names in an activate column, and the default spell,
//// is planned or has one named reason. Expected values come from the client's Spell4 and
//// Creature2 tables.

import client_tables
import genesis_prime/game/activate.{CannotBePlanned, NoSpell4Row, Planned}
import genesis_prime/game/spell_plan
import genesis_prime/table/creature2
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import unitest

pub fn every_activate_spell_has_a_plan_or_a_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let activations = activate.activations(tables:)
  let named =
    list.flat_map(creature2.all(tables), fn(row) {
      list.map(activate.creature_of(row:).columns, fn(column) {
        column.spell4_id
      })
    })
    |> list.filter(fn(spell4_id) { spell4_id != 0 })
    |> list.append([activations.default_spell])
    |> set.from_list
    |> set.to_list
    |> list.sort(by: int.compare)
  assert list.length(named) > 2000
    as "the client's Creature2 rows name more than 2000 distinct activate spells (2,124 at the time of writing, with the default spell)"
  assert list.all(named, fn(spell4_id) {
    dict.has_key(activations.spells, spell4_id)
  })
    as "the load holds a plan or a reason for every spell a column names, and for the default spell"
  let outcomes =
    list.map(named, fn(spell4_id) {
      let assert Ok(planned) = activate.planned_of(activations:, spell4_id:)
      #(spell4_id, planned)
    })
  assert list.filter_map(outcomes, fn(outcome) {
      case outcome.1 {
        NoSpell4Row -> Ok(outcome.0)
        Planned(..) | CannotBePlanned(..) -> Error(Nil)
      }
    })
    == [6754, 6755, 24_941, 30_850, 33_436, 34_250, 38_375]
    as "Spell4 has no row for exactly these seven activate spells of Creature2 (each is refused with result 4, SpellUnknown)"
  let reasons =
    list.filter_map(outcomes, fn(outcome) {
      case outcome.1 {
        CannotBePlanned(why:) -> Ok(#(outcome.0, why))
        Planned(..) | NoSpell4Row -> Error(Nil)
      }
    })
  assert list.all(reasons, fn(reason) { string.starts_with(reason.1, "the ") })
    as "each spell the plan cannot build holds the plan's own reason in words: the Spell4 row and the effect it does not read, or the table row it lacks"
  assert list.length(reasons) == 511
    as "511 of the activate spells cannot be planned: 103 hold an effect the plan does not read (a CCStateSet, a DisguiseOutfit, a SpellForceRemove, a VitalModifier, a Stealth or a Proxy row, or a missing Spell4Base row) and 408 more hold an effect other than Activate aimed at the target or an area of a type some rule reads for that aim (a Proxy, Damage, Fluff, RavelSignal and so on), which an activate cast, striking no one, would lose: the press is refused as not built, with the reason logged once; a row of a type no rule reads is dropped by every cast and refuses nothing"
  assert list.count(reasons, fn(reason) {
      string.contains(reason.1, "aims at the target or an area")
    })
    == 408
    as "408 of the 511 are refused for an effect aimed at the target or an area"
  let assert Ok(why) = list.key_find(reasons, 38_392)
    as "Spell4 38392 (Creature2 19232's spell) is among them"
  assert string.contains(why, "82255")
    as "its Spell4Effects 82255 is a Proxy aimed at the primary target (targetFlags 2), the effect the cast would lose"
  let method_of = fn(spell4_id) {
    let assert Ok(Planned(spell:, ..)) =
      activate.planned_of(activations:, spell4_id:)
    spell.method
  }
  assert method_of(activations.default_spell) == spell_plan.Normal
    as "the default spell 8 is a plain cast (Spell4 8, castMethod 0)"
  assert method_of(1817) == spell_plan.Normal
    as "Spell4 1817, the Seaspine Mollusk's spell, is a plain cast"
  assert list.any(outcomes, fn(outcome) {
    case outcome.1 {
      Planned(spell:, ..) -> spell.method == spell_plan.ClientSideInteraction
      NoSpell4Row | CannotBePlanned(..) -> False
    }
  })
    as "some activate spells are castMethod 5 (client side interaction), which the cast rule does not build: the plan holds them and the press is refused as not built"
}
