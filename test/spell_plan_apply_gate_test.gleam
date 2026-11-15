//// The plan's and the area's damage and crowd-control rows behind an apply prerequisite
//// (`genesis_prime/game/spell_plan` `row_condition_of`, `genesis_prime/game/spell_area`
//// `damage_row_of`). Expected values come from these places.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects 38307 122821
////   99347 115034`, `-- Prerequisite 3476 24214 3286 860`):
////   - 38307 (Spell4 23980): effectType 8, targetFlags 4, target apply 3476, one condition of
////     type 38 (comparison 2, value 12703).
////   - 122821 (Spell4 51989): effectType 4, targetFlags 4, target apply 24214, one condition
////     of type 130 (comparison 2, object 465).
////   - 99347 (Spell4 43131): effectType 4, targetFlags 2, caster apply 3286, one condition of
////     type 37 (comparison 6, value 60).
////   - 115034 (Spell4 48757): effectType 4, targetFlags 2, target apply 860, one condition of
////     type 37 (comparison 6, value 10).
//// - `Spell4Effects.prerequisiteIdTargetApply` and `prerequisiteIdCasterApply`: a row lands
////   only where its prerequisites pass, so a row whose prerequisite the server cannot read
////   cannot be applied and fails the load, naming the issue that will read it.
//// - `Prerequisite.prerequisiteTypeId.12`: the server has not decoded it (#818). Type 15
////   reads the state of the creature it is tested on (#817), which a strike's picture does not
////   hold (`prerequisite.struck_unread_types`).

import client_tables
import fixture_tables
import genesis_prime/coverage/effect_row
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  type Condition, type CrowdControl, Always, GatedOnCaster, GatedOnTarget,
}
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import planted_table
import unitest

fn effect_row_in(
  tables tables: store.Tables,
  id id: Int,
) -> spell4_effects.Spell4Effects {
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(id))
    as "the fixture holds the client's row"
  row
}

/// The place of a spell no Proxy starts on each struck unit, whose costs spend nothing.
fn no_proxy_place() -> spell_plan.RowPlace {
  spell_plan.RowPlace(struck_by: None, spends_all: False)
}

/// Whether the coverage measure counts the client's row `id` as read in `tables`.
fn is_read_by_the_measure(tables tables: store.Tables, id id: Int) -> Bool {
  effect_row.is_read(
    tables:,
    spell_groups: spell_plan.spell_groups(tables:),
    place: no_proxy_place(),
    effect: effect_row_in(tables:, id:),
  )
}

/// The client's spell `spell4_id` planned alone from `tables`.
fn plan_of(
  tables tables: store.Tables,
  spell4_id spell4_id: Int,
) -> Result(spell_plan.Spell, spell_plan.PlanError) {
  spell_plan.spell_alone(
    tables:,
    sources: spell_plan.sources_of(tables:),
    spell4_id:,
    chain: [],
  )
}

/// The CCStateSet row `effect_id` of the client's spell `spell4_id`, planned alone.
fn control_of(
  spell4_id spell4_id: Int,
  effect_id effect_id: Int,
) -> CrowdControl {
  let assert Ok(spell) = plan_of(tables: fixture_tables.shared(), spell4_id:)
    as "the client's spell plans"
  let assert Ok(row) =
    list.find(spell.controls, fn(row) {
      row.effect_id == Spell4EffectsId(effect_id)
    })
    as "the plan lists the row among the spell's states"
  row
}

