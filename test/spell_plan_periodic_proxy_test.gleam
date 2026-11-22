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
//// - `Spell4Effects.effectType.26.periodic`: a row with flags bit 2 and a tickTime ticks
////   every tickTime until its cast's node ends, so the plan reads it with an open schedule
////   when it is aimed at the caster (targetFlags 1 or 2) and leaves the area rows out. The
////   counts are the client's rows read by `table_rows -- Spell4Effects`: 829 rows with flags
////   bit 2, a tickTime and a named spell, of which 268 are aimed at the area and 561 at the
////   caster, and 2 that name no spell.
//// - `Spell4Effects.prerequisiteIdCasterApply`: the client reads no effect row's persistence
////   columns, so a periodic Proxy's caster persistence is the row's column as it stands
////   (Prerequisite 903, type 28: the caster in combat) and its target persistence is read by no
////   rule. Row 903 is `table_rows -- Prerequisite 903`: type 28, comparison 1, objectId 0 and
////   value 0, which `Prerequisite.prerequisiteTypeId.28` passes for a unit in combat.

import client_tables
import fixture_tables
import genesis_prime/game/effect_row_read
import genesis_prime/game/prerequisite.{Fails, Passes, Subject}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  Applied, LeftOut, ProxyNamesNoSpell, ReadProxy,
}
import genesis_prime/game/ticking.{Schedule, Ticks}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table
import prerequisite_support
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
      Schedule(
        delay_ms: 1,
        tick_ms: 1000,
        duration_ms: 10_000,
        count: Ticks(10),
      ),
    ),
    #(
      178_429,
      70_369,
      Schedule(delay_ms: 0, tick_ms: 1000, duration_ms: 5000, count: Ticks(5)),
    ),
    #(
      85_298,
      39_180,
      Schedule(delay_ms: 0, tick_ms: 1000, duration_ms: 5050, count: Ticks(5)),
    ),
    #(
      228_473,
      38_787,
      Schedule(delay_ms: 0, tick_ms: 500, duration_ms: 5000, count: Ticks(10)),
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

/// The reading of the client's row `row_id` as the plan reads it.
fn reading_of_client_row(
  tables tables: store.Tables,
  row_id row_id: Int,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  let row = client_row(tables:, id: row_id)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  spell_plan.read_row(
    tables:,
    sources: spell_plan.sources_of(tables:),
    place: place_of(row.spell_id),
    effect: row,
  )
}

pub fn every_until_removed_periodic_proxy_aimed_at_the_caster_reads_as_an_open_schedule_and_the_area_ones_stay_left_out_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  let sources = spell_plan.sources_of(tables:)
  let open_rows =
    list.filter(spell4_effects.all(tables), fn(row) {
      row.effect_type == 26
      && int.bitwise_and(row.flags, 2) != 0
      && row.tick_time > 0
    })
  let reading_of = fn(row: Spell4Effects) {
    spell_plan.read_row(
      tables:,
      sources:,
      place: place_of(row.spell_id),
      effect: row,
    )
  }
  let named = fn(row) { spell_plan.proxy_named(tables:, effect: row) != 0 }
  // The rows that name a spell and are aimed at the caster (targetFlags 1 or 2), the rows
  // aimed at the area (4 or 6), and the rows that name none (`table_rows -- Spell4Effects`).
  let at_the_caster =
    list.filter(open_rows, fn(row) {
      named(row) && { row.target_flags == 1 || row.target_flags == 2 }
    })
  let at_the_area =
    list.filter(open_rows, fn(row) {
      named(row) && { row.target_flags == 4 || row.target_flags == 6 }
    })
  let naming_none = list.filter(open_rows, fn(row) { !named(row) })
  assert list.length(at_the_caster) == 561
    && list.length(at_the_area) == 268
    && list.length(naming_none) == 2
    && list.length(open_rows)
    == list.length(at_the_caster)
    + list.length(at_the_area)
    + list.length(naming_none)
    as "the client's until-removed periodic Proxies: 561 aimed at the caster (465 by 1 and 96 by 2), 268 at the area, and 2 that name no spell, which together are every one"
  list.each(at_the_caster, fn(row) {
    let assert Ok(Applied(ReadProxy(period: Some(periodic), ..))) =
      reading_of(row)
      as "an until-removed periodic Proxy aimed at the caster is applied as a periodic Proxy, never held and never an error"
    assert periodic.schedule.count == ticking.UntilTheNodeEnds
      && periodic.schedule.tick_ms == row.tick_time
      && periodic.schedule.delay_ms == row.delay_time
      as "its schedule is open, with the row's delay and tickTime"
    assert option.is_some(periodic.persistence)
      == { row.prerequisite_id_caster_persistence != 0 }
      as "its persistence is held exactly where the row's caster persistence column is set"
  })
  assert list.count(at_the_caster, fn(row) {
      row.prerequisite_id_caster_persistence != 0
    })
    == 33
    as "33 of the 561 rows hold a caster persistence"
  list.each(at_the_area, fn(row) {
    assert reading_of(row)
      == Ok(LeftOut(why: spell_plan.PeriodicProxyOnAreaNotRead))
      as "an until-removed periodic Proxy aimed at the area is left out by name"
  })
  list.each(naming_none, fn(row) {
    assert reading_of(row) == Ok(LeftOut(why: ProxyNamesNoSpell))
      as "one that names no spell is left out as any Proxy that names none"
  })
  // The named rows: Augmented Blade's stack maker 210304 (tickTime 1000 after a delay of
  // 1000), the stack's own drain 210337 (tickTime 250, gated by Prerequisite 43748, not
  // under Overdrive) and the removal 217944 (tickTime 500, persistence Prerequisite 38758).
  let open = fn(delay_ms, tick_ms) {
    Schedule(
      delay_ms:,
      tick_ms:,
      duration_ms: 0,
      count: ticking.UntilTheNodeEnds,
    )
  }
  let cases = [
    #(
      210_304,
      open(1000, 1000),
      spell_plan.Always,
      None,
      "the stack maker has no gate and no persistence",
    ),
    #(
      210_337,
      open(0, 250),
      spell_plan.GatedOnCaster(gates: [
        prerequisite_support.fixture_row(row: 43_748),
      ]),
      None,
      "the drain is gated by the prerequisite its dataBits06 names",
    ),
    #(
      217_944,
      open(0, 500),
      spell_plan.Always,
      Some(prerequisite_support.fixture_row(row: 38_758)),
      "the removal holds the persistence its row names",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(row_id, schedule, condition, persistence, reason) = case_
    assert reading_of_client_row(tables:, row_id:)
      == Ok(
        Applied(ReadProxy(
          targets: [spell_plan.OnCaster],
          condition:,
          period: Some(spell_plan.Periodic(schedule:, persistence:)),
        )),
      )
      as reason
  })
  assert reading_of_client_row(tables:, row_id: 141_450)
    == Ok(LeftOut(why: spell_plan.PeriodicProxyOnAreaNotRead))
    as "the area row 141450 is left out by name"
  let plans = spell_plan.plans_with_later(tables:)
  let assert Ok(unplanned) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  list.each([70_757, 46_935], fn(ability) {
    assert list.any(dict.values(plans), fn(spell) {
      spell.spell4_id == Spell4Id(ability)
    })
      as "Nullifier 70757 and Augmented Blade 46935 are planned"
    assert !list.any(unplanned, fn(one) { one.spell4_id == ability })
      as "and are not listed unplanned"
  })
}

