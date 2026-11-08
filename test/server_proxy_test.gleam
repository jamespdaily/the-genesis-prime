//// The server's Proxies (`genesis_prime/game/server_proxy`): the row of the server_proxy
//// table turned into a Proxy of the ability's tree, and every way a row is refused.
//// Expected values come from these places, each named at its assertion:
//// - The client's rows: `Spell4.42148` (95337: +15 of vital 6 behind prerequisite 903),
////   Pulse Blast 42276 (gos at 0 and 1250 ms, SpellPhase 5390 and 5391; Proxy 95881 to
////   37302 at its second go), the damage spell 37302 (gos at 0, 1, 2 and 3 ms,
////   SpellPhase 2820 to 2823) and Telekinetic Strike 32893 (one go, a Proxy to 30900 aimed
////   at the area).
//// - Migration 0018's seed row (26468, go 1, 42148), a server choice (Jim, issue 419).
//// - The content refusal pattern (`genesis_prime/content/refusal`): a table, a key and a rule.

import fixture_tables
import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/server_proxy.{Row}
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/loader/store
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables

/// The seed row.
fn seed() -> server_proxy.Row {
  spell_tables.volatility_row()
}

/// The Pulse Blast tree of these plans.
fn pulse_blast(plans: Plans) -> Spell {
  let assert Ok(spell) = spell_plan.in_plans(plans:, base: Spell4BaseId(26_468))
    as "the plans hold Pulse Blast"
  spell
}

/// The only Proxy of the Pulse Blast tree, which starts the damage spell 37302.
fn striking_proxy(plans: Plans) -> spell_plan.Proxy {
  let assert [proxy] = pulse_blast(plans).proxies
    as "Pulse Blast has one Proxy, 95881 to 37302"
  proxy
}

/// The plans of the tables with the rows selected and planted, or the refusals.
fn planted_on(
  tables tables: store.Tables,
  rows rows: List(server_proxy.Row),
) -> Result(Plans, List(Refusal)) {
  let assert Ok(plans) = spell_plan.build(tables:)
    as "the fixture's rows build the plans"
  server_proxy.select(rows:, tables:, plans:)
  |> result.map(fn(proxies) { server_proxy.planted_into(plans:, proxies:) })
}

/// The same on the client's rows.
fn planted_by(
  rows rows: List(server_proxy.Row),
) -> Result(Plans, List(Refusal)) {
  planted_on(tables: fixture_tables.shared(), rows:)
}

// ---- 1 ----

pub fn the_seed_row_plants_42148_into_the_damage_spell_at_its_last_go_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(plans) = planted_by(rows: [seed()])
  let host = striking_proxy(plans)
  assert host.spell.spell4_id == id.Spell4Id(37_302)
    && host.phase_flags == 2
    && host.delay_ms == 0
    as "Pulse Blast's own Proxy 95881 to 37302 is as the client's rows have it (phaseFlags 2)"
  let assert [planted] = host.spell.proxies
    as "the damage spell holds only the server's Proxy: 37302 has no Proxy of its own"
  assert planted.spell.spell4_id == id.Spell4Id(42_148)
    as "the spell the row names"
  assert planted.phase_flags == 8
    as "37302 goes four times, 1 ms apart (SpellPhase 2820 to 2823), so its last go is phase 3, bit 8"
  assert planted.delay_ms == 0 && planted.condition == spell_plan.Always
    as "a Proxy of the server's starts at once, with no gate of its own"
  assert planted.target == spell_plan.OnCaster
    as "42148 is cast on the caster: 95337 aims at it (targetFlags 1)"
  let assert [gain] = planted.spell.gains
    as "42148's one effect 95337 is a gain"
  let assert spell_plan.Gain(slot: 1, amount: 15, prerequisite: Some(..), ..) =
    gain
    as "+15 of vital 6, which is slot 1, behind prerequisite 903 (Spell4Effects 95337)"
  Nil
}

pub fn a_go_that_starts_no_spell_at_once_takes_the_proxy_itself_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [Row(spell4_base_id: 19_102, phase: 0, spell4_id: 42_148)]
  let assert Ok(plans) = planted_by(rows:)
  let assert Ok(strike) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(19_102))
    as "the plans hold Telekinetic Strike"
  let assert Ok(planted) = list.last(strike.proxies)
    as "the ability holds a Proxy after its own"
  assert planted.spell.spell4_id == id.Spell4Id(42_148)
    && planted.phase_flags == 1
    as "Telekinetic Strike's only Proxy is aimed at the area, so no spell starts at once on the caster: the Proxy is the ability's own, at its go 0"
  assert list.length(strike.proxies) == 2
    as "the ability's own Proxy 62204 stays"
}

