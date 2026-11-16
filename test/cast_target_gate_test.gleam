//// The cast rule's rows behind a target apply prerequisite (`genesis_prime/game/cast`).
//// Expected values come from these places:
//// - `Spell4Effects.prerequisiteIdTargetApply`: a row lands only on the units that pass
////   its gate, the unit the row reaches first and the caster second.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects 144869 179592
////   177849 58547 67780 38480` and `-- Prerequisite 13148 20210 903 8757 10849 3475 5734`):
////   - Ruin's remove 144869 (Spell4 38841): type 80, aimed at the area, behind 13148, one
////     type 130 condition (comparison 1, object 464): the unit carries a cast of the
////     caster's whose spell is in spell group 464.
////   - Row 179592 (Spell4 70611): type 81, aimed at the primary target and the area
////     (flags 6), behind 20210, three type 38 conditions (comparison 1, values 48009,
////     48404 and 48494) of which one is enough (flags 1).
////   - Row 177849 (Spell4 62637): type 81, aimed at the caster, behind 903, one type 28
////     condition (comparison 1): the caster is in combat.
////   - Heals 58547 (Spell4 31475) and 67780 (Spell4 34330), aimed at the caster, behind
////     8757 and 10849: a type 38 condition of comparison 1 on a Creature2 row.
////   - Row 38480 (Spell4 24079): type 11, aimed at the area, behind 3475, a type 38
////     condition (comparison 1, value 12700).
////   - 5734: one type 108 condition (comparison 1, row 53), the first unit seen from
////     behind by the second.
//// - `Prerequisite.prerequisiteTypeId.38`: a type 38 condition of comparison 1 passes when
////   the first unit is the creature of its Creature2 row, and one of comparison 2 when it
////   is not; the caster is a player, so comparison 1 fails it and comparison 2 passes it.
//// - `Prerequisite.prerequisiteTypeId.37`: a type 37 condition takes one roll from 1 to 100
////   each time it is tested ("the units and the objectId are not read"), and Prerequisite
////   4585 (comparison 6 on 50) passes a roll of at most 50. A row behind it is tested once
////   for each unit it reaches, so each unit takes a roll of its own, in the order of the
////   units. The client's rows hold 117 type 37 conditions, and 3 rows of Spell4Effects are
////   behind a target gate that holds one (`table_rows -- Prerequisite
////   prerequisiteTypeId0=37`, then `-- Spell4Effects prerequisiteIdTargetApply=<id>` for
////   each): one type 80 remove, 173068 (Spell4 41193, targetFlags 2, past the caster, gate
////   650: comparison 6 on 50), and two type 4 crowd control rows, 115034 and 176214, which
////   a plan reads behind their gates and a go's strike checks (`strike_gate_test`).
//// - `Prerequisite.prerequisiteTypeId.108`: a unit the caster's picture holds no place for
////   leaves a positional condition unread.

import cast_support as support
import genesis_prime/game/area.{type Pose}
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Caster, type Effect, type Struck} as cast_state
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite.{NonPlayer}
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, AimsAtArea, AimsAtCaster, GatedOnTarget,
}
import genesis_prime/game/spend
import genesis_prime/game/start_place
import genesis_prime/game/unit_properties
import genesis_prime/message/spell_go
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{
  Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import prerequisite_support
import spell_tables

// The planted bases 1, 2 and 3 are the bag indices 8, 10 and 11
// (`cast_support.abilities`).
const bag_of_base_1 = 8

const bag_of_base_2 = 10

const bag_of_base_3 = 11

/// The effect ids each unit's entry of the go lists, by unit, in unit order. A struck
/// unit is an entry of the go whatever the rows do, so a unit that lists no effect is left out.
fn listed(effects effects: List(Effect)) -> List(#(Int, List(Int))) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  list.map(decoded.targets, fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) { effect.spell4_effects_id })
        |> list.sort(int.compare),
    )
  })
  |> list.filter(fn(entry) { entry.1 != [] })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// A Fluff effect aimed at the area that lasts until removed.
fn marker_row(id id: Int) -> spell_plan.Lasting {
  spell_plan.Lasting(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    aim: AimsAtArea,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition: spell_plan.Always,
    tag: spend.always,
  )
}

// ---- a remove ----

