//// The plans of the activate spells (genesis_prime/game/activate) from the client's own
//// tables: every spell a Creature2 row names in an activate column, and the default spell,
//// is planned or has one named reason. Expected values come from the client's Spell4 and
//// Creature2 tables.

import cast_support
import client_tables
import fixture_tables
import genesis_prime/game/activate.{CannotBePlanned, NoSpell4Row, Planned}
import genesis_prime/game/cast
import genesis_prime/game/spell_plan.{AliveOrDead, CannotBeDead, MustBeDead}
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result
import genesis_prime/step.{LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Spell4ConditionsId, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_conditions
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/set
import gleam/string
import owned_test
import place_support
import planted_table.{Integer}
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
  assert list.length(reasons) == 260
    as "260 of the activate spells cannot be planned: 103 hold an effect the plan does not read (a CCStateSet, a DisguiseOutfit, a SpellForceRemove, a VitalModifier, a Stealth or a Proxy row, or a missing Spell4Base row) and 157 more hold an effect other than Activate aimed at the target or an area of a type some rule reads for that aim (a Proxy, Damage, Fluff and so on; a RavelSignal aimed at the target alone refuses nothing: 251 of the 408 that hold one are planned), which an activate cast, striking no one, would lose: the press is refused as not built, with the reason logged once; a row of a type no rule reads is dropped by every cast and refuses nothing"
  assert list.count(reasons, fn(reason) {
      string.contains(reason.1, "aims at the target or an area")
    })
    == 157
    as "157 of the 260 are refused for an effect aimed at the target or an area"
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

/// What the plan holds of the spell's target death, from the fixture's rows.
fn target_death_of(
  activations activations: activate.Activations,
  spell4_id spell4_id: Int,
) -> spell_plan.CasterDeath {
  let assert Ok(Planned(spell:, ..)) =
    activate.planned_of(activations:, spell4_id:)
    as "the spell is planned"
  spell.target_death
}

pub fn an_activate_spells_target_row_says_whether_its_target_may_be_dead_test() -> Nil {
  use <- owned_test.run(60_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  assert target_death_of(activations:, spell4_id: 1817) == CannotBeDead
    as "Spell4 1817's target row is Spell4Conditions 15 (mask 129, value 0): bit 0 is in the mask and not in the value, so a dead target is refused (0x1403b2240 lines 63-77)"
  assert target_death_of(activations:, spell4_id: 6772) == AliveOrDead
    as "Spell4 6772's target row is Spell4Conditions 4 (mask 0): the cast tests no death"
  // No activate spell has a must-be-dead target; Spell4Conditions 16 (mask 225, value 1)
  // is the client's own must-be-dead row, which Spell4 596 names.
  let must_be_dead =
    fixture_tables.changed(
      table: "Spell4",
      id: 1817,
      with: [#("spell4ConditionsIdTarget", Integer(16))],
      body: fn(tables) {
        target_death_of(
          activations: activate.activations(tables:),
          spell4_id: 1817,
        )
      },
    )
  assert must_be_dead == MustBeDead
    as "Spell4Conditions 16 holds bit 0 in the mask and in the value: a living target is refused"
}

/// The target death the row of the spell's target conditions asks for, read from the
/// mask and value bits (0x1403b2240 lines 63-77), not from the plan.
fn death_of_row(
  row row: spell4_conditions.Spell4Conditions,
) -> spell_plan.CasterDeath {
  case
    int.bitwise_and(row.condition_mask, 1),
    int.bitwise_and(row.condition_value, 1)
  {
    0, _ -> AliveOrDead
    _, 0 -> CannotBeDead
    _, _ -> MustBeDead
  }
}

pub fn every_activate_creatures_target_death_matches_its_conditions_row_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let activations = activate.activations(tables:)
  let spells_of_creatures =
    list.filter_map(creature2.all(tables), fn(row) {
      case
        list.filter(activate.creature_of(row:).columns, fn(column) {
          column.spell4_id != 0
        })
      {
        [] -> Error(Nil)
        columns -> Ok(list.map(columns, fn(column) { column.spell4_id }))
      }
    })
  assert list.length(spells_of_creatures) == 8463
    as "8,463 Creature2 rows name an activate spell (a count of the table's dump)"
  let target_row_of = fn(spell4_id) {
    // A spell with no Spell4 row has no conditions to read.
    case spell4.get(tables:, id: Spell4Id(spell4_id)) {
      Error(Nil) -> Error(Nil)
      Ok(row) ->
        case spell4.spell4_conditions_id_target(row).value {
          0 -> Ok(spell4_conditions.Spell4Conditions(0, 0, 0))
          conditions_id -> {
            let assert Ok(conditions) =
              spell4_conditions.get(
                tables:,
                id: Spell4ConditionsId(conditions_id),
              )
              as "the Spell4 row's target conditions row exists"
            Ok(conditions)
          }
        }
    }
  }
  assert list.count(spells_of_creatures, fn(spells) {
      list.any(spells, fn(spell4_id) {
        case target_row_of(spell4_id) {
          Ok(row) -> death_of_row(row:) == CannotBeDead
          Error(Nil) -> False
        }
      })
    })
    == 7903
    as "7,903 of the 8,463 creatures have an activate spell whose target row refuses a dead target; the count is an own count over the dumps of Creature2, Spell4 and Spell4Conditions"
  let distinct = list.flatten(spells_of_creatures) |> list.unique
  assert list.all(distinct, fn(spell4_id) {
    case target_row_of(spell4_id) {
      Ok(row) -> int.bitwise_and(row.condition_mask, int.bitwise_not(227)) == 0
      Error(Nil) -> True
    }
  })
    as "no activate spell's target row tests a bit but 0, 1, 5, 6 and 7 (mask 227): the plan reads those and refuses a spell with another"
  let planned =
    list.filter_map(distinct, fn(spell4_id) {
      case activate.planned_of(activations:, spell4_id:) {
        Ok(Planned(spell:, ..)) -> Ok(#(spell4_id, spell.target_death))
        Ok(NoSpell4Row) | Ok(CannotBePlanned(..)) | Error(Nil) -> Error(Nil)
      }
    })
  assert planned != [] as "some activate spells are planned"
  assert list.all(planned, fn(spell) {
    let assert Ok(row) = target_row_of(spell.0)
    spell.1 == death_of_row(row:)
  })
    as "each planned spell's target death is its target row's bit 0 and value"
  assert list.all(planned, fn(spell) { spell.1 != MustBeDead })
    as "no activate spell has a must-be-dead target"
}

pub fn an_activate_spell_whose_target_row_tests_a_bit_the_plan_does_not_model_is_not_planned_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Conditions 2 has the mask 1773: bits 0, 2, 3, 5, 6, 8, 9 and 10; the plan reads
  // bits 0, 1, 5, 6 and 7 of the target row.
  let #(planned, pressed) =
    fixture_tables.changed(
      table: "Spell4",
      id: 1817,
      with: [#("spell4ConditionsIdTarget", Integer(2))],
      body: fn(tables) {
        let activations = activate.activations(tables:)
        let assert Ok(planned) =
          activate.planned_of(activations:, spell4_id: 1817)
        #(planned, pressed_with(activations:))
      },
    )
  let assert CannotBePlanned(why:) = planned
    as "a target row with a bit the plan does not model is a plan the server cannot judge"
  assert string.starts_with(why, "the ")
    && string.contains(why, "1817")
    && string.contains(why, "1773")
    as "the reason names the spell and the row's mask"
  assert cast_support.refusal_results(effects: pressed)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "a press of a spell the plan cannot build is refused as not built (285)"
  let assert [#(LogWarning, line)] = cast_support.logs(effects: pressed)
    as "the refusal is logged"
  assert string.contains(line, "1773")
}

/// The effects of a press at a creature of Spell4 1817 standing in range.
fn pressed_with(
  activations activations: activate.Activations,
) -> List(cast.Effect) {
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 4096.0,
      y: 0.0,
      z: 512.0,
    )
  let assert Ok(body) =
    cast_activate.encode(CastActivate(client_cast_id: 9, target_unit_id: 5000))
    as "the message fits"
  let assert Ok(#(_, effects)) =
    cast.activate(
      cast: cast.new(),
      body:,
      caster: cast.Caster(..cast_support.caster(), place:),
      activations:,
      target_of: fn(_) {
        activate.Usable(
          creature_id: 26_462,
          creature: activate.Creature(
            columns: [activate.Column(prerequisite_id: 0, spell4_id: 1817)],
            cast_time_ms: 2000,
            min_range: 0.0,
            max_range: 5.0,
          ),
          checklist_index: 0,
          link: activate.NoLink,
          body: activate.Body(place:, radius: 0.25),
          alive: True,
          withheld: option.None,
        )
      },
      caster_radius: 0.5,
      now: cast_support.at(ms: 1000),
    )
    as "a refusal is an answer, not an error"
  effects
}
