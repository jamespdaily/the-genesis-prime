//// The cast rule's use of a unit with no activate spell (`genesis_prime/game/cast.activate_unit`),
//// the client's 0xb3. Expected values come from these places.
//// - `opcode.0xb3` and `0x14039d510`: the client sends 0xb3 only when the unit's activate
////   spell is 0 (the creature's pick, `0x14046c580`); a unit that has a spell is cast at
////   with 0x97 (`cast_activate_test`). The use is at once, with no cast and no range.
//// - Creature2 26462 (the Seaspine Mollusk): activate spell 1817 behind Prerequisite 9358,
////   and the default activate spell 8 when that fails (`cast_activate_test`).
//// - Creature2 73500 (the primal manifestation of quest 10520's objective 21294): it has
////   no activate column.

import cast_support as support
import character_tables
import genesis_prime/game/activate
import genesis_prime/game/cast.{type Effect}
import genesis_prime/message/client_activate_unit.{ClientActivateUnit}
import genesis_prime/step.{LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import gleam/dict
import gleam/list
import gleam/string
import owned_test

const the_mollusk = 26_462

const a_manifestation = 73_500

const its_unit = 5000

/// What the caster's 0xb3 for `unit_id` gives, when the units it sees are the creature
/// of each pair, by unit id.
fn used(seen seen: List(#(Int, Int)), unit_id unit_id: Int) -> List(Effect) {
  let tables = character_tables.shared()
  let creatures =
    dict.from_list(
      list.map(seen, fn(pair) {
        let assert Ok(row) = creature2.get(tables, Creature2Id(pair.1))
          as "the fixture holds the creature's row"
        #(pair.0, #(pair.1, activate.creature_of(row:)))
      }),
    )
  let assert Ok(body) =
    client_activate_unit.encode(ClientActivateUnit(unit_id:))
    as "a unit id fits the message"
  let assert Ok(effects) =
    cast.activate_unit(
      cast: cast.new(),
      body:,
      caster: support.caster(),
      activations: activate.activations(tables:),
      creature_of: fn(unit) { dict.get(creatures, unit) },
    )
    as "a 0xb3 that fits the message is taken"
  effects
}

pub fn a_client_activate_unit_on_a_unit_with_no_activate_spell_is_used_at_once_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(seen: [#(its_unit, a_manifestation)], unit_id: its_unit)
    == [cast.Activated(unit_id: its_unit, creature_id: a_manifestation)]
    as "a creature with no activate column is used with no cast and no wait"
}

pub fn a_client_activate_unit_on_a_unit_with_an_activate_spell_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [cast.Log(level: LogWarning, text:)] =
    used(seen: [#(its_unit, the_mollusk)], unit_id: its_unit)
    as "a creature whose pick is a spell is logged and nothing else: no Activated, no write"
  assert string.contains(text, "0x97")
    as "the log says the client casts such a unit with 0x97"
}

pub fn a_client_activate_unit_on_a_unit_the_client_does_not_show_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [cast.Log(level: LogWarning, text:)] =
    used(seen: [#(its_unit, a_manifestation)], unit_id: its_unit + 1)
    as "a unit that is no creature or object in the picture is logged and counts nothing"
  assert string.contains(text, "no creature or object") as "the log says why"
}
