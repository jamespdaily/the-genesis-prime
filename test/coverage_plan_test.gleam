//// The effect measure counts an effect row as read exactly when the plan loads it
//// (`genesis_prime/shared/spell_plan.read_row`), on the client's tables. A test here counts
//// the rows of a type from the client alone, or takes each row of a type through the
//// plan and checks the reading the row's own columns give it; how many rows the plan
//// leaves out is the coverage run's number, not a test's.
//// - `Spell4Effects.effectType.26.periodic`: a Proxy that names no Spell4 row is left out;
////   one that ticks on the area for allies, or is aimed by a flag with bit 8, is refused.
//// - `Spell4Effects.effectType.15` and `.97`: the columns that decide each reason.

import client_tables
import coverage_support
import genesis_prime/coverage/engine
import genesis_prime/coverage/gaps
import genesis_prime/coverage/measurement.{HandledWithGap}
import genesis_prime/game/effect_row_read
import genesis_prime/shared/activate
import genesis_prime/shared/spell_plan
import genesis_prime/table/id
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import genesis_prime/table/spell4_target_mechanics
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import spell_tables
import unitest

/// Whether a Proxy row names no Spell4 row: its dataBits00 is 0 and its dataBits01 is 0 or
/// an id the table lacks (`Spell4Effects.effectType.26.periodic`).
fn proxy_names_no_spell(
  tables tables: store.Tables,
  row row: Spell4Effects,
) -> Bool {
  row.data_bits00 == 0
  && spell4.get(tables:, id: id.Spell4Id(row.data_bits01)) == Error(Nil)
}

/// Stops the test at a row whose reading no rule of the test names: the plan read or
/// refused it for a reason its columns do not give.
fn unexpected(
  row row: Spell4Effects,
  reading reading: Result(spell_plan.RowReading, spell_plan.PlanError),
) -> a {
  case reading {
    Error(error) ->
      panic as {
        "row "
        <> int.to_string(row.id)
        <> " is refused for a reason its columns do not give: "
        <> spell_plan.describe(error:)
      }
    Ok(..) ->
      panic as {
        "row "
        <> int.to_string(row.id)
        <> " is read in a way its columns do not give"
      }
  }
}

// ---- the rows and gaps of the client's types ----

pub fn the_clients_7185_crowd_control_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 4)
  assert line.rows == 7185
    as "table_rows -- Spell4Effects effectType=4: 7,185 rows"
}

pub fn the_clients_2049_gain_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 1)
  assert line.rows == 2049
    as "table_rows -- Spell4Effects effectType=1: 2,049 rows"
}

pub fn the_clients_29445_damage_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 8)
  assert line.rows == 29_445
    as "table_rows -- Spell4Effects effectType=8: 29,445 rows"
}

pub fn the_clients_4645_type_3_rows_count_with_a_stated_gap_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let line = coverage_support.partial_line("Spell effects", type_number: 3)
  assert line.rows == 4645
    as "table_rows -- Spell4Effects effectType=3: 4,645 rows"
  let assert HandledWithGap(reason:, fact_key:, ..) = line.status
  assert fact_key == "Spell4Effects.effectType.3"
  assert string.contains(
      reason,
      "aimed at another unit behind a target apply prerequisite",
    )
    && !string.contains(reason, "#")
    as "the gap names the rows still unread and no issue"
  assert !string.contains(reason, "bit 8")
    as "the rows aimed at other units are no longer the gap"
}

// ---- each row of a type is read, left out or refused for the reason its columns give ----