/// The verdicts of the persistence for a caster in combat and one out of it.
fn in_and_out_of_combat(
  persistence persistence: prerequisite.Prerequisite,
) -> #(prerequisite.Verdict, prerequisite.Verdict) {
  let verdict = fn(in_combat) {
    prerequisite.check(
      prerequisite: persistence,
      subject: Subject(
        ..prerequisite_support.holding(held: [], second_unit: Some(7)),
        in_combat:,
      ),
    )
  }
  #(verdict(True), verdict(False))
}

pub fn a_periodic_proxys_caster_persistence_is_read_from_its_row_and_a_target_persistence_is_not_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each case plants one row of the fixture, the timed periodic Proxy 121345: the cells it
  // changes and the persistence the read Proxy holds.
  let cases = [
    #(
      "a caster persistence of Prerequisite 903 is the row's persistence",
      [#("prerequisiteIdCasterPersistence", planted_table.Integer(903))],
      Some(prerequisite_support.fixture_row(row: 903)),
    ),
    #(
      "no caster persistence is none",
      [#("prerequisiteIdCasterPersistence", planted_table.Integer(0))],
      None,
    ),
    #(
      "a target persistence alone is read by no rule, so the Proxy holds none",
      [
        #("prerequisiteIdCasterPersistence", planted_table.Integer(0)),
        #("prerequisiteIdTargetPersistence", planted_table.Integer(903)),
      ],
      None,
    ),
  ]
  list.each(cases, fn(case_) {
    let #(reason, cells, expected) = case_
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 121_345,
      with: cells,
      body: fn(tables) {
        let sources = spell_plan.sources_of(tables:)
        let row = client_row(tables:, id: 121_345)
        let place_of =
          effect_row_read.places(tables:, effects: spell4_effects.all(tables))
        let assert Ok(Applied(ReadProxy(period: Some(periodic), ..))) =
          spell_plan.read_row(
            tables:,
            sources:,
            place: place_of(row.spell_id),
            effect: row,
          )
          as "the timed periodic Proxy aimed at the caster is read"
        assert periodic.persistence == expected as reason
        case periodic.persistence {
          Some(persistence) -> {
            assert in_and_out_of_combat(persistence:) == #(Passes, Fails)
              as "the persistence the plan holds is row 903 as the client has it: a caster in combat passes it and one out of combat fails it"
          }
          None -> Nil
        }
        assert periodic.schedule
          == Schedule(
            delay_ms: 1,
            tick_ms: 1000,
            duration_ms: 10_000,
            count: Ticks(10),
          )
          as "the schedule is the row's whatever its persistence"
      },
    )
  })
}
