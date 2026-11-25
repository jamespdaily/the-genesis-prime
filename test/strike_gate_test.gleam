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
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/hit.{Rolls}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/player_state
import genesis_prime/game/prerequisite.{NonPlayer}
import genesis_prime/game/spell_area.{
  type DamageEffect, type TickingDamage, Once, TickingDamage,
}
import genesis_prime/game/spell_plan.{
  type Condition, type CrowdControl, AimsAtArea, AimsAtPrimaryTarget,
  GatedOnTarget,
}
import genesis_prime/game/spend
import genesis_prime/game/start_place
import genesis_prime/game/strike.{
  type Effect, type Selection, type State, Aimed, Selection,
}
import genesis_prime/game/strike_tell.{Answered, Landed, Refused}
import genesis_prime/game/ticking
import genesis_prime/step.{ConnectionId, LogDebug, Now}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/string
import map_support
import owned_test
import player_state_support
import prerequisite_support
import rating_support
import spell_tables
import strike_support

// ---- the client's rows ----

fn effect_row(id id: Int) -> spell4_effects.Spell4Effects {
  spell_tables.effect_row_in(tables: fixture_tables.shared(), id:)
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
      fired: False,
    ),
    units: list.map(units, fn(unit_id) { Aimed(unit_id:, life: 3) }),
    area: units,
    blows:,
    ticking:,
    controls:,
    gates: [],
    players: [],
    acts_on_each_unit: False,
    heals: [],
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
  list.map(strike_support.creatures_told(effects:), fn(told) {
    let #(unit_id, _life, strike_tell.Strike(offence:, controls:, ..)) = told
    #(
      unit_id,
      list.map(offence.blows, fn(blow) { blow.spell4_effects_id }),
      list.map(controls, fn(control) { control.effect_id }),
    )
  })
}

fn told_units(effects effects: List(Effect)) -> List(Int) {
  list.map(told(effects:), fn(entry) { entry.0 })
}

/// The structs of the round that closed in these effects.
fn went(effects effects: List(Effect)) -> List(cast_state.Struck) {
  list.flat_map(strike_support.rounds_closed(effects:), fn(closed) { closed.1 })
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
  strike_support.lines_logged(effects:)
}

