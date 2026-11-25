//// The cast rule's unit states on creatures (`genesis_prime/game/cast`,
//// `genesis_prime/game/cast/control` `unit_states_told`, `genesis_prime/game/cast/press`
//// `unit_state_refusal`). Expected values come from these places:
//// - `Spell4Effects.effectType.15`: a UnitStateSet row holds its state on the unit its
////   targetFlags name for its durationTime after its delayTime; the client reads no row of
////   the type, so what the server tells is its own. The rows are 64365 (Spell4 32683, state
////   6, targetFlags 2, durationTime 8500), 204411 (Spell4 48565, targetFlags 4, delayTime
////   500, durationTime 2000) and Spell4 4178's seven rows (7022, 10150 to 10157: states 6
////   and 13 to 18 on one unit), `table_rows -- Spell4Effects effectType=15`.
//// - The design of the step: the creature owns the end of a state, so the cast tells every
////   creature the go hit in the go's own step with the rows and the go's time and arms no
////   timer; the strike time of the round tells which life it hit.
//// - `Spell4Effects.phaseFlags`: bit n is phase n; a row applies in the phases it names.
//// - `Prerequisite.prerequisiteTypeId.37` (comparison 6, value 50, row 4585) and `.38`
////   (Prerequisite 20210's shape): the gates a unit state row may sit behind.
//// - `Spell.CodeEnumCastResult.306_308`: 306 is "Target immune to hostile spells" and 308
////   "Target immune to beneficial spells"; the client's own check of a unit's invulnerability
////   comes first of its target checks (`0x1403b2240` line 44, result 96), before the crowd
////   control checks (122 and the others).
//// - `Spell4TargetMechanics.flags` bit 0: the client's split of a spell into hostile and
////   beneficial (`Unit.GetBuffs` keeps a beneficial spell's buffs apart). Spell4TargetMechanics 3 (flags 16) is the row of Spell4Base
////   42972, the base of Spell4 64944, an aimed shortcut spell.
//// - `opcode.0x247.immunity` and `opcode.0x7f4`: a unit the creature answered `Immune` for is
////   named in the go and followed by a combat log entry of type 18 for the caster.

