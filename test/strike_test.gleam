//// A player's strikes (`genesis_prime/game/strike`), run as the pure rule it is on
//// a driven clock: a go's selection, its round, the answers, the deadline and the
//// timer. Expected values come from these places.
//// - The rule's doc comment: a strike is told to each selected unit in selection
////   order with the caster's rolls (12 seed bytes for each unit, 4 for each of the
////   critical hit, deflect and glance rolls, each a fraction of 2^32); a round closes
////   when each answer is in or its 1 s deadline has passed; the go lists the units in
////   selection order; a refusal or a silent creature is left out and the count is not
////   refilled; an answer for a closed round is dropped; the rounds of one cast close in
////   phase order, an empty one too; one strike timer is set to the earliest open
////   deadline and set again only when it is not running; health news of a unit of an open
////   round is held until the round's go.
//// - Design 274 section 2: the deadline is 1 second.
//// - The cast and phase of Stagger's gos: `Spell4.38791.area`.
//// - Kick's area row and cone: `Spell4.58591.area` (5 units, 0 to 8 m, 180 degrees; a
////   cone 1 to 7 m over 100 degrees); the Beast's hit radius is 3.0.
//// - A creature that is not a foe or is dead is never selected
////   (`Spell4ValidTargets.targetBitmask`, `0x1403ad540`).

import attacker_support
import cast_support as support
import class_resource_support
import client_tables
import crowd_control_support
import genesis_prime/game/area.{Point, Pose}
import genesis_prime/game/cast/state.{type GoAsked, GoAsked} as cast_state
import genesis_prime/game/class_resource.{Resource}
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/forced_move
import genesis_prime/game/hit.{type Offence, Blow, Offence, Rolls, Worked}
import genesis_prime/game/player_address
import genesis_prime/game/shown.{ShownPlayer}
import genesis_prime/game/spell_area.{DamageEffect}
import genesis_prime/game/spell_plan.{AimsAtArea}
import genesis_prime/game/spend
import genesis_prime/game/strike.{
  type Attacker, type Effect, type Selection, type State, Aimed, Attacker,
  Selection,
}
import genesis_prime/game/strike_tell.{
  Answered, Dead, Deflected, Key, Landed, Refused,
}
import genesis_prime/game/target_mechanic
import genesis_prime/game/unit_news
import genesis_prime/game/unit_properties
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state
import genesis_prime/step.{ConnectionId, Now}
import genesis_prime/table/id.{Creature2Id, Spell4EffectsId, Spell4Id}
import genesis_prime/world_map/creature_life.{Attackable, Hostile}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import map_support
import owned_test
import place_support
import player_state_support
import properties_support
import rating_support
import spell_tables
import strike_support
import unitest

fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

fn asked(cast_id cast_id: Int, phase phase: Int) -> GoAsked {
  GoAsked(
    cast_id:,
    phase:,
    spell4_id: Spell4Id(58_591),
    primary_target: 7,
    spent: None,
    started_at: strike_support.start_pose(),
    fired: False,
  )
}

fn selection(
  asked asked: GoAsked,
  units units: List(Int),
  damaging damaging: Bool,
) -> Selection {
  Selection(
    asked:,
    units: list.map(units, fn(unit_id) { Aimed(unit_id:, life: 3) }),
    area: units,
    blows: case damaging {
      True -> [strike_support.damage_effect()]
      False -> []
    },
    controls: [],
    ticking: [],
    gates: [],
    players: [],
    acts_on_each_unit: False,
    heals: [],
  )
}

/// 12 seed bytes for each unit: the critical hit roll's 4 bytes, the deflect roll's, then
/// the glance roll's (a number n is the fraction n / 2^32).
fn entropy(rolls rolls: List(#(Int, Int, Int))) -> BitArray {
  list.fold(rolls, <<>>, fn(bytes, triple) {
    <<bytes:bits, triple.0:size(32), triple.1:size(32), triple.2:size(32)>>
  })
}

fn begun(
  state state: State,
  selection selection: Selection,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  strike.begin(
    strike: state,
    selection:,
    attacker: strike_support.attacker(),
    formulas: rating_support.formulas(),
    entropy: entropy(rolls: list.map(selection.units, fn(_) { #(0, 0, 0) })),
    gate: strike_support.passes_all(),
    now: at(ms: now_ms),
  )
}

fn answer(
  state state: State,
  key key: strike_tell.Key,
  outcome outcome: strike_tell.Outcome,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  strike.answered(
    strike: state,
    answer: Answered(key:, outcome:),
    now: at(ms: now_ms),
  )
}

fn landed() -> strike_tell.Outcome {
  Landed(descriptions: [], controls: [], armor_removed: 0, gates_passed: [])
}

fn tells(effects effects: List(Effect)) -> List(strike.Effect) {
  strike_support.only(effects:, kinds: [strike_support.CreatureTold])
}

/// The units each round that closed in these effects named, in order, by cast
/// and phase.
fn went(
  effects effects: List(Effect),
) -> List(#(Int, Int, List(cast_state.Struck))) {
  list.map(strike_support.rounds_closed(effects:), fn(closed) {
    #({ closed.0 }.cast_id, { closed.0 }.phase, closed.1)
  })
}

fn timers(effects effects: List(Effect)) -> List(strike.Effect) {
  strike_support.timers(effects:)
}

pub fn a_go_that_strikes_several_creatures_tells_each_in_selection_order_with_its_own_rolls_and_arms_one_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let chosen =
    selection(
      asked: asked(cast_id: 5, phase: 0),
      units: [10, 11, 12],
      damaging: True,
    )
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: chosen,
      attacker: strike_support.attacker(),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [
        #(0, 2_147_483_648, 0),
        #(1_073_741_824, 3_221_225_472, 2_147_483_648),
        #(0, 0, 0),
      ]),
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let told =
    list.map(strike_support.creatures_told(effects:), fn(told) {
      case told {
        #(
          unit_id,
          life,
          strike_tell.Strike(
            key:,
            from:,
            striker: strike_tell.PlayerStriker(rolls:, ..),
            ..,
          ),
        ) -> #(unit_id, life, key, from, rolls)
        #(
          _,
          _,
          strike_tell.Strike(striker: strike_tell.CreatureStriker(..), ..),
        ) -> panic as "a player's strike carries a player striker"
      }
    })
  assert told
    == [
      #(
        10,
        3,
        Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
        step.Connection(ConnectionId(2)),
        Rolls(crit: 0.0, deflect: 0.5, glance: 0.0),
      ),
      #(
        11,
        3,
        Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 11),
        step.Connection(ConnectionId(2)),
        Rolls(crit: 0.25, deflect: 0.75, glance: 0.5),
      ),
      #(
        12,
        3,
        Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 12),
        step.Connection(ConnectionId(2)),
        Rolls(crit: 0.0, deflect: 0.0, glance: 0.0),
      ),
    ]
    as "one strike for each selected unit in selection order, each with its own 12 bytes of the caster's seed as three fractions of 2^32, answered to the caster's connection"
  assert timers(effects:)
    == [strike.StartTimer(timer: strike.strike_timer, after_ms: 1000)]
    as "one strike timer for the round's deadline, 1 s after the go"
  assert went(effects:) == [] as "the go is written when its round closes"
}

pub fn a_strike_carries_the_casters_blows_by_the_clients_formula_with_its_gear_and_the_players_base_chances_test() -> Nil {
  use <- owned_test.run(5000)
  let novice = attacker_support.novice()
  let paralytic_surge =
    DamageEffect(
      effect_id: Spell4EffectsId(96_125),
      damage_type: 2,
      delay_ms: 0,
      phase_flags: -1,
      aim: AimsAtArea,
      formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
        damage.Parameter(kind: 12, value: 0.0935),
        damage.Parameter(kind: 13, value: 0.0935),
        damage.Parameter(kind: 10, value: 8.14),
      ]),
      threat_multiplier: 1.0,
      condition: spell_plan.Always,
      tag: spend.always,
    )
  let telekinetic_strike =
    DamageEffect(
      effect_id: Spell4EffectsId(62_159),
      damage_type: 3,
      delay_ms: 0,
      phase_flags: -1,
      aim: AimsAtArea,
      formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
        damage.Parameter(kind: 12, value: 0.336),
        damage.Parameter(kind: 10, value: 18.0),
      ]),
      threat_multiplier: 2.0,
      condition: spell_plan.Always,
      tag: spend.always,
    )
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: Selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [strike.Aimed(unit_id: 10, life: 3)],
        area: [10],
        blows: [paralytic_surge, telekinetic_strike],
        controls: [],
        ticking: [],
        gates: [],
        players: [],
        acts_on_each_unit: False,
        heals: [],
      ),
      attacker: Attacker(..strike_support.attacker(), stats: novice),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [#(0, 0, 0)]),
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [strike.TellStrike(tell: strike_tell.Strike(offence:, ..), ..)] =
    tells(effects:)
    as "one strike for the one selected unit"
  assert offence
    == Offence(
      blows: [
        Blow(
          spell4_effects_id: 96_125,
          damage_type: 2,
          damage: Worked(14),
          delay_ms: 0,
          threat_multiplier: 1.0,
        ),
        Blow(
          spell4_effects_id: 62_159,
          damage_type: 3,
          damage: Worked(35),
          delay_ms: 0,
          threat_multiplier: 2.0,
        ),
      ],
      crit_chance: 0.0,
      crit_severity: 1.5,
      strikethrough: 0.0,
    )
    as "a level-1 Novice's gear gives Assault Rating 203.0625 and Support Rating 55.6875, so Assault Power 50.77 and Support Power 13.92 (0x14064c960): Paralytic Surge is 0.0935 x 50.77 + 0.0935 x 13.92 = 6.05, rounded to 6, plus 8.14 for the level, 14.14, rounded to 14; Telekinetic Strike is 0.336 x 50.77 = 17.06, rounded to 17, plus 18.0, 35 (0x140565600, Spell4Effects 96125 and 62159); the gear gives no critical hit, severity or strikethrough rating, so the player's base chances stand: 0, a severity of 1.5 and 0 (UnitProperty2 102, 127 and 104)"
}

/// A damage effect on every phase that aims at the area, with this formula.
fn effect_of(formula formula: damage.Formula) -> spell_area.DamageEffect {
  DamageEffect(
    ..strike_support.damage_effect(),
    effect_id: Spell4EffectsId(7),
    formula:,
  )
}

/// The offences each strike of a go carries, by the unit it is told to.
fn offences_told(effects effects: List(Effect)) -> List(#(Int, Offence)) {
  list.map(strike_support.creatures_told(effects:), fn(told) {
    #(told.0, { told.2 }.offence)
  })
}