pub fn the_measure_counts_a_proxy_that_names_no_spell_or_is_for_allies_as_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let line = coverage_support.partial_line("Spell effects", type_number: 26)
  assert line.rows == 16_929
    as "table_rows -- Spell4Effects effectType=26: 16,929 rows"
  // A named spell is beneficial when its Spell4Base's target mechanic has flags bit 0
  // (`Spell4TargetMechanics.flags`), read here through the tables' own rows.
  let beneficial = fn(row: Spell4Effects) {
    let assert Ok(named) =
      spell4.get(
        tables:,
        id: id.Spell4Id(spell_plan.proxy_named(tables:, effect: row)),
      )
    let assert Ok(base) =
      spell4_base.get(
        tables:,
        id: id.Spell4BaseId(named.spell4_base_id_base_spell),
      )
    let assert Ok(mechanic) =
      spell4_target_mechanics.get(
        tables:,
        id: id.Spell4TargetMechanicsId(base.spell4_target_mechanic_id),
      )
    int.bitwise_and(mechanic.flags, 1) == 1
  }
  let classes =
    list.map(
      spell_tables.rows_read(tables: client_tables.shared(), effect_type: 26),
      fn(read) {
        let #(row, reading) = read
        case
          proxy_names_no_spell(tables:, row:),
          row.tick_time > 0 && list.contains([4, 6], row.target_flags),
          int.bitwise_and(row.target_flags, 8) != 0
        {
          True, _, _ -> {
            assert reading
              == Ok(spell_plan.LeftOut(why: spell_plan.ProxyNamesNoSpell))
              as {
                "row "
                <> int.to_string(row.id)
                <> " names no Spell4 row, so the plan leaves it out"
              }
            "names no spell"
          }
          False, True, _ ->
            case beneficial(row) {
              True -> {
                assert reading
                  == Error(spell_plan.PeriodicProxyAtAlliesNotRead(
                    spell4_id: row.spell_id,
                    effect_id: row.id,
                    named_spell4_id: spell_plan.proxy_named(
                      tables:,
                      effect: row,
                    ),
                  ))
                  as {
                    "row "
                    <> int.to_string(row.id)
                    <> " ticks on the area for allies, whom the server does not find, so the plan refuses it"
                  }
                "for allies"
              }
              False -> {
                let assert Ok(spell_plan.Applied(..)) = reading
                  as {
                    "row "
                    <> int.to_string(row.id)
                    <> " ticks on the foes in the area, so the plan reads it"
                  }
                "for foes"
              }
            }
          False, False, True -> {
            let assert Error(spell_plan.ProxyAimNotRead(
              effect_id:,
              target_flags:,
              ..,
            )) = reading
              as {
                "row "
                <> int.to_string(row.id)
                <> " is aimed by a flag with bit 8, which the plan refuses"
              }
            assert effect_id == row.id && target_flags == row.target_flags
            "aimed by bit 8"
          }
          False, False, False -> "another"
        }
      },
    )
  list.each(
    ["names no spell", "for allies", "for foes", "aimed by bit 8"],
    fn(class) {
      assert list.contains(classes, class)
        as { "the client holds a Proxy row of the class: " <> class }
    },
  )
  let not_read =
    list.count(
      spell_tables.rows_read(tables: client_tables.shared(), effect_type: 26),
      fn(read) {
        case read.1 {
          Ok(spell_plan.Applied(..)) -> False
          _ -> True
        }
      },
    )
  let assert HandledWithGap(unread_rows:, ..) = line.status
    as "type 26 is handled with a stated gap"
  assert unread_rows == not_read
    as "the measure counts a Proxy row as not read exactly when the plan does not apply it (a row that names no spell, one for allies, one aimed by a flag with bit 8 or one that starts tiers with no choice)"
  assert unread_rows
    >= list.count(classes, fn(class) {
      class == "names no spell"
      || class == "for allies"
      || class == "aimed by bit 8"
    })
    as "the rows of those classes are among the unread"
  assert line.starting_unread == 0
    as "no starting ability holds a Proxy row that is not read"
}

pub fn a_periodic_row_of_types_8_10_and_118_that_lasts_until_removed_is_not_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let effects = spell4_effects.all(tables)
  let place_of = effect_row_read.places(tables:, effects:)
  let until_removed =
    list.filter(effects, fn(row) {
      list.contains([8, 10, 118], row.effect_type)
      && row.tick_time > 0
      && int.bitwise_and(row.flags, 2) != 0
    })
  assert until_removed != []
    as "the client holds periodic rows of these types that last until removed (Spell4Effects.flags bit 2)"
  list.each(until_removed, fn(row) {
    assert !effect_row_read.is_read(
      tables:,
      sources:,
      place: place_of(row.spell_id),
      effect: row,
    )
      as {
        "row "
        <> int.to_string(row.id)
        <> " ticks until removed, which no schedule ends, so it is not read"
      }
  })
}

