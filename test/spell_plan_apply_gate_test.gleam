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
////   cannot be applied and fails the load, naming what is not read.
//// - `Prerequisite.prerequisiteTypeId.12`: the server has not decoded it. Type 15
////   reads what the casts held on the creature it is tested on hold, which a strike's picture does not
////   hold (`prerequisite.struck_unread_types`).

import client_tables
import fixture_tables
import genesis_prime/game/effect_row_read
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
import gleam/option.{None, Some}
import gleam/string
import owned_test
import planted_table
import spell_tables
import unitest

/// The place of a spell no Proxy starts on each struck unit, whose costs spend nothing.
fn no_proxy_place() -> spell_plan.RowPlace {
  spell_plan.RowPlace(
    struck_by: None,
    spends_all: False,
    hits_foes: False,
    throws_target: False,
    finds_allies: False,
    ends_as_aura: False,
  )
}

/// Whether the coverage measure counts the client's row `id` as read in `tables`.
fn is_read_by_the_measure(tables tables: store.Tables, id id: Int) -> Bool {
  effect_row_read.is_read(
    tables:,
    sources: spell_plan.sources_of(tables:),
    place: no_proxy_place(),
    effect: spell_tables.effect_row_in(tables:, id:),
  )
}

/// The CCStateSet row `effect_id` of the client's spell `spell4_id`, planned alone.
fn control_of(
  spell4_id spell4_id: Int,
  effect_id effect_id: Int,
) -> CrowdControl {
  let assert Ok(spell) =
    spell_tables.planned_alone(tables: fixture_tables.shared(), spell4_id:)
    as "the client's spell plans"
  let assert Ok(row) =
    list.find(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_control),
      fn(row) { row.effect_id == Spell4EffectsId(effect_id) },
    )
    as "the plan lists the row among the spell's states"
  row
}

pub fn damage_row_with_undecoded_gate_is_refused_at_load_naming_what_is_not_read_test() -> Nil {
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
          effect: spell_tables.effect_row_in(tables:, id: 38_307),
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
      assert string.contains(text, "12")
        && string.ends_with(text, "which is not decoded")
        as "the refusal names the type and says it is not decoded, with no issue"
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
      ..spell_tables.effect_row_in(tables:, id: 38_307),
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
  assert !effect_row_read.is_read(
    tables:,
    sources: spell_plan.sources_of(tables:),
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
      ..spell_tables.effect_row_in(tables:, id: 38_307),
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

/// A damage row aimed at the area (targetFlags 4) behind a target gate that reads what the
/// creature it strikes holds is refused at load: no creature holds a player's picture of it
/// for the caster's check, and none checks it itself. Type 15 reads the state of the creature
/// it is tested on; type 40 (a unit's health percentage, `0x1404a4d90`) reads a health the
/// caster's picture holds of a player only, where a heal row of a friendly area behind it is
/// read (`a_friendly_area_heal_behind_a_gate_the_strike_cannot_check_for_an_ally_keeps_the_casters_own_heal_test`).
pub fn damage_row_past_the_caster_behind_a_gate_reading_the_struck_unit_is_refused_at_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 3476, the target gate of damage row 38307 (targetFlags 4), made a
  // condition of each row's type, comparison and value.
  list.each(
    [
      #(
        "type 15 (comparison 1) reads the state of the creature it is tested on",
        15,
        1,
        None,
        "which reads what the casts held on the creature it strikes hold",
      ),
      #(
        "type 40 (comparison 6, value 30) reads a health no creature holds for the caster's check",
        40,
        6,
        Some(30),
        "which reads the state of the creature it strikes, and the row is not one its strike carries to the creature",
      ),
    ],
    fn(row) {
      let #(reason, prerequisite_type, comparison, value, told) = row
      use tables <- fixture_tables.changed(
        table: "Prerequisite",
        id: 3476,
        with: [
          #("prerequisiteTypeId0", planted_table.Integer(prerequisite_type)),
          #("prerequisiteComparisonId0", planted_table.Integer(comparison)),
          ..case value {
            Some(value) -> [#("value0", planted_table.Integer(value))]
            None -> []
          }
        ],
      )
      let result =
        spell_area.damage_row_of(
          tables:,
          spell4_id: 23_980,
          effect: spell_tables.effect_row_in(tables:, id: 38_307),
        )
      assert result
        == Error(
          spell_area.ApplyGateNotRead(
            spell_plan.TargetPrerequisiteReadsStruckUnit(
              spell4_id: 23_980,
              effect_id: 38_307,
              prerequisite_type:,
            ),
          ),
        )
        as reason
      let assert Error(error) = result
      assert string.ends_with(spell_area.describe(error:), told)
        as "the refusal says what the gate reads of the struck unit, with no issue"
    },
  )
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
      body: fn(tables) {
        spell_tables.planned_alone(tables:, spell4_id: 51_989)
      },
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
      body: fn(tables) {
        spell_tables.planned_alone(tables:, spell4_id: 51_989)
      },
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
      body: fn(tables) {
        spell_tables.planned_alone(tables:, spell4_id: 43_131)
      },
    )
  assert unread_caster
    == Error(spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: 43_131,
      effect_id: 99_347,
      prerequisite_type: 12,
    ))
    as "a state behind a caster gate the server cannot read fails the plan"
}

/// Kept edit: a Prerequisite made one condition of type 28, whether the unit is in combat
/// (comparison 1), which reads the state the unit it is tested on holds itself
/// (`prerequisite.checked_by_creature`).
const in_combat_gate = [
  #("prerequisiteTypeId0", planted_table.Integer(28)),
  #("prerequisiteComparisonId0", planted_table.Integer(1)),
  #("objectId0", planted_table.Integer(0)),
  #("value0", planted_table.Integer(0)),
]