pub fn every_unit_of_a_go_is_told_the_same_unfinished_blow_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 case 7 reads the maximum health of the unit that is struck, which only
  // that unit's owner holds, so the go tells the formula as far as the caster's side goes.
  let row =
    effect_of(
      formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
        damage.Parameter(kind: 7, value: 0.1),
      ]),
    )
  let chosen =
    Selection(
      ..selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10, 11],
        damaging: True,
      ),
      blows: [row],
    )
  let #(_, effects) =
    begun(state: strike.new(), selection: chosen, now_ms: 1000)
  let partial =
    damage.Partial(stat_part: 0, base: 0.0, multiplier: 1.0, terms: [
      damage.OfTarget(kind: 7, factor: 0.1),
    ])
  let blow =
    Blow(
      spell4_effects_id: 7,
      damage_type: 1,
      damage: hit.ByTarget(partial),
      delay_ms: 166,
      threat_multiplier: 1.0,
    )
  let offences = offences_told(effects:)
  assert list.map(offences, fn(told) { #(told.0, { told.1 }.blows) })
    == [#(10, [blow]), #(11, [blow])]
    as "both units are told the one blow with the target's term left open, each finishes it with its own maximum health"
}

pub fn the_casters_vitals_at_the_go_are_in_the_blow_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x140566ad0 reads the caster's health (case 23, 0x40 slot) and the caster's maximum
  // health less its health (case 25) of the unit that casts, here at 800 of 1000.
  let formula = fn(kind) {
    damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
      damage.Parameter(kind:, value: 0.5),
    ])
  }
  let chosen =
    Selection(
      ..selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      blows: [effect_of(formula: formula(23)), effect_of(formula: formula(25))],
    )
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: chosen,
      attacker: Attacker(
        ..strike_support.attacker(),
        vitals: damage.Vitals(
          health: 800,
          max_health: 1000,
          shield: 0,
          max_shield: 0,
        ),
      ),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [#(0, 0, 0)]),
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [#(10, offence)] = offences_told(effects:)
  assert list.map(offence.blows, fn(blow) { blow.damage })
    == [Worked(400), Worked(100)]
    as "0.5 x the health of 800, then 0.5 x the 200 missing, the caster's own vitals at the go"
}

pub fn answers_out_of_order_are_listed_in_selection_order_when_the_round_closes_test() -> Nil {
  use <- owned_test.run(5000)
  let go = asked(cast_id: 5, phase: 0)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(asked: go, units: [10, 11, 12], damaging: True),
      now_ms: 1000,
    )
  let key = fn(unit_id) {
    Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id:)
  }
  let #(state, first) =
    answer(state:, key: key(12), outcome: landed(), now_ms: 1100)
  let #(state, second) =
    answer(
      state:,
      key: key(10),
      outcome: Deflected(gates_passed: []),
      now_ms: 1200,
    )
  assert went(effects: list.append(first, second)) == []
    as "the round waits for the unit that has not answered"
  let #(_, third) =
    answer(state:, key: key(11), outcome: landed(), now_ms: 1300)
  assert went(effects: third)
    == [
      #(5, 0, [
        cast_state.Deflected(unit_id: 10),
        cast_state.Hit(
          unit_id: 11,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
        cast_state.Hit(
          unit_id: 12,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ]),
    ]
    as "the go lists the units in selection order whatever order the answers came in; a deflect is its own entry"
}

pub fn a_creature_that_died_in_flight_is_left_out_and_the_count_is_not_refilled_test() -> Nil {
  use <- owned_test.run(5000)
  let go = asked(cast_id: 5, phase: 0)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(asked: go, units: [10, 11, 12], damaging: True),
      now_ms: 1000,
    )
  let key = fn(unit_id) {
    Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id:)
  }
  let #(state, _) =
    answer(state:, key: key(10), outcome: Refused(why: Dead), now_ms: 1100)
  let #(state, _) =
    answer(state:, key: key(11), outcome: landed(), now_ms: 1200)
  let #(_, closing) =
    answer(state:, key: key(12), outcome: landed(), now_ms: 1300)
  assert went(effects: closing)
    == [
      #(5, 0, [
        cast_state.Hit(
          unit_id: 11,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
        cast_state.Hit(
          unit_id: 12,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ]),
    ]
    as "Spell4ValidTargets.targetBitmask: a dead unit is never struck; the 0x7f4 names the two that were, and no other unit takes the dead one's place"
}

pub fn a_silent_creature_is_left_out_at_the_deadline_on_a_driven_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let go = asked(cast_id: 5, phase: 0)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(asked: go, units: [10, 11], damaging: True),
      now_ms: 1000,
    )
  let #(state, _) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  let #(_, early) = strike.timer_fired(strike: state, now: at(ms: 1999))
  assert went(effects: early) == []
    as "the deadline is 1 s after the go: nothing closes at 1999 ms"
  let #(_, due) = strike.timer_fired(strike: state, now: at(ms: 2000))
  assert went(effects: due)
    == [
      #(5, 0, [
        cast_state.Hit(
          unit_id: 10,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ]),
    ]
    as "the creature that never answered is left out at its round's deadline"
  assert timers(effects: due) == []
    as "the timer that fired is no longer running and no round is open, so none is set or cancelled"
}

pub fn the_timer_is_set_again_after_it_fired_with_a_round_still_waiting_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(_, fired_early) = strike.timer_fired(strike: state, now: at(ms: 1500))
  assert timers(effects: fired_early)
    == [strike.StartTimer(timer: strike.strike_timer, after_ms: 500)]
    as "the timer fired and ended, so it is set again for the deadline 500 ms on: the shell refuses to start a timer that is running"
}

pub fn an_answer_for_a_closed_round_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let go = asked(cast_id: 5, phase: 0)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(asked: go, units: [10, 11], damaging: True),
      now_ms: 1000,
    )
  let #(state, _) = strike.timer_fired(strike: state, now: at(ms: 2000))
  let #(_, late) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 2500,
    )
  assert went(effects: late) == [] && tells(effects: late) == []
    as "an answer after the deadline is dropped: the creature's 0x937 shows its health with no number"
}

pub fn a_later_phase_is_never_written_before_an_earlier_one_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(state, _) =
    begun(
      state:,
      selection: selection(
        asked: asked(cast_id: 5, phase: 1),
        units: [11],
        damaging: True,
      ),
      now_ms: 1200,
    )
  let #(state, later) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 1), unit_id: 11),
      outcome: landed(),
      now_ms: 1300,
    )
  assert went(effects: later) == []
    as "phase 1 has every answer but waits for phase 0, which Stagger's gos are written in order"
  let #(_, earlier) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1400,
    )
  assert list.map(went(effects: earlier), fn(round) { #(round.0, round.1) })
    == [#(5, 0), #(5, 1)]
    as "both close at once, phase 0 first"
}

pub fn an_empty_selection_waits_behind_the_casts_earlier_rounds_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(state, empty) =
    begun(
      state:,
      selection: selection(
        asked: asked(cast_id: 5, phase: 1),
        units: [],
        damaging: True,
      ),
      now_ms: 1200,
    )
  assert went(effects: empty) == []
    as "Stagger 38780: phase 0 waits on a creature that crashed, so phase 1, which selects nobody, is not written before it"
  let #(_, due) = strike.timer_fired(strike: state, now: at(ms: 2000))
  assert list.map(went(effects: due), fn(round) { #(round.0, round.1, round.2) })
    == [#(5, 0, []), #(5, 1, [])]
    as "the deadline closes phase 0 with nobody, and phase 1 follows it"
}

pub fn the_one_strike_timer_moves_to_the_next_open_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(state, second) =
    begun(
      state:,
      selection: selection(
        asked: asked(cast_id: 6, phase: 0),
        units: [11],
        damaging: True,
      ),
      now_ms: 1500,
    )
  assert timers(effects: first)
    == [strike.StartTimer(timer: strike.strike_timer, after_ms: 1000)]
  assert timers(effects: second) == []
    as "the timer already waits for the earlier deadline, 2000 ms, and is not started again while it runs"
  let #(_, closed) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1600,
    )
  assert timers(effects: closed)
    == [
      strike.CancelTimer(timer: strike.strike_timer),
      strike.StartTimer(timer: strike.strike_timer, after_ms: 900),
    ]
    as "the first round closed, so the timer moves to the second's deadline, 2500 ms: 900 ms after 1600"
}

pub fn a_go_that_selects_no_foe_closes_at_once_with_no_tell_and_no_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [],
        damaging: True,
      ),
      now_ms: 1000,
    )
  assert went(effects:) == [#(5, 0, [])]
    as "the go names no foe and no 0x937 is sent"
  assert tells(effects:) == [] && timers(effects:) == []
}

pub fn a_spell_that_only_selects_names_each_unit_at_once_without_a_tell_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: False,
      ),
      now_ms: 1000,
    )
  assert went(effects:)
    == [
      #(5, 0, [
        cast_state.Hit(
          unit_id: 10,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ]),
    ]
    as "Crush's first spell has only a Proxy on its area: the go names its foe with no effect info (Spell4.32812.area)"
  assert tells(effects:) == []
}

pub fn the_player_leaving_cancels_the_timer_and_drops_later_answers_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(state, leaving) = strike.left(strike: state)
  assert leaving == [strike.CancelTimer(timer: strike.strike_timer)]
    as "nothing is written; the creatures keep what the strikes did"
  let #(_, late) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  assert went(effects: late) == []
}

pub fn health_news_of_a_unit_of_an_open_round_is_held_until_the_rounds_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10, 11],
        damaging: True,
      ),
      now_ms: 1000,
    )
  assert strike.holds(strike: state, unit_id: 10)
    && !strike.holds(strike: state, unit_id: 99)
    as "unit 10 is in the caster's open round, unit 99 is not"
  let death = unit_news.Died
  let state = strike.hold(strike: state, unit_id: 10, news: death)
  let #(state, first) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  assert first == []
    as "the answer of unit 10 leaves the round open for unit 11: nothing is written, nothing released"
  let #(state, closing) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 11),
      outcome: landed(),
      now_ms: 1200,
    )
  assert list.map(closing, fn(effect) {
      case effect {
        strike.Went(..) -> "went"
        strike.Ticked(..) -> "ticked"
        strike.Released(unit_id:, ..) -> "released " <> unit_label(unit_id)
        strike.CancelTimer(..) -> "cancel"
        strike.TellStrike(..)
        | strike.TellPlayerStrike(..)
        | strike.StartTimer(..)
        | strike.Log(..) -> "other"
      }
    })
    == ["cancel", "went", "released ten"]
    as "the go is written first, then the death the held news carries: the client shows the number before the death; the timer moves before either, since the go may begin a round of its own"
  assert !strike.holds(strike: state, unit_id: 10)
}

pub fn a_closing_rounds_timer_effects_come_before_its_go_so_the_rounds_the_go_begins_keep_their_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(state, closing) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  assert list.map(closing, effect_label) == ["cancel", "went"]
    as "the only waiting round closed: the timer is cancelled before the go, which a damage child's round follows in the connection's order of effects"
  let #(state, child) =
    begun(
      state:,
      selection: selection(
        asked: asked(cast_id: 5, phase: 1),
        units: [10],
        damaging: True,
      ),
      now_ms: 1100,
    )
  assert timers(effects: child)
    == [strike.StartTimer(timer: strike.strike_timer, after_ms: 1000)]
    as "the child's round, begun while the go is carried out, starts the timer once, after the cancel, and it is not cancelled again"
  let #(_, fired) = strike.timer_fired(strike: state, now: at(ms: 2100))
  assert went(effects: fired) == [#(5, 1, [])]
    as "the child's round keeps its 1 s deadline and closes there with nobody answered"
}

/// A short name of an effect, in the order the connection carries them out.
fn effect_label(effect: Effect) -> String {
  case effect {
    strike.Went(..) -> "went"
    strike.Ticked(..) -> "ticked"
    strike.Released(..) -> "released"
    strike.CancelTimer(..) -> "cancel"
    strike.StartTimer(..) -> "start"
    strike.TellStrike(..) -> "tell"
    strike.TellPlayerStrike(..) -> "player tell"
    strike.Log(..) -> "log"
  }
}

pub fn the_news_held_for_a_unit_is_dropped_when_the_unit_is_forgotten_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10, 11],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let state =
    strike.hold(
      strike: strike.hold(strike: state, unit_id: 10, news: unit_news.Died),
      unit_id: 11,
      news: unit_news.Health(health: 5, dead: False),
    )
  let state = strike.forget(strike: state, unit_id: 10)
  let #(state, _) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  let #(_, closing) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 11),
      outcome: landed(),
      now_ms: 1200,
    )
  assert list.filter_map(closing, fn(effect) {
      case effect {
        strike.Released(unit_id:, ..) -> Ok(unit_id)
        strike.TellStrike(..)
        | strike.TellPlayerStrike(..)
        | strike.StartTimer(..)
        | strike.CancelTimer(..)
        | strike.Went(..)
        | strike.Ticked(..)
        | strike.Log(..) -> Error(Nil)
      }
    })
    == [11]
    as "unit 10 was removed from the client's picture (0x355), so its death is not written onto a unit that may stand again; unit 11's health is"
}

fn unit_label(unit_id: Int) -> String {
  case unit_id {
    10 -> "ten"
    _ -> "another"
  }
}

