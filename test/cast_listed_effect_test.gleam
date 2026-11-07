//// The cast rule (`genesis_prime/game/cast`) for the Scale (18), RavelSignal (81) and
//// UnitPropertyConversion (145) rows the plan reads. Each spell holds the rows as the plan
//// reads them from planted Spell4Effects rows (`spell_plan_listed_effect_test`), on a clock
//// the test drives. Expected values come from these places:
//// - `opcode.0x7f4.target_info`, `opcode.0x7f4.instance_count` and
////   `opcode.0x7f4.effect_time`: a go's effect info names the effect row, the result bit,
////   the instance count 1 for one application and the fourth value 0, which leaves the
////   lifetime to the client's own rule (delay plus durationTime).
//// - `cast.target_node_end`: the client ends no buff on time, so the server holds the
////   0x7fe of a cast with a node that has life left; an early 0x7fe would undo the scale.
//// - `Spell4Effects.effectType.18`: the client resizes any unit the go names the effect on,
////   so a Scale row aimed at the area is listed on each struck unit.
//// - `Spell4Effects.effectType.81`: the plan's rule that an effect behind a target apply
////   prerequisite is not applied, with one debug line, as a forced move behind one is.
//// - `Spell4Effects.effectType.145` and the modifiers' rule "until removed": row 229304 of
////   the Engineer passive 45000 is flags 2, so its conversion starts at the go and has no
////   end timer; `cast.died` ends every modifier but the innate passive's.

import cast_support as support
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/spell_plan.{type Plans, type Spell, Spell}
import genesis_prime/game/unit_properties
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_target_info.{type SpellTargetInfo}
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, UnitProperty2Id}
import gleam/list
import gleam/string
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables

const one_point_three = 1_067_869_798

const a_quarter = 1_048_576_000

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// A spell of no cast time and no cooldown that holds the lasting and modifier rows the
/// plan reads from this planted row, and no other.
fn spell_of(
  row row: List(Cell),
  id id: Int,
  spell4_id spell4_id: Int,
  base base: Int,
) -> Spell {
  let assert Ok(planned) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the plan builds"
  let wanted = Spell4EffectsId(id)
  Spell(
    ..support.child(spell4_id:, base:),
    lasting: list.filter(planned.lasting, fn(lasting) {
      lasting.effect_id == wanted
    }),
    modifiers: list.filter(planned.modifiers, fn(modifier) {
      modifier.effect_id == wanted
    }),
  )
}

/// The units each go names, with the effects it lists on each.
fn targets_of(effects effects: List(Effect)) -> List(SpellTargetInfo) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  decoded.targets
}

fn listed(effects effects: List(Effect)) -> List(Int) {
  list.flat_map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(decoded) = spell_go.decode(frame.body)
      list.flat_map(decoded.targets, fn(target) {
        list.map(target.effects, fn(effect) { effect.spell4_effects_id })
      })
    },
  )
}

// ---- a Scale row ----

pub fn a_go_lists_a_scale_row_on_the_caster_and_the_nodes_life_is_the_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  // 109482's shape: the caster, 1.3 over 500 ms, 8000 ms, here with a delay of 120 ms.
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 109_482,
        effect_type: 18,
        target_flags: 1,
        columns: [
          #("delayTime", Integer(120)),
          #("durationTime", Integer(8000)),
          #("dataBits00", Integer(one_point_three)),
          #("dataBits01", Integer(500)),
          #("dataBits02", Integer(1000)),
        ],
      ),
      id: 109_482,
      spell4_id: 42_908,
      base: 3,
    )
  let #(_, effects) =
    support.press(
      plans: support.plans_of([spell]),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [info] = targets_of(effects:)
  assert info.unit_id == 7 as "the caster is the unit the row aims at"
  assert info.instance_count == 1
    as "one application is a count of 1 (opcode.0x7f4.instance_count)"
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 109_482,
        instance_id: 1,
        delay_ms: 120,
        field_4: 0,
        result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
      ),
    ]
    as "the row's delay, the result bit and the fourth value 0 that leaves the lifetime to the client (opcode.0x7f4.effect_time)"
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [8120]
    as "the node lives for the row's delay and durationTime from the go"
}

pub fn a_spell_whose_only_row_with_a_life_is_a_scale_row_lingers_until_the_rows_end_and_then_finishes_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 109_482,
        effect_type: 18,
        target_flags: 1,
        columns: [
          #("durationTime", Integer(8000)),
          #("dataBits00", Integer(one_point_three)),
        ],
      ),
      id: 109_482,
      spell4_id: 42_908,
      base: 3,
    )
  let #(state, effects) =
    support.press(
      plans: support.plans_of([spell]),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the client ends no buff on time, so an early 0x7fe would undo the scale (cast.target_node_end)"
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, early) = support.fired(state:, timer:, at: 8999)
  assert support.finished_ids(support.writes(effects: early)) == []
    as "a timer that fires with life left writes nothing"
  let assert [#(timer, 1)] = support.started_timers(effects: early)
  let #(_, ended) = support.fired(state:, timer:, at: 9000)
  assert support.finished_ids(support.writes(effects: ended)) == [id]
    as "the 0x7fe comes with the end of the row's 8000 ms"
}

