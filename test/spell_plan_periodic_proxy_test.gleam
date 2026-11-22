//// A Proxy effect (`Spell4Effects.effectType.26`) with a tickTime, which the plan reads as a
//// cast of its named spell at each tick (`genesis_prime/game/spell_plan`). Expected values
//// come from these places:
//// - `Spell4Effects.effectType.26.periodic`: the client gives a Proxy no behaviour, so its
////   name is the rows': dataBits00, else dataBits01 when that is a Spell4 row (of 1,808 rows
////   with dataBits00 0, 1,701 name a Spell4 row and 107 do not), and a tickTime and a
////   durationTime give its ticks as every periodic row's (`ticking.schedule_of`).
//// - Texts 504979 (Spectral Form: "generate 1 Psi Point every 1s for 5s"), 311216 (Plasma
////   Wall: "every 0.5s") and 245408 (Mental Boon heals "every 0.5 s", the heal sitting only
////   in 33258, which only the tick-0 Proxy 76609 names).
//// - Rows read with `table_rows -- Spell4Effects 121345 178429 85298 228473 141450 210304
////   210337 217944 76609`.

import client_tables
import fixture_tables
import genesis_prime/game/effect_row_read
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  Applied, LeftOut, ProxyNamesNoSpell, ReadProxy,
}
import genesis_prime/game/ticking.{Schedule}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import owned_test
import spell_tables
import unitest

/// A Proxy row aimed at the caster that names `named` in dataBits00 and `second` in dataBits01.
fn proxy_row(
  id id: Int,
  named named: Int,
  second second: Int,
) -> Spell4Effects {
  Spell4Effects(
    ..spell_tables.blank_effect(
      id:,
      spell: 90_100,
      effect_type: 26,
      target_flags: 1,
    ),
    data_bits00: named,
    data_bits01: second,
  )
}

fn client_row(tables tables: store.Tables, id id: Int) -> Spell4Effects {
  let assert Ok(row) = spell4_effects.get(tables:, id: id.Spell4EffectsId(id))
    as "the client's table holds the row"
  row
}

pub fn a_proxy_names_its_spell_in_data_bits00_else_in_data_bits01_and_a_name_with_no_spell4_row_names_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let missing = 4_000_000
  assert spell4.get(tables:, id: Spell4Id(missing)) == Error(Nil)
    as "the Spell4 table has no row 4,000,000"
  assert spell4.get(tables:, id: Spell4Id(71_371)) != Error(Nil)
    as "the Spell4 table has the row 71371, which row 121345 names"
  let rows = [
    #(proxy_row(id: 999_001, named: 71_371, second: 0), 71_371),
    #(proxy_row(id: 999_002, named: 0, second: 71_371), 71_371),
    #(proxy_row(id: 999_003, named: 0, second: 0), 0),
    #(proxy_row(id: 999_004, named: 0, second: missing), 0),
  ]
  list.each(rows, fn(case_) {
    let #(row, named) = case_
    assert spell_plan.proxy_named(tables:, effect: row) == named
      as "dataBits00 names the spell, else dataBits01 when the Spell4 table has that row, else nothing"
  })
  let readings =
    spell_tables.read_rows(
      effects: list.map(rows, fn(case_) { case_.0 }),
      place: spell_tables.pressed,
    )
  assert readings
    == [
      Ok(
        Applied(ReadProxy(
          targets: [spell_plan.OnCaster],
          condition: spell_plan.Always,
          period: None,
        )),
      ),
      Ok(
        Applied(ReadProxy(
          targets: [spell_plan.OnCaster],
          condition: spell_plan.Always,
          period: None,
        )),
      ),
      Ok(LeftOut(why: ProxyNamesNoSpell)),
      Ok(LeftOut(why: ProxyNamesNoSpell)),
    ]
    as "a row that names a Spell4 row in either column is read, one that names none is left out and the load goes on"
}

pub fn every_reader_of_a_proxys_child_takes_the_public_proxy_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let stance = client_row(tables:, id: 121_345)
  assert stance.data_bits00 == 0 && stance.data_bits01 == 71_371
    as "Spell4Effects 121345 (`table_rows -- Spell4Effects 121345`) names 71371 in dataBits01 and nothing in dataBits00"
  assert spell_plan.proxy_named(tables:, effect: stance) == 71_371
  assert spell_plan.is_child(sources:, spell4_id: 71_371)
    as "a spell a Proxy names in dataBits01 is a child (`is_child`)"
  assert !spell_plan.is_child(sources:, spell4_id: 47_866)
    as "the Engineer's ability, which no Proxy names, is not"
  let area_proxy =
    Spell4Effects(
      ..proxy_row(id: 999_005, named: 0, second: 71_371),
      spell_id: 57_685,
      target_flags: 4,
    )
  assert dict.to_list(
      spell_plan.struck_unit_children(tables:, effects: [
        area_proxy,
      ]),
    )
    == [
      #(
        71_371,
        spell_plan.StruckBy(spell4_id: 57_685, proxy_effect_id: 999_005),
      ),
    ]
    as "a Proxy aimed at the area that names its spell in dataBits01 starts it on each struck unit, as one that names it in dataBits00 does (`struck_unit_children`)"
  let assert Ok(engineer) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(31_779),
    )
    as "the plans hold the Engineer's innate, base 31779"
  assert list.contains(
    list.map(
      spell_plan.tree(spell: engineer, started: fn(_) { True }),
      fn(member) { member.spell4_id.value },
    ),
    71_371,
  )
    as "the tree of Spell4 47866 holds 71371, which the periodic Proxy 121345 starts (`tree`)"
}