fn picture() -> shown.Picture {
  let both = Attackable(exile: True, dominion: True)
  dict.from_list([
    #(
      21,
      strike_support.creature_at(x: 0.0, z: -3.0, alive: True, attackable: both),
    ),
    #(
      22,
      strike_support.creature_at(x: 0.0, z: -5.0, alive: True, attackable: both),
    ),
    #(
      23,
      strike_support.creature_at(x: 0.0, z: -6.5, alive: True, attackable: both),
    ),
    #(
      24,
      strike_support.creature_at(x: 0.0, z: 4.0, alive: True, attackable: both),
    ),
    #(
      25,
      strike_support.creature_at(x: 0.0, z: -8.0, alive: True, attackable: both),
    ),
    #(
      26,
      strike_support.creature_at(
        x: 0.0,
        z: -4.0,
        alive: False,
        attackable: both,
      ),
    ),
    #(
      27,
      strike_support.creature_at(
        x: 0.0,
        z: -4.0,
        alive: True,
        attackable: Attackable(exile: False, dominion: True),
      ),
    ),
    #(28, ShownPlayer(state: player_state_support.a_player())),
    #(
      20,
      strike_support.creature_at(
        x: 40.0,
        z: 40.0,
        alive: True,
        attackable: both,
      ),
    ),
  ])
}

pub fn the_caster_selects_the_foes_inside_kicks_cone_nearest_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let areas = spell_tables.fixture_areas()
  let chosen =
    strike.select(
      asked: asked(cast_id: 5, phase: 0),
      attacker: strike_support.attacker(),
      picture: picture(),
      areas:,
      now_ms: 0,
    )
  assert list.map(chosen.units, fn(aimed) { aimed.unit_id }) == [21, 22, 23, 25]
    as "Kick's cone is 1 to 7 m over 100 degrees ahead: units 21, 22 and 23, and 25, which is 8 m ahead, past the cone by less than its hit radius of 3 (a unit's radius counts for every shape); 24 is behind, 26 is dead, 27 is Friendly to Exiles and 28 is a player (Spell4.58591.area)"
  assert list.length(chosen.blows) == 1
    as "Kick's one damage effect, aimed at the area"
}

/// The fixture's areas with Kick's area (58591) changed by `change`.
fn kick_areas_changed(
  change change: fn(spell_area.SpellArea) -> spell_area.SpellArea,
) -> spell_area.Areas {
  let areas = spell_tables.fixture_areas()
  let assert Ok(kick) = dict.get(areas, 58_591)
    as "Kick is in the fixture's areas"
  dict.insert(areas, 58_591, change(kick))
}

/// Kick's area (58591) with its spell's valid targets bitmask replaced.
fn kick_areas_with_valid_targets(
  valid_targets valid_targets: Int,
) -> spell_area.Areas {
  kick_areas_changed(change: fn(kick) {
    spell_area.SpellArea(
      ..kick,
      spell: spell_plan.Spell(
        ..kick.spell,
        targeting: target_mechanic.Targeting(
          ..kick.spell.targeting,
          valid_targets:,
        ),
      ),
    )
  })
}

pub fn a_creature_inside_kicks_cone_is_not_selected_by_a_spell_whose_valid_targets_name_party_members_test() -> Nil {
  use <- owned_test.run(60_000)
  let select = fn(valid_targets) {
    strike.select(
      asked: asked(cast_id: 5, phase: 0),
      attacker: strike_support.attacker(),
      picture: picture(),
      areas: kick_areas_with_valid_targets(valid_targets:),
      now_ms: 0,
    )
  }
  let party_only = select(16)
  assert party_only.units == []
    as "valid targets bit 16 names the caster's party members (0x1403b0880 line 66, UnitsShareGroup 0x140561e60), and a creature is never in a group: units 21, 22, 23 and 25 are not selected"
  assert party_only.area == []
    as "the area holds no unit, so the damage effect aimed at the area strikes nobody"
  assert selected_units(selection: select(256)) == [21, 22, 23, 25]
    as "the control: bit 256 excludes only a pet, so the same cone selects the same four creatures, and the case above fails for the bit and not for the picture"
  Nil
}

/// Kick's area (58591) with its row's order and count replaced.
fn kick_areas_ordered(
  order order: area.Order,
  target_count target_count: Int,
) -> spell_area.Areas {
  kick_areas_changed(change: fn(kick) {
    let assert Some(row) = kick.row as "Kick has an area row"
    spell_area.SpellArea(
      ..kick,
      row: Some(area.Row(..row, order:, target_count:)),
    )
  })
}

fn selected_units(selection selection: Selection) -> List(Int) {
  list.map(selection.units, fn(aimed) { aimed.unit_id })
}

pub fn a_player_area_that_picks_the_furthest_strikes_the_furthest_units_inside_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  // The caster stands at the origin and Kick's cone holds 21, 22, 23 and 25 at 3, 5, 6.5 and 8 m
  // (the z of their rows in `picture`), so the farthest-first order is 25, 23, 22, 21; 24 is
  // behind, 26 is dead, 27 is Friendly to Exiles and 28 is a player. The N furthest foes are
  // the texts' words ("Pull the 3 furthest foes", text 320951); the distance from the area's
  // centre and a tie to the lower id are guesses the gap states.
  list.each(
    [
      #(3, [25, 23, 22], "the 3 furthest inside, furthest first"),
      #(10, [25, 23, 22, 21], "a count above the units inside takes them all"),
    ],
    fn(case_) {
      let #(target_count, wanted, reason) = case_
      assert selected_units(selection: strike.select(
          asked: asked(cast_id: 5, phase: 0),
          attacker: strike_support.attacker(),
          picture: picture(),
          areas: kick_areas_ordered(order: area.Furthest, target_count:),
          now_ms: 0,
        ))
        == wanted
        as reason
    },
  )
}

pub fn a_player_area_that_picks_at_random_follows_the_cast_id_and_every_go_of_one_cast_ranks_alike_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each unit's key is the 32-bit finalizer of MurmurHash3 over `cast_id * 0x9E3779B1 +
  // unit_id`, ascending, the lower id first on a tie (`area.mix`, a guess: the client names
  // Random and orders nothing). The lists were worked out once with an independent script over
  // units 21, 22, 23 and 25, the units inside Kick's cone.
  let areas = kick_areas_ordered(order: area.Random, target_count: 2)
  let select_at = fn(cast_id) {
    selected_units(selection: strike.select(
      asked: asked(cast_id:, phase: 0),
      attacker: strike_support.attacker(),
      picture: picture(),
      areas:,
      now_ms: 0,
    ))
  }
  list.each(
    [
      #(5, [22, 21]),
      #(6, [22, 23]),
      #(7, [23, 25]),
      #(8, [21, 25]),
      #(10, [25, 22]),
    ],
    fn(case_) {
      assert select_at(case_.0) == case_.1
        as "the cast id seeds the order, so the same cast id picks the same units"
      assert select_at(case_.0) == select_at(case_.0)
        as "a replayed cast picks the same units"
    },
  )
  // Stagger 38780 at its four gos: one cast id ranks the units alike at every go, the phase
  // is not in the seed.
  use <- unitest.guard(client_tables.present())
  let stagger_areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(stagger) = dict.get(stagger_areas, 38_780)
    as "Stagger is in the areas of the level-1 abilities"
  let assert Some(row) = stagger.row as "Stagger has an area row"
  let randomised =
    dict.insert(
      stagger_areas,
      38_780,
      spell_area.SpellArea(
        ..stagger,
        row: Some(area.Row(..row, order: area.Random, target_count: 3)),
      ),
    )
  let close_by =
    dict.from_list([
      #(21, foe_at(x: 0.0, z: -1.0)),
      #(22, foe_at(x: 0.0, z: -2.0)),
      #(23, foe_at(x: 0.0, z: -3.0)),
      #(24, foe_at(x: 0.0, z: -4.0)),
      #(25, foe_at(x: 0.0, z: -5.0)),
      #(26, foe_at(x: 0.0, z: -6.0)),
      #(27, foe_at(x: 0.0, z: -9.0)),
    ])
  let by_go =
    list.map([0, 1, 2, 3], fn(phase) {
      selected_units(selection: strike.select(
        asked: GoAsked(..asked(cast_id: 5, phase:), spell4_id: Spell4Id(38_780)),
        attacker: strike_support.attacker(),
        picture: close_by,
        areas: randomised,
        now_ms: 0,
      ))
    })
  let assert [first, ..rest] = by_go
  assert list.all(rest, fn(later) { later == first })
    as "every go of one cast ranks the units alike"
  assert first == [22, 21, 23]
    as "cast id 5 ranks the units 21 to 27 as 22, 21, 27, 23, 25, 26, 24 (the same key rule as above); unit 27 stands at 9 m, outside Stagger's 8 m row, so the three taken are the first three inside it: 22, 21 and 23"
}

pub fn a_damage_aimed_at_the_cast_target_strikes_the_primary_target_alone_test() -> Nil {
  use <- owned_test.run(60_000)
  let chosen =
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(38_781),
        primary_target: 20,
        spent: None,
        started_at: strike_support.start_pose(),
        fired: False,
      ),
      attacker: strike_support.attacker(),
      picture: picture(),
      areas: spell_tables.fixture_areas(),
      now_ms: 0,
    )
  assert chosen.units == [Aimed(unit_id: 20, life: 4)]
    as "Spell4Effects.targetFlags 2 strikes the cast's own target (38781 on each struck unit), with that creature's life"
}

pub fn a_despawn_row_selects_no_player_and_no_static_object_test() -> Nil {
  use <- owned_test.run(60_000)
  // `shown.life_of` is an error for another player's unit and for a static object: only a
  // creature has a life to aim at, so a despawn row aimed at the cast's target selects the
  // target only when it is a creature (`Spell4Effects.effectType.97`: the server removes
  // creatures, a player is never removed).
  let areas =
    dict.from_list([
      #(
        spell_tables.despawn_only_spell4_id,
        spell_tables.despawn_only_area(target_flags: 2),
      ),
    ])
  let object =
    shown.ShownObject(
      spawn_id: SpawnId(2),
      creature_id: Creature2Id(73_464),
      faction_id: 0,
      checklist_index: 0,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 5967,
        x: 0.0,
        y: 0.0,
        z: -3.0,
      ),
      hit_radius: 1.0,
      hostile_to: Hostile(exile: False, dominion: False),
    )
  let picture =
    dict.from_list([
      #(
        20,
        strike_support.creature_at(
          x: 0.0,
          z: -3.0,
          alive: True,
          attackable: Attackable(exile: True, dominion: True),
        ),
      ),
      #(28, ShownPlayer(state: player_state_support.a_player())),
      #(29, object),
    ])
  let selected = fn(primary_target) {
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(spell_tables.despawn_only_spell4_id),
        primary_target:,
        spent: None,
        started_at: strike_support.start_pose(),
        fired: False,
      ),
      attacker: strike_support.attacker(),
      picture:,
      areas:,
      now_ms: 0,
    ).units
  }
  assert selected(20) == [Aimed(unit_id: 20, life: 4)]
    as "a creature the cast is aimed at is selected, with its life"
  assert selected(28) == [] as "another player's unit is not selected"
  assert selected(29) == [] as "a static object is not selected"
}

pub fn a_spell_the_areas_do_not_hold_strikes_nobody_test() -> Nil {
  use <- owned_test.run(60_000)
  let areas = spell_tables.fixture_areas()
  let chosen =
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(1),
        primary_target: 7,
        spent: None,
        started_at: strike_support.start_pose(),
        fired: False,
      ),
      attacker: strike_support.attacker(),
      picture: picture(),
      areas:,
      now_ms: 0,
    )
  assert chosen.units == [] && chosen.blows == []
}

/// A foe at (x, z), alive and attackable by an Exile.
fn foe_at(x x: Float, z z: Float) -> shown.Shown {
  strike_support.creature_at(
    x:,
    z:,
    alive: True,
    attackable: Attackable(exile: True, dominion: True),
  )
}

