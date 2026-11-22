//// A go's strike checks the apply prerequisite of each damage, periodic damage and
//// crowd-control row for each unit it would reach (`genesis_prime/game/strike` `begin`),
//// with the gate the cast rule builds in the caster's picture (`cast_tick.strike_gate`), run as
//// the pure rule it is: the effect lists are the whole observation. Expected values come
//// from these places.
//// - `Spell4Effects.prerequisiteIdTargetApply` and `prerequisiteIdCasterApply`: a row lands
////   only on the units that pass its target apply prerequisite, the unit the row reaches
////   first and the caster second, and only when its caster apply prerequisite passes
////   against the caster, as both units.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects 38307 122821
////   99347 115034`, `-- Prerequisite 3476 24214 3286 860 903`):
////   - 38307 (Spell4 23980): damage, aimed at the area, behind 3476, one type 38 condition
////     (comparison 2, value 12703).
////   - 122821 (Spell4 51989): CCStateSet, aimed at the area, behind 24214, one type 130
////     condition (comparison 2, object 465).
////   - 99347 (Spell4 43131): CCStateSet, behind caster apply 3286, one type 37 condition
////     (comparison 6, value 60).
////   - 115034 (Spell4 48757): CCStateSet, behind target apply 860, one type 37 condition
////     (comparison 6, value 10).
////   - 903: one type 28 condition (comparison 1): the unit is in combat.
//// - `Prerequisite.prerequisiteTypeId.38`: a type 38 condition of comparison 2 passes a unit
////   that is not the creature of its Creature2 row.
//// - `Prerequisite.prerequisiteTypeId.130`: a condition of comparison 2 passes a unit that
////   does not carry a cast of the caster's whose spell is in the group.
//// - `Prerequisite.prerequisiteTypeId.37`: each test takes a roll of its own, from 1 to 100
////   (1 + floor(100 r) for the draw r of 4 seed bytes over 2^32), and comparison 6 passes a
////   roll of at most its value.
//// - `Prerequisite.prerequisiteTypeId.108`: a unit the caster's picture holds no place for
////   leaves a positional condition unread.
//// - The strike rule's own doc comment: a strike is told to each selected unit in selection
////   order with 12 seed bytes for each unit; a unit with no row told is still a place of
////   the round that the go names; a refusal is left out of the go.

import cast_support as support
import fixture_tables
import genesis_prime/game/area.{type Pose}
import genesis_prime/game/cast/state.{type Caster, GoAsked} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/crowd_control
import genesis_prime/game/hit.{Rolls}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite.{NonPlayer}
import genesis_prime/game/spell_area.{
  type DamageEffect, type TickingDamage, Once, TickingDamage,
}
import genesis_prime/game/spell_plan.{
  type Condition, type CrowdControl, AimsAtArea, GatedOnTarget,
}
import genesis_prime/game/spend
import genesis_prime/game/start_place
import genesis_prime/game/strike.{
  type Effect, type Selection, type State, Aimed, Selection,
}
import genesis_prime/game/strike_tell.{Answered, Landed, Refused}
import genesis_prime/game/ticking
import genesis_prime/step.{LogDebug, Now}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import prerequisite_support
import rating_support
import strike_support

// ---- the client's rows ----

fn effect_row(id id: Int) -> spell4_effects.Spell4Effects {
  let assert Ok(row) =
    spell4_effects.get(tables: fixture_tables.shared(), id: Spell4EffectsId(id))
    as "the fixture holds the row"
  row
}

/// The client's damage row 38307: behind the type 38 target gate 3476.
fn gated_damage() -> DamageEffect {
  let assert Ok(Once(effect:)) =
    spell_area.damage_row_of(
      tables: fixture_tables.shared(),
      spell4_id: 23_980,
      effect: effect_row(id: 38_307),
    )
    as "the area reads the client's damage row 38307"
  effect
}

/// The CCStateSet row `effect_id` of the client's spell `spell4_id`.
fn control_row(
  spell4_id spell4_id: Int,
  effect_id effect_id: Int,
) -> CrowdControl {
  let tables = fixture_tables.shared()
  let assert Ok(spell) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id:,
      chain: [],
    )
    as "the client's spell plans alone"
  let assert [row] =
    list.filter(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_control),
      fn(row) { row.effect_id == Spell4EffectsId(effect_id) },
    )
    as "the client's spell holds the row"
  row
}