pub fn a_scale_row_aimed_at_the_area_is_listed_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 192_250,
        effect_type: 18,
        target_flags: 4,
        columns: [
          #("durationTime", Integer(5000)),
          #("dataBits00", Integer(one_point_three)),
        ],
      ),
      id: 192_250,
      spell4_id: 101,
      base: 3,
    )
  let #(state, effects) =
    support.pressed_raw_in(
      plans: support.plans_of([spell]),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_by(state:, effects:, at: 1000, struck: [
      cast.Hit(unit_id: 20, descriptions: [], controls: []),
      cast.Hit(unit_id: 21, descriptions: [], controls: []),
    ])
  assert list.map(targets_of(effects:), fn(info) {
      #(
        info.unit_id,
        list.map(info.effects, fn(effect) { effect.spell4_effects_id }),
      )
    })
    == [#(20, [192_250]), #(21, [192_250])]
    as "Spell4Effects.effectType.18: the client resizes any unit the go names the effect on, so each struck unit's info lists the row"
}

// ---- a RavelSignal row ----

pub fn a_ravel_signal_row_behind_a_target_prerequisite_is_not_listed_and_says_so_test() -> Nil {
  use <- owned_test.run(60_000)
  // 91018 as the client holds it: the caster, behind target apply prerequisite 11311.
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 91_018,
        effect_type: 81,
        target_flags: 1,
        columns: [
          #("dataBits00", Integer(1)),
          #("dataBits01", Integer(13_076)),
          #("durationTime", Integer(1000)),
          #("prerequisiteIdTargetApply", Integer(11_311)),
        ],
      ),
      id: 91_018,
      spell4_id: 38_784,
      base: 3,
    )
  let #(_, effects) =
    support.press(
      plans: support.plans_of([spell]),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert listed(effects:) == []
    as "a row behind a target prerequisite is not applied, as a forced move behind one is not listed"
  let lines =
    list.filter(support.logs(effects:), fn(line) {
      string.contains(line.1, "91018")
    })
  assert list.map(lines, fn(line) { line.0 }) == [LogDebug]
    as "one debug line names the row that is not applied"
}

// ---- a PropertyConversion row ----

/// The Engineer passive's shape: 229304, flags 2, from property 47 to 60 at a quarter.
fn passive() -> Spell {
  spell_of(
    row: spell_tables.effect_row_with(
      id: 229_304,
      effect_type: 145,
      target_flags: 1,
      columns: [
        #("flags", Integer(2)),
        #("dataBits00", Integer(47)),
        #("dataBits01", Integer(60)),
        #("dataBits02", Integer(a_quarter)),
      ],
    ),
    id: 229_304,
    spell4_id: 250_001,
    base: 250_001,
  )
}

fn caster_of_passive() -> Caster {
  cast.Caster(..support.caster(), abilities: [Spell4BaseId(250_001)])
}

/// The passive started at the time, its go answered with no unit struck.
fn passive_started(plans plans: Plans, at ms: Int) -> #(State, List(Effect)) {
  let #(state, effects) =
    cast.passive_started(
      cast: cast.new(),
      caster: caster_of_passive(),
      plans:,
      base: Spell4BaseId(250_001),
      now: support.at(ms:),
    )
  support.answered_as(
    caster: caster_of_passive(),
    state:,
    effects:,
    at: ms,
    struck: [],
    rolls: [],
  )
}

fn conversion() -> unit_properties.Modifier {
  unit_properties.Conversion(
    from: UnitProperty2Id(47),
    to: UnitProperty2Id(60),
    share: 0.25,
  )
}

pub fn the_innate_passives_go_lists_its_conversion_on_the_caster_and_starts_it_with_no_end_timer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, effects) =
    passive_started(plans: support.plans_of([passive()]), at: 1000)
  assert listed(effects:) == [229_304] as "row 229304 is listed on the caster"
  let assert [#(source, modifier)] = support.property_starts(effects:)
  assert source.effect_id == Spell4EffectsId(229_304)
  assert modifier == conversion()
  assert support.started_timers(effects:) == []
    as "flags 2: the conversion lasts until it is removed, so no end timer and no node end"
}

pub fn the_casters_death_leaves_the_innate_passives_conversion_live_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = support.plans_of([passive()])
  // The control: the same spell pressed as an ordinary ability, whose conversion a death
  // ends with the cast.
  let #(pressed, _) =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: caster_of_passive(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let #(_, ordinary_death) =
    cast.died(
      cast: pressed,
      caster: cast.Caster(..caster_of_passive(), dead: True),
      now: support.at(ms: 5000),
    )
  assert list.length(support.caster_change_ends(effects: ordinary_death)) == 1
    as "the control: a death ends an ordinary cast's modifier"
  let #(passive_state, _) = passive_started(plans:, at: 1000)
  let #(_, died) =
    cast.died(
      cast: passive_state,
      caster: cast.Caster(..caster_of_passive(), dead: True),
      now: support.at(ms: 5000),
    )
  assert support.caster_change_ends(effects: died) == []
    as "cast.died: every modifier ends but the innate passive's, so its conversion stays"
}