/// The foes `select` finds in the area of `spell4_id` for a go whose cast started at the
/// origin facing -z, struck by a caster that has since moved to x 40 and turned half a turn
/// (facing +z): the ids of the units in `candidates`, nearest first, at go `phase`. The primary
/// target is `primary_target`.
fn selected_after_the_caster_moved(
  areas areas: spell_area.Areas,
  spell4_id spell4_id: Int,
  phase phase: Int,
  primary_target primary_target: Int,
  candidates candidates: List(#(Int, Float, Float)),
) -> List(Int) {
  let moved = Pose(at: Point(x: 40.0, z: 0.0), yaw: 3.1415927)
  let chosen =
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase:,
        spell4_id: Spell4Id(spell4_id),
        primary_target:,
        spent: None,
        started_at: Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0),
        fired: False,
      ),
      attacker: strike.Attacker(..strike_support.attacker(), pose: moved),
      picture: dict.from_list(
        list.map(candidates, fn(candidate) {
          #(candidate.0, foe_at(x: candidate.1, z: candidate.2))
        }),
      ),
      areas:,
      now_ms: 0,
    )
  chosen.area
}

pub fn a_row_fixed_at_the_cast_start_strikes_where_the_cast_started_and_one_that_follows_strikes_where_the_caster_stands_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  // The start pose faces -z from the origin, so 6 m ahead of it is (0, -6); the moved caster
  // at (40, 0) faces +z, so 6 m ahead of it is (40, 6). A creature's hit radius is 3.
  list.each(
    [
      #(
        41_844,
        7,
        [#(21, 0.0, -6.0), #(22, 40.0, 6.0)],
        [21],
        "Fissure's child: TelegraphDamage 2998, a rectangle 10 wide from 1 to 15 m ahead, flag 8, holds the creature 6 m ahead of the start and not the one 6 m ahead of the moved caster",
      ),
      #(
        39_269,
        7,
        [#(21, 0.0, -20.0), #(22, 40.0, 20.0)],
        [21],
        "Razor Disk's child: TelegraphDamage 2123, a rectangle 3 wide from 1 to 30 m ahead, flag 8: the creature 20 m ahead of the start",
      ),
      #(
        58_591,
        7,
        [#(21, 0.0, -5.0), #(22, 40.0, 5.0)],
        [22],
        "Kick: TelegraphDamage 168, flag 1, follows the caster: the creature 5 m ahead of where the caster stands",
      ),
      #(
        41_844,
        99,
        [#(21, 0.0, -6.0)],
        [],
        "a primary target the picture does not show strikes nobody, whatever the anchor",
      ),
      #(
        58_591,
        99,
        [#(22, 40.0, 5.0)],
        [],
        "the same for a row that follows the caster",
      ),
    ],
    fn(row) {
      let #(spell4_id, primary_target, candidates, expected, reason) = row
      assert selected_after_the_caster_moved(
          areas:,
          spell4_id:,
          phase: 0,
          primary_target:,
          candidates:,
        )
        == expected
        as reason
    },
  )
}

pub fn a_fissure_go_strikes_the_foes_inside_its_own_rectangle_and_not_the_wider_one_of_the_go_before_test() -> Nil {
  use <- owned_test.run(60_000)
  let areas = spell_tables.fixture_areas()
  // The cast started at the origin facing -z, so 6 m ahead of the start is z -6. The
  // rectangles of TelegraphDamage 2998, 2997 and 2996 are 10, 6 and 2 wide, so their half
  // widths are 5, 3 and 1; a creature's hit radius is 3. Foe 21 (x 0) is inside all three,
  // foe 22 (x 5) is 0, 2 and 4 m from them, foe 23 (x 7) is 2, 4 and 6 m from them. Foe 24
  // stands where the moved caster would strike if the rows followed it.
  let candidates = [
    #(21, 0.0, -6.0),
    #(22, 5.0, -6.0),
    #(23, 7.0, -6.0),
    #(24, 40.0, 6.0),
  ]
  list.each(
    [
      #(
        0,
        [21, 22, 23],
        "go 0 strikes the 10 wide rectangle of row 2998, phaseFlags 1",
      ),
      #(
        1,
        [21, 22],
        "go 1 strikes the 6 wide rectangle of row 2997, phaseFlags 2",
      ),
      #(2, [21], "go 2 strikes the 2 wide rectangle of row 2996, phaseFlags 4"),
    ],
    fn(row) {
      let #(phase, expected, reason) = row
      assert list.sort(
          selected_after_the_caster_moved(
            areas:,
            spell4_id: 41_844,
            phase:,
            primary_target: 7,
            candidates:,
          ),
          int.compare,
        )
        == expected
        as reason
    },
  )
}

pub fn a_go_whose_phase_names_no_hit_row_selects_nobody_from_the_area_test() -> Nil {
  use <- owned_test.run(60_000)
  // Fissure's child 41844 with its three gos' damage replaced by one row of phaseFlags -1
  // that every go takes, so each go selects the area; its hit shapes are planted: none at go 0
  // and the area row's own range at go 1 (the area row is 0 to 20 m over 360 degrees).
  let fissure =
    spell_area.of_spell(
      areas: spell_tables.fixture_areas(),
      spell4_id: Spell4Id(41_844),
    )
  let assert Ok(fissure) = fissure
    as "Fissure's child is in the fixture's areas"
  let assert [effect, ..] = fissure.damage as "the child holds damage rows"
  let aimed = fn(aim) {
    let planted =
      spell_area.SpellArea(
        ..fissure,
        inside_by_go: [None, Some(area.InsideRow), Some(area.InsideRow)],
        damage: [spell_area.DamageEffect(..effect, phase_flags: -1, aim:)],
      )
    dict.insert(spell_tables.fixture_areas(), 41_844, planted)
  }
  // A foe 6 m ahead of the start, in the caster's picture; unit 7 is the caster.
  let selected = fn(areas, phase) {
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase:,
        spell4_id: Spell4Id(41_844),
        primary_target: 21,
        spent: None,
        started_at: Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0),
        fired: False,
      ),
      attacker: strike_support.attacker(),
      picture: dict.from_list([#(21, foe_at(x: 0.0, z: -6.0))]),
      areas:,
      now_ms: 0,
    )
  }
  let in_the_area = selected(aimed(spell_plan.AimsAtArea), 0)
  assert in_the_area.area == [] && in_the_area.units == []
    as "a go whose phase no hit row names selects nobody from the area, though its damage aims at the area"
  let next_go = selected(aimed(spell_plan.AimsAtArea), 1)
  assert next_go.area == [21]
    as "the next go, whose hit shapes are the area row's range, selects the foe 6 m ahead"
  let at_the_target = selected(aimed(spell_plan.AimsAtPrimaryTargetAndArea), 0)
  assert at_the_target.area == []
    && list.map(at_the_target.units, fn(unit) { unit.unit_id }) == [21]
    as "a damage row aimed at the target as well still strikes the primary target at that go, and nobody from the area"
}

pub fn a_row_placed_on_the_cast_target_strikes_around_the_unit_a_spell_is_started_on_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  // The start pose faces -z from the origin; the moved caster (unit 7) stands at (40, 0). A
  // creature's hit radius is 3 (`foe_at`). Field Probes' children (41404 and 55046) are started
  // on the caster, and their area-aimed row is a Proxy that casts its dataBits01 spell every
  // tick, which the plan does not start (`Spell4Effects.effectType.26.periodic`), so no case
  // here is one of them.
  list.each(
    [
      #(
        47_202,
        21,
        [#(21, 10.0, 0.0), #(22, 13.0, 0.0), #(23, 20.0, 0.0), #(24, 40.0, 0.0)],
        [21, 22],
        "Flash Bang's child 47202, TelegraphDamage 1766 (a circle of radius 4, flags 0x1200, targetTypeFlags 2), started on the struck unit 21 shown at (10, 0): the unit itself and the creature 3 m from it are inside, the one 10 m from it and the one where the caster stands are not",
      ),
      #(
        35_360,
        21,
        [#(21, 10.0, 0.0), #(22, 13.0, 0.0), #(23, 20.0, 0.0), #(24, 40.0, 0.0)],
        [21, 22],
        "Rapid Fire's child 35360, its twin TelegraphDamage 204 (a circle of radius 5, flags 0x801040, targetTypeFlags 2) beside the drawn row 137, started on the struck unit 21 shown at (10, 0): the unit and the creature 3 m from it are inside, the one 10 m from it is not",
      ),
      #(
        41_343,
        21,
        [#(21, 10.0, 0.0), #(22, 13.0, 0.0), #(23, 20.0, 0.0), #(24, 40.0, 0.0)],
        [21, 22],
        "Bio Shell's child 41343, TelegraphDamage 15498 (a circle of radius 6, flags 0x1140220, targetTypeFlags 2, following its unit), started on the struck unit 21: the unit and the creature 3 m from it are inside, the one 10 m from it is not",
      ),
    ],
    fn(row) {
      let #(spell4_id, primary_target, candidates, expected, reason) = row
      assert selected_after_the_caster_moved(
          areas:,
          spell4_id:,
          phase: 0,
          primary_target:,
          candidates:,
        )
        == expected
        as reason
    },
  )
}

pub fn crushs_second_spell_strikes_up_to_four_within_4_m_of_the_struck_foe_and_the_foe_once_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let around_the_foe =
    dict.from_list([
      #(21, foe_at(x: 0.0, z: -3.0)),
      #(22, foe_at(x: 0.0, z: -5.0)),
      #(23, foe_at(x: 3.0, z: -3.0)),
      #(24, foe_at(x: 0.0, z: -7.0)),
      #(25, foe_at(x: 5.0, z: -3.0)),
      #(26, foe_at(x: 0.0, z: -6.5)),
    ])
  let chosen =
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(42_297),
        primary_target: 21,
        spent: None,
        started_at: strike_support.start_pose(),
        fired: False,
      ),
      attacker: strike_support.attacker(),
      picture: around_the_foe,
      areas:,
      now_ms: 0,
    )
  assert list.map(chosen.units, fn(aimed) { aimed.unit_id }) == [21, 22, 23, 26]
    as "Spell4.32812.area: row 704 takes 4 within 4 m of the foe it is cast on, nearest first: the foe (0 m), 22 (2 m), 23 (3 m) and 26 (3.5 m); 24 is 4 m away and fifth, 25 is 5 m away; the foe is selected by the area and added once"
  assert list.length(chosen.blows) == 1
    as "Spell4Effects 95950: Magic damage, aimed at both the cast's target and the area"
}

pub fn staggers_multiphase_spell_selects_up_to_five_within_8_m_at_each_phase_and_its_child_strikes_its_own_target_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let close_by =
    dict.from_list([
      #(21, foe_at(x: 0.0, z: -1.0)),
      #(22, foe_at(x: 0.0, z: -2.0)),
      #(23, foe_at(x: 0.0, z: -3.0)),
      #(24, foe_at(x: 0.0, z: -4.0)),
      #(25, foe_at(x: 0.0, z: -5.0)),
      #(26, foe_at(x: 0.0, z: -6.0)),
      #(27, foe_at(x: 0.0, z: -9.0)),
    ])
  list.each([0, 1, 2, 3], fn(phase) {
    let chosen =
      strike.select(
        asked: GoAsked(
          cast_id: 5,
          phase:,
          spell4_id: Spell4Id(38_780),
          primary_target: 7,
          spent: None,
          started_at: strike_support.start_pose(),
          fired: False,
        ),
        attacker: strike_support.attacker(),
        picture: close_by,
        areas:,
        now_ms: 0,
      )
    assert list.map(chosen.units, fn(aimed) { aimed.unit_id })
      == [21, 22, 23, 24, 25]
      && chosen.area == [21, 22, 23, 24, 25]
      && chosen.blows == []
      as "Spell4.38791.area: 38780 picks its 5 nearest ahead within its 8 m cone (90 degrees, twin 2189) at each of its four phases and strikes nobody itself (its Proxy starts 38781 on each)"
  })
  let child =
    strike.select(
      asked: GoAsked(
        cast_id: 6,
        phase: 0,
        spell4_id: Spell4Id(38_781),
        primary_target: 22,
        spent: None,
        started_at: strike_support.start_pose(),
        fired: False,
      ),
      attacker: strike_support.attacker(),
      picture: close_by,
      areas:,
      now_ms: 0,
    )
  assert child.units == [Aimed(unit_id: 22, life: 4)]
    && list.length(child.blows) == 1
    as "38781 damages its own target, the unit it was started on (Spell4Effects 83829: targetFlags 2)"
}