import cast_support as support
import fixture_tables
import genesis_prime/game/activate.{Body, Usable}
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/held_state
import genesis_prime/game/prerequisite
import genesis_prime/game/shortcut_spell
import genesis_prime/game/shown
import genesis_prime/game/spell_plan.{type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/game/start_place
import genesis_prime/game/unit_state
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_objective_ability.{CastObjectiveAbility}
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_immunity.{CombatLogImmunity}
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState, Stun}
import genesis_prime/message/spell_go
import genesis_prime/step.{LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Spell4EffectsId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{Attackable, Hostile}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/set
import gleam/string
import owned_test
import place_support
import planted_table.{Integer}
import prerequisite_support

/// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// A unit state row of Spell4Effects 64365's shape: phase 0, aimed at the units the go hit.
fn state_row(
  effect_id effect_id: Int,
  state state: Int,
  delay_ms delay_ms: Int,
  duration_ms duration_ms: Int,
) -> spell_plan.UnitState {
  spell_plan.UnitState(
    effect_id: Spell4EffectsId(effect_id),
    phase_flags: 1,
    aim: spell_plan.AimsAtArea,
    row: unit_state.Row(state:, delay_ms:, duration_ms:),
    condition: Always,
    tag: spend.always,
  )
}

fn holder(rows rows: List(spell_plan.UnitState)) -> Spell {
  support.with_effects(
    spell: support.child(spell4_id: 32_683, base: 3),
    kinds: list.map(rows, spell_plan.UnitStateEffect),
  )
}

/// A creature the round hit in `life` at the monotonic time 900, before the go at 1000.
fn hit(unit_id unit_id: Int, life life: Int) -> cast_state.Struck {
  support.creature_hit(unit_id:, life:, struck_at_ms: 900)
}

/// The press of the spell at 1000 aimed at `target`, and the go its round answers at 1000.
fn went(
  spell spell: Spell,
  target target: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(cast_state.Effect)) {
  support.pressed_and_answered(
    spell:,
    bag_index: bag_of_base_3,
    target:,
    struck:,
    at: 1000,
  )
}

fn holding(
  unit_id unit_id: Int,
  life life: Int,
  rows rows: List(unit_state.Row),
) -> cast_state.Effect {
  cast_state.CreatureHoldsUnitStates(
    unit_id:,
    life:,
    struck_at_ms: 900,
    went_at_ms: 1000,
    rows:,
  )
}

fn row_of(
  state state: Int,
  delay_ms delay_ms: Int,
  duration_ms duration_ms: Int,
) -> unit_state.Row {
  unit_state.Row(state:, delay_ms:, duration_ms:)
}

pub fn a_go_tells_a_hit_creature_its_unit_states_once_after_the_go_frames_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 4178's seven rows (7022 and 10150 to 10157: states 6 and 13 to 18) sit on one
  // unit: the creature is told once, with the rows in row order.
  let rows =
    list.map(
      [#(1, 6), #(2, 13), #(3, 14), #(4, 15), #(5, 16), #(6, 17), #(7, 18)],
      fn(row) {
        state_row(
          effect_id: 99_000 + row.0,
          state: row.1,
          delay_ms: 0,
          duration_ms: 30_000,
        )
      },
    )
  let #(_, effects) =
    went(spell: holder(rows:), target: 0, struck: [hit(unit_id: 21, life: 3)])
  assert support.unit_states_told(effects:)
    == [
      holding(
        unit_id: 21,
        life: 3,
        rows: list.map([6, 13, 14, 15, 16, 17, 18], fn(state) {
          row_of(state:, delay_ms: 0, duration_ms: 30_000)
        }),
      ),
    ]
    as "one tell for the creature, its seven rows in row order"
  let position_of = fn(wanted) {
    let assert Ok(found) =
      list.key_find(
        list.index_map(effects, fn(effect, i) { #(effect, i) }),
        wanted,
      )
    found
  }
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert [told] = support.unit_states_told(effects:)
  assert position_of(cast_state.Send(frame: go)) < position_of(told)
    as "the go's frame is written before the creature is told, so the caster sees the go first"
}

pub fn the_tell_carries_the_life_and_both_times_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 204411's shape: delay 500, duration 2000.
  let #(_, effects) =
    went(
      spell: holder(rows: [
        state_row(effect_id: 99_001, state: 6, delay_ms: 500, duration_ms: 2000),
      ]),
      target: 0,
      struck: [hit(unit_id: 21, life: 3), hit(unit_id: 23, life: 5)],
    )
  assert support.unit_states_told(effects:)
    == [
      holding(unit_id: 21, life: 3, rows: [
        row_of(state: 6, delay_ms: 500, duration_ms: 2000),
      ]),
      holding(unit_id: 23, life: 5, rows: [
        row_of(state: 6, delay_ms: 500, duration_ms: 2000),
      ]),
    ]
    as "each creature in the life the round hit, struck_at_ms the round's time 900, went_at_ms the go's time 1000, and the row's delay and duration as the plan read them"
}

pub fn a_unit_the_round_left_out_or_deflected_is_told_no_state_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    holder(rows: [
      state_row(effect_id: 99_001, state: 6, delay_ms: 0, duration_ms: 8500),
    ])
  let #(_, deflected) =
    went(spell:, target: 0, struck: [
      cast_state.Deflected(unit_id: 21),
      hit(unit_id: 23, life: 5),
    ])
  assert support.unit_states_told(effects: deflected)
    == [
      holding(unit_id: 23, life: 5, rows: [
        row_of(state: 6, delay_ms: 0, duration_ms: 8500),
      ]),
    ]
    as "a deflected creature took no effect of the strike (a server guess, as a throw's); only the one the go hit is told"
  // A creature that refused the strike as dead, or gave no answer by the round's deadline, is
  // left out of the round (`strike.filled`), so the go does not name it.
  let #(_, nobody) = went(spell:, target: 0, struck: [])
  assert support.unit_states_told(effects: nobody) == []
    as "a round that hit nobody tells nobody"
}

pub fn a_row_of_another_phase_or_behind_a_failed_gate_is_not_told_test() -> Nil {
  use <- owned_test.run(5000)
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(_, other_phase) =
    went(
      spell: holder(rows: [
        spell_plan.UnitState(
          ..state_row(
            effect_id: 99_001,
            state: 6,
            delay_ms: 0,
            duration_ms: 8500,
          ),
          phase_flags: 2,
        ),
      ]),
      target: 0,
      struck: creatures,
    )
  assert support.unit_states_told(effects: other_phase) == []
    as "phaseFlags 2 names phase 1 only: the go of phase 0 tells nothing"
  // Prerequisite 4585 is a type 37 chance gate (comparison 6, value 50) on the caster; the go
  // draws one roll for it, and a roll of 51 fails.
  let gated =
    spell_plan.UnitState(
      ..state_row(effect_id: 99_001, state: 6, delay_ms: 0, duration_ms: 8500),
      condition: spell_plan.GatedOnCaster(gates: [
        prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50)),
      ]),
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell: holder(rows: [gated])),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let rolled = fn(roll) {
    let #(_, effects) =
      support.answered_as(
        caster: support.caster(),
        state:,
        effects: raw,
        at: 1000,
        struck: creatures,
        rolls: [roll],
      )
    support.unit_states_told(effects:)
  }
  assert rolled(50)
    == [
      holding(unit_id: 21, life: 3, rows: [
        row_of(state: 6, delay_ms: 0, duration_ms: 8500),
      ]),
    ]
    as "a roll of 50 passes comparison 6 on 50 and the creature is told"
  assert rolled(51) == [] as "a roll of 51 fails the caster gate: no tell"
  // Prerequisite.prerequisiteTypeId.38, Prerequisite 20210's shape: comparison 1 passes the
  // unit that is the creature of Creature2 48404. Unit 23 is that creature and 21 is not.
  let target_gated =
    spell_plan.UnitState(
      ..state_row(effect_id: 99_001, state: 6, delay_ms: 0, duration_ms: 8500),
      condition: spell_plan.GatedOnTarget(
        prerequisite: prerequisite_support.single(id: 20_210, condition: #(
          38,
          1,
          0,
          48_404,
        )),
      ),
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell: holder(rows: [target_gated])),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(_, answered) =
    support.answered_known(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1000,
      struck_of: fn(_) {
        [hit(unit_id: 21, life: 3), hit(unit_id: 23, life: 5)]
      },
      rolls: [],
      poses: dict.new(),
      units: dict.from_list([
        #(21, prerequisite.NonPlayer(1)),
        #(23, prerequisite.NonPlayer(48_404)),
      ]),
    )
  assert support.unit_states_told(effects: answered)
    == [
      holding(unit_id: 23, life: 5, rows: [
        row_of(state: 6, delay_ms: 0, duration_ms: 8500),
      ]),
    ]
    as "creature 23 passes the target gate and is told; creature 21 fails it and holds nothing"
}