pub fn a_row_aimed_by_3_5_or_7_is_never_refused_for_its_aim_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows =
    list.flat_map([4, 8, 17, 18, 26, 80, 81], fn(type_number) {
      list.filter(
        spell_tables.rows_read(
          tables: client_tables.shared(),
          effect_type: type_number,
        ),
        fn(read) { list.contains([3, 5, 7], { read.0 }.target_flags) },
      )
    })
  assert rows != []
    as "the client holds rows of these types aimed by 3, 5 or 7 (the caster and other units)"
  list.each(rows, fn(read) {
    let #(row, reading) = read
    let refused_for_its_aim = case reading {
      Error(spell_plan.ProxyAimNotRead(target_flags:, ..))
      | Error(spell_plan.GainAimNotRead(target_flags:, ..))
      | Error(spell_plan.LastingAimNotRead(target_flags:, ..))
      | Error(spell_plan.ControlAimNotRead(target_flags:, ..)) ->
        list.contains([3, 5, 7], target_flags)
      _ -> False
    }
    assert !refused_for_its_aim
      as {
        "row "
        <> int.to_string(row.id)
        <> " aimed by "
        <> int.to_string(row.target_flags)
        <> " is refused for its aim"
      }
    case reading {
      Error(spell_plan.FriendlyAreaNotRead(..)) -> {
        assert list.contains([17, 18, 80, 81], row.effect_type)
          as {
            "row "
            <> int.to_string(row.id)
            <> " of type "
            <> int.to_string(row.effect_type)
            <> " is refused for a friendly area; only the kinds that keep a state on the area's units are"
          }
      }
      _ -> Nil
    }
    case row.effect_type == 26 && proxy_names_no_spell(tables:, row:) {
      True -> {
        assert reading
          == Ok(spell_plan.LeftOut(why: spell_plan.ProxyNamesNoSpell))
          as "a union Proxy that names no Spell4 row is left out for that"
      }
      False -> Nil
    }
  })
}

pub fn type_97_rows_are_each_read_left_out_or_refused_by_name_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let rows =
    spell_tables.rows_read(tables: client_tables.shared(), effect_type: 97)
  assert list.length(rows) == 855
    as "table_rows -- Spell4Effects effectType=97: 855 rows"
  list.each(rows, fn(read) {
    let #(row, reading) = read
    case reading {
      Ok(spell_plan.LeftOut(why:)) -> {
        assert why
          == case row.target_flags, row.data_bits00, row.data_bits01 {
            1, _, _ -> spell_plan.DespawnAimedAtTheCasterOnly
            _, 0, 0 -> unexpected(row:, reading:)
            _, 0, _ -> spell_plan.DespawnDataNotRead(column: "dataBits01")
            _, _, _ -> spell_plan.DespawnDataNotRead(column: "dataBits00")
          }
          as {
            "row " <> int.to_string(row.id) <> " is left out for another reason"
          }
      }
      Ok(spell_plan.Applied(..))
      | Ok(spell_plan.Held(..))
      | Ok(spell_plan.ReadByArea)
      | Ok(spell_plan.ReadByActivation) -> {
        assert row.target_flags != 1
          && row.data_bits00 == 0
          && row.data_bits01 == 0
          as {
            "row "
            <> int.to_string(row.id)
            <> " is read though it is aimed at the caster alone or holds data"
          }
      }
      Error(spell_plan.ApplyPrerequisiteNotRead(..)) -> Nil
      Error(..) -> unexpected(row:, reading:)
    }
  })
}

pub fn type_15_rows_are_each_read_left_out_or_refused_by_name_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let rows =
    spell_tables.rows_read(tables: client_tables.shared(), effect_type: 15)
  assert list.length(rows) == 752
    as "table_rows -- Spell4Effects effectType=15: 752 rows"
  list.each(rows, fn(read) {
    let #(row, reading) = read
    let left_out = fn(why) {
      assert reading == Ok(spell_plan.LeftOut(why:))
        as {
          "row "
          <> int.to_string(row.id)
          <> " is left out for another reason than its columns give"
        }
    }
    case
      row.target_flags,
      int.bitwise_and(row.flags, 2) != 0,
      row.data_bits01,
      row.prerequisite_id_target_persistence
    {
      1, _, _, _ -> left_out(spell_plan.UnitStateAimedAtTheCasterOnly)
      _, True, _, _ -> left_out(spell_plan.UnitStateUntilRemoved)
      _, _, data_bits01, _ if data_bits01 != 0 ->
        left_out(spell_plan.UnitStateDataNotRead(column: "dataBits01"))
      _, _, _, persistence if persistence != 0 ->
        left_out(spell_plan.UnitStateBehindPersistence)
      _, _, _, _ ->
        case reading {
          Ok(spell_plan.Applied(..)) -> Nil
          Error(spell_plan.ApplyPrerequisiteNotRead(..))
          | Error(spell_plan.TargetPrerequisiteReadsStruckUnit(..)) -> Nil
          _ -> unexpected(row:, reading:)
        }
    }
  })
}