/// The condition the client's caster apply prerequisite 903 (the caster is in combat) makes
/// of a row.
fn in_combat() -> Condition {
  let assert Ok(condition) =
    spell_plan.row_condition_of(
      tables: fixture_tables.shared(),
      effect: spell4_effects.Spell4Effects(
        ..effect_row(id: 38_307),
        prerequisite_id_caster_apply: 903,
        prerequisite_id_target_apply: 0,
      ),
      aim: AimsAtArea,
    )
    as "a row behind the caster apply prerequisite 903 is read"
  condition
}

// ---- the round ----

fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

fn selection(
  units units: List(Int),
  blows blows: List(DamageEffect),
  ticking ticking: List(TickingDamage),
  controls controls: List(CrowdControl),
) -> Selection {
  Selection(
    asked: GoAsked(
      cast_id: 5,
      phase: 0,
      spell4_id: Spell4Id(58_591),
      primary_target: 7,
      spent: None,
      started_at: strike_support.start_pose(),
    ),
    units: list.map(units, fn(unit_id) { Aimed(unit_id:, life: 3) }),
    area: units,
    blows:,
    ticking:,
    controls:,
    gates: [],
  )
}

/// 12 seed bytes for each unit (the critical hit roll's 4 bytes, the deflect roll's, the
/// glance roll's), then the 4 bytes of each gate roll.
fn entropy(
  rolls rolls: List(#(Int, Int, Int)),
  gate gate: List(Int),
) -> BitArray {
  let hit =
    list.fold(rolls, <<>>, fn(bytes, triple) {
      <<bytes:bits, triple.0:size(32), triple.1:size(32), triple.2:size(32)>>
    })
  list.fold(gate, hit, fn(bytes, word) { <<bytes:bits, word:size(32)>> })
}

/// The seed bytes of a roll from 1 to 100: the middle of the 32-bit words that make it
/// (`prerequisite.rolls_of`).
fn word_for(roll roll: Int) -> Int {
  { roll - 1 } * 42_949_673 + 21_474_836
}

fn begun(
  selection selection: Selection,
  gate gate: cast_state.StrikeGate,
  entropy entropy: BitArray,
) -> #(State, List(Effect)) {
  strike.begin(
    strike: strike.new(),
    selection:,
    attacker: strike_support.attacker(),
    formulas: rating_support.formulas(),
    entropy:,
    gate:,
    now: at(ms: 1000),
  )
}

/// Each strike told: the unit, the damage rows' effect ids and the states' effect ids.
fn told(effects effects: List(Effect)) -> List(#(Int, List(Int), List(Int))) {
  list.filter_map(effects, fn(effect) {
    case effect {
      strike.TellStrike(
        unit_id:,
        tell: strike_tell.Strike(offence:, controls:, ..),
        ..,
      ) ->
        Ok(#(
          unit_id,
          list.map(offence.blows, fn(blow) { blow.spell4_effects_id }),
          list.map(controls, fn(control) { control.effect_id }),
        ))
      strike.StartTimer(..)
      | strike.CancelTimer(..)
      | strike.Went(..)
      | strike.Ticked(..)
      | strike.Released(..)
      | strike.Log(..) -> Error(Nil)
    }
  })
}

fn told_units(effects effects: List(Effect)) -> List(Int) {
  list.map(told(effects:), fn(entry) { entry.0 })
}

/// The structs of the round that closed in these effects.
fn went(effects effects: List(Effect)) -> List(cast_state.Struck) {
  list.flat_map(effects, fn(effect) {
    case effect {
      strike.Went(struck:, ..) -> struck
      strike.TellStrike(..)
      | strike.StartTimer(..)
      | strike.CancelTimer(..)
      | strike.Ticked(..)
      | strike.Released(..)
      | strike.Log(..) -> []
    }
  })
}

fn struck_ids(struck struck: List(cast_state.Struck)) -> List(Int) {
  list.map(struck, fn(entry) {
    case entry {
      cast_state.Hit(unit_id:, ..)
      | cast_state.Deflected(unit_id:)
      | cast_state.Immune(unit_id:, ..) -> unit_id
    }
  })
}

fn logs(effects effects: List(Effect)) -> List(#(step.LogLevel, String)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      strike.Log(level:, text:) -> Ok(#(level, text))
      strike.TellStrike(..)
      | strike.StartTimer(..)
      | strike.CancelTimer(..)
      | strike.Went(..)
      | strike.Ticked(..)
      | strike.Released(..) -> Error(Nil)
    }
  })
}

