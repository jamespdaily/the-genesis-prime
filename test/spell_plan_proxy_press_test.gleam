//// How the plan loads a RapidTap or ChargeRelease ability whose thresholdTime is 0
//// (`genesis_prime/game/spell_plan`). Expected values come from these places.
//// - ResolveProxyByCasterApply `0x1403d3520`: the press walks the ability's effects in
////   row order, skips every row that is not a Proxy or whose caster apply prerequisite is
////   0 (`0x1403d35c3`), and takes the dataBits00 spell of the first whose caster apply
////   passes; with none, ResolveThresholdSpell `0x1403bfd60` returns the press's own spell,
////   which the 285 test refuses (facts `cast.proxy_press`).
//// - FindSpell `0x1403acd90`: the Proxy's spell is looked up by its Spell4 id in the
////   registry built from the tables, and fails only for a Spell4 id with no row.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects 96985 96992
////   96993 56164`, `-- Spell4 42603 1421 30646`):
////   - Spell4 42603: castMethod 6 (RapidTap) on Spell4Base 26793, thresholdTime 0, the
////     Proxy rows 96985 (orderIndex 0, dataBits00 42604, caster apply 16450), 96992
////     (orderIndex 1, 42605, 16451) and 96993 (orderIndex 2, 42606, 16452), each gate a
////     type 59 condition on Spell4 42607.
////   - Spell4 1421: castMethod 6, thresholdTime 0, no Proxy row.
////   - Spell4 30646: castMethod 7 (ChargeRelease), thresholdTime 0, one Proxy row, 56164,
////     whose caster apply is 0.
//// - `prerequisite.press_unread_types`: a press gate whose check draws a roll (type 37)
////   or reads the unit the press names second (types 50, 108 and 130) is refused at load,
////   as an undecoded gate is (`Prerequisite.prerequisiteTypeId`).

import client_tables
import fixture_tables
import genesis_prime/game/spell_plan.{type PlanError, type Spell}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import owned_test
import planted_table
import unitest

/// The client's spell `spell4_id` as the plan loads an ability.
fn ability_of(
  tables tables: store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Spell, PlanError) {
  spell_plan.ability_alone(
    tables:,
    sources: spell_plan.sources_of(tables:),
    spell4_id:,
  )
}

pub fn threshold_spell_with_no_threshold_time_loads_as_a_proxy_press_only_when_a_proxy_is_gated_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let assert Ok(press) = ability_of(tables:, spell4_id: 42_603)
    as "42603 plans as an ability: its Proxies are gated on the caster"
  assert list.map(press.press_proxies, fn(proxy) {
      #(proxy.effect_id, proxy.spell.spell4_id)
    })
    == [
      #(Spell4EffectsId(96_985), Spell4Id(42_604)),
      #(Spell4EffectsId(96_992), Spell4Id(42_605)),
      #(Spell4EffectsId(96_993), Spell4Id(42_606)),
    ]
    as "the press holds the three gated Proxies of Spell4Effects 96985, 96992 and 96993 in row order (orderIndex 0, 1 and 2), each with the spell its dataBits00 names (0x1403d3520)"
  let assert Error(rapid_tap) = ability_of(tables:, spell4_id: 1421)
    as "1421 holds no Proxy"
  assert rapid_tap == spell_plan.NoThresholdTime(spell4_id: 1421)
    as "a RapidTap spell with thresholdTime 0 and no Proxy is refused as before (0x1403bfd60)"
  let assert Error(charge_release) = ability_of(tables:, spell4_id: 30_646)
    as "30646 holds only a Proxy with no caster apply"
  assert charge_release == spell_plan.NoThresholdTime(spell4_id: 30_646)
    as "a ChargeRelease spell whose only Proxy has caster apply 0 is refused as before: the press skips that row (0x1403d35c3)"
}