pub fn a_timed_periodic_proxy_on_the_caster_reads_as_the_schedule_of_its_row_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  // Each row, the spell that holds it, and its schedule: delay, tickTime, durationTime and
  // the whole ticks in the durationTime (`table_rows -- Spell4Effects <id>`).
  let cases = [
    #(
      121_345,
      47_860,
      Schedule(delay_ms: 1, tick_ms: 1000, duration_ms: 10_000, count: 10),
    ),
    #(
      178_429,
      70_369,
      Schedule(delay_ms: 0, tick_ms: 1000, duration_ms: 5000, count: 5),
    ),
    #(
      85_298,
      39_180,
      Schedule(delay_ms: 0, tick_ms: 1000, duration_ms: 5050, count: 5),
    ),
    #(
      228_473,
      38_787,
      Schedule(delay_ms: 0, tick_ms: 500, duration_ms: 5000, count: 10),
    ),
  ]
  list.each(cases, fn(case_) {
    let #(row_id, holder, schedule) = case_
    let row = client_row(tables:, id: row_id)
    let place_of =
      effect_row_read.places(tables:, effects: spell4_effects.all(tables))
    let assert Ok(Applied(ReadProxy(targets:, period:, ..))) =
      spell_plan.read_row(
        tables:,
        sources:,
        place: place_of(holder),
        effect: row,
      )
      as "a timed Proxy aimed at the caster is read"
    assert targets == [spell_plan.OnCaster]
      as "targetFlags 1 casts on the caster"
    assert period == Some(spell_plan.Periodic(schedule:, persistence: None))
      as "the schedule of the row: tick k lands delay plus k times tickTime, for durationTime over tickTime ticks (texts 504979 and 311216)"
    let assert Ok(spell) =
      spell_plan.spell_alone(tables:, sources:, spell4_id: holder, chain: [])
      as "the holder plans alone"
    let assert [proxy] =
      list.filter(
        spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy),
        fn(proxy) { proxy.effect_id.value == row_id },
      )
      as "the holder's plan holds the Proxy of the row once"
    assert proxy.delay_ms == 0
      && proxy.period == Some(spell_plan.Periodic(schedule:, persistence: None))
      as "the row's delay is the schedule's, not a wait before the cast"
  })
}

pub fn a_proxy_with_no_tick_time_reads_as_a_once_proxy_whatever_column_names_its_spell_test() -> Nil {
  use <- owned_test.run(60_000)
  // The real row 76609 has targetFlags 5 in 36562, a spell that hits no foes, which start the
  // child on the caster alone; the twins have targetFlags 1, the caster.
  let readings =
    spell_tables.read_rows(
      effects: [
        proxy_row(id: 999_006, named: 0, second: 33_258),
        proxy_row(id: 999_007, named: 33_258, second: 0),
      ],
      place: spell_tables.pressed,
    )
  assert readings
    == [
      Ok(
        Applied(ReadProxy(
          targets: [spell_plan.OnCaster],
          condition: spell_plan.Always,
          period: None,
        )),
      ),
      Ok(
        Applied(ReadProxy(
          targets: [spell_plan.OnCaster],
          condition: spell_plan.Always,
          period: None,
        )),
      ),
    ]
    as "text 245408: Mental Boon heals every 0.5 s and the heal sits only in 33258, which only a Proxy with no tickTime names, so such a row casts once, whichever column names its spell"
}

pub fn a_periodic_proxy_aimed_at_the_area_or_left_until_removed_is_left_out_by_name_and_its_ability_stays_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  let cases = [
    #(141_450, spell_plan.PeriodicProxyOnAreaNotRead),
    #(210_304, spell_plan.PeriodicProxyUntilRemovedNotRead),
    #(210_337, spell_plan.PeriodicProxyUntilRemovedNotRead),
    #(217_944, spell_plan.PeriodicProxyUntilRemovedNotRead),
  ]
  list.each(cases, fn(case_) {
    let #(row_id, why) = case_
    let row = client_row(tables:, id: row_id)
    assert spell_plan.read_row(
        tables:,
        sources:,
        place: place_of(row.spell_id),
        effect: row,
      )
      == Ok(LeftOut(why:))
      as "a periodic Proxy aimed at the area is left out first (the area check comes before the life), one left until removed (flags bit 2) by its own name, and none reads as a once Proxy nor fails the load"
  })
  let plans = spell_plan.plans_with_later(tables:)
  let assert Ok(unplanned) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  list.each([70_757, 46_935], fn(ability) {
    assert list.any(dict.values(plans), fn(spell) {
      spell.spell4_id == Spell4Id(ability)
    })
      as "Nullifier 70757 and Augmented Blade 46935 are planned on main and stay planned"
    assert !list.any(unplanned, fn(one) { one.spell4_id == ability })
      as "and are not listed unplanned"
  })
}