pub fn damage_row_with_undecoded_gate_is_refused_at_load_naming_its_issue_test() -> Nil {
  use <- owned_test.run(60_000)
  assert !prerequisite.is_read(type_id: 12)
    as "the server has not decoded type 12"
  // Kept edit: Prerequisite 3476, the target gate of damage row 38307, made a condition of
  // type 12, which the server has not decoded.
  fixture_tables.changed(
    table: "Prerequisite",
    id: 3476,
    with: [#("prerequisiteTypeId0", planted_table.Integer(12))],
    body: fn(tables) {
      let result =
        spell_area.damage_row_of(
          tables:,
          spell4_id: 23_980,
          effect: effect_row_in(tables:, id: 38_307),
        )
      assert result
        == Error(
          spell_area.ApplyGateNotRead(spell_plan.ApplyPrerequisiteNotRead(
            spell4_id: 23_980,
            effect_id: 38_307,
            prerequisite_type: 12,
          )),
        )
      let assert Error(error) = result
      let text = spell_area.describe(error:)
      assert string.contains(text, "12") && string.contains(text, "#818")
        as "the refusal names the type and the issue that will read it"
      assert !is_read_by_the_measure(tables:, id: 38_307)
        as "the coverage measure counts the row as not read"
      assert is_read_by_the_measure(tables: fixture_tables.shared(), id: 38_307)
        as "the client's row, with its gate decoded, is read"
    },
  )
  // Kept edit: Prerequisite 3286, the caster gate of row 99347, made a condition of type 12;
  // damage row 38307 is given it as its caster apply.
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 3286, with: [
    #("prerequisiteTypeId0", planted_table.Integer(12)),
  ])
  let by_caster =
    spell4_effects.Spell4Effects(
      ..effect_row_in(tables:, id: 38_307),
      prerequisite_id_caster_apply: 3286,
    )
  assert spell_area.damage_row_of(tables:, spell4_id: 23_980, effect: by_caster)
    == Error(
      spell_area.ApplyGateNotRead(spell_plan.ApplyPrerequisiteNotRead(
        spell4_id: 23_980,
        effect_id: 38_307,
        prerequisite_type: 12,
      )),
    )
    as "a row behind a caster gate the server cannot read is refused too"
  assert !effect_row.is_read(
    tables:,
    spell_groups: spell_plan.spell_groups(tables:),
    place: no_proxy_place(),
    effect: by_caster,
  )
    as "the coverage measure counts the caster-gated row as not read"
}

pub fn until_removed_periodic_damage_row_behind_an_unread_gate_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 3476, the target gate of damage row 38307, made a condition of
  // type 12, which the server has not decoded; the row is given a tickTime and flags bit 2
  // (until removed), as the area load's reader is given it.
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 3476, with: [
    #("prerequisiteTypeId0", planted_table.Integer(12)),
  ])
  let row =
    spell4_effects.Spell4Effects(
      ..effect_row_in(tables:, id: 38_307),
      tick_time: 1000,
      duration_time: 0,
      flags: 2,
    )
  assert spell_area.damage_row_of(tables:, spell4_id: 23_980, effect: row)
    == Error(spell_area.TickingUntilRemoved(
      spell4_id: 23_980,
      effect_id: 38_307,
    ))
    as "an until-removed row is left out before its gate is read, as it was before the gates were read, so the load goes on"
}

pub fn damage_row_past_the_caster_reading_struck_state_is_refused_at_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 3476 made a condition of type 15 (comparison 1), which reads
  // the state of the creature it is tested on, and the row is aimed at the area (targetFlags 4).
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 3476, with: [
    #("prerequisiteTypeId0", planted_table.Integer(15)),
    #("prerequisiteComparisonId0", planted_table.Integer(1)),
  ])
  let result =
    spell_area.damage_row_of(
      tables:,
      spell4_id: 23_980,
      effect: effect_row_in(tables:, id: 38_307),
    )
  assert result
    == Error(
      spell_area.ApplyGateNotRead(spell_plan.TargetPrerequisiteReadsStruckUnit(
        spell4_id: 23_980,
        effect_id: 38_307,
        prerequisite_type: 15,
      )),
    )
  let assert Error(error) = result
  assert string.contains(spell_area.describe(error:), "#817")
    as "the refusal names the issue that will read the struck unit's state"
}