pub fn proxy_press_whose_proxy_spell_cannot_be_planned_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let missing = 400_000
  // Kept edit: Spell4Effects 96992, the Proxy of 42603 gated by 16451, made to name a
  // Spell4 id that has no row.
  fixture_tables.changed(
    table: "Spell4Effects",
    id: 96_992,
    with: [#("dataBits00", planted_table.Integer(missing))],
    body: fn(tables) {
      assert ability_of(tables:, spell4_id: 42_603)
        == Error(spell_plan.NoRow(table: "Spell4", id: missing))
        as "FindSpell 0x1403acd90 fails for a Spell4 id with no row, and the client then casts no Proxy; the load refuses the row so that path cannot be reached at run time"
    },
  )
}

pub fn proxy_press_gate_holding_a_condition_type_the_server_does_not_read_is_refused_at_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 16451, the caster apply gate of Proxy row 96992, made a
  // condition of type 102, the type of Prerequisite 11196 and 11197 (Spell4Effects 69198
  // and 69199), which `Prerequisite.prerequisiteTypeId0` names and no decoder reads.
  fixture_tables.changed(
    table: "Prerequisite",
    id: 16_451,
    with: [#("prerequisiteTypeId0", planted_table.Integer(102))],
    body: fn(tables) {
      assert ability_of(tables:, spell4_id: 42_603)
        == Error(spell_plan.ApplyPrerequisiteNotRead(
          spell4_id: 42_603,
          effect_id: 96_992,
          prerequisite_type: 102,
        ))
        as "a gate holding a type no decoder reads is refused at load, as every apply gate is, not skipped at run time"
    },
  )
}

pub fn proxy_press_gate_that_needs_a_roll_or_the_second_unit_is_refused_at_load_test() -> Nil {
  use <- owned_test.run(60_000)
  [37, 130]
  |> list.each(fn(type_id) {
    // Kept edit: Prerequisite 16451, the caster apply gate of Proxy row 96992, made a
    // condition of type 37 (a roll) and then of type 130 (the second unit's groups).
    fixture_tables.changed(
      table: "Prerequisite",
      id: 16_451,
      with: [#("prerequisiteTypeId0", planted_table.Integer(type_id))],
      body: fn(tables) {
        let result = ability_of(tables:, spell4_id: 42_603)
        assert result
          == Error(spell_plan.ApplyPrerequisiteNotRead(
            spell4_id: 42_603,
            effect_id: 96_992,
            prerequisite_type: type_id,
          ))
          as "the refusal an undecoded gate gets, naming the spell, the Proxy row and the type"
        let assert Error(error) = result
        let text = spell_plan.describe(error:)
        assert string.contains(text, int.to_string(type_id))
          && string.ends_with(text, "which is not decoded")
          as "the text names the type and says it is not decoded, with no issue"
      },
    )
  })
}

// Reads the client's own tables, so the test runs alone in the client-suite part of
// `./check` (tag `client_rows`).
pub fn every_press_spell_of_the_client_plans_but_the_two_the_plan_cannot_read_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.tag("client_rows")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let #(planned, refused) =
    spell_plan.press_spell_ids(tables:, sources:)
    |> list.map(fn(spell4_id) {
      ability_of(tables:, spell4_id:)
      |> result.map_error(fn(error) { #(spell4_id, error) })
    })
    |> result.partition
  assert list.length(planned) == 38
    as "38 of the client's press spells (a RapidTap or ChargeRelease spell with thresholdTime 0 and a gated Proxy row) plan as an ability"
  assert list.sort(refused, fn(a, b) { int.compare(a.0, b.0) })
    == [
      #(
        34_759,
        spell_plan.ApplyPrerequisiteNotRead(
          spell4_id: 34_759,
          effect_id: 69_198,
          prerequisite_type: 102,
        ),
      ),
      #(76_511, spell_plan.NoRow(table: "Spell4Base", id: 76_506)),
    ]
    as "Spell4 34759 is refused for the type 102 gate (Prerequisite 11196) of its Proxy row 69198, which no decoder reads; were it read, its child 34760 is refused for row 69200, aimed by flag 5. Spell4 76511 is refused for the Spell4Base row 76506 its tree names, which the client's table does not hold"
}