pub fn a_unit_state_never_names_the_caster_or_another_player_test() -> Nil {
  use <- owned_test.run(5000)
  // A row aimed at the primary target and the area, pressed on the caster's own unit 7,
  // whose round holds another player's unit 9 and a creature 21: only a creature the round
  // hit is told (a server guess: no client row shows a player holding a state).
  let wide =
    spell_plan.UnitState(
      ..state_row(effect_id: 99_001, state: 6, delay_ms: 0, duration_ms: 8500),
      aim: spell_plan.AimsAtPrimaryTargetAndArea,
    )
  let #(_, effects) =
    went(spell: holder(rows: [wide]), target: 7, struck: [
      cast_state.Hit(
        unit_id: 9,
        unit: cast_state.HitPlayer,
        descriptions: [],
        controls: [],
        armor_removed: 0,
        ticking: [],
      ),
      hit(unit_id: 21, life: 3),
    ])
  assert support.unit_states_told(effects:)
    == [
      holding(unit_id: 21, life: 3, rows: [
        row_of(state: 6, delay_ms: 0, duration_ms: 8500),
      ]),
    ]
    as "neither the caster 7 (the primary target) nor the player 9 is told to hold a state"
}

pub fn a_unit_state_tell_arms_no_cast_timer_so_the_casters_leaving_cannot_cancel_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Every timer of a cast is cleared when the caster leaves (`cast_tick.left`); a state told at
  // the go holds none, so the 30000 ms of Spell4 4178's rows survive it.
  let #(state, effects) =
    went(
      spell: holder(rows: [
        state_row(effect_id: 99_001, state: 6, delay_ms: 0, duration_ms: 30_000),
      ]),
      target: 0,
      struck: [hit(unit_id: 21, life: 3)],
    )
  assert support.unit_states_told(effects:)
    == [
      holding(unit_id: 21, life: 3, rows: [
        row_of(state: 6, delay_ms: 0, duration_ms: 30_000),
      ]),
    ]
    as "the go told the creature already, with its duration"
  assert support.started_timers(effects:) == []
    as "and armed nothing the caster's leaving could clear"
  let #(_, after_leaving) = cast_tick.left(cast: state)
  assert support.unit_states_told(effects: after_leaving) == []
    as "the caster's leaving tells no second state and cancels no first one"
  assert support.cancelled_timers(effects: after_leaving) == []
}