fn timers(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      strike.StartTimer(..) | strike.CancelTimer(..) -> True
      strike.TellStrike(..)
      | strike.Went(..)
      | strike.Ticked(..)
      | strike.Released(..)
      | strike.Log(..) -> False
    }
  })
}

fn answer(
  state state: State,
  unit_id unit_id: Int,
  outcome outcome: strike_tell.Outcome,
) -> #(State, List(Effect)) {
  strike.answered(
    strike: state,
    answer: Answered(
      key: strike_tell.Key(
        cast_id: 5,
        occasion: strike_tell.AtGo(phase: 0),
        unit_id:,
      ),
      outcome:,
    ),
    now: at(ms: 1100),
  )
}

fn landed() -> strike_tell.Outcome {
  strike_tell.Landed(
    descriptions: [],
    controls: [],
    armor_removed: 0,
    gates_passed: [],
  )
}

// ---- the gate ----

/// The gate of a go whose caster is `caster`, in a picture whose units are these creatures.
fn gate_of(
  caster caster: Caster,
  creatures creatures: List(#(Int, Int)),
) -> cast_state.StrikeGate {
  gate_in(cast: cast_state.new(), caster:, poses: dict.new(), creatures:)
}

fn gate_in(
  cast cast: cast_state.State,
  caster caster: Caster,
  poses poses: dict.Dict(Int, Pose),
  creatures creatures: List(#(Int, Int)),
) -> cast_state.StrikeGate {
  cast_tick.strike_gate(
    cast:,
    caster:,
    poses:,
    indexes: dict.new(),
    units: dict.from_list(
      list.map(creatures, fn(creature) {
        #(creature.0, NonPlayer(creature2_id: creature.1))
      }),
    ),
  )
}

/// A Fluff effect aimed at the area that lasts until removed, of the spell group 465.
fn marker_row() -> spell_plan.Lasting {
  spell_plan.Lasting(
    effect_id: Spell4EffectsId(1),
    phase_flags: -1,
    aim: AimsAtArea,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition: spell_plan.Always,
    tag: spend.always,
  )
}

/// A cast state in which the caster's cast of the spell group 465 is on this unit: a
/// planted spell of that group presses and its go lists the unit.
fn carrying_group_465(unit_id unit_id: Int) -> cast_state.State {
  let marker =
    support.with_effects(
      spell: spell_plan.Spell(..support.child(spell4_id: 101, base: 3), groups: [
        465,
      ]),
      kinds: [spell_plan.LastingEffect(marker_row())],
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_of([marker]),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: 11,
      target: 0,
      at: 1000,
    )
  let #(state, _) =
    support.answered_by(
      state:,
      effects: raw,
      at: 1000,
      struck: support.hits([unit_id]),
    )
  state
}

/// The caster, unit 7, standing at x and z.
fn caster_at(x x: Float, z z: Float) -> Caster {
  let caster = support.caster()
  cast_state.Caster(
    ..caster,
    place: start_place.moved(
      place: caster.place,
      x:,
      y: start_place.y(caster.place),
      z:,
    ),
  )
}

/// A damage row behind a target gate that needs the unit's place in the caster's picture:
/// the first unit seen from behind by the second (Prerequisite 5734, a type 108 condition
/// of PositionalRequirement 53).
fn behind_gated_damage() -> DamageEffect {
  let behind =
    prerequisite_support.prerequisite_of_arcs(
      row: prerequisite_support.row(id: 5734, flags: 0, conditions: [
        #(108, 1, 53, 0),
      ]),
      arcs: [prerequisite_support.behind_arc()],
    )
  spell_area.DamageEffect(
    ..strike_support.damage_effect(),
    condition: GatedOnTarget(prerequisite: behind),
  )
}

/// Unit 10 stands at the origin facing yaw 0, and the caster stands behind it.
fn poses_of_unit_10() -> dict.Dict(Int, Pose) {
  dict.from_list([#(10, prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0))])
}

// ---- tests ----

pub fn damage_row_behind_target_gate_strikes_only_passing_units_test() -> Nil {
  use <- owned_test.run(5000)
  // Unit 11 is the creature 12703 that gate 3476 (comparison 2) does not pass.
  let #(state, effects) =
    begun(
      selection: selection(
        units: [10, 11, 12],
        blows: [gated_damage()],
        ticking: [],
        controls: [],
      ),
      gate: gate_of(caster: support.caster(), creatures: [
        #(10, 500),
        #(11, 12_703),
        #(12, 600),
      ]),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told(effects:) == [#(10, [38_307], []), #(12, [38_307], [])]
    as "the units that are not the creature 12703 pass gate 3476 and are told the row; unit 11 is told nothing"
  let #(state, _) = answer(state:, unit_id: 10, outcome: landed())
  let #(_, closed) = answer(state:, unit_id: 12, outcome: landed())
  assert struck_ids(struck: went(effects: closed)) == [10, 11, 12]
    as "the go names unit 11 too, in selection order, since its other rows are the go's to apply"
}

pub fn damage_row_whose_caster_gate_fails_strikes_no_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let row = spell_area.DamageEffect(..gated_damage(), condition: in_combat())
  let chosen =
    selection(units: [10, 11], blows: [row], ticking: [], controls: [])
  let bytes = entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: [])
  let #(_, out_of_combat) =
    begun(
      selection: chosen,
      gate: gate_of(
        caster: support.caster_in_combat(in_combat: False),
        creatures: [],
      ),
      entropy: bytes,
    )
  assert told(effects: out_of_combat) == []
    as "the caster is out of combat, so gate 903 fails against the caster and no unit is struck"
  assert timers(effects: out_of_combat) == [] as "no round waits for an answer"
  assert struck_ids(struck: went(effects: out_of_combat)) == [10, 11]
    as "the go closes at once and names every selected unit, as a spell that only selects does"
  let #(_, in_combat) =
    begun(
      selection: chosen,
      gate: gate_of(
        caster: support.caster_in_combat(in_combat: True),
        creatures: [],
      ),
      entropy: bytes,
    )
  assert told_units(effects: in_combat) == [10, 11]
    as "the caster is in combat, so every unit is told"
}

pub fn ticking_damage_behind_target_gate_ticks_only_passing_units_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    TickingDamage(
      damage: gated_damage(),
      schedule: ticking.Schedule(
        delay_ms: 0,
        tick_ms: 1000,
        duration_ms: 3000,
        count: ticking.Ticks(3),
      ),
    )
  let #(state, effects) =
    begun(
      selection: selection(
        units: [10, 11],
        blows: [],
        ticking: [row],
        controls: [],
      ),
      gate: gate_of(caster: support.caster(), creatures: [
        #(10, 500),
        #(11, 12_703),
      ]),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told_units(effects:) == [10]
    as "the periodic row alone still tells its unit, and only the unit that passes gate 3476"
  let #(_, closed) = answer(state:, unit_id: 10, outcome: landed())
  let assert [
    cast_state.Hit(unit_id: 10, ticking: first, ..),
    cast_state.Hit(unit_id: 11, ticking: second, ..),
  ] = went(effects: closed)
    as "the go names both units"
  assert first == [row]
    as "the passing unit's hit carries the row, which ticks on it"
  assert second == []
    as "the failing unit's hit carries none, so nothing ticks on it"
}

pub fn control_behind_target_gate_is_told_only_to_passing_units_test() -> Nil {
  use <- owned_test.run(5000)
  // Unit 10 carries the caster's cast of the group 465, which gate 24214 (comparison 2)
  // does not pass.
  let control = control_row(spell4_id: 51_989, effect_id: 122_821)
  let #(_, effects) =
    begun(
      selection: selection(units: [10, 11], blows: [], ticking: [], controls: [
        control,
      ]),
      gate: gate_in(
        cast: carrying_group_465(unit_id: 10),
        caster: support.caster(),
        poses: dict.new(),
        creatures: [],
      ),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told(effects:) == [#(11, [], [122_821])]
    as "only unit 11, which carries no cast of group 465, is told the state"
  let assert [
    strike.TellStrike(tell: strike_tell.Strike(controls: [state], ..), ..),
  ] =
    list.filter(effects, fn(effect) {
      case effect {
        strike.TellStrike(..) -> True
        strike.StartTimer(..)
        | strike.CancelTimer(..)
        | strike.Went(..)
        | strike.Ticked(..)
        | strike.Released(..)
        | strike.Log(..) -> False
      }
    })
  assert state.instance_id
    == crowd_control.instance_id(caster_unit_id: 7, count: 1)
    as "the caster's count advances for a state told only, so unit 11's is the first"
}

pub fn control_behind_caster_gate_is_told_when_it_passes_and_not_when_it_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let control =
    spell_plan.CrowdControl(
      ..control_row(spell4_id: 51_989, effect_id: 122_821),
      condition: in_combat(),
    )
  let chosen =
    selection(units: [10], blows: [], ticking: [], controls: [control])
  let bytes = entropy(rolls: [#(0, 0, 0)], gate: [])
  let #(_, passing) =
    begun(
      selection: chosen,
      gate: gate_of(
        caster: support.caster_in_combat(in_combat: True),
        creatures: [],
      ),
      entropy: bytes,
    )
  assert told(effects: passing) == [#(10, [], [122_821])]
    as "the caster is in combat, so the state is told to the unit its aim names"
  let #(_, failing) =
    begun(
      selection: chosen,
      gate: gate_of(
        caster: support.caster_in_combat(in_combat: False),
        creatures: [],
      ),
      entropy: bytes,
    )
  assert told(effects: failing) == []
    as "the caster is out of combat, so the state is told to no unit"
  assert struck_ids(struck: went(effects: failing)) == [10]
    as "the unit is still named by the go"
}

pub fn unit_whose_every_row_fails_is_named_by_the_go_without_a_tell_test() -> Nil {
  use <- owned_test.run(5000)
  // Unit 11 is the creature 12703 and carries the caster's cast of group 465: it fails
  // the damage row's gate 3476 and the state's gate 24214. Unit 10 passes both.
  let #(state, effects) =
    begun(
      selection: selection(
        units: [10, 11],
        blows: [gated_damage()],
        ticking: [],
        controls: [control_row(spell4_id: 51_989, effect_id: 122_821)],
      ),
      gate: gate_in(
        cast: carrying_group_465(unit_id: 11),
        caster: support.caster(),
        poses: dict.new(),
        creatures: [#(10, 500), #(11, 12_703)],
      ),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told(effects:) == [#(10, [38_307], [122_821])]
    as "unit 10 is told both rows and unit 11 is told nothing"
  assert went(effects:) == [] as "the round waits for unit 10"
  let #(_, closed) = answer(state:, unit_id: 10, outcome: landed())
  let assert [
    cast_state.Hit(unit_id: 10, ..),
    cast_state.Hit(
      unit_id: 11,
      descriptions: [],
      controls: [],
      ticking: [],
      armor_removed: 0,
      ..,
    ),
  ] = went(effects: closed)
    as "the go names unit 10 then unit 11, selection order, unit 11 with an empty hit"
  Nil
}

pub fn gate_rolls_follow_each_units_hit_rolls_in_row_then_selection_order_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 99347's caster gate 3286 takes one roll (at most 60 passes), and row 115034's
  // target gate 860 takes one roll for each unit it reaches (at most 10 passes). Both rows
  // are aimed at the area here, so the plan's reach does not hide the second unit.
  let caster_gated =
    spell_plan.CrowdControl(
      ..control_row(spell4_id: 43_131, effect_id: 99_347),
      aim: AimsAtArea,
    )
  let unit_gated =
    spell_plan.CrowdControl(
      ..control_row(spell4_id: 48_757, effect_id: 115_034),
      aim: AimsAtArea,
    )
  let chosen =
    selection(units: [10, 11], blows: [], ticking: [], controls: [
      caster_gated,
      unit_gated,
    ])
  assert strike.entropy_needed(selection: chosen)
    == 2 * 12 + 3 * prerequisite.roll_bytes
    as "12 bytes for each unit, then one roll for the caster gate and one for each of the two units"
  let #(_, effects) =
    begun(
      selection: chosen,
      gate: gate_of(caster: support.caster(), creatures: []),
      entropy: entropy(
        rolls: [#(1_073_741_824, 0, 0), #(2_147_483_648, 0, 3_221_225_472)],
        gate: [word_for(roll: 1), word_for(roll: 5), word_for(roll: 50)],
      ),
    )
  assert told(effects:) == [#(10, [], [99_347, 115_034]), #(11, [], [99_347])]
    as "the caster gate takes the first roll (1, passes), unit 10 the second (5, passes) and unit 11 the third (50, fails)"
  let rolls =
    list.filter_map(effects, fn(effect) {
      case effect {
        strike.TellStrike(
          tell: strike_tell.Strike(
            striker: strike_tell.PlayerStriker(rolls:, ..),
            ..,
          ),
          ..,
        ) -> Ok(rolls)
        strike.TellStrike(..)
        | strike.StartTimer(..)
        | strike.CancelTimer(..)
        | strike.Went(..)
        | strike.Ticked(..)
        | strike.Released(..)
        | strike.Log(..) -> Error(Nil)
      }
    })
  assert rolls
    == [
      Rolls(crit: 0.25, deflect: 0.0, glance: 0.0),
      Rolls(crit: 0.5, deflect: 0.0, glance: 0.75),
    ]
    as "each unit's hit rolls are read at the offsets they have with no gate"
}

pub fn a_gate_unread_at_run_time_drops_the_row_for_that_unit_with_a_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    begun(
      selection: selection(
        units: [10, 11],
        blows: [behind_gated_damage()],
        ticking: [],
        controls: [],
      ),
      gate: gate_in(
        cast: cast_state.new(),
        caster: caster_at(x: 0.0, z: 5.0),
        poses: poses_of_unit_10(),
        creatures: [],
      ),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told_units(effects:) == [10]
    as "unit 10 stands at the origin facing yaw 0 with the caster behind it, so 5734 passes; unit 11 has no place in the picture"
  let lines = logs(effects:)
  let assert [#(LogDebug, text)] = lines
    as "one debug line says the row on unit 11 is behind a prerequisite the server cannot tell"
  assert string.contains(text, "damage effect 1")
  assert string.contains(text, "unit 11")
  assert string.contains(text, "5734")
  assert string.contains(text, "type 108")
  let #(_, closed) = answer(state:, unit_id: 10, outcome: landed())
  assert struck_ids(struck: went(effects: closed)) == [10, 11]
    as "unit 11 is still named by the go"
}

pub fn a_passing_unit_that_dies_before_it_answers_is_left_out_and_the_go_names_the_rest_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    begun(
      selection: selection(
        units: [10, 11],
        blows: [gated_damage()],
        ticking: [],
        controls: [],
      ),
      gate: gate_of(caster: support.caster(), creatures: [
        #(10, 500),
        #(11, 12_703),
      ]),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told_units(effects:) == [10]
    as "unit 10 passes and is told; unit 11 fails and is a place of the round already answered"
  let #(_, closed) =
    answer(state:, unit_id: 10, outcome: Refused(why: strike_tell.Dead))
  assert struck_ids(struck: went(effects: closed)) == [11]
    as "unit 10 died after the picture was taken, so the round closes on its refusal with no timer and the go names the unit that failed the gate"
  assert timers(effects: closed)
    == [strike.CancelTimer(timer: strike.strike_timer)]
    as "the refusal closed the round before its deadline: the strike timer set at the go is cancelled, none restarts, and the unit that failed the gate is not waited for"
}

pub fn a_told_unit_the_client_stops_showing_still_fills_its_place_and_its_gate_is_not_checked_again_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    begun(
      selection: selection(
        units: [10],
        blows: [behind_gated_damage()],
        ticking: [],
        controls: [],
      ),
      gate: gate_in(
        cast: cast_state.new(),
        caster: caster_at(x: 0.0, z: 5.0),
        poses: poses_of_unit_10(),
        creatures: [],
      ),
      entropy: entropy(rolls: [#(0, 0, 0)], gate: []),
    )
  assert told_units(effects:) == [10]
    as "unit 10 passes the positional gate at the strike and is told"
  // The client's 0x355 for the unit: the picture no longer holds it, which the strike never
  // reads again for the gate: the round holds the decision the strike made.
  let state = strike.forget(strike: state, unit_id: 10)
  let #(_, closed) =
    answer(
      state:,
      unit_id: 10,
      outcome: Landed(
        descriptions: [],
        controls: [],
        armor_removed: 2,
        gates_passed: [],
      ),
    )
  let assert [cast_state.Hit(unit_id: 10, armor_removed: 2, ..)] =
    went(effects: closed)
    as "its answer fills its place and the go names it with what it took"
  Nil
}

// ---- a spell whose gate decides nothing ----

pub fn a_row_behind_no_gate_starts_for_every_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    begun(
      selection: selection(
        units: [10, 11],
        blows: [strike_support.damage_effect()],
        ticking: [],
        controls: [],
      ),
      gate: gate_of(caster: support.caster(), creatures: []),
      entropy: entropy(rolls: [#(0, 0, 0), #(0, 0, 0)], gate: []),
    )
  assert told_units(effects:) == [10, 11]
    as "a row with no apply prerequisite is told to every unit, taking no gate roll"
}