fn timers(effects effects: List(Effect)) -> List(Effect) {
  strike_support.timers(effects:)
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

// ---- the heal rows a go tells a player ----

/// The player 9 on connection 3, which a heal row is told to.
fn ally() -> PlayerAddress {
  PlayerAddress(
    connection: ConnectionId(3),
    unit_id: 9,
    stay: map_support.stay(count: 2),
  )
}

/// Mind Over Body's real row 62019 as an instant heal of the primary target, behind the
/// real prerequisites `caster_apply` and `target_apply` (0 for none): no tier of the spell
/// that holds a gate is in the fixture, so the row is edited to hold one of the file's real
/// gates (3286 and 860, type 37 rolls).
fn heal_row(
  caster_apply caster_apply: Int,
  target_apply target_apply: Int,
) -> spell_area.InstantHeal {
  let assert Ok(condition) =
    spell_plan.row_condition_of(
      tables: fixture_tables.shared(),
      effect: spell4_effects.Spell4Effects(
        ..effect_row(id: 62_019),
        prerequisite_id_caster_apply: caster_apply,
        prerequisite_id_target_apply: target_apply,
      ),
      aim: AimsAtPrimaryTarget,
    )
    as "a heal row behind real prerequisites is read"
  spell_area.InstantHeal(
    effect_id: Spell4EffectsId(62_019),
    vital: effect_kind.Health,
    aim: AimsAtPrimaryTarget,
    condition:,
    formula: damage.Formula(multiplier: 1.0, base: 10.0, parameters: []),
  )
}

/// The same row with another id and no gate.
fn ungated_heal_row(effect_id effect_id: Int) -> spell_area.InstantHeal {
  spell_area.InstantHeal(
    ..heal_row(caster_apply: 0, target_apply: 0),
    effect_id: Spell4EffectsId(effect_id),
  )
}

/// The go of the player 9 as the primary target, struck with these heal rows and no creature.
fn heal_selection(heals heals: List(spell_area.InstantHeal)) -> Selection {
  let alone = selection(units: [], blows: [], ticking: [], controls: [])
  Selection(
    ..alone,
    asked: GoAsked(..alone.asked, primary_target: 9),
    players: [ally()],
    heals:,
  )
}

/// The Spell4Effects ids of the heal rows each heal strike told carries.
fn told_heals(effects effects: List(Effect)) -> List(List(Int)) {
  list.map(strike_support.players_told(effects:), fn(told) {
    list.map({ told.1 }.heals, fn(heal) { heal.effect_id.value })
  })
}

/// Whether a round closed in these effects.
fn closed(effects effects: List(Effect)) -> Bool {
  strike_support.rounds_closed(effects:) != []
}

type HealRow {
  HealRow(
    reason: String,
    heals: List(spell_area.InstantHeal),
    gate_rolls: List(Int),
    told: List(List(Int)),
    timer_started: Bool,
    logs: Int,
  )
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
  let assert [#(_, _, strike_tell.Strike(controls: [state], ..))] =
    strike_support.creatures_told(effects:)
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

pub fn a_heal_row_reaches_a_player_only_past_its_gates_and_the_rows_around_it_still_go_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 62019 behind caster apply 3286 (a type 37 roll, at most 60 passes) or target apply
  // 860 (a type 37 roll, at most 10 passes), or behind 5734 (a type 108 condition, which
  // reads the unit's place: the player has none in the caster's picture, so it is unread).
  let behind =
    prerequisite_support.prerequisite_of_arcs(
      row: prerequisite_support.row(id: 5734, flags: 0, conditions: [
        #(108, 1, 53, 0),
      ]),
      arcs: [prerequisite_support.behind_arc()],
    )
  let unread_heal =
    spell_area.InstantHeal(
      ..heal_row(caster_apply: 0, target_apply: 0),
      condition: GatedOnTarget(prerequisite: behind),
    )
  list.each(
    [
      HealRow(
        "the caster gate passes on a roll of 1: the row is told, the round waits for the answer",
        [heal_row(caster_apply: 3286, target_apply: 0)],
        [word_for(roll: 1)],
        [[62_019]],
        True,
        0,
      ),
      HealRow(
        "the caster gate fails on a roll of 100: no tell, no place, no timer, and the go names no one",
        [heal_row(caster_apply: 3286, target_apply: 0)],
        [word_for(roll: 100)],
        [],
        False,
        0,
      ),
      HealRow(
        "the target gate fails for the player on a roll of 50: the same",
        [heal_row(caster_apply: 0, target_apply: 860)],
        [word_for(roll: 50)],
        [],
        False,
        0,
      ),
      HealRow(
        "a target gate the server cannot read (the player has no place) leaves that row out with one debug line, and the ungated row beside it is told",
        [unread_heal, ungated_heal_row(effect_id: 62_020)],
        [],
        [[62_020]],
        True,
        1,
      ),
      HealRow(
        "two rows where the first fails its gate: the tell holds the second alone",
        [
          heal_row(caster_apply: 3286, target_apply: 0),
          ungated_heal_row(effect_id: 62_020),
        ],
        [word_for(roll: 100)],
        [[62_020]],
        True,
        0,
      ),
    ],
    fn(row) {
      let chosen = heal_selection(heals: row.heals)
      let #(_, effects) =
        begun(
          selection: chosen,
          gate: gate_of(caster: support.caster(), creatures: []),
          entropy: entropy(rolls: [], gate: row.gate_rolls),
        )
      assert told_heals(effects:) == row.told as row.reason
      assert timers(effects:)
        == case row.timer_started {
          True -> [
            strike.StartTimer(timer: strike.strike_timer, after_ms: 1000),
          ]
          False -> []
        }
        as row.reason
      assert list.length(logs(effects:)) == row.logs as row.reason
      assert closed(effects:) == list.is_empty(row.told)
        as "a go that told nobody closes at once, and one that told the player waits for its answer"
      assert struck_ids(struck: went(effects:)) == []
        as "the player is never named before it answers"
    },
  )
  let #(_, unread) =
    begun(
      selection: heal_selection(heals: [
        spell_area.InstantHeal(
          ..heal_row(caster_apply: 0, target_apply: 0),
          condition: GatedOnTarget(prerequisite: behind),
        ),
      ]),
      gate: gate_of(caster: support.caster(), creatures: []),
      entropy: entropy(rolls: [], gate: []),
    )
  let assert [#(LogDebug, text)] = logs(effects: unread)
    as "one debug line says the row on the player is behind a prerequisite the server cannot tell"
  assert string.contains(text, "heal effect 62019")
  assert string.contains(text, "unit 9")
  assert string.contains(text, "5734")
  assert string.contains(text, "type 108")
  // Regenerative Pulse's two rows aimed at the area alone (Spell4Effects 204551 behind
  // Prerequisite 13986, type 40 comparison 3 value 30: more than 30 percent health; 204560 behind
  // 13985, comparison 6: at most 30), told to the allies whose health the caster's picture
  // holds: unit 9 at 25 of 100, unit 12 at 80 of 100, and unit 13, whose health the picture
  // does not hold.
  let more_than_30 =
    prerequisite_support.single(id: 13_986, condition: #(40, 3, 0, 30))
  let at_most_30 =
    prerequisite_support.single(id: 13_985, condition: #(40, 6, 0, 30))
  let pulse_row = fn(effect_id, prerequisite) {
    spell_area.InstantHeal(
      ..heal_row(caster_apply: 0, target_apply: 0),
      effect_id: Spell4EffectsId(effect_id),
      aim: spell_plan.AimsAtArea,
      condition: GatedOnTarget(prerequisite:),
    )
  }
  let in_sight = fn(unit_id) {
    PlayerAddress(..ally(), unit_id:, stay: map_support.stay(count: 2))
  }
  let health_of = fn(unit_id, health) {
    #(
      unit_id,
      player_state.PlayerState(
        ..player_state_support.a_player(),
        health:,
        maximum_health: 100,
      ),
    )
  }
  let pulse =
    Selection(
      ..selection(units: [], blows: [], ticking: [], controls: []),
      players: [in_sight(9), in_sight(12), in_sight(13)],
      area: [9, 12, 13],
      heals: [pulse_row(204_551, more_than_30), pulse_row(204_560, at_most_30)],
    )
  let #(_, pulsed) =
    begun(
      selection: pulse,
      gate: gate_of(
        caster: cast_state.Caster(
          ..support.caster(),
          other_players: dict.from_list([health_of(9, 25), health_of(12, 80)]),
        ),
        creatures: [],
      ),
      entropy: entropy(rolls: [], gate: []),
    )
  assert list.map(strike_support.players_told(effects: pulsed), fn(told) {
      #(
        told.0.unit_id,
        list.map({ told.1 }.heals, fn(heal) { heal.effect_id.value }),
      )
    })
    == [#(9, [204_560]), #(12, [204_551])]
    as "the ally at 25 percent is told the row for at most 30 and not the row for more than 30, the ally at 80 percent the reverse, from the health the picture holds"
  let assert [#(LogDebug, first), #(LogDebug, second)] = logs(effects: pulsed)
    as "the ally the picture holds no health for is told neither row, and a debug line is logged for each row"
  assert string.contains(first, "heal effect 204551")
    && string.contains(second, "heal effect 204560")
    as "the lines name the rows"
  assert list.all([first, second], fn(text) {
    string.contains(text, "unit 13") && string.contains(text, "type 40")
  })
    as "each line names the unit and the type that is not read"
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
    list.filter_map(strike_support.creatures_told(effects:), fn(told) {
      case told {
        #(
          _,
          _,
          strike_tell.Strike(striker: strike_tell.PlayerStriker(rolls:, ..), ..),
        ) -> Ok(rolls)
        #(
          _,
          _,
          strike_tell.Strike(striker: strike_tell.CreatureStriker(..), ..),
        ) -> Error(Nil)
      }
    })
  assert rolls
    == [
      Rolls(crit: 0.25, deflect: 0.0, glance: 0.0),
      Rolls(crit: 0.5, deflect: 0.0, glance: 0.75),
    ]
    as "each unit's hit rolls are read at the offsets they have with no gate"
  // A player primary target with a heal row behind caster apply 3286 and target apply 860:
  // it adds one caster roll and one target roll for the player after the states', takes no
  // hit-roll bytes, and its rolls are the fourth and fifth words.
  let healing =
    Selection(
      ..chosen,
      asked: GoAsked(..chosen.asked, primary_target: 9),
      players: [ally()],
      heals: [heal_row(caster_apply: 3286, target_apply: 860)],
    )
  assert strike.entropy_needed(selection: healing)
    == 2 * 12 + 5 * prerequisite.roll_bytes
    as "12 bytes for each of the two creatures, then the rolls of the states (one for the caster gate and one for each unit) and the heal row's one caster roll and one target roll for the player: none of the player's is a hit roll"
  let #(_, with_heal) =
    begun(
      selection: healing,
      gate: gate_of(caster: support.caster(), creatures: []),
      entropy: entropy(
        rolls: [#(1_073_741_824, 0, 0), #(2_147_483_648, 0, 3_221_225_472)],
        gate: [
          word_for(roll: 1),
          word_for(roll: 5),
          word_for(roll: 50),
          word_for(roll: 1),
          word_for(roll: 50),
        ],
      ),
    )
  assert told(effects: with_heal)
    == [#(10, [], [99_347, 115_034]), #(11, [], [99_347])]
    as "the states take the first three rolls as before"
  assert told_heals(effects: with_heal) == []
    as "the heal row takes the rolls after the states': the caster roll 1 passes and the player's roll 50 fails the target gate 860 (read before the states', it would have been given the rolls 1 and 5 and told)"
  // The same row aimed at the caster and the area, whose area found the allies 9 and 12: its
  // target gate is rolled once for each ally, after the one caster roll.
  let other_ally =
    PlayerAddress(..ally(), unit_id: 12, stay: map_support.stay(count: 3))
  let area_heal =
    spell_area.InstantHeal(
      ..heal_row(caster_apply: 3286, target_apply: 860),
      aim: spell_plan.AimsAtCasterAndArea,
    )
  let healing_allies =
    Selection(
      ..chosen,
      players: [ally(), other_ally],
      area: [10, 11, 9, 12],
      heals: [area_heal],
    )
  assert strike.entropy_needed(selection: healing_allies)
    == 2 * 12 + 6 * prerequisite.roll_bytes
    as "12 bytes for each of the two creatures, the states' three rolls, then the heal row's one caster roll and one target roll for each of the two allies"
  let #(_, with_allies) =
    begun(
      selection: healing_allies,
      gate: gate_of(caster: support.caster(), creatures: []),
      entropy: entropy(
        rolls: [#(1_073_741_824, 0, 0), #(2_147_483_648, 0, 3_221_225_472)],
        gate: [
          word_for(roll: 1),
          word_for(roll: 5),
          word_for(roll: 50),
          word_for(roll: 1),
          word_for(roll: 5),
          word_for(roll: 50),
        ],
      ),
    )
  assert list.map(strike_support.players_told(effects: with_allies), fn(told) {
      told.0.unit_id
    })
    == [9]
    as "the caster roll 1 passes, ally 9's roll 5 passes the target gate 860 and ally 12's roll 50 fails it: only ally 9 is told"
  // The same row aimed at the area alone, whose area took the caster (unit 7) and the ally 9
  // as candidates: the caster's side is rolled once, then the target gate once for the
  // caster as a unit the row reaches and once for the ally, so the go draws no roll of its own.
  let caster_address =
    PlayerAddress(
      connection: ConnectionId(2),
      unit_id: 7,
      stay: map_support.stay(count: 1),
    )
  let at_the_area_alone =
    spell_area.InstantHeal(
      ..heal_row(caster_apply: 3286, target_apply: 860),
      aim: spell_plan.AimsAtArea,
    )
  let with_the_caster =
    Selection(
      ..selection(units: [], blows: [], ticking: [], controls: []),
      players: [caster_address, ally()],
      area: [7, 9],
      heals: [at_the_area_alone],
    )
  assert strike.entropy_needed(selection: with_the_caster)
    == 3 * prerequisite.roll_bytes
    as "one roll for the caster's side and one for each of the two units the row reaches, the caster among them"
  list.each(
    [
      #(
        "the caster's side 1 and its own target gate 5 pass, the ally's 50 fails: the caster alone, which the go lists, and nobody is told",
        [word_for(roll: 1), word_for(roll: 5), word_for(roll: 50)],
        [7],
        [],
      ),
      #(
        "the caster's own target gate fails (50), the ally's passes (5): the ally alone is told and the go names no caster",
        [word_for(roll: 1), word_for(roll: 50), word_for(roll: 5)],
        [],
        [[62_019]],
      ),
    ],
    fn(row) {
      let #(reason, gate_rolls, struck, told) = row
      let #(_, effects) =
        begun(
          selection: with_the_caster,
          gate: gate_of(caster: support.caster(), creatures: []),
          entropy: entropy(rolls: [], gate: gate_rolls),
        )
      assert told_heals(effects:) == told as reason
      assert list.map(strike_support.players_told(effects:), fn(told) {
          told.0.unit_id
        })
        == list.map(told, fn(_) { 9 })
        as "the caster is never told a strike: it applies its own heal at the go"
      assert struck_ids(struck: went(effects:)) == struck as reason
    },
  )
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