pub fn each_pulse_of_electrocutes_channel_selects_the_foes_its_area_row_names_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  let close_by =
    dict.from_list([
      #(21, foe_at(x: 0.0, z: -1.0)),
      #(22, foe_at(x: 0.0, z: -2.0)),
      #(23, foe_at(x: 0.0, z: -3.0)),
      #(24, foe_at(x: 0.0, z: -4.0)),
      #(25, foe_at(x: 0.0, z: -5.0)),
      #(26, foe_at(x: 0.0, z: -6.0)),
    ])
  // Spell4.41276: channelInitialDelay 500, channelMaxTime 3000 and channelPulseTime
  // 500 give the pulses 0 to 5 of the recording's cast 2147485756 (0x7f4 phases 0 to 5).
  list.each([0, 1, 2, 3, 4, 5], fn(pulse) {
    let chosen =
      strike.select(
        asked: GoAsked(
          cast_id: 5,
          phase: pulse,
          spell4_id: Spell4Id(41_276),
          primary_target: 7,
          spent: None,
          started_at: strike_support.start_pose(),
          fired: False,
        ),
        attacker: strike_support.attacker(),
        picture: close_by,
        areas:,
        now_ms: 0,
      )
    assert list.map(chosen.units, fn(aimed) { aimed.unit_id })
      == [21, 22, 23, 24, 25]
      && list.map(chosen.blows, fn(blow) { blow.effect_id })
      == [Spell4EffectsId(92_587)]
      as {
        "Spell4.41276.area: area row 411 (5 units, 0 to 25 m, 360 degrees), and its one damage effect 92587 (targetFlags 4, phaseFlags -1: every pulse) strikes the 5 nearest foes at each pulse, as it does at pulse 0; pulse "
        <> int.to_string(pulse)
      }
  })
}

// ---- a spell with an innate cost EMM id strikes with the effects its n chooses ----

/// The areas of the client's rows, where Mind Burst spends every Psi Point held
/// (`Spell4.32809`).
fn mind_burst_areas() -> spell_area.Areas {
  spell_tables.fixture_areas()
}

/// The go the cast rule asks for when an Esper holding `points` Psi Points presses
/// Mind Burst (bag index 2).
fn mind_burst_go(points points: Int) -> GoAsked {
  let assert Ok(mind_burst) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: id.Spell4BaseId(19_019),
    )
    as "the planted Esper holds Mind Burst"
  let resources =
    class_resource_support.new(
      resource: Resource(
        ..class_resource_support.resource_of(3),
        start: int.to_float(points),
      ),
    )
  let #(_, effects) =
    support.pressed_raw_in(
      plans: support.with_spells(plans: support.plans(), spells: [mind_burst]),
      state: cast_state.new(),
      caster: support.caster_holding(resources:),
      bag_index: 2,
      target: 0,
      at: 1000,
    )
  let assert [asked] =
    list.filter_map(effects, fn(effect) {
      case effect {
        cast_state.Strike(asked:) -> Ok(asked)
        _ -> Error(Nil)
      }
    })
    as "Mind Burst has no cast time: its go is asked at the accept"
  asked
}

pub fn mind_burst_at_p_points_strikes_with_only_the_damage_effect_of_p_minus_1_test() -> Nil {
  use <- owned_test.run(60_000)
  let areas = mind_burst_areas()
  list.each([1, 2, 3, 4, 5], fn(points) {
    let chosen =
      strike.select(
        asked: mind_burst_go(points:),
        attacker: strike_support.attacker(),
        picture: dict.new(),
        areas:,
        now_ms: 0,
      )
    assert list.map(chosen.blows, fn(blow) { blow.effect_id })
      == [Spell4EffectsId(61_992 + points)]
      as "Spell4.32809: p Psi Points apply the damage effect of emmValue p - 1, 61993 to 61997, and no other"
  })
}

pub fn a_3_point_mind_burst_tells_its_creature_only_effect_61995_test() -> Nil {
  use <- owned_test.run(60_000)
  let picture = dict.from_list([#(21, foe_at(x: 0.0, z: -3.0))])
  let chosen =
    strike.select(
      asked: mind_burst_go(points: 3),
      attacker: strike_support.attacker(),
      picture:,
      areas: mind_burst_areas(),
      now_ms: 0,
    )
  assert list.map(chosen.units, fn(aimed) { aimed.unit_id }) == [21]
    as "Spell4.32809.area: row 345 takes the foe 3 m away"
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: chosen,
      attacker: strike_support.attacker(),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [#(0, 0, 0)]),
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [strike.TellStrike(tell: strike_tell.Strike(offence:, ..), ..)] =
    tells(effects:)
    as "one strike for the one foe"
  assert list.map(offence.blows, fn(blow) { blow.spell4_effects_id })
    == [61_995]
    as "Spell4.32809 at 3 Psi Points (n 2): the creature answers with a description of 61995 alone, so the 0x7f4 names no other of 61993 to 61997"
}

pub fn a_go_with_no_n_strikes_with_every_damage_effect_the_spell_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  let go = mind_burst_go(points: 3)
  let chosen =
    strike.select(
      asked: GoAsked(..go, spent: None),
      attacker: strike_support.attacker(),
      picture: dict.new(),
      areas: mind_burst_areas(),
      now_ms: 0,
    )
  assert list.map(chosen.blows, fn(blow) { blow.effect_id.value })
    == [61_993, 61_994, 61_995, 61_996, 61_997]
    as "Spell4Effects.emmComparison: a cast with no n chooses nothing, so none of the five is left out"
}

// ---- crowd-control states (`genesis_prime/game/crowd_control`) ----
//
// Expected values come from these places: Gate's Stun, Spell4Effects 100836 (state 0,
// durationTime 3250, delayTime 0, dataBits03 1, aimed at the area) from
// `table_rows -- Spell4Effects 100836`; the instance id is the caster's unit id x 4096
// plus its count of the states it told, from 1 (the doc of `crowd_control.instance_id`:
// non-zero, within 32 bits, and a different caster's ids differ).

fn stun_row(aim aim: spell_plan.Aim) -> spell_plan.CrowdControl {
  spell_plan.CrowdControl(
    effect_id: Spell4EffectsId(100_836),
    phase_flags: -1,
    aim:,
    row: crowd_control.Row(
      state: crowd_control_state.Stun,
      delay_ms: 0,
      duration_ms: 3250,
      armor_removed: 1,
      until_removed: False,
    ),
    condition: spell_plan.Always,
    tag: spend.always,
    move: None,
  )
}

/// A selection of these units, with no damage and Gate's Stun aimed so.
fn stunning(
  asked asked: GoAsked,
  units units: List(Int),
  aim aim: spell_plan.Aim,
) -> Selection {
  Selection(..selection(asked:, units:, damaging: False), controls: [
    stun_row(aim:),
  ])
}

pub fn a_stun_with_no_damage_is_told_to_each_unit_with_the_next_instance_ids_of_the_casters_count_test() -> Nil {
  use <- owned_test.run(5000)
  let chosen =
    stunning(
      asked: asked(cast_id: 5, phase: 0),
      units: [10, 11],
      aim: AimsAtArea,
    )
  assert strike.entropy_needed(selection: chosen) == 24
    as "a strike takes its rolls: 12 seed bytes for each unit, though it has no damage"
  let #(state, effects) =
    begun(state: strike.new(), selection: chosen, now_ms: 1000)
  let assert [
    strike.TellStrike(unit_id: 10, tell: first, ..),
    strike.TellStrike(unit_id: 11, tell: second, ..),
  ] = tells(effects:)
    as "each unit is told, though the phase has no damage"
  assert first.controls
    == [crowd_control_support.gate_stun(instance_id: 28_673)]
    && second.controls == [crowd_control_support.gate_stun(instance_id: 28_674)]
    as "unit 7's first and second state: 7 x 4096 + 1 and + 2, each unit its own"
  assert first.offence.blows == []
  assert went(effects:) == [] as "the round waits for the creatures' answers"
  let #(_, later) =
    begun(
      state:,
      selection: stunning(
        asked: asked(cast_id: 6, phase: 0),
        units: [10],
        aim: AimsAtArea,
      ),
      now_ms: 1100,
    )
  let assert [strike.TellStrike(tell: third, ..)] = tells(effects: later)
  assert third.controls
    == [crowd_control_support.gate_stun(instance_id: 28_675)]
    as "the count goes on from one go to the next"
}

pub fn two_casters_instance_ids_for_one_creature_differ_test() -> Nil {
  use <- owned_test.run(5000)
  let chosen =
    stunning(asked: asked(cast_id: 5, phase: 0), units: [10], aim: AimsAtArea)
  let told_by = fn(attacker: Attacker) {
    let #(_, effects) =
      strike.begin(
        strike: strike.new(),
        selection: chosen,
        attacker:,
        formulas: rating_support.formulas(),
        entropy: entropy(rolls: [#(0, 0, 0)]),
        gate: strike_support.passes_all(),
        now: at(ms: 1000),
      )
    let assert [strike.TellStrike(tell:, ..)] = tells(effects:)
    tell.controls
  }
  let first = told_by(strike_support.attacker())
  let second = told_by(Attacker(..strike_support.attacker(), unit_id: 8))
  assert first == [crowd_control_support.gate_stun(instance_id: 28_673)]
    && second == [crowd_control_support.gate_stun(instance_id: 32_769)]
    as "7 x 4096 + 1 and 8 x 4096 + 1: no id is shared, and none is 0"
}

pub fn union_control_row_is_both_a_restriction_and_a_told_state_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 60607 (`table_rows -- Spell4Effects 60607`): spell 32236, effectType 4,
  // targetFlags 5 (the caster and the area), state 0 (Stun), durationTime 3000, dataBits03
  // 1, phaseFlags 1.
  let spell = spell_tables.client_spell(spell4_id: 32_236)
  let ids = fn(rows: List(spell_plan.CrowdControl)) {
    list.map(rows, fn(control) { control.effect_id.value })
  }
  assert list.contains(
    ids(spell_plan.restrictions_in_phase(spell:, phase: 0, spent: None)),
    60_607,
  )
    as "targetFlags 5 names the caster, so the state is one of the caster's restrictions"
  let told = spell_plan.controls_in_phase(spell:, phase: 0, spent: None)
  let assert [control] =
    list.filter(told, fn(control) { control.effect_id.value == 60_607 })
    as "targetFlags 5 names the area, so the state is one of the creatures' states"
  assert control.aim == spell_plan.AimsAtCasterAndArea
  assert control.row
    == crowd_control.Row(
      state: crowd_control_state.Stun,
      delay_ms: 0,
      duration_ms: 3000,
      armor_removed: 1,
      until_removed: False,
    )
    as "dataBits00 the state, durationTime the time, dataBits03 the armor"
  // The caster is unit 7 (`strike_support.attacker`); the area holds units 10 and 11.
  let chosen =
    Selection(
      ..selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10, 11],
        damaging: False,
      ),
      controls: [control],
    )
  let #(_, effects) =
    begun(state: strike.new(), selection: chosen, now_ms: 1000)
  let assert [
    strike.TellStrike(unit_id: 10, tell: first, ..),
    strike.TellStrike(unit_id: 11, tell: second, ..),
  ] = tells(effects:)
    as "the state is told to each struck creature and to nobody else: the caster is not told"
  assert list.map(first.controls, fn(told) { told.effect_id }) == [60_607]
  assert list.map(second.controls, fn(told) { told.effect_id }) == [60_607]
}

pub fn a_knockback_control_is_told_with_its_drawn_move_and_the_strikers_place_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 56250 (`table_rows -- Spell4Effects 56250`): spell 30693, effectType 4,
  // targetFlags 4 (the area), state 16 (Knockback), delayTime 0, durationTime 0, dataBits03 1,
  // dataBits07 21, phaseFlags 1. Its helper's throw is Spell4Effects 73826: away from the
  // reference unit, 10.0 m, 375 ms, no gravity, flags 1, height 2.0.
  let spell = spell_tables.client_spell(spell4_id: 30_693)
  let assert [control] =
    spell_plan.controls_in_phase(spell:, phase: 0, spent: None)
    as "the spell's one state lands in phase 0"
  let chosen =
    Selection(
      ..selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10, 11],
        damaging: False,
      ),
      controls: [control],
    )
  assert strike.entropy_needed(selection: chosen) == 24 + 2 * 8
    as "12 seed bytes for each of the 2 units, then 8 draw bytes for the one throwing row and each unit"
  // The striker stands somewhere that is neither the origin nor a number the draws share.
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 12.5,
      y: 1.0,
      z: -7.0,
    )
  let striker = Attacker(..strike_support.attacker(), place:, hit_radius: 0.75)
  // Each draw is a 32-bit word, a fraction of 2^32: unit 10's draws are 0x40000000 and
  // 0x80000000 (a quarter and a half), unit 11's 0xC0000000 and 0x20000000 (three quarters
  // and an eighth).
  let seed = <<
    0:size(96),
    0:size(96),
    0x40000000:size(32),
    0x80000000:size(32),
    0xC0000000:size(32),
    0x20000000:size(32),
  >>
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: chosen,
      attacker: striker,
      formulas: rating_support.formulas(),
      entropy: seed,
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [
    strike.TellStrike(unit_id: 10, tell: first, ..),
    strike.TellStrike(unit_id: 11, tell: second, ..),
  ] = tells(effects:)
    as "each unit is told the state"
  let move =
    forced_move.Move(
      way: forced_move.Away,
      mover: forced_move.Flight,
      min_distance: 10.0,
      max_distance: 10.0,
      flight_ms: 375,
      gravity: 0.0,
      flags: 1,
      height: 2.0,
    )
  let reference = forced_move.Reference(place:, radius: 0.75)
  let throw_of = fn(told: strike_tell.Tell) {
    let assert [control] = told.controls
    assert control.effect_id == 56_250
    assert control.row.state == crowd_control_state.Knockback
    control.throw
  }
  assert throw_of(first)
    == Some(forced_move.Throw(
      move:,
      draws: forced_move.Draws(distance: 0.25, angle: 0.5),
      reference:,
    ))
    as "unit 10 takes the first 8 draw bytes, with the striker's place and radius"
  assert throw_of(second)
    == Some(forced_move.Throw(
      move:,
      draws: forced_move.Draws(distance: 0.75, angle: 0.125),
      reference:,
    ))
    as "unit 11 takes the next 8"
}