pub fn remove_lands_only_on_the_unit_carrying_the_casters_group_test() -> Nil {
  use <- owned_test.run(60_000)
  // Two markers of spell group 23183, only the first also of group 464 (the group Ruin's
  // gate 13148 reads); Ruin's remove takes the group's casts off the units it reaches.
  // The remove is the client's row 144869 with its selector a group the planted markers
  // hold, since a planted spell takes the Spell4Base of an ability of the bag.
  let real = spell_tables.client_spell(spell4_id: 38_841)
  let assert [row] = real.removes as "Ruin's tree holds the one remove 144869"
  assert row.effect_id == Spell4EffectsId(144_869)
  let assert GatedOnTarget(..) = row.condition
    as "the remove keeps its target apply prerequisite 13148"
  let ruin =
    spell_plan.Spell(..support.child(spell4_id: 38_841, base: 1), removes: [
      spell_plan.ForceRemove(..row, selector: lasting.Group(23_183)),
    ])
  let marked_twice =
    spell_plan.Spell(
      ..support.child(spell4_id: 101, base: 3),
      groups: [464, 23_183],
      lasting: [marker_row(id: 1)],
    )
  let marked_once =
    spell_plan.Spell(
      ..support.child(spell4_id: 102, base: 2),
      groups: [23_183],
      lasting: [marker_row(id: 2)],
    )
  let plans = support.plans_of([ruin, marked_twice, marked_once])
  let press = fn(state, bag, struck, at) {
    let #(state, raw) =
      support.pressed_raw_in(
        plans:,
        state:,
        caster: support.caster(),
        bag_index: bag,
        target: 0,
        at:,
      )
    support.answered_by(state:, effects: raw, at:, struck:)
  }
  let #(state, first) =
    press(cast_state.new(), bag_of_base_3, support.hits([20]), 1000)
  let #(state, second) = press(state, bag_of_base_2, support.hits([21]), 1100)
  let #(_, removal) = press(state, bag_of_base_1, support.hits([20, 21]), 1200)
  assert support.removed_targets(support.writes(effects: removal))
    == [#(support.pressed_id(effects: first), [20])]
    as "unit 20 carries the caster's cast of group 464 and passes 13148; unit 21's cast is of group 23183 alone, so Ruin leaves it"
  assert support.pressed_id(effects: second)
    != support.pressed_id(effects: first)
}

// ---- a lasting row aimed at the primary target and the area ----

/// What a go lists when the units given are these creatures, behind gate 20210; the
/// round strikes unit 20 and unit 21.
fn listed_for_units(
  units units: List(#(Int, prerequisite.FirstUnit)),
) -> List(#(Int, List(Int))) {
  let spell =
    support.client_lasting(spell4_id: 70_611, base: 3, effect_ids: [179_592])
  let plans = support.plans_of([spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 20,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_known(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1000,
      struck_of: fn(_) { support.hits([20, 21]) },
      rolls: [],
      poses: dict.new(),
      units: dict.from_list(units),
    )
  listed(effects:)
}

/// What a go lists when unit 20 and unit 21 are the given creatures, behind gate 20210.
fn listed_for_creatures(
  creature_20 creature_20: Int,
  creature_21 creature_21: Int,
) -> List(#(Int, List(Int))) {
  listed_for_units(units: [
    #(20, NonPlayer(creature_20)),
    #(21, NonPlayer(creature_21)),
  ])
}

pub fn is_creature_gate_lands_only_on_the_named_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  assert listed_for_creatures(creature_20: 48_404, creature_21: 1)
    == [#(20, [179_592])]
    as "unit 20 is the creature 48404, one of the three 20210 names, so the row lands there; unit 21 is creature 1, none of them"
  assert listed_for_creatures(creature_20: 1, creature_21: 48_404)
    == [#(21, [179_592])]
    as "with the creatures swapped the row lands on unit 21 and not on unit 20: the gate reads each unit's own creature, not the first unit or the primary target"
  assert listed_for_units(units: [
      #(7, NonPlayer(48_404)),
      #(20, NonPlayer(1)),
      #(21, NonPlayer(1)),
    ])
    == []
    as "the caster, unit 7, is the creature 48404 and the units struck are not: the gate reads the units the row reaches, so the row lists nothing"
}

pub fn a_gate_that_asks_for_another_creature_passes_the_casters_own_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // A type 38 condition of comparison 2 passes a first unit that is not the creature; the
  // caster is a player, so the gate fails a unit that is the creature and would pass the
  // caster if it were read as the first unit.
  let spell =
    spell_plan.Spell(..support.child(spell4_id: 101, base: 3), lasting: [
      spell_plan.Lasting(
        ..marker_row(id: 7),
        condition: GatedOnTarget(
          prerequisite: prerequisite_support.single(id: 5001, condition: #(
            38,
            2,
            0,
            48_404,
          )),
        ),
      ),
    ])
  let plans = support.plans_of([spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 20,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_known(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1000,
      struck_of: fn(_) { support.hits([20, 21]) },
      rolls: [],
      poses: dict.new(),
      units: dict.from_list([
        #(20, NonPlayer(48_404)),
        #(21, NonPlayer(1)),
      ]),
    )
  assert listed(effects:) == [#(21, [7])]
    as "unit 20 is the creature 48404 and fails comparison 2, unit 21 is not and passes it: with the caster, a player, as the first unit both would pass"
}

// ---- a row aimed at the caster ----

pub fn self_aimed_row_gate_reads_the_casters_whole_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    support.plans_of([
      support.client_lasting(spell4_id: 62_637, base: 3, effect_ids: [177_849]),
    ])
  let #(_, in_combat) =
    support.press_as(
      plans:,
      state: cast_state.new(),
      caster: support.caster_in_combat(in_combat: True),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert listed(effects: in_combat) == [#(7, [177_849])]
    as "gate 903 is type 28, the caster in combat: the row lands on the caster"
  let #(_, out_of_combat) =
    support.press_as(
      plans:,
      state: cast_state.new(),
      caster: support.caster_in_combat(in_combat: False),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert listed(effects: out_of_combat) == []
    as "out of combat the same gate fails the caster and the row is not applied"
}

// ---- type 37: the roll ----

/// Prerequisite 4585: one type 37 condition, comparison 6 on 50.
fn chance_gate() -> prerequisite.Prerequisite {
  prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50))
}

/// A planted spell holding one marker row with this aim behind the chance gate as its
/// target apply prerequisite.
fn chance_spell(aim aim: spell_plan.Aim) -> Spell {
  spell_plan.Spell(..chance_child(aim:), spell4_base_id: Spell4BaseId(3))
}

/// The same as a child of its own base, for a Proxy to start.
fn chance_child(aim aim: spell_plan.Aim) -> Spell {
  spell_plan.Spell(..support.child(spell4_id: 101, base: 101), lasting: [
    spell_plan.Lasting(
      ..marker_row(id: 7),
      aim:,
      condition: GatedOnTarget(prerequisite: chance_gate()),
    ),
  ])
}

pub fn a_caster_row_behind_a_type_37_target_gate_takes_one_roll_and_lands_when_it_passes_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = support.plans_of([chance_spell(aim: AimsAtCaster)])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
  assert cast.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "Prerequisite 4585 is type 37: the target gate of the row takes one roll for the caster"
  let went = fn(roll) {
    let #(_, effects) =
      support.answered_as(
        caster: support.caster(),
        state:,
        effects: raw,
        at: 1000,
        struck: [],
        rolls: [roll],
      )
    listed(effects:)
  }
  assert went(50) == [#(7, [7])] as "a roll of 50 passes comparison 6 on 50"
  assert went(51) == [] as "a roll of 51 fails the gate: the row is not applied"
}

pub fn each_unit_a_row_past_the_caster_reaches_takes_a_roll_of_its_own_in_unit_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = support.plans_of([chance_spell(aim: AimsAtArea)])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
  let struck = support.hits([20, 21, 22])
  assert cast.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck:,
    )
    == 3
    as "Prerequisite 4585 is type 37 and the row reaches three units, each tested once: three rolls"
  assert cast.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: support.hits([20]),
    )
    == 1
    as "one unit, one roll"
  let went = fn(rolls) {
    let #(_, effects) =
      support.answered_as(
        caster: support.caster(),
        state:,
        effects: raw,
        at: 1000,
        struck:,
        rolls:,
      )
    effects
  }
  assert listed(effects: went([50, 51, 1])) == [#(20, [7]), #(22, [7])]
    as "unit 20 takes the first roll 50, which passes comparison 6 on 50, unit 21 the second, 51, which fails, and unit 22 the third, 1, which passes"
  assert listed(effects: went([51, 50, 100])) == [#(21, [7])]
    as "the rolls in another order land the row on the other unit: each roll is the next unit's, in the order of the units"
  assert listed(effects: went([1, 1, 1]))
    == [#(20, [7]), #(21, [7]), #(22, [7])]
    as "every roll passes: the row lands on every unit"
  let none_given = went([50])
  assert listed(effects: none_given) == [#(20, [7])]
    as "a unit left without a roll leaves the gate unread, and the row lands only on the unit that had one"
  let lines =
    list.filter(support.logs(effects: none_given), fn(line) {
      line.0 == LogDebug && string.contains(line.1, "type 37")
    })
  assert list.length(lines) == 2
    as "one debug line for each of units 21 and 22 says the row is behind a prerequisite of type 37, which is not read"
}

pub fn rolls_needed_counts_a_union_row_once_for_each_unit_it_reaches_test() -> Nil {
  use <- owned_test.run(60_000)
  // `Spell4Effects.targetFlags` 3 names bit 1 (the caster) and bit 2 (the primary target).
  // A press has the caster as its own primary target, so the cast whose primary target is
  // another unit is the child a Proxy starts on the creature 20 the parent struck: its
  // row behind the type 37 gate reaches the caster, unit 7, and the creature, unit 20, and
  // the gate is tested once for each, so the child's go takes two rolls.
  let assert Ok(union) = spell_plan.aim_of(target_flags: 3)
  let plans =
    support.plans_starting_on_each_struck(started: chance_child(aim: union))
  let #(pressed, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let assert [parent_asked] = support.goes_asked(effects: raw)
  let #(state, started) =
    cast.went(
      cast: pressed,
      caster: support.caster(),
      now: support.at(ms: 1000),
      cast_id: parent_asked.cast_id,
      phase: parent_asked.phase,
      spell: Error(Nil),
      struck: support.hits([20]),
      poses: dict.new(),
      indexes: dict.new(),
      units: dict.new(),
      rolls: [],
      gates_passed: dict.new(),
    )
  let assert [child_asked] = support.goes_asked(effects: started)
    as "the parent's go starts the child, which asks for its own go"
  assert child_asked.primary_target == 20
    as "the child's primary target is the creature the parent struck"
  assert cast.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: child_asked.cast_id,
      phase: child_asked.phase,
      struck: [],
    )
    == 2
    as "Prerequisite 4585 is type 37 and the row reaches the caster and the creature, each tested once: two rolls"
  let went = fn(rolls) {
    let #(_, effects) =
      support.answered_each(
        caster: support.caster(),
        state: pressed,
        effects: raw,
        at: 1000,
        struck_of: fn(asked) {
          case asked.spell4_id == Spell4Id(101) {
            True -> []
            False -> support.hits([20])
          }
        },
        rolls:,
        poses: dict.new(),
      )
    support.child_go_listing(effects: list.append(raw, effects))
  }
  assert went([50, 51]) == [#(7, [7])]
    as "the caster takes the first roll, 50, which passes comparison 6 on 50, and the creature the second, 51, which fails"
  assert went([51, 50]) == [#(20, [7])]
    as "the rolls the other way round land the row on the creature: the go takes exactly one roll for each unit, caster first"
  assert went([1, 1]) == [#(7, [7]), #(20, [7])]
    as "every roll passes: the row lands on both units"
}

// ---- a positional gate ----

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

pub fn struck_unit_with_no_pose_leaves_a_positional_gate_unread_test() -> Nil {
  use <- owned_test.run(60_000)
  let behind =
    prerequisite_support.prerequisite_of_arcs(
      row: prerequisite_support.row(id: 5734, flags: 0, conditions: [
        #(108, 1, 53, 0),
      ]),
      arcs: [prerequisite_support.behind_arc()],
    )
  let spell =
    spell_plan.Spell(..support.child(spell4_id: 101, base: 3), lasting: [
      spell_plan.Lasting(
        ..marker_row(id: 7),
        condition: GatedOnTarget(prerequisite: behind),
      ),
    ])
  let plans = support.plans_of([spell])
  let caster = caster_at(x: 0.0, z: 5.0)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let poses: dict.Dict(Int, Pose) =
    dict.from_list([#(20, prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0))])
  let struck: List(Struck) = support.hits([20, 21])
  let #(_, effects) =
    support.answered_posed(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck:,
      rolls: [],
      poses:,
    )
  assert listed(effects:) == [#(20, [7])]
    as "unit 20 stands at the origin facing yaw 0 and the caster stands behind it, so 5734 passes; unit 21 has no place in the picture, so its row is not applied"
  let lines =
    list.filter(support.logs(effects:), fn(line) {
      line.0 == LogDebug && string.contains(line.1, "unit 21")
    })
  assert list.length(lines) == 1
    as "one debug line says the row on unit 21 is behind a prerequisite the server cannot tell"
  assert list.all(lines, fn(line) {
    string.contains(line.1, "not read") && string.contains(line.1, "type 108")
  })
  assert list.all(support.logs(effects:), fn(line) {
    !string.contains(line.1, "unit 20")
  })
    as "unit 20 passes and is not logged"
}

// ---- heals and a modifier ----

/// A shield heal of Energize's formula aimed at the caster, behind the gate.
fn healing(
  id id: Int,
  gate gate: prerequisite.Prerequisite,
) -> spell_plan.Heal {
  spell_plan.Heal(
    effect_id: Spell4EffectsId(id),
    vital: effect_kind.Shield,
    phase_flags: -1,
    aim: AimsAtCaster,
    condition: GatedOnTarget(prerequisite: gate),
    tag: spend.always,
    formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 22, value: 0.3),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
    delay_ms: 0,
  )
}

/// A type 38 target gate of this id, comparison and Creature2 row.
fn creature_gate(
  id id: Int,
  comparison comparison: Int,
  creature creature: Int,
) -> prerequisite.Prerequisite {
  prerequisite_support.single(id:, condition: #(38, comparison, 0, creature))
}

pub fn heal_and_modifier_behind_target_gate_reach_only_passing_units_test() -> Nil {
  use <- owned_test.run(60_000)
  // Heal 58547's gate shape (38, comparison 1) fails a player caster, so the heal that
  // would be 67780's is dropped; a heal behind comparison 2 passes it. The modifier
  // 38480's shape (38, comparison 1, 12700) lands on the creature 12700 alone.
  let slowing =
    spell_plan.PropertyModifier(
      effect_id: Spell4EffectsId(38_480),
      phase_flags: 1,
      change: spell_plan.StruckChange(
        modifier: unit_properties_change(),
        aim: AimsAtArea,
      ),
      row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
      condition: GatedOnTarget(prerequisite: creature_gate(
        id: 3475,
        comparison: 1,
        creature: 12_700,
      )),
      tag: spend.always,
      armor: None,
    )
  let spell =
    spell_plan.Spell(
      ..support.child(spell4_id: 101, base: 3),
      heals: [
        healing(
          id: 58_547,
          gate: creature_gate(id: 8757, comparison: 2, creature: 25_708),
        ),
        healing(
          id: 67_780,
          gate: creature_gate(id: 10_849, comparison: 1, creature: 25_708),
        ),
      ],
      modifiers: [slowing],
    )
  let plans: Plans = support.plans_of([spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let struck =
    list.map([21, 22], fn(unit_id) {
      cast_state.Hit(
        unit_id:,
        unit: cast_state.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [],
        armor_removed: 0,
        ticking: [],
      )
    })
  let #(_, effects) =
    support.answered_known(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1000,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
      units: dict.from_list([#(21, NonPlayer(12_700)), #(22, NonPlayer(1))]),
    )
  assert listed(effects:) == [#(7, [58_547]), #(21, [38_480])]
    as "the caster passes comparison 2 on 25708 and fails comparison 1, so only 58547 lists; creature 21 is 12700 and 22 is not, so only 21 holds the modifier"
  assert list.length(support.target_changes(effects:)) == 1
    as "the modifier starts on the one creature it reaches"
}

fn unit_properties_change() -> unit_properties.Modifier {
  unit_properties.Change(
    property: UnitProperty2Id(100),
    mode: 2,
    multiplier: 0.5,
    flat: 0.0,
    per_level: 0.0,
  )
}