// A hostile aimed press at a creature: Spell4 64944 (Spell4Base 42972, the shortcut spell of
// quest 9373's objective 17880), at Creature2 57226, which is in its cast group. Its own
// target cast, Prerequisite 28001, is of a type the server does not read and refuses 281
// whatever the creature holds, so the row is planted without it and the arms below meet the
// unit-state test and what follows it alone.

const the_spell = 64_944

const a_creature_of_its_group = 57_226

const the_unit = 920

const creature_radius = 1.0

/// What the caster's client shows of the creature: how it holds crowd-control and unit states.
type Shown {
  Shown(held: List(CrowdControlState), unit_states: List(Int))
}

fn place_of_the_unit() -> start_place.Place {
  support.place_beside_the_player(radius: creature_radius, gap: 10.0)
}

fn picture_of(shown shown: Shown) -> shown.Picture {
  dict.from_list([
    #(
      the_unit,
      shown.ShownCreature(
        spawn_id: SpawnId(1),
        creature_id: Creature2Id(a_creature_of_its_group),
        faction_id: 0,
        checklist_index: 0,
        path: creature_path.Standing(at: place_of_the_unit()),
        life: 100,
        alive: True,
        hit_radius: creature_radius,
        attackable: Attackable(exile: True, dominion: True),
        hostile_to: Hostile(exile: False, dominion: False),
        in_combat: False,
        held: list.map(shown.held, fn(state) {
          held_state.HeldState(state:, instance_id: 1)
        }),
        unit_states: list.index_map(shown.unit_states, fn(state, number) {
          shown.HeldUnitState(state:, number:)
        }),
        face: option.None,
        faced_yaw: option.None,
        fights: True,
      ),
    ),
  ])
}

fn target_of(shown shown: Shown) -> fn(Int) -> activate.Target {
  fn(unit_id) {
    case unit_id == the_unit {
      False -> activate.Unseen
      True -> {
        let assert Ok(row) =
          creature2.get(
            tables: fixture_tables.shared(),
            id: Creature2Id(a_creature_of_its_group),
          )
          as "the creature is a root of the fixture"
        Usable(
          spawn_id: SpawnId(1),
          creature_id: a_creature_of_its_group,
          creature: activate.creature_of(row:),
          checklist_index: 0,
          link: activate.NoLink,
          body: Body(place: place_of_the_unit(), radius: creature_radius),
          alive: True,
          in_combat: False,
          held: shown.held,
          unit_states: shown.unit_states,
          withheld: None,
        )
      }
    }
  }
}