pub fn each_throwing_row_and_unit_takes_its_own_draw_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 56250 (spell 30693, a Knockback with a helper, as above) is the first
  // throwing row; the second is the same row under another id, which the plan tells apart
  // by its effect id.
  let spell = spell_tables.client_spell(spell4_id: 30_693)
  let assert [first_row] =
    spell_plan.controls_in_phase(spell:, phase: 0, spent: None)
    as "the spell's one state lands in phase 0"
  let second_row =
    spell_plan.CrowdControl(..first_row, effect_id: Spell4EffectsId(56_251))
  let chosen =
    Selection(
      ..selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10, 11],
        damaging: False,
      ),
      controls: [first_row, second_row],
    )
  assert strike.entropy_needed(selection: chosen) == 24 + 4 * 8
    as "12 seed bytes for each of the 2 units, then 8 draw bytes for each of the 2 rows and each of the 2 units"
  // The draws are 32-bit words, each a fraction of 2^32: the slots are the row's and the
  // unit's, in row order and then selection order. Every word differs, so a slot read for
  // the wrong row or unit gives other draws.
  let seed = <<
    0:size(96),
    0:size(96),
    0x10000000:size(32),
    0x20000000:size(32),
    0x30000000:size(32),
    0x40000000:size(32),
    0x50000000:size(32),
    0x60000000:size(32),
    0x70000000:size(32),
    0x80000000:size(32),
  >>
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: chosen,
      attacker: strike_support.attacker(),
      formulas: rating_support.formulas(),
      entropy: seed,
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [
    strike.TellStrike(unit_id: 10, tell: first, ..),
    strike.TellStrike(unit_id: 11, tell: second, ..),
  ] = tells(effects:)
    as "each unit is told both states"
  let draws_of = fn(told: strike_tell.Tell) {
    list.map(told.controls, fn(control) {
      let assert Some(throw) = control.throw as "each row throws"
      #(control.effect_id, throw.draws)
    })
  }
  assert draws_of(first)
    == [
      #(56_250, forced_move.Draws(distance: 0.0625, angle: 0.125)),
      #(56_251, forced_move.Draws(distance: 0.3125, angle: 0.375)),
    ]
    as "unit 10 takes the 1st and 3rd slots: its row's, then the second row's"
  assert draws_of(second)
    == [
      #(56_250, forced_move.Draws(distance: 0.1875, angle: 0.25)),
      #(56_251, forced_move.Draws(distance: 0.4375, angle: 0.5)),
    ]
    as "unit 11 takes the 2nd and 4th slots"
}

pub fn a_state_aimed_at_the_primary_target_is_told_to_it_alone_test() -> Nil {
  use <- owned_test.run(5000)
  let goes = GoAsked(..asked(cast_id: 5, phase: 0), primary_target: 11)
  let #(state, effects) =
    begun(
      state: strike.new(),
      selection: stunning(
        asked: goes,
        units: [10, 11],
        aim: spell_plan.AimsAtPrimaryTarget,
      ),
      now_ms: 1000,
    )
  let assert [strike.TellStrike(unit_id: 11, tell:, ..)] = tells(effects:)
    as "only the primary target is told"
  assert tell.controls == [crowd_control_support.gate_stun(instance_id: 28_673)]
  let landed =
    strike_tell.ControlLanded(
      tell: crowd_control_support.gate_stun(instance_id: 28_673),
      ends_at_ms: 4250,
      interrupted: None,
    )
  let #(_, closed) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 11),
      outcome: Landed(
        descriptions: [],
        controls: [landed],
        armor_removed: 0,
        gates_passed: [],
      ),
      now_ms: 1050,
    )
  assert went(effects: closed)
    == [
      #(5, 0, [
        cast_state.Hit(
          unit_id: 10,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
        cast_state.Hit(
          unit_id: 11,
          unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
          descriptions: [],
          controls: [landed],
          armor_removed: 0,
          ticking: [],
        ),
      ]),
    ]
    as "the go names the states that landed, as the creature answered them"
}

pub fn a_state_aimed_at_the_area_does_not_reach_a_primary_target_outside_it_but_one_aimed_at_both_does_test() -> Nil {
  use <- owned_test.run(5000)
  // Unit 10 is inside the area and unit 11, the cast's target, is appended outside it
  // (`strike.select` adds the primary target for a damage effect aimed at it).
  let goes = GoAsked(..asked(cast_id: 5, phase: 0), primary_target: 11)
  let told_to = fn(aim) {
    let #(_, effects) =
      begun(
        state: strike.new(),
        selection: Selection(
          ..stunning(asked: goes, units: [10, 11], aim:),
          area: [10],
        ),
        now_ms: 1000,
      )
    list.map(strike_support.creatures_told(effects:), fn(told) { told.0 })
  }
  assert told_to(AimsAtArea) == [10]
    as "Spell4Effects.targetFlags 4 aims at the units the area selected"
  assert told_to(spell_plan.AimsAtPrimaryTargetAndArea) == [10, 11]
    as "targetFlags 6 aims at the area's units and the cast's target"
  assert told_to(spell_plan.AimsAtPrimaryTarget) == [11]
    as "targetFlags 2 aims at the cast's target alone"
}

// ---- the caster's properties ----

/// The offence the strike carries to one unit for a caster with these properties, the
/// round's one blow of 10 damage.
fn offence_of_caster_with(
  properties properties: unit_properties.Properties,
) -> Offence {
  let blow =
    DamageEffect(
      ..strike_support.damage_effect(),
      formula: damage.Formula(multiplier: 1.0, base: 10.0, parameters: []),
    )
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: Selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [strike.Aimed(unit_id: 10, life: 3)],
        area: [10],
        blows: [blow],
        controls: [],
        ticking: [],
        gates: [],
        players: [],
        acts_on_each_unit: False,
        heals: [],
      ),
      attacker: Attacker(..strike_support.attacker(), properties:),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [#(0, 0, 0)]),
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [strike.TellStrike(tell: strike_tell.Strike(offence:, ..), ..)] =
    tells(effects:)
    as "one strike for the one selected unit"
  offence
}

fn with_crit_modifier(flat flat: Float) -> unit_properties.Properties {
  properties_support.with_modifier(
    properties: properties_support.fresh(level: 1),
    source: unit_properties.Source(
      cast_id: 1,
      effect_id: Spell4EffectsId(135_954),
    ),
    modifier: unit_properties.Change(
      property: id.UnitProperty2Id(102),
      mode: 3,
      multiplier: 1.0,
      flat:,
      per_level: 0.0,
    ),
  )
}

pub fn a_crit_chance_modifier_on_the_player_changes_the_chance_its_strikes_carry_test() -> Nil {
  use <- owned_test.run(5000)
  // BaseCritChance is 0.0 and 135954 adds 0.08, as a 32-bit float (0x3da3d70a,
  // `table_rows -- Spell4Effects 135954`). The chance a strike carries is the formula's
  // at rating 0, which is the base alone: 0.0, then 0.08 while the modifier lasts.
  assert offence_of_caster_with(properties: properties_support.fresh(level: 1)).crit_chance
    == 0.0
  assert offence_of_caster_with(properties: with_crit_modifier(
      flat: 0.07999999821186066,
    )).crit_chance
    == 0.07999999821186066
    as "the base of the hit chance is the property's value, 0.0 + 0.08 while the modifier lasts"
}

pub fn a_planted_100_percent_crit_modifier_makes_every_blow_crit_test() -> Nil {
  use <- owned_test.run(5000)
  // The hit rule: a blow is critical when the crit roll is below the crit chance
  // (genesis_prime/game/hit), at a severity of 1.5. A roll of 0.99 never crits at a
  // chance of 0.0 and always at a chance of 1.0.
  let roll = Rolls(crit: 0.99, deflect: 0.5, glance: 0.5)
  let outcome = fn(properties) {
    hit.apply(
      target: damage.Vitals(
        health: 100,
        max_health: 100,
        shield: 0,
        max_shield: 0,
      ),
      absorbs: [],
      offence: offence_of_caster_with(properties:),
      defence: hit.unprotected,
      rolls: roll,
    )
  }
  let assert hit.Landed(descriptions: [plain], ..) =
    outcome(properties_support.fresh(level: 1))
  assert plain.damage.combat_result == combat_result.Hit
  assert plain.damage.raw_damage == 10
  let assert hit.Landed(descriptions: [critical], ..) =
    outcome(with_crit_modifier(flat: 1.0))
  assert critical.damage.combat_result == combat_result.Critical
    as "the modified chance is 1.0, so the roll 0.99 crits"
  assert critical.damage.raw_damage == 15
    as "at the player's severity, 1.5 (UnitProperty2 127's default)"
}

/// Paralytic Surge's damage row (Spell4Effects 96125), as a periodic row of the tick
/// tests: the row's own formula, so a tick's value follows the caster's ratings.
fn surge_blow() -> spell_area.DamageEffect {
  DamageEffect(
    effect_id: Spell4EffectsId(96_125),
    damage_type: 2,
    delay_ms: 0,
    phase_flags: -1,
    aim: AimsAtArea,
    formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
      damage.Parameter(kind: 12, value: 0.0935),
      damage.Parameter(kind: 13, value: 0.0935),
      damage.Parameter(kind: 10, value: 8.14),
    ]),
    threat_multiplier: 1.0,
    condition: spell_plan.Always,
    tag: spend.always,
  )
}