pub fn a_base_with_no_row_keeps_its_tree_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(planted) = planted_by(rows: [seed()])
  let assert Ok(untouched) = planted_by(rows: [])
  assert dict.get(planted, 19_102) == dict.get(untouched, 19_102)
    as "a base no row names is the client's tree"
  assert dict.get(planted, 26_468) != dict.get(untouched, 26_468)
    as "the base the row names holds the Proxy"
}

// ---- 10, 11, 12 ----

fn refused_on(
  tables tables: store.Tables,
  rows rows: List(server_proxy.Row),
) -> List(Refusal) {
  let assert Error(refusals) = planted_on(tables:, rows:)
    as "the rows are refused"
  refusals
}

fn refused_by(rows rows: List(server_proxy.Row)) -> List(Refusal) {
  refused_on(tables: fixture_tables.shared(), rows:)
}

fn keys_of(refusals: List(Refusal)) -> List(String) {
  list.map(refusals, fn(refused) {
    let assert Refusal(table: "server_proxy", row: RowName(name), ..) = refused
      as "a server_proxy row is refused by its key"
    name
  })
}

pub fn a_row_whose_base_has_no_plan_is_refused_naming_the_table_and_the_key_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusals =
    refused_by(rows: [Row(spell4_base_id: 99_999, phase: 0, spell4_id: 42_148)])
  assert keys_of(refusals) == ["99999 0 42148"]
  let assert [Refusal(rule:, ..)] = refusals
  assert string.contains(rule, "no plan")
    as "a base that is not a level-1 ability or an innate has no plan (spell_plan `Plans`)"
}

pub fn a_row_whose_phase_is_not_a_go_of_the_plan_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusals =
    refused_by(rows: [
      Row(spell4_base_id: 26_468, phase: 2, spell4_id: 42_148),
      Row(spell4_base_id: 26_468, phase: -1, spell4_id: 42_148),
    ])
  assert keys_of(refusals) == ["26468 2 42148", "26468 -1 42148"]
    as "Pulse Blast goes at 0 and 1250 ms (SpellPhase 5390 and 5391): phase 2 and phase -1 are no go"
  let assert [Refusal(rule:, ..), ..] = refusals
  assert string.contains(rule, "which goes 2 times")
}

pub fn a_row_whose_spell_has_no_row_or_whose_tree_fails_is_refused_with_the_plans_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let missing =
    refused_by(rows: [Row(spell4_base_id: 26_468, phase: 1, spell4_id: 99_999)])
  let assert [Refusal(rule: missing_rule, ..)] = missing
  assert string.contains(missing_rule, "the table Spell4 has no row 99999")
    as "the plan's own reason for a Spell4 the tables lack (spell_plan `NoRow`)"
  // Edge cases no client row holds: a gain of 42148 aimed at another unit, and a
  // spell of 42148 that leads back to Pulse Blast. Each is a copy of 42148's own
  // effect 95337 with the cells that make the case.
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 95_337,
    id: 95_338,
    with: [#("targetFlags", Integer(4))],
    body: fn(tables) {
      let failed = refused_on(tables:, rows: [seed()])
      let assert [Refusal(rule: failed_rule, ..)] = failed
      assert string.contains(failed_rule, "VitalModifier effect 95338")
        && string.contains(failed_rule, "only one aimed at the caster is read")
        as "a gain aimed at another unit is not read, for the plan's own reason (spell_plan `GainAimNotRead`)"
    },
  )
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 95_337,
    id: 95_339,
    with: [
      #("effectType", Integer(26)),
      #("dataBits00", Integer(42_276)),
    ],
    body: fn(tables) {
      let cycle = refused_on(tables:, rows: [seed()])
      let assert [Refusal(rule: cycle_rule, ..)] = cycle
      assert string.contains(cycle_rule, "42276 -> 37302 -> 42148 -> 42276")
        as "a spell that leads back to the ability fails as a cycle, the chain running through the spell that strikes"
    },
  )
}

pub fn every_refused_row_is_named_together_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusals =
    refused_by(rows: [
      Row(spell4_base_id: 99_999, phase: 0, spell4_id: 42_148),
      seed(),
      Row(spell4_base_id: 26_468, phase: 7, spell4_id: 42_148),
    ])
  assert keys_of(refusals) == ["99999 0 42148", "26468 7 42148"]
    as "the good row is not named; both bad rows are, in the order of the rows"
}