pub fn ccstateset_row_behind_an_apply_prerequisite_is_read_with_its_gates_test() -> Nil {
  use <- owned_test.run(60_000)
  let area = control_of(spell4_id: 51_989, effect_id: 122_821)
  let assert GatedOnTarget(prerequisite: gate) = area.condition
    as "Spell4Effects.122821 is behind a target apply prerequisite only"
  assert prerequisite.id(gate) == PrerequisiteId(24_214)
    as "Spell4Effects.122821: prerequisiteIdTargetApply 24214"
  assert area.aim == spell_plan.AimsAtArea as "targetFlags 4 is the area"
  let by_caster = control_of(spell4_id: 43_131, effect_id: 99_347)
  let assert GatedOnCaster(gates:) = by_caster.condition
    as "Spell4Effects.99347 is behind a caster apply prerequisite only"
  assert list.map(gates, prerequisite.id) == [PrerequisiteId(3286)]
    as "Spell4Effects.99347: prerequisiteIdCasterApply 3286"
  let by_roll = control_of(spell4_id: 48_757, effect_id: 115_034)
  let assert GatedOnTarget(prerequisite: roll_gate) = by_roll.condition
    as "Spell4Effects.115034 is behind a target apply prerequisite only"
  assert prerequisite.id(roll_gate) == PrerequisiteId(860)
    as "Spell4Effects.115034: prerequisiteIdTargetApply 860"
  assert prerequisite.rolls_needed(prerequisite: roll_gate) == 1
    as "its one type 37 condition takes one roll for each unit"
  // Kept edit: Prerequisite 24214, the target gate of CCStateSet row 122821 (targetFlags 4),
  // made a condition of type 12, which the server has not decoded.
  let unread_target =
    fixture_tables.changed(
      table: "Prerequisite",
      id: 24_214,
      with: [#("prerequisiteTypeId0", planted_table.Integer(12))],
      body: fn(tables) { plan_of(tables:, spell4_id: 51_989) },
    )
  assert unread_target
    == Error(spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: 51_989,
      effect_id: 122_821,
      prerequisite_type: 12,
    ))
    as "a state behind a target gate the server cannot read fails the plan, naming the type"
  // Kept edit: the same prerequisite made a condition of type 15, which reads the state of
  // the creature it is tested on; the row is aimed at the area, past the caster.
  let struck_state =
    fixture_tables.changed(
      table: "Prerequisite",
      id: 24_214,
      with: [
        #("prerequisiteTypeId0", planted_table.Integer(15)),
        #("prerequisiteComparisonId0", planted_table.Integer(1)),
      ],
      body: fn(tables) { plan_of(tables:, spell4_id: 51_989) },
    )
  assert struck_state
    == Error(spell_plan.TargetPrerequisiteReadsStruckUnit(
      spell4_id: 51_989,
      effect_id: 122_821,
      prerequisite_type: 15,
    ))
    as "a state behind a type 15 gate past the caster fails the plan"
  // Kept edit: Prerequisite 3286, the caster gate of CCStateSet row 99347, made a condition
  // of type 12.
  let unread_caster =
    fixture_tables.changed(
      table: "Prerequisite",
      id: 3286,
      with: [#("prerequisiteTypeId0", planted_table.Integer(12))],
      body: fn(tables) { plan_of(tables:, spell4_id: 43_131) },
    )
  assert unread_caster
    == Error(spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: 43_131,
      effect_id: 99_347,
      prerequisite_type: 12,
    ))
    as "a state behind a caster gate the server cannot read fails the plan"
}

pub fn no_planned_spell_holds_a_refused_damage_or_control_row_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let areas = spell_area.areas(tables:)
  let planned =
    dict.values(spell_plan.plans(tables:))
    |> list.flat_map(fn(spell) {
      spell_plan.tree(spell:, started: fn(_) { True })
    })
  let rows =
    list.flat_map(planned, fn(spell) {
      let Spell4Id(value:) = spell.spell4_id
      let damage = case dict.get(areas, value) {
        Ok(area) ->
          list.append(
            list.map(area.damage, fn(effect) {
              #(effect.effect_id, effect.condition)
            }),
            list.map(area.ticking, fn(row) {
              #(row.damage.effect_id, row.damage.condition)
            }),
          )
        Error(Nil) -> []
      }
      list.append(
        damage,
        list.map(spell.controls, fn(control) {
          #(control.effect_id, control.condition)
        }),
      )
    })
  assert rows != [] as "the planned trees hold damage and crowd-control rows"
  let disagreeing =
    list.filter(rows, fn(row: #(id.Spell4EffectsId, Condition)) {
      let effect = effect_row_in(tables:, id: { row.0 }.value)
      let gated =
        effect.prerequisite_id_caster_apply != 0
        || effect.prerequisite_id_target_apply != 0
      gated == { row.1 == Always }
    })
  assert disagreeing == []
    as "every planned row holds the condition its apply prerequisites make: none is gated by a prerequisite it dropped"
}