/// Kept edits: Prerequisite 3476, the target gate of damage row 38307 (targetFlags 4, the
/// area), made the type 28 condition above; and ForcedMove row 38308 of the same spell,
/// which shares the gate and which the plan reads for the cast alone, given no target apply
/// prerequisite so that the spell plans.
fn rows_with_the_gate_made_in_combat() -> fixture_tables.Rows {
  spell_tables.changed_rows(
    rows: spell_tables.changed_rows(
      rows: fixture_tables.rows(),
      table: "Prerequisite",
      id: 3476,
      with: in_combat_gate,
    ),
    table: "Spell4Effects",
    id: 38_308,
    with: [#("prerequisiteIdTargetApply", planted_table.Integer(0))],
  )
}

pub fn damage_row_past_the_caster_behind_a_creature_state_gate_is_left_to_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.on_rows(
    rows: rows_with_the_gate_made_in_combat(),
    reaching: [],
  )
  let assert Ok(spell_area.Once(effect:)) =
    spell_area.damage_row_of(
      tables:,
      spell4_id: 23_980,
      effect: spell_tables.effect_row_in(tables:, id: 38_307),
    )
    as "a damage row behind a gate on each creature's own state is read"
  assert effect.condition == Always
    as "the strike checks no gate of the row itself: the creature it names does"
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 23_980)
    as "the spell plans"
  let assert [gate] = spell.struck_gates
    as "the spell tells the gate to the creatures its strike reaches"
  assert gate.effect_id == Spell4EffectsId(38_307)
  assert prerequisite.id(gate.prerequisite) == PrerequisiteId(3476)
    as "Spell4Effects.38307: prerequisiteIdTargetApply 3476"
  assert gate.aim == spell_plan.AimsAtArea
    as "Spell4Effects.38307: targetFlags 4, the area"
  assert is_read_by_the_measure(tables:, id: 38_307)
    as "the coverage measure counts the row as read"
}

pub fn periodic_damage_row_left_out_as_until_removed_tells_no_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: damage row 38307 given a tickTime and flags bit 2 (until removed), which the
  // area load leaves out, on the rows `rows_with_the_gate_made_in_combat` makes.
  use tables <- fixture_tables.on_rows(
    rows: spell_tables.changed_rows(
      rows: rows_with_the_gate_made_in_combat(),
      table: "Spell4Effects",
      id: 38_307,
      with: [
        #("tickTime", planted_table.Integer(1000)),
        #("durationTime", planted_table.Integer(0)),
        #("flags", planted_table.Integer(2)),
      ],
    ),
    reaching: [],
  )
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 23_980)
    as "the spell plans"
  assert spell.struck_gates == []
    as "a row the area load leaves out has no creature to ask, so no strike round is run for it"
}

pub fn ccstateset_row_past_the_caster_behind_a_creature_state_gate_is_left_to_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 24214, the target gate of CCStateSet row 122821 (targetFlags 4,
  // the area), made the type 28 condition above.
  use tables <- fixture_tables.changed(
    table: "Prerequisite",
    id: 24_214,
    with: in_combat_gate,
  )
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 51_989)
    as "a state behind a gate on each creature's own state plans"
  let assert Ok(control) =
    list.find(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_control),
      fn(row) { row.effect_id == Spell4EffectsId(122_821) },
    )
    as "the plan lists the row among the spell's states"
  assert control.condition == Always
    as "the strike checks no gate of the row itself: the creature it names does"
  let assert Ok(gate) =
    list.find(spell.struck_gates, fn(gate) {
      gate.effect_id == Spell4EffectsId(122_821)
    })
    as "the spell tells the row's gate to the creatures its strike reaches"
  assert prerequisite.id(gate.prerequisite) == PrerequisiteId(24_214)
    as "Spell4Effects.122821: prerequisiteIdTargetApply 24214"
  assert gate.aim == spell_plan.AimsAtArea
    as "Spell4Effects.122821: targetFlags 4, the area"
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
      // A row whose target gate the creatures it strikes check holds none of it: the
      // spell lists the row's id among its struck gates instead.
      let row = fn(effect_id, condition) {
        #(
          effect_id,
          condition,
          list.any(spell.struck_gates, fn(gate) { gate.effect_id == effect_id }),
        )
      }
      let damage = case dict.get(areas, value) {
        Ok(area) ->
          list.append(
            list.map(area.damage, fn(effect) {
              row(effect.effect_id, effect.condition)
            }),
            list.map(area.ticking, fn(ticking) {
              row(ticking.damage.effect_id, ticking.damage.condition)
            }),
          )
        Error(Nil) -> []
      }
      list.append(
        damage,
        list.map(
          spell_plan.payloads(spell:, as_kind: spell_plan.as_control),
          fn(control) { row(control.effect_id, control.condition) },
        ),
      )
    })
  assert rows != [] as "the planned trees hold damage and crowd-control rows"
  let disagreeing =
    list.filter(rows, fn(row: #(id.Spell4EffectsId, Condition, Bool)) {
      let effect = spell_tables.effect_row_in(tables:, id: { row.0 }.value)
      let gated =
        effect.prerequisite_id_caster_apply != 0
        || { effect.prerequisite_id_target_apply != 0 && !row.2 }
      gated == { row.1 == Always }
    })
  assert disagreeing == []
    as "every planned row holds the condition its apply prerequisites make, or its spell tells the target gate to the creatures: none is gated by a prerequisite it dropped"
}