fn tick_asked(go go: Int, tick tick: Int) -> cast_state.TickAsked {
  cast_state.TickAsked(
    cast_id: 5,
    spell4_id: Spell4Id(58_591),
    effect_id: Spell4EffectsId(96_125),
    unit_id: 10,
    life: 3,
    go:,
    tick:,
    what: cast_state.StrikeWithBlow(blow: surge_blow()),
  )
}

fn tick_key(go go: Int, tick tick: Int) -> strike_tell.Key {
  Key(
    cast_id: 5,
    occasion: strike_tell.AtTick(effect_id: Spell4EffectsId(96_125), go:, tick:),
    unit_id: 10,
  )
}

fn tick_begun(
  state state: State,
  asked asked: cast_state.TickAsked,
  stats stats: damage.Attacker,
  rolls rolls: #(Int, Int, Int),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  strike.begin_tick(
    strike: state,
    asked:,
    attacker: Attacker(..strike_support.attacker(), stats:),
    formulas: rating_support.formulas(),
    entropy: entropy(rolls: [rolls]),
    now: at(ms: now_ms),
  )
}

/// Each strike told, as its unit, life, key, rolls and blows; a strike that tells a
/// state is not a tick's.
fn tick_tells(
  effects effects: List(Effect),
) -> List(#(Int, Int, strike_tell.Key, hit.Rolls, List(hit.Blow))) {
  list.filter_map(strike_support.creatures_told(effects:), fn(told) {
    case told {
      #(
        unit_id,
        life,
        strike_tell.Strike(
          key:,
          striker: strike_tell.PlayerStriker(rolls:, ..),
          offence:,
          controls: [],
          ..,
        ),
      ) -> Ok(#(unit_id, life, key, rolls, offence.blows))
      #(_, _, strike_tell.Strike(..)) -> Error(Nil)
    }
  })
}

/// The tick rounds that closed in these effects, in order.
fn ticked(
  effects effects: List(Effect),
) -> List(#(cast_state.TickAsked, Option(cast_state.Struck))) {
  strike_support.ticks_closed(effects:)
}

fn surge_tick_blow(damage damage: Int) -> hit.Blow {
  Blow(
    spell4_effects_id: 96_125,
    damage_type: 2,
    damage: Worked(damage),
    delay_ms: 0,
    threat_multiplier: 1.0,
  )
}

pub fn each_tick_rolls_the_hit_rule_on_the_value_of_its_time_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    tick_begun(
      state: strike.new(),
      asked: tick_asked(go: 1, tick: 1),
      stats: attacker_support.fresh(),
      rolls: #(0, 2_147_483_648, 0),
      now_ms: 2000,
    )
  assert tick_tells(effects: first)
    == [
      #(
        10,
        3,
        tick_key(go: 1, tick: 1),
        Rolls(crit: 0.0, deflect: 0.5, glance: 0.0),
        [surge_tick_blow(damage: 8)],
      ),
    ]
    as "the tick strikes its one unit in the life the go struck, keyed by the go and the tick, with its own 12 seed bytes and the row's damage alone: with no rating, Paralytic Surge is 8.14 for the level, rounded to 8 (Spell4Effects 96125, 0x140565600), and no state"
  assert timers(effects: first)
    == [strike.StartTimer(timer: strike.strike_timer, after_ms: 1000)]
    as "the tick's round has the strike's 1 s deadline"
  let #(state, landed_first) =
    answer(
      state:,
      key: tick_key(go: 1, tick: 1),
      outcome: landed(),
      now_ms: 2100,
    )
  assert ticked(effects: landed_first)
    == [
      #(
        tick_asked(go: 1, tick: 1),
        Some(
          cast_state.Hit(
            unit_id: 10,
            unit: cast_state.HitCreature(life: 3, struck_at_ms: 2000),
            descriptions: [],
            controls: [],
            armor_removed: 0,
            ticking: [],
          ),
        ),
      ),
    ]
    as "the landed tick closes its round as a hit on the life it was told to, struck at the tick"
  let #(state, second) =
    tick_begun(
      state:,
      asked: tick_asked(go: 1, tick: 2),
      stats: attacker_support.novice(),
      rolls: #(1_073_741_824, 3_221_225_472, 2_147_483_648),
      now_ms: 3000,
    )
  assert tick_tells(effects: second)
    == [
      #(
        10,
        3,
        tick_key(go: 1, tick: 2),
        Rolls(crit: 0.25, deflect: 0.75, glance: 0.5),
        [surge_tick_blow(damage: 14)],
      ),
    ]
    as "the next tick rolls its own seed bytes and reads the caster as it is now: with the Novice's gear, Assault Power 50.77 and Support Power 13.92, Paralytic Surge is 0.0935 x 50.77 + 0.0935 x 13.92 = 6.05, rounded to 6, plus 8.14, 14.14, rounded to 14 (0x14064c960)"
  let #(_, deflected) =
    answer(
      state:,
      key: tick_key(go: 1, tick: 2),
      outcome: Deflected(gates_passed: []),
      now_ms: 3100,
    )
  assert ticked(effects: deflected)
    == [#(tick_asked(go: 1, tick: 2), Some(cast_state.Deflected(unit_id: 10)))]
    as "a deflected tick closes with no description"
}

pub fn a_tick_while_the_last_is_open_closes_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tick_begun(
      state: strike.new(),
      asked: tick_asked(go: 1, tick: 1),
      stats: attacker_support.fresh(),
      rolls: #(0, 0, 0),
      now_ms: 2000,
    )
  let #(state, _) =
    tick_begun(
      state:,
      asked: tick_asked(go: 1, tick: 2),
      stats: attacker_support.fresh(),
      rolls: #(0, 0, 0),
      now_ms: 2250,
    )
  let #(state, later) =
    answer(
      state:,
      key: tick_key(go: 1, tick: 2),
      outcome: landed(),
      now_ms: 2300,
    )
  assert ticked(effects: later) == []
    as "tick 2 has its answer but waits for tick 1, as a cast's rounds close in the order they began"
  let #(_, earlier) =
    answer(
      state:,
      key: tick_key(go: 1, tick: 1),
      outcome: landed(),
      now_ms: 2400,
    )
  assert list.map(ticked(effects: earlier), fn(closed) { { closed.0 }.tick })
    == [1, 2]
    as "both close at once, tick 1 first"
  // A heal tick of an ally whose answer is in waits for the cast's earlier go round, which
  // a creature has not answered, and closes after it.
  let ally =
    player_address.PlayerAddress(
      connection: ConnectionId(3),
      unit_id: 9,
      stay: map_support.stay(count: 2),
    )
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        damaging: True,
      ),
      now_ms: 1000,
    )
  let #(state, _) =
    strike.begin_tick(
      strike: state,
      asked: cast_state.TickAsked(
        ..tick_asked(go: 1, tick: 1),
        unit_id: 9,
        life: 0,
        what: cast_state.TellHeal(
          vital: effect_kind.Health,
          formula: damage.Formula(multiplier: 1.0, base: 50.0, parameters: []),
          passed_in: None,
        ),
      ),
      attacker: Attacker(
        ..strike_support.attacker(),
        players_in_sight: dict.from_list([#(9, ally)]),
      ),
      formulas: rating_support.formulas(),
      entropy: <<>>,
      now: at(ms: 1500),
    )
  let #(state, healed) =
    strike.player_answered(
      strike: state,
      answer: strike_tell.PlayerAnswered(
        key: Key(
          cast_id: 5,
          occasion: strike_tell.AtTick(
            effect_id: Spell4EffectsId(96_125),
            go: 1,
            tick: 1,
          ),
          unit_id: 9,
        ),
        outcome: strike_tell.HealsLanded(heals: []),
      ),
      now: at(ms: 1600),
    )
  assert went(effects: healed) == [] && ticked(effects: healed) == []
    as "the ally's heal tick has its answer but waits for the go before it, which the creature has not answered"
  let #(_, after) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: landed(),
      now_ms: 1700,
    )
  assert list.map(
      strike_support.only(effects: after, kinds: [
        strike_support.RoundClosed,
        strike_support.TickClosed,
      ]),
      strike_support.kind_of,
    )
    == [strike_support.RoundClosed, strike_support.TickClosed]
    as "the go closes first and the ally's heal tick after it"
}

pub fn a_tick_left_out_at_the_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    tick_begun(
      state: strike.new(),
      asked: tick_asked(go: 1, tick: 1),
      stats: attacker_support.fresh(),
      rolls: #(0, 0, 0),
      now_ms: 2000,
    )
  let #(state, due) = strike.timer_fired(strike: state, now: at(ms: 3000))
  assert ticked(effects: due) == [#(tick_asked(go: 1, tick: 1), None)]
    as "no answer by the 1 s deadline: the tick closes with its unit left out"
  let #(_, late) =
    answer(
      state:,
      key: tick_key(go: 1, tick: 1),
      outcome: landed(),
      now_ms: 3100,
    )
  assert late == [] as "a later answer finds no round and is dropped"
}

pub fn an_answer_after_the_deadline_that_broke_a_cast_logs_no_interrupt_test() -> Nil {
  use <- owned_test.run(5000)
  // Unit 10 is stunned by the go and the stun broke its charge, but its answer, which carries
  // the mark, arrives after the round's 1 s deadline: the go was written at the deadline with
  // the unit left out, and the answer is dropped.
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: stunning(
        asked: asked(cast_id: 5, phase: 0),
        units: [10],
        aim: AimsAtArea,
      ),
      now_ms: 1000,
    )
  let #(state, due) = strike.timer_fired(strike: state, now: at(ms: 2000))
  assert went(effects: due) == [#(5, 0, [])]
    as "the round closes at its deadline with the unit left out: no state to log (type 1) and no mark (type 19)"
  let marked =
    strike_tell.ControlLanded(
      ..crowd_control_support.kick_landed(ends_at_ms: 4166),
      interrupted: Some(strike_tell.Interrupted(spell4_id: Spell4Id(85_469))),
    )
  let #(_, late) =
    answer(
      state:,
      key: Key(cast_id: 5, occasion: strike_tell.AtGo(phase: 0), unit_id: 10),
      outcome: Landed(
        descriptions: [],
        controls: [marked],
        armor_removed: 0,
        gates_passed: [],
      ),
      now_ms: 2500,
    )
  assert went(effects: late) == [] && tells(effects: late) == []
    as "the late marked answer finds no round: nothing is written, so no line"
}

/// The ask of a tick of Nullifier's field Proxy (Spell4Effects 141450 in Spell4 58868) for
/// cast 5: tick `tick`, the go that armed it the first, the phase 0, the caster (unit 7) the
/// primary target and the cast started at the origin.
fn field_tick(tick tick: Int) -> cast_state.ProxyTickAsked {
  cast_state.ProxyTickAsked(
    cast_id: 5,
    spell4_id: Spell4Id(58_868),
    effect_id: Spell4EffectsId(141_450),
    phase: 0,
    primary_target: 7,
    started_at: strike_support.start_pose(),
    primary_pose: None,
    go: 1,
    tick:,
  )
}

/// Nullifier's field area from the fixture with `row` as its area row, `inside_by_go` as its
/// hit shapes and `anchor` as its anchor.
fn field_areas(
  anchor anchor: area.Anchor,
  row row: Option(area.Row),
  inside_by_go inside_by_go: List(Option(area.Inside)),
) -> spell_area.Areas {
  let assert Ok(nullifier) =
    spell_area.of_spell(
      areas: spell_tables.fixture_areas(),
      spell4_id: Spell4Id(58_868),
    )
    as "Nullifier's field is in the fixture's areas"
  dict.insert(
    spell_tables.fixture_areas(),
    58_868,
    spell_area.SpellArea(..nullifier, anchor:, row:, inside_by_go:),
  )
}

