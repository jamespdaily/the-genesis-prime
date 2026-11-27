//// How long a Spell4Effects row lasts (`genesis_prime/shared/lasts`). Expected values come
//// from these places.
//// - `Spell4Effects.flags` bit 2 is a row that lasts until removed, whatever its
////   durationTime (`lasting.life_of`, `opcode.0x7f4.effect_time`).
//// - The client's own Spell4Effects table, for the rows that name both.

import client_tables
import fixture_tables
import genesis_prime/shared/lasts
import genesis_prime/shared/spell_effect
import genesis_prime/shared/spell_plan
import genesis_prime/table/spell4_effects.{Spell4Effects}
import gleam/list
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

pub fn no_spell_effect_row_both_lasts_until_removed_and_names_a_duration_test() -> Nil {
  // deadline: 12 ms measured with the client's tables already read, 120 s for a cold read on a loaded machine: it reads every Spell4Effects row
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let both =
    list.filter(spell4_effects.all(client_tables.shared()), fn(effect) {
      spell_effect.has_flag(flags: effect.flags, bit: 2)
      && effect.duration_time > 0
    })
  assert list.map(both, fn(effect) { effect.id }) == []
    as "Spell4Effects: no row has flags bit 2 and a durationTime above 0, so a row's lasts is one or the other"
}

/// The caster-aimed CCStateSet row 224967 (Spell4 85563, state 27, flags 2), edited to
/// `flags` and a durationTime of 5000: no client row names both, so the case is edited in.
fn crowd_control_lasts_of(flags flags: Int) -> lasts.Lasts {
  fixture_tables.changed(
    table: "Spell4Effects",
    id: 224_967,
    with: [#("flags", Integer(flags)), #("durationTime", Integer(5000))],
    body: fn(tables) {
      let assert Ok(spell) =
        spell_tables.planned_alone(tables:, spell4_id: 85_563)
        as "spell 85563 loads"
      let assert [control] =
        spell_plan.payloads(spell:, as_kind: spell_plan.as_control)
        as "its one CCStateSet row is planned"
      control.row.lasts
    },
  )
}

pub fn a_row_that_lasts_until_removed_reads_so_whatever_its_duration_and_one_without_the_flag_lasts_its_duration_test() -> Nil {
  // deadline: 12 ms measured on the fixture, 60 s for a loaded machine: it plans spell 85563 twice
  use <- owned_test.run(60_000)
  let row = fn(flags) {
    Spell4Effects(
      ..spell_tables.blank_effect(
        id: 1,
        spell: 1,
        effect_type: 17,
        target_flags: 1,
      ),
      flags:,
      duration_time: 5000,
    )
  }
  list.each(
    [
      #(
        2,
        lasts.UntilRemoved,
        "flags bit 2 with durationTime 5000 lasts until removed, as lasting.life_of reads it",
      ),
      #(
        0,
        lasts.For(duration_ms: 5000),
        "flags 0 with durationTime 5000 lasts 5000 ms",
      ),
    ],
    fn(scene) {
      let #(flags, expected, reason) = scene
      assert spell_plan.lasting_row_of(effect: row(flags)).lasts == expected
        as reason
      assert crowd_control_lasts_of(flags:) == expected
        as "a CCStateSet row of the same flags and durationTime 5000 reads the same"
    },
  )
}