// ---- the gaps the engine states ----

pub fn types_1_4_8_and_26_state_their_gap_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["coverage", "gaps"])
  let facts = coverage_support.fact_file()
  let declared = coverage_support.engine_named("Spell effects")
  let fact_keys = [
    #(1, "Spell4Effects.effectType.1"),
    #(4, "Spell4Effects.effectType.4"),
    #(8, "0x140566ad0"),
    #(26, "Spell4Effects.effectType.26"),
  ]
  list.each(fact_keys, fn(expected) {
    let #(type_number, fact_key) = expected
    let assert Ok(gap) =
      list.find(declared.partial, fn(gap) { gap.type_number == type_number })
      as {
        "type " <> int.to_string(type_number) <> " is handled with a stated gap"
      }
    assert gap.fact_key == fact_key
      as "the gap cites the client's reading: the type's own record, and for the damage rows the formula's parameters (0x140566ad0)"
    assert coverage_support.has_record(facts:, key: fact_key)
      as { "the fact file holds " <> fact_key }
    assert engine.handles(engine: declared, type_number:)
  })
  let assert Ok(remove) =
    list.find(declared.partial, fn(gap) { gap.type_number == 80 })
    as "type 80 is partial"
  assert !string.contains(remove.reason, "is not counted")
    as "a selector that names no row is counted not read, since the measure holds the tables"
  let assert Ok(proxy) =
    list.find(declared.partial, fn(gap) { gap.type_number == 26 })
    as "type 26 is partial"
  assert string.contains(
      proxy.reason,
      "cast a beneficial spell on the allies in the area",
    )
    && !string.contains(proxy.reason, "the plan does not start it")
    as "the gap names the periodic Proxies the plan refuses by name, the ones for allies"
  assert !string.contains(proxy.reason, "until removed")
    as "a periodic Proxy aimed at the caster that lasts until removed is read as an open schedule, so it is no gap"
  assert !string.contains(
    proxy.reason,
    "whose dataBits00 is 0, which name their spell",
  )
    as "a Proxy that names its spell in dataBits01 is no longer the gap: the plan starts it"
  assert string.contains(proxy.reason, "bit 8")
    && string.contains(proxy.reason, "several tiers of one ability")
    as "the gap names the aim with bit 8 and the Proxies that start tiers with no choice"
  assert !string.contains(proxy.reason, "3, 5 or 7")
    as "a Proxy aimed by 3, 5 or 7 is read, as the caster alone where the area of a spell that hits no foes finds no allies and as the caster and each ally where it does, so the gap does not name those flags"
  let entries = gaps.registry()
  [
    #(
      "the rows of the child a friendly area's Proxy starts on each ally that land nowhere",
      ["each ally", "a Proc", "Triage's shield row 174070"],
    ),
    #("a Proxy that starts tiers with no choice is left out", [
      "several tiers",
      "tier",
      "Flash",
    ]),
  ]
  |> list.each(fn(row) {
    let #(limit, words) = row
    assert list.any(entries, fn(entry) {
      entry.area == "Spell areas"
      && list.all(words, fn(word) { string.contains(entry.missing, word) })
    })
      as { limit <> " is stated as a gap of the Spell areas" }
  })
}

pub fn no_type_15_row_past_the_caster_sits_in_an_activated_spell_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let activated = activate.activated_spell_ids(tables:, sources:)
  assert set.size(activated) > 0
    as "the activated set holds the creature activate columns, the item use spells and the default spell"
  let held =
    list.filter(spell4_effects.all(tables), fn(row) {
      row.effect_type == 15
      && row.target_flags != 1
      && set.contains(activated, row.spell_id)
    })
  assert list.map(held, fn(row) { row.id }) == []
    as "scratch count: no UnitStateSet row aimed past the caster is in a spell a creature's activate column, an item's use or the default activate spell names, so the activate cast's drop of such a row changes no activation of the client's data"
}