/// A circle of `max_range` metres around the centre that takes the first 10 units in
/// `order`.
fn circle(max_range max_range: Float, order order: area.Order) -> area.Row {
  area.Row(min_range: 0.0, max_range:, degrees: 360.0, target_count: 10, order:)
}

pub fn a_tick_of_a_field_selects_the_units_inside_its_box_and_range_around_the_pose_the_cast_started_at_test() -> Nil {
  use <- owned_test.run(60_000)
  // Nullifier's field 58868 (fixture): TelegraphDamage 2789 is a box 14 wide and 14 deep
  // placed 8 m ahead of the start pose (flags 0x1000, FixedAtCaster), so it covers z -15 to -1
  // and x -7 to 7, and Spell4AoeTargetConstraints 119 takes the nearest 10 within 20 m. The
  // cast started at the origin facing -z; the caster has since walked to (30, 0) and faces +z,
  // so a box that followed it would cover z 1 to 15 around x 30. A creature's hit radius is 3.
  let areas = spell_tables.fixture_areas()
  let attacker =
    strike.Attacker(
      ..strike_support.attacker(),
      pose: Pose(at: Point(x: 30.0, z: 0.0), yaw: 3.1415927),
    )
  let friendly =
    strike_support.creature_at(
      x: 0.0,
      z: -6.0,
      alive: True,
      attackable: Attackable(exile: False, dominion: True),
    )
  let dead =
    strike_support.creature_at(
      x: 0.0,
      z: -7.0,
      alive: False,
      attackable: Attackable(exile: True, dominion: True),
    )
  let selected = fn(placed: List(#(Int, Float, Float))) {
    strike.select_proxy_tick(
      asked: field_tick(tick: 1),
      attacker:,
      picture: dict.merge(
        dict.from_list(
          list.map(placed, fn(entry) {
            #(entry.0, foe_at(x: entry.1, z: entry.2))
          }),
        ),
        dict.from_list([#(25, friendly), #(26, dead)]),
      ),
      areas:,
      now_ms: 0,
    )
  }
  assert selected([
      #(21, 0.0, -8.0),
      #(22, 0.0, 10.0),
      #(23, 0.0, -30.0),
      #(24, 30.0, 8.0),
    ])
    == [21]
    as "only the foe inside the box 8 m ahead of the start is selected: 22 is within 20 m of the start but behind it, 23 is beyond 20 m, 24 stands where a box that followed the caster would be, 25 is friendly and 26 dead"
  assert selected([
      #(21, 0.0, 10.0),
      #(22, 0.0, 10.0),
      #(27, 3.0, -5.0),
      #(24, 30.0, 8.0),
    ])
    == [27]
    as "a later tick selects whoever is inside then: 21 walked out of the box and 27 walked in (texts 574032 and 306769, foes inside the field every second)"
}

pub fn a_tick_of_a_fixed_at_target_area_on_another_unit_stays_where_the_unit_stood_at_the_go_and_a_following_one_follows_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Nullifier's field planted with a circle of 5 m anchored on the target, fixed and
  // following. The anchor's doc (`area.FixedAtTarget`): the hit stays where the target stood
  // when the cast began, whatever it does. Unit 21 is the cast's primary target, an ally,
  // which stood at (0, -20) at the go and now stands at (20, -20); foe 31 stands at its old
  // place, foe 32 at its new one.
  let areas_anchored = fn(anchor) {
    field_areas(
      anchor:,
      row: Some(circle(max_range: 5.0, order: area.Nearest)),
      inside_by_go: [Some(area.InsideRow)],
    )
  }
  let picture =
    dict.from_list([
      #(
        21,
        strike_support.creature_at(
          x: 20.0,
          z: -20.0,
          alive: True,
          attackable: Attackable(exile: False, dominion: True),
        ),
      ),
      #(31, foe_at(x: 0.0, z: -20.0)),
      #(32, foe_at(x: 20.0, z: -21.0)),
    ])
  let stood_at_the_go = Some(Pose(at: Point(x: 0.0, z: -20.0), yaw: 0.0))
  list.each(
    [
      #(
        area.FixedAtTarget,
        stood_at_the_go,
        [31],
        "a fixed area stays at the pose the target stood in at the go, so it holds the foe at the old place and not the one at the new place",
      ),
      #(
        area.FollowsTarget,
        stood_at_the_go,
        [32],
        "a following area is centred on the target where the picture shows it now",
      ),
      #(
        area.FixedAtTarget,
        None,
        [32],
        "a target the picture did not show at the go has no carried pose, so a fixed area reads the picture now",
      ),
    ],
    fn(row) {
      let #(anchor, primary_pose, expected, reason) = row
      assert strike.select_proxy_tick(
          asked: cast_state.ProxyTickAsked(
            ..field_tick(tick: 1),
            primary_target: 21,
            primary_pose:,
          ),
          attacker: strike_support.attacker(),
          picture:,
          areas: areas_anchored(anchor),
          now_ms: 0,
        )
        == expected
        as reason
    },
  )
  // Facing. Unit 21 stands at (0, -20) facing -x (a quarter turn, `area.origin_of`: ahead is
  // (-sin yaw, -cos yaw)): a box 2 by 2 placed 6 m ahead of it is centred on (-6, -20), and one
  // that read it facing -z would
  // be centred on (0, -26), where foe 42 stands. A go and a tick read the unit's facing the
  // same way, the picture's (`shown.pose_of`), and an area fixed at its target keeps the
  // facing it carries in the row.
  let quarter_turn = 1.5707964
  let ahead =
    area.InsideShapes(placements: [
      area.Placement(
        shape: area.Box(width: 2.0, length: 2.0),
        ahead: 6.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ])
  let facing_picture = fn(unit_21_at: #(Float, Float), faced_yaw: Option(Float)) {
    dict.from_list([
      #(
        21,
        strike_support.creature_facing(
          x: unit_21_at.0,
          z: unit_21_at.1,
          alive: True,
          attackable: Attackable(exile: False, dominion: True),
          faced_yaw:,
        ),
      ),
      #(41, foe_at(x: -6.0, z: -20.0)),
      #(42, foe_at(x: 0.0, z: -26.0)),
    ])
  }
  let boxed = fn(anchor) {
    field_areas(
      anchor:,
      row: Some(circle(max_range: 20.0, order: area.Nearest)),
      inside_by_go: [Some(ahead)],
    )
  }
  let ticked = fn(anchor, picture, primary_pose) {
    strike.select_proxy_tick(
      asked: cast_state.ProxyTickAsked(
        ..field_tick(tick: 1),
        primary_target: 21,
        primary_pose:,
      ),
      attacker: strike_support.attacker(),
      picture:,
      areas: boxed(anchor),
      now_ms: 0,
    )
  }
  assert ticked(
      area.FollowsTarget,
      facing_picture(#(0.0, -20.0), Some(quarter_turn)),
      None,
    )
    == [41]
    as "a following area at a tick is centred on the unit's facing in the picture, not on yaw 0"
  assert ticked(
      area.FixedAtTarget,
      facing_picture(#(20.0, -20.0), None),
      Some(Pose(at: Point(x: 0.0, z: -20.0), yaw: quarter_turn)),
    )
    == [41]
    as "a fixed area keeps the facing the unit had at the go, which the row carries with its pose, whichever way the unit faces now"
  // The same at a go: Kick's area (58591) with the box as its hit shape, the anchor changed,
  // struck at unit 21 as the cast's primary target.
  let go_selected = fn(anchor) {
    strike.select(
      asked: GoAsked(..asked(cast_id: 5, phase: 0), primary_target: 21),
      attacker: strike_support.attacker(),
      picture: facing_picture(#(0.0, -20.0), Some(quarter_turn)),
      areas: kick_areas_changed(change: fn(kick) {
        spell_area.SpellArea(
          ..kick,
          anchor:,
          row: Some(circle(max_range: 20.0, order: area.Nearest)),
          inside_by_go: [Some(ahead)],
        )
      }),
      now_ms: 0,
    ).area
  }
  assert go_selected(area.FollowsTarget) == [41]
    as "a go on another unit is centred on that unit's facing in the picture, not on yaw 0"
  assert go_selected(area.FixedAtTarget) == [41]
    as "and so is a go of an area fixed at its target"
}

pub fn a_random_rows_tick_orders_by_the_cast_id_and_the_tick_so_ticks_differ_and_one_ask_repeats_test() -> Nil {
  use <- owned_test.run(60_000)
  // Nullifier's field planted with a Random row of 10 within 30 m over a circle, and 20 foes
  // inside it. Random is the server's order, seeded by the cast and the tick (`area.mix`, a
  // guess: the client names Random, `Spell4AoeTargetConstraints.targetSelection` 3, and
  // ranks nothing).
  let areas =
    field_areas(
      anchor: area.FixedAtCaster,
      row: Some(circle(max_range: 30.0, order: area.Random)),
      inside_by_go: [Some(area.InsideRow)],
    )
  let picture =
    dict.from_list(
      list.map(numbers(from: 21, to: 40), fn(unit_id) {
        #(unit_id, foe_at(x: 0.0, z: int.to_float(unit_id) *. -0.5))
      }),
    )
  let selected = fn(cast_id, tick) {
    strike.select_proxy_tick(
      asked: cast_state.ProxyTickAsked(..field_tick(tick:), cast_id:),
      attacker: strike_support.attacker(),
      picture:,
      areas:,
      now_ms: 0,
    )
  }
  assert list.length(selected(5, 1)) == 10
    as "the row takes 10 of the 20 foes inside"
  assert selected(5, 1) == selected(5, 1)
    as "the same ask picks the same units in the same order"
  assert list.length(
      list.unique(
        list.map(numbers(from: 1, to: 12), fn(tick) { selected(5, tick) }),
      ),
    )
    >= 2
    as "ticks 1 to 12 of one cast do not all pick the same units"
  assert selected(5, 2) != selected(6, 1)
    as "cast 5's tick 2 and cast 6's tick 1 do not share a seed (a plain sum of cast id and tick would give both 7)"
  assert selected(5, 1) != selected(6, 1)
    as "a second cast at the same tick picks differently"
}

pub fn a_tick_selects_nobody_without_an_area_row_a_hit_row_that_names_no_go_or_a_primary_target_the_picture_lost_test() -> Nil {
  use <- owned_test.run(60_000)
  let picture = dict.from_list([#(21, foe_at(x: 0.0, z: -5.0))])
  let near = circle(max_range: 20.0, order: area.Nearest)
  list.each(
    [
      #(
        field_areas(anchor: area.FixedAtCaster, row: Some(near), inside_by_go: [
          Some(area.InsideRow),
        ]),
        field_tick(tick: 1),
        [21],
        "the control: a circle with an area row finds the foe 5 m away",
      ),
      #(
        field_areas(anchor: area.FixedAtCaster, row: None, inside_by_go: [
          Some(area.InsideRow),
        ]),
        field_tick(tick: 1),
        [],
        "a spell with no area row finds nobody (the order is by health, which a tick does not read)",
      ),
      #(
        field_areas(anchor: area.FixedAtCaster, row: Some(near), inside_by_go: [
          None,
        ]),
        field_tick(tick: 1),
        [],
        "hit rows exist and none names the ask's phase, so nobody is inside (spell_area.inside)",
      ),
      #(
        field_areas(anchor: area.FixedAtCaster, row: Some(near), inside_by_go: [
          Some(area.InsideRow),
        ]),
        cast_state.ProxyTickAsked(..field_tick(tick: 1), primary_target: 99),
        [],
        "a primary target that is not the caster and not in the picture gives no centre",
      ),
    ],
    fn(row) {
      let #(areas, asked, expected, reason) = row
      assert strike.select_proxy_tick(
          asked:,
          attacker: strike_support.attacker(),
          picture:,
          areas:,
          now_ms: 0,
        )
        == expected
        as reason
    },
  )
}

/// The integers from `from` to `to`, both included.
fn numbers(from from: Int, to to: Int) -> List(Int) {
  list.reverse(
    int.range(from:, to: to + 1, with: [], run: fn(all, number) {
      [number, ..all]
    }),
  )
}
