//// The FullScreenEffect (95) rows of the plan (`genesis_prime/shared/spell_plan`,
//// `genesis_prime/shared/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.95`: the client draws a FullScreenEffect only for the
////   player's own unit and does all of it, so the server lists a row aimed at the caster in
////   the go with its life; the game holds 136 rows of it, targetFlags 1 for 78, 2 for 37 and
////   4 for 21 (`table_rows -- Spell4Effects effectType=95`), 49 of them the Level Up tiers.
//// - `opcode.0x7f4.effect_time`: a row's life is its delay and durationTime, and flags bit 2
////   is "never ends".
//// - `Spell4.tierIndex.level_up`: Spell4Base 53378 holds 49 Spell4 rows of no cast time, no
////   cost, no cooldown and global cooldown kind 3, each with one FullScreenEffect row aimed at
////   the caster for 5000 ms (`table_rows -- Spell4 spell4BaseIdBaseSpell=53378` and
////   `-- Spell4Effects spellId=<tier>`), kept in the fixture.

import fixture_tables
import genesis_prime/shared/effect_kind
import genesis_prime/shared/lasting.{LastingRow}
import genesis_prime/shared/lasts
import genesis_prime/shared/spell_plan.{AimsAtCaster}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import gleam/option.{None}
import level_up_support
import owned_test
import planted_table.{Integer}
import spell_tables

pub fn a_full_screen_row_is_read_when_it_is_aimed_at_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 95) == effect_kind.FullScreenEffect
    as "Spell.CodeEnumSpellEffectType value 95 'FullScreenEffect' (Spell4Effects.effectType.95)"
  assert effect_kind.is_read(effect_type: 95)
  list.each(
    [
      #(1, True, "the caster alone: the one unit the client draws it for"),
      #(3, True, "the caster and the primary target"),
      #(5, True, "the caster and the area"),
      #(7, True, "all three"),
      #(2, False, "the primary target alone: the client draws nothing there"),
      #(4, False, "the area alone"),
      #(6, False, "the primary target and the area"),
    ],
    fn(case_) {
      let #(flags, read, why) = case_
      assert effect_kind.is_row_read(effect_type: 95, target_flags: flags)
        == read
        as { "targetFlags " <> int.to_string(flags) <> ": " <> why }
    },
  )
}

pub fn a_full_screen_row_is_a_lasting_row_with_the_rows_delay_and_life_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each planted row takes an id no client row holds; the shape is the Level Up tier's row:
  // the caster, 5000 ms, every phase.
  list.each(
    [
      #(
        "the tier's own shape: no delay, 5000 ms",
        [#("durationTime", Integer(5000))],
        1,
        Ok(LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 5000))),
      ),
      #(
        "a delay stays the row's own",
        [#("delayTime", Integer(120)), #("durationTime", Integer(1000))],
        1,
        Ok(LastingRow(delay_ms: 120, lasts: lasts.For(duration_ms: 1000))),
      ),
      #(
        "flags bit 2 never ends (opcode.0x7f4.effect_time)",
        [#("flags", Integer(2))],
        1,
        Ok(LastingRow(delay_ms: 0, lasts: lasts.UntilRemoved)),
      ),
      #(
        "a row aimed at the primary target is left out: the client draws nothing for it",
        [#("durationTime", Integer(5000))],
        2,
        Error(Nil),
      ),
    ],
    fn(case_) {
      let #(why, columns, flags, expected) = case_
      let spell =
        spell_tables.planned_with_row(row: spell_tables.effect_row_with(
          id: 99_201,
          effect_type: 95,
          target_flags: flags,
          columns:,
        ))
      let found = spell_tables.lasting_row_of(spell:, effect_id: 99_201)
      case expected {
        Ok(row) -> {
          let assert Ok(lasting) = found as why
          assert lasting.row == row as why
          assert lasting.aim == AimsAtCaster
            as "targetFlags 1 aims at the caster alone"
        }
        Error(Nil) -> {
          assert found == Error(Nil) as why
        }
      }
    },
  )
}

pub fn every_level_up_tier_plans_as_one_caster_row_with_no_cost_or_cooldown_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let tiers =
    list.filter(spell4.all(tables), fn(row) {
      row.spell4_base_id_base_spell == 53_378
    })
  assert list.length(tiers) == 49
    as "Spell4.tierIndex.level_up: 49 Spell4 rows of Spell4Base 53378"
  list.each(tiers, fn(row) {
    let name = "tier " <> int.to_string(row.tier_index)
    let assert Ok(spell) =
      spell_plan.spell_alone(tables:, sources:, spell4_id: row.id, chain: [])
      as { name <> " plans" }
    assert spell.cast_time_ms == 0 as { name <> ": no cast time" }
    assert spell.cooldown_ms == 0 as { name <> ": no cooldown of its own" }
    assert spell.global_cooldown.starts_for_ms == None
      as { name <> ": global cooldown kind 3 starts none" }
    assert spell.costs == [] as { name <> ": no cost" }
    assert spell.cast_bar == spell_plan.HidesCastBar
      as { name <> ": no cast bar" }
    let assert [lasting] =
      spell_plan.payloads(spell:, as_kind: spell_plan.as_lasting)
      as { name <> ": exactly one lasting row" }
    assert lasting.aim == AimsAtCaster as { name <> ": aimed at the caster" }
    assert lasting.row
      == LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 5000))
      as { name <> ": no delay, 5000 ms" }
    let assert [effect] =
      list.filter(spell4_effects.all(tables), fn(effect) {
        effect.spell_id == row.id
      })
      as { name <> ": the Spell4 holds one Spell4Effects row" }
    assert lasting.effect_id.value == effect.id
      as { name <> ": the lasting row is that Spell4Effects row" }
    assert effect.effect_type == 95 as { name <> ": a FullScreenEffect row" }
    case
      list.find(level_up_support.tiers, fn(tier) { tier.spell4_id == row.id })
    {
      Ok(tier) -> {
        assert tier.level == row.tier_index + 1
          as { name <> ": the level is the tierIndex plus 1" }
        assert effect.id == tier.effect_id
          as { name <> ": the effect id the table names" }
      }
      Error(Nil) -> Nil
    }
  })
}