/// The effects of the press of the spell at the creature, over these tables.
fn pressed_at_the_unit(
  tables tables: table_store.Tables,
  shown shown: Shown,
) -> List(Effect) {
  let assert Ok(body) =
    cast_objective_ability.encode(CastObjectiveAbility(
      client_cast_id: 7,
      spell4_id: the_spell,
      target_unit_id: the_unit,
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  let picture = picture_of(shown:)
  let assert Ok(#(_, effects)) =
    cast.shortcut(
      cast: cast_state.new(),
      body:,
      caster: support.caster(),
      shortcuts: shortcut_spell.shortcuts(tables:),
      held: set.from_list([the_spell]),
      activations: activate.activations(tables:),
      target_of: target_of(shown:),
      in_cast_group: fn(group, unit_id) {
        shown.in_group(tables:, picture:, group:, unit_id:)
      },
      caster_radius: place_support.player_hit_radius,
      now: support.at(ms: 1000),
    )
    as "a 0x9d that fits the message is taken, started or refused"
  effects
}

/// The press over the tables the test needs: Spell4 64944 without its unread target
/// prerequisite and, when `beneficial`, its Spell4TargetMechanics 3 with flags bit 0 set.
fn with_the_spell(
  beneficial beneficial: Bool,
  body body: fn(table_store.Tables) -> a,
) -> a {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4",
      id: the_spell,
      with: [#("prerequisiteIdTargetCast", Integer(0))],
    )
    as "Spell4 64944 is a root of the fixture"
  let assert Ok(rows) = case beneficial {
    True ->
      fixture_tables.change(rows:, table: "Spell4TargetMechanics", id: 3, with: [
        #("flags", Integer(17)),
      ])
    False -> Ok(rows)
  }
    as "Spell4TargetMechanics 3 is a root of the fixture"
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

fn refused_with(effects effects: List(Effect)) -> List(Int) {
  assert support.tells(effects:) == [] && support.started_timers(effects:) == []
    as "a refused press starts no cast"
  support.refusal_results(effects:)
}

fn confirmed_targets(effects effects: List(Effect)) -> List(Int) {
  list.map(support.confirmed_in(effects:), fn(confirmed) {
    confirmed.primary_target_unit_id
  })
}

pub fn a_hostile_aimed_press_at_an_invulnerable_creature_is_refused_306_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_spell(beneficial: False)
  let effects =
    pressed_at_the_unit(tables:, shown: Shown(held: [], unit_states: [6]))
  assert refused_with(effects:) == [306]
    as "the picture shows state 6 held, and Spell4TargetMechanics 3's flags 16 have bit 0 clear: the 0x7fc carries result 306, which clears the client's global cooldown as any refusal does"
  assert confirmed_targets(effects:) == [] as "and no cast starts"
}

pub fn the_same_press_goes_once_the_state_is_gone_from_the_picture_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_spell(beneficial: False)
  let effects =
    pressed_at_the_unit(tables:, shown: Shown(held: [], unit_states: []))
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [the_unit]
    as "the picture holds no state: the press starts the cast on the creature"
}

pub fn a_beneficial_aimed_press_at_an_invulnerable_creature_goes_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_spell(beneficial: True)
  let effects =
    pressed_at_the_unit(tables:, shown: Shown(held: [], unit_states: [6]))
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [the_unit]
    as "Spell4TargetMechanics 3 with flags bit 0 set is beneficial: state 6 does not refuse it"
}

pub fn a_beneficial_aimed_press_at_a_state_19_creature_is_refused_308_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_spell(beneficial: True)
  let effects =
    pressed_at_the_unit(tables:, shown: Shown(held: [], unit_states: [19]))
  assert refused_with(effects:) == [308]
    as "state 19 is 'Immune (Beneficial)' (row 219651's spell): a beneficial press is refused 308"
}

pub fn the_unit_state_refusal_comes_before_the_crowd_control_refusal_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_spell(beneficial: False)
  let held_and_stunned = Shown(held: [Stun], unit_states: [6])
  assert refused_with(effects: pressed_at_the_unit(
      tables:,
      shown: held_and_stunned,
    ))
    == [306]
    as "0x1403b2240 gives its invulnerability result (96) before the crowd-control checks: a creature that holds Stun and state 6 gives 306 and not 122"
  assert refused_with(effects: pressed_at_the_unit(
      tables:,
      shown: Shown(held: [Stun], unit_states: []),
    ))
    == [122]
    as "the same creature holding no state is refused its Stun as before"
}

pub fn a_press_at_a_creature_with_no_unit_state_is_decided_as_before_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_spell(beneficial: False)
  // Spell4 64944's target conditions row masks Stun and Sleep (Spell4CCConditions 1); a
  // creature that holds a state with no reading (Block, 1) and none of those goes.
  let effects =
    pressed_at_the_unit(tables:, shown: Shown(held: [], unit_states: [1, 23]))
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [the_unit]
    as "states with no reading refuse nothing: the press starts as it does for a creature holding none"
}

/// The right-click, at `ms`, of the Seaspine Mollusk (Creature2 26462, whose activate spell is
/// Spell4 1817), which the caster's picture shows holding these unit states, over these
/// tables: the state it leaves and the effects it takes.
fn right_clicked(
  tables tables: table_store.Tables,
  state state: State,
  unit_states unit_states: List(Int),
  at ms: Int,
) -> #(State, List(Effect)) {
  let caster =
    cast_state.Caster(
      ..support.caster(),
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 4096.0,
        y: 0.0,
        z: 512.0,
      ),
    )
  let assert Ok(row) = creature2.get(tables:, id: Creature2Id(26_462))
    as "Creature2 26462 is a root of the fixture"
  let assert Ok(body) =
    cast_activate.encode(CastActivate(client_cast_id: 9, target_unit_id: 5000))
    as "the message fits"
  let assert Ok(taken) =
    cast.activate(
      cast: state,
      body:,
      caster:,
      activations: activate.activations(tables:),
      target_of: fn(unit_id) {
        case unit_id == 5000 {
          True ->
            Usable(
              spawn_id: SpawnId(1),
              creature_id: 26_462,
              creature: activate.creature_of(row:),
              checklist_index: 0,
              link: activate.NoLink,
              body: Body(
                place: place_support.at(
                  world_id: 3460,
                  world_zone_id: 6009,
                  x: 4098.0,
                  y: 0.0,
                  z: 512.0,
                ),
                radius: 0.25,
              ),
              alive: True,
              in_combat: False,
              held: [],
              unit_states:,
              withheld: None,
            )
          False -> activate.Unseen
        }
      },
      caster_radius: 0.5,
      now: support.at(ms:),
    )
    as "the right-click is taken"
  taken
}

