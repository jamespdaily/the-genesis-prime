//// The activate cast's pick of a spell (genesis_prime/game/activate): which of a creature's
//// four activate columns the client casts when the player right-clicks it. Expected values
//// come from the client's pick, `0x14046c580` (fact `opcode.0x97.pick`), and the rows of the
//// Seaspine Mollusk, Creature2 26462, in the client's tables.

import fixture_tables
import genesis_prime/game/activate.{
  ActivateEffect, CannotBePlanned, Column, Creature, NoActivateSpell, Picked,
  Planned, Unread,
}
import genesis_prime/game/prerequisite.{Fails, NotRead, Passes}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Spell4EffectsId}
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import prerequisite_support

/// A creature of these columns, with the cast time and range of no row.
fn creature_of(columns columns: List(#(Int, Int))) -> activate.Creature {
  Creature(
    columns: list.map(columns, fn(column) {
      Column(prerequisite_id: column.0, spell4_id: column.1)
    }),
    cast_time_ms: 0,
    min_range: 0.0,
    max_range: 0.0,
  )
}

pub fn activate_pick_takes_first_passing_column_test() -> Nil {
  use <- owned_test.run(5000)
  // The prerequisites the check answers: 11 and 13 pass, 12 fails, 14 holds a condition the
  // server does not read.
  let check = fn(prerequisite_id) {
    case prerequisite_id {
      11 | 13 -> Passes
      14 -> NotRead(prerequisite_type: 999)
      _ -> Fails
    }
  }
  let picked = fn(columns) {
    activate.pick(creature: creature_of(columns:), default_spell: 8, check:)
  }
  assert picked([#(0, 100), #(11, 200)]) == Picked(spell4_id: 100)
    as "0x14046c580: a column whose prerequisite is 0 wins without a check"
  assert picked([#(12, 100), #(13, 200), #(11, 300)]) == Picked(spell4_id: 200)
    as "0x14046c580: a failing first column is skipped, and the first passing one wins even when a later one passes too"
  assert picked([#(12, 100), #(12, 200)]) == Picked(spell4_id: 8)
    as "0x14046c580: when no column passes the pick stays GameFormula 414's dataint0, 8"
  assert picked([#(12, 100), #(11, 0), #(13, 300)]) == NoActivateSpell
    as "0x14046c580: a passing column whose spell is 0 wins and the client refuses with result 100 (TargetIsNotUseable)"
  assert picked([#(0, 0)]) == NoActivateSpell
    as "0x14046c580: a column of prerequisite 0 and spell 0 is the same refusal"
  assert picked([#(12, 100), #(14, 200), #(11, 300)])
    == Unread(prerequisite_type: 999)
    as "a column the server cannot read stops the pick, so the cast is refused as not built, never another column's spell"
  assert picked([#(11, 100), #(14, 200)]) == Picked(spell4_id: 100)
    as "a column after the winner is never checked"
}

pub fn seaspine_mollusk_activates_with_1817_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let assert Ok(row) = creature2.get(tables:, id: Creature2Id(26_462))
    as "Creature2 26462, the Seaspine Mollusk, is a root of the fixture"
  let creature = activate.creature_of(row:)
  let activations = activate.activations(tables:)
  assert activations.default_spell == 8
    as "GameFormula 414's dataint0 (0x14046c580)"
  assert creature.cast_time_ms == 2000
    as "Creature2 26462's activateSpellCastTime is 2000"
  let player_with_it =
    prerequisite.Subject(
      ..prerequisite_support.holding(held: [], second_unit: Some(5000)),
      player: Some(prerequisite_support.player()),
    )
  assert activate.pick(
      creature:,
      default_spell: activations.default_spell,
      check: activate.checker(activations:, subject: player_with_it),
    )
    == Picked(spell4_id: 1817)
    as "the creature's first column names Prerequisite 9358, which passes for a player with no challenge record (type 125 comparison 2), so the pick is Spell4 1817"
  let assert Ok(Planned(effects:, ..)) =
    activate.planned_of(activations:, spell4_id: 1817)
    as "the load plans Spell4 1817"
  assert effects
    == [ActivateEffect(effect_id: Spell4EffectsId(2821), delay_ms: 0)]
    as "Spell4 1817's one Activate row is Spell4Effects 2821, delay 0"
}

pub fn activate_spell_that_strikes_cannot_be_planned_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  let assert Ok(CannotBePlanned(why:)) =
    activate.planned_of(activations:, spell4_id: 38_392)
    as "Spell4 38392, Creature2 19232's activate spell, is held with a reason"
  assert string.contains(why, "82255") && string.contains(why, "38392")
    as "Spell4Effects 82255 of Spell4 38392 is a Proxy (effectType 26) aimed at the primary target (targetFlags 2) beside its Activate row 82254: the activate cast strikes no one, so the reason names that row"
  let assert Ok(CannotBePlanned(why: signal)) =
    activate.planned_of(activations:, spell4_id: 39_244)
    as "Spell4 39244 is held with a reason"
  assert string.contains(signal, "85564")
    as "Spell4Effects 85564 of Spell4 39244 is a RavelSignal (effectType 81) aimed at the primary target (targetFlags 2): the strike lists it as a life on each struck unit (genesis_prime/game/cast aimed_at), so an activate cast that strikes no one would lose it"
}

pub fn activate_spell_with_an_unread_target_effect_is_planned_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  let assert Ok(Planned(effects:, ..)) =
    activate.planned_of(activations:, spell4_id: 34_512)
    as "Spell4 34512 is planned: its only other row, Spell4Effects 179989, is effectType 107 aimed at the primary target (targetFlags 2), a type no server rule reads, which the strike drops on every path"
  assert effects
    == [ActivateEffect(effect_id: Spell4EffectsId(68_310), delay_ms: 0)]
    as "Spell4Effects 68310 is Spell4 34512's Activate row, delay 0"
}