pub fn an_activate_cast_is_not_refused_by_a_unit_state_test() -> Nil {
  use <- owned_test.run(10_000)
  // An activate cast is a use, not a cast the client calls hostile or beneficial in any
  // table, and no client row holds a state in an activated spell.
  let tables = fixture_tables.shared()
  let #(_, without) =
    right_clicked(tables:, state: cast_state.new(), unit_states: [], at: 1000)
  assert support.refusal_results(effects: without) == []
    && support.ids(frames: support.writes(effects: without)) == [0x07FD]
    as "the creature holding no state is activated"
  let #(_, with_state) =
    right_clicked(
      tables:,
      state: cast_state.new(),
      unit_states: [6, 19],
      at: 1000,
    )
  assert support.refusal_results(effects: with_state) == []
    && support.ids(frames: support.writes(effects: with_state)) == [0x07FD]
    as "states 6 and 19 refuse neither with 306 nor with 308: the activation starts as without them"
}

pub fn an_activation_with_a_dropped_unit_state_row_logs_it_once_and_activates_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects 2821 is the Activate row of Spell4 1817 (the mollusk's spell). A UnitStateSet
  // row aimed at the target is added beside it; the activate cast strikes no unit, so it drops
  // the row, logs it once for the spell, and the activation works as it does without it.
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 2821,
    id: 99_097,
    with: [#("effectType", Integer(15)), #("dataBits00", Integer(6))],
    body: fn(tables) {
      let #(state, first) =
        right_clicked(
          tables:,
          state: cast_state.new(),
          unit_states: [],
          at: 1000,
        )
      assert support.refusal_results(effects: first) == []
        as "a dropped unit state refuses nothing: no result 285"
      assert support.ids(frames: support.writes(effects: first)) == [0x07FD]
        as "the activation starts"
      let assert [#(LogWarning, line)] = support.logs(effects: first)
        as "the dropped row is logged once, as one line"
      assert string.contains(line, "1817")
        && string.contains(line, "UnitStateSet")
        && string.contains(line, "99097")
        as "the line names the spell, the kind and the effect"
      let #(_, second) =
        right_clicked(tables:, state:, unit_states: [], at: 60_000)
      assert support.logs(effects: second) == []
        as "the same spell's dropped row is not logged again"
    },
  )
}

pub fn an_area_go_logs_type_18_for_the_immune_creature_only_test() -> Nil {
  use <- owned_test.run(5000)
  // Creature 23 answered the strike `Immune` (it holds state 6, which the creature decides),
  // creature 21 took it: the 0x7f4 names both, the immune one with no effect, and the caster
  // is written one 0x247 of type 18 for the immune one alone (`opcode.0x247.immunity`).
  let unit = cast_state.HitCreature(life: 5, struck_at_ms: 900)
  let #(_, effects) =
    went(spell: support.child(spell4_id: 58_591, base: 3), target: 0, struck: [
      hit(unit_id: 21, life: 3),
      cast_state.Immune(
        unit_id: 23,
        unit:,
        controls: [],
        armor_removed: 0,
        ticking: [],
      ),
    ])
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  assert list.map(decoded.targets, fn(info) { info.unit_id }) == [21, 23]
    as "the go names both creatures"
  assert list.map(decoded.targets, fn(info) { info.effects }) == [[], []]
    as "neither lists an effect: the immune one has no description"
  let logged =
    list.map(
      support.frames_of(message_id: combat_log.message_id, effects:),
      fn(frame) {
        let assert Ok(decoded) = combat_log.decode(frame.body)
          as "a 0x247 the rule wrote decodes"
        decoded.entry
      },
    )
  assert logged
    == [
      combat_log_entry.Immunity(CombatLogImmunity(
        caster_unit_id: 7,
        target_unit_id: 23,
        spell4_id: 58_591,
        combat_result: combat_result.Hit,
      )),
    ]
    as "one type 18 entry, for creature 23 alone, with the caster 7, the target and Spell4 58591"
}
