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

import area_tables
import cast_support as support
import class_resource_support
import client_tables
import genesis_prime/client_connection
import genesis_prime/game/area.{Point, Pose}
import genesis_prime/game/cast.{type GoAsked, GoAsked}
import genesis_prime/game/class_resource.{Resource}
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/shown.{Exile, ShownCreature, ShownPlayer}
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
import genesis_prime/message/crowd_control_state
import genesis_prime/step.{ConnectionId, Now}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/world_map/creature_life.{type Attackable, Attackable}
import genesis_prime/world_map/creature_path
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import map_support
import owned_test
import place_support
import rating_support
import spell_tables
import unitest

fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

fn attacker() -> Attacker {
  Attacker(
    unit_id: 7,
    connection: ConnectionId(2),
    pose: Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    move_seq: 1,
    stay: map_support.stay(count: 1),
    faction: Exile,
    stats: damage.Attacker(level: 1, assault_rating: 0.0, support_rating: 0.0),
  )
}

fn damage_effect() -> spell_area.DamageEffect {
  DamageEffect(
    effect_id: Spell4EffectsId(1),
    damage_type: 1,
    delay_ms: 166,
    phase_flags: -1,
    aim: AimsAtArea,
    formula: damage.Formula(multiplier: 1.0, base: 0, parameters: []),
    threat_multiplier: 1.0,
    tag: spend.always,
  )
}

fn asked(cast_id cast_id: Int, phase phase: Int) -> GoAsked {
  GoAsked(
    cast_id:,
    phase:,
    spell4_id: Spell4Id(58_591),
    primary_target: 7,
    spent: None,
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
    blows: case damaging {
      True -> [damage_effect()]
      False -> []
    },
    controls: [],
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
    attacker: attacker(),
    formulas: rating_support.formulas(),
    entropy: entropy(rolls: list.map(selection.units, fn(_) { #(0, 0, 0) })),
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
  Landed(descriptions: [], controls: [])
}

fn tells(effects effects: List(Effect)) -> List(strike.Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      strike.TellStrike(..) -> True
      strike.StartTimer(..)
      | strike.CancelTimer(..)
      | strike.Went(..)
      | strike.Released(..)
      | strike.Log(..) -> False
    }
  })
}

/// The units each round that closed in these effects named, in order, by cast
/// and phase.
fn went(effects effects: List(Effect)) -> List(#(Int, Int, List(cast.Struck))) {
  list.filter_map(effects, fn(effect) {
    case effect {
      strike.Went(asked:, struck:) -> Ok(#(asked.cast_id, asked.phase, struck))
      strike.TellStrike(..)
      | strike.StartTimer(..)
      | strike.CancelTimer(..)
      | strike.Released(..)
      | strike.Log(..) -> Error(Nil)
    }
  })
}

fn timers(effects effects: List(Effect)) -> List(strike.Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      strike.StartTimer(..) | strike.CancelTimer(..) -> True
      strike.TellStrike(..)
      | strike.Went(..)
      | strike.Released(..)
      | strike.Log(..) -> False
    }
  })
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
      attacker: attacker(),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [
        #(0, 2_147_483_648, 0),
        #(1_073_741_824, 3_221_225_472, 2_147_483_648),
        #(0, 0, 0),
      ]),
      now: at(ms: 1000),
    )
  let told =
    list.filter_map(tells(effects:), fn(effect) {
      case effect {
        strike.TellStrike(
          unit_id:,
          life:,
          tell: strike_tell.Strike(
            key:,
            from:,
            striker: strike_tell.PlayerStriker(rolls:, ..),
            ..,
          ),
        ) -> Ok(#(unit_id, life, key, from, rolls))
        strike.TellStrike(
          tell: strike_tell.Strike(striker: strike_tell.CreatureStriker, ..),
          ..,
        ) -> panic as "a player's strike carries a player striker"
        strike.StartTimer(..)
        | strike.CancelTimer(..)
        | strike.Went(..)
        | strike.Released(..)
        | strike.Log(..) -> Error(Nil)
      }
    })
  assert told
    == [
      #(
        10,
        3,
        Key(cast_id: 5, phase: 0, unit_id: 10),
        step.Connection(ConnectionId(2)),
        Rolls(crit: 0.0, deflect: 0.5, glance: 0.0),
      ),
      #(
        11,
        3,
        Key(cast_id: 5, phase: 0, unit_id: 11),
        step.Connection(ConnectionId(2)),
        Rolls(crit: 0.25, deflect: 0.75, glance: 0.5),
      ),
      #(
        12,
        3,
        Key(cast_id: 5, phase: 0, unit_id: 12),
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
  let novice =
    damage.Attacker(level: 1, assault_rating: 203.0625, support_rating: 55.6875)
  let paralytic_surge =
    DamageEffect(
      effect_id: Spell4EffectsId(96_125),
      damage_type: 2,
      delay_ms: 0,
      phase_flags: -1,
      aim: AimsAtArea,
      formula: damage.Formula(multiplier: 1.0, base: 0, parameters: [
        damage.Parameter(kind: 12, value: 0.0935),
        damage.Parameter(kind: 13, value: 0.0935),
        damage.Parameter(kind: 10, value: 8.14),
      ]),
      threat_multiplier: 1.0,
      tag: spend.always,
    )
  let telekinetic_strike =
    DamageEffect(
      effect_id: Spell4EffectsId(62_159),
      damage_type: 3,
      delay_ms: 0,
      phase_flags: -1,
      aim: AimsAtArea,
      formula: damage.Formula(multiplier: 1.0, base: 0, parameters: [
        damage.Parameter(kind: 12, value: 0.336),
        damage.Parameter(kind: 10, value: 18.0),
      ]),
      threat_multiplier: 2.0,
      tag: spend.always,
    )
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: Selection(
        asked: asked(cast_id: 5, phase: 0),
        units: [strike.Aimed(unit_id: 10, life: 3)],
        blows: [paralytic_surge, telekinetic_strike],
        controls: [],
      ),
      attacker: Attacker(..attacker(), stats: novice),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [#(0, 0, 0)]),
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
          damage: 14,
          delay_ms: 0,
          threat_multiplier: 1.0,
        ),
        Blow(
          spell4_effects_id: 62_159,
          damage_type: 3,
          damage: 35,
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

pub fn answers_out_of_order_are_listed_in_selection_order_when_the_round_closes_test() -> Nil {
  use <- owned_test.run(5000)
  let go = asked(cast_id: 5, phase: 0)
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection(asked: go, units: [10, 11, 12], damaging: True),
      now_ms: 1000,
    )
  let key = fn(unit_id) { Key(cast_id: 5, phase: 0, unit_id:) }
  let #(state, first) =
    answer(state:, key: key(12), outcome: landed(), now_ms: 1100)
  let #(state, second) =
    answer(state:, key: key(10), outcome: Deflected, now_ms: 1200)
  assert went(effects: list.append(first, second)) == []
    as "the round waits for the unit that has not answered"
  let #(_, third) =
    answer(state:, key: key(11), outcome: landed(), now_ms: 1300)
  assert went(effects: third)
    == [
      #(5, 0, [
        cast.Deflected(unit_id: 10),
        cast.Hit(unit_id: 11, descriptions: [], controls: []),
        cast.Hit(unit_id: 12, descriptions: [], controls: []),
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
  let key = fn(unit_id) { Key(cast_id: 5, phase: 0, unit_id:) }
  let #(state, _) =
    answer(state:, key: key(10), outcome: Refused(why: Dead), now_ms: 1100)
  let #(state, _) =
    answer(state:, key: key(11), outcome: landed(), now_ms: 1200)
  let #(_, closing) =
    answer(state:, key: key(12), outcome: landed(), now_ms: 1300)
  assert went(effects: closing)
    == [
      #(5, 0, [
        cast.Hit(unit_id: 11, descriptions: [], controls: []),
        cast.Hit(unit_id: 12, descriptions: [], controls: []),
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
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  let #(_, early) = strike.timer_fired(strike: state, now: at(ms: 1999))
  assert went(effects: early) == []
    as "the deadline is 1 s after the go: nothing closes at 1999 ms"
  let #(_, due) = strike.timer_fired(strike: state, now: at(ms: 2000))
  assert went(effects: due)
    == [#(5, 0, [cast.Hit(unit_id: 10, descriptions: [], controls: [])])]
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
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
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
      key: Key(cast_id: 5, phase: 1, unit_id: 11),
      outcome: landed(),
      now_ms: 1300,
    )
  assert went(effects: later) == []
    as "phase 1 has every answer but waits for phase 0, which Stagger's gos are written in order"
  let #(_, earlier) =
    answer(
      state:,
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
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
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
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
    == [#(5, 0, [cast.Hit(unit_id: 10, descriptions: [], controls: [])])]
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
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
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
  let death = client_connection.Died
  let state = strike.hold(strike: state, unit_id: 10, news: death)
  let #(state, first) =
    answer(
      state:,
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  assert first == []
    as "the answer of unit 10 leaves the round open for unit 11: nothing is written, nothing released"
  let #(state, closing) =
    answer(
      state:,
      key: Key(cast_id: 5, phase: 0, unit_id: 11),
      outcome: landed(),
      now_ms: 1200,
    )
  assert list.map(closing, fn(effect) {
      case effect {
        strike.Went(..) -> "went"
        strike.Released(unit_id:, ..) -> "released " <> unit_label(unit_id)
        strike.CancelTimer(..) -> "cancel"
        strike.TellStrike(..) | strike.StartTimer(..) | strike.Log(..) ->
          "other"
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
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
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
    strike.Released(..) -> "released"
    strike.CancelTimer(..) -> "cancel"
    strike.StartTimer(..) -> "start"
    strike.TellStrike(..) -> "tell"
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
      strike: strike.hold(
        strike: state,
        unit_id: 10,
        news: client_connection.Died,
      ),
      unit_id: 11,
      news: client_connection.Health(health: 5, dead: False),
    )
  let state = strike.forget(strike: state, unit_id: 10)
  let #(state, _) =
    answer(
      state:,
      key: Key(cast_id: 5, phase: 0, unit_id: 10),
      outcome: landed(),
      now_ms: 1100,
    )
  let #(_, closing) =
    answer(
      state:,
      key: Key(cast_id: 5, phase: 0, unit_id: 11),
      outcome: landed(),
      now_ms: 1200,
    )
  assert list.filter_map(closing, fn(effect) {
      case effect {
        strike.Released(unit_id:, ..) -> Ok(unit_id)
        strike.TellStrike(..)
        | strike.StartTimer(..)
        | strike.CancelTimer(..)
        | strike.Went(..)
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

fn creature_at(
  x x: Float,
  z z: Float,
  alive alive: Bool,
  attackable attackable: Attackable,
) -> shown.Shown {
  ShownCreature(
    path: creature_path.Standing(at: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x:,
      y: 0.0,
      z:,
    )),
    life: 4,
    alive:,
    hit_radius: 3.0,
    attackable:,
  )
}

fn picture() -> shown.Picture {
  let both = Attackable(exile: True, dominion: True)
  dict.from_list([
    #(21, creature_at(x: 0.0, z: -3.0, alive: True, attackable: both)),
    #(22, creature_at(x: 0.0, z: -5.0, alive: True, attackable: both)),
    #(23, creature_at(x: 0.0, z: -6.5, alive: True, attackable: both)),
    #(24, creature_at(x: 0.0, z: 4.0, alive: True, attackable: both)),
    #(25, creature_at(x: 0.0, z: -8.0, alive: True, attackable: both)),
    #(26, creature_at(x: 0.0, z: -4.0, alive: False, attackable: both)),
    #(
      27,
      creature_at(
        x: 0.0,
        z: -4.0,
        alive: True,
        attackable: Attackable(exile: False, dominion: True),
      ),
    ),
    #(28, ShownPlayer),
    #(20, creature_at(x: 40.0, z: 40.0, alive: True, attackable: both)),
  ])
}

pub fn the_caster_selects_the_foes_inside_kicks_cone_nearest_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(areas) = area_tables.built(kick: area_tables.kick())
    as "the planted Kick builds"
  let chosen =
    strike.select(
      asked: asked(cast_id: 5, phase: 0),
      attacker: attacker(),
      picture: picture(),
      areas:,
      now_ms: 0,
    )
  assert list.map(chosen.units, fn(aimed) { aimed.unit_id }) == [21, 22, 23]
    as "Kick's cone is 1 to 7 m over 100 degrees ahead: units 21, 22 and 23; 24 is behind, 25 past 7 m, 26 is dead, 27 is Friendly to Exiles and 28 is a player (Spell4.58591.area)"
  assert list.length(chosen.blows) == 1
    as "Kick's one damage effect, aimed at the area"
}

pub fn a_damage_aimed_at_the_cast_target_strikes_the_primary_target_alone_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(areas) =
    area_tables.built(
      kick: area_tables.Kick(..area_tables.kick(), effect_target_flags: 2),
    )
    as "the planted Kick builds"
  let chosen =
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(58_591),
        primary_target: 20,
        spent: None,
      ),
      attacker: attacker(),
      picture: picture(),
      areas:,
      now_ms: 0,
    )
  assert chosen.units == [Aimed(unit_id: 20, life: 4)]
    as "Spell4Effects.targetFlags 2 strikes the cast's own target (38781 on each struck unit), with that creature's life"
}

pub fn a_spell_the_areas_do_not_hold_strikes_nobody_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(areas) = area_tables.built(kick: area_tables.kick())
    as "the planted Kick builds"
  let chosen =
    strike.select(
      asked: GoAsked(
        cast_id: 5,
        phase: 0,
        spell4_id: Spell4Id(1),
        primary_target: 7,
        spent: None,
      ),
      attacker: attacker(),
      picture: picture(),
      areas:,
      now_ms: 0,
    )
  assert chosen.units == [] && chosen.blows == []
}

/// A foe at (x, z), alive and attackable by an Exile.
fn foe_at(x x: Float, z z: Float) -> shown.Shown {
  creature_at(
    x:,
    z:,
    alive: True,
    attackable: Attackable(exile: True, dominion: True),
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
      ),
      attacker: attacker(),
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
        ),
        attacker: attacker(),
        picture: close_by,
        areas:,
        now_ms: 0,
      )
    assert list.map(chosen.units, fn(aimed) { aimed.unit_id })
      == [21, 22, 23, 24, 25]
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
      ),
      attacker: attacker(),
      picture: close_by,
      areas:,
      now_ms: 0,
    )
  assert child.units == [Aimed(unit_id: 22, life: 4)]
    && list.length(child.blows) == 1
    as "38781 damages its own target, the unit it was started on (Spell4Effects 83829: targetFlags 2)"
}

// ---- a spell with an innate cost EMM id strikes with the effects its n chooses ----

/// The areas of the planted rows with Mind Burst's spend as the client's rows hold it
/// (`spell_tables.rows_with_mind_burst_spend`).
fn mind_burst_areas() -> spell_area.Areas {
  let assert Ok(areas) =
    spell_tables.with_loaded_deriving(
      rows: spell_tables.rows_with_mind_burst_spend(
        emm_id: 4,
        cost: #(6, 1),
        damage: spell_tables.mind_burst_damage,
      ),
      derivations: [spell_plan.derivation()],
      body: fn(tables) { spell_area.build(tables:) },
    )
    as "the planted Mind Burst builds its areas"
  areas
}

/// The go the cast rule asks for when an Esper holding `points` Psi Points presses
/// Mind Burst (bag index 2).
fn mind_burst_go(points points: Int) -> GoAsked {
  let assert Ok(mind_burst) =
    spell_plan.in_plans(
      plans: spell_tables.plans_with_mind_burst_spend(),
      base: id.Spell4BaseId(19_019),
    )
    as "the planted Esper holds Mind Burst"
  let resources =
    class_resource.new(
      resource: Resource(
        ..class_resource_support.resource_of(3),
        start: int.to_float(points),
      ),
    )
  let #(_, effects) =
    support.pressed_raw_in(
      plans: support.with_spells(plans: support.plans(), spells: [mind_burst]),
      state: cast.new(),
      caster: support.caster_holding(resources:),
      bag_index: 2,
      target: 0,
      at: 1000,
    )
  let assert [asked] =
    list.filter_map(effects, fn(effect) {
      case effect {
        cast.Strike(asked:) -> Ok(asked)
        cast.Send(..)
        | cast.Tell(..)
        | cast.StartTimer(..)
        | cast.CancelTimer(..)
        | cast.Log(..)
        | cast.Pay(..)
        | cast.Gain(..) -> Error(Nil)
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
        attacker: attacker(),
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
      attacker: attacker(),
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
      attacker: attacker(),
      formulas: rating_support.formulas(),
      entropy: entropy(rolls: [#(0, 0, 0)]),
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
      attacker: attacker(),
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
    ),
    tag: spend.always,
  )
}

fn told_stun(instance_id instance_id: Int) -> strike_tell.ControlTell {
  strike_tell.ControlTell(
    effect_id: 100_836,
    state: crowd_control_state.Stun,
    instance_id:,
    delay_ms: 0,
    duration_ms: 3250,
    armor_removed: 1,
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
  assert first.controls == [told_stun(instance_id: 28_673)]
    && second.controls == [told_stun(instance_id: 28_674)]
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
  assert third.controls == [told_stun(instance_id: 28_675)]
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
        now: at(ms: 1000),
      )
    let assert [strike.TellStrike(tell:, ..)] = tells(effects:)
    tell.controls
  }
  let first = told_by(attacker())
  let second = told_by(Attacker(..attacker(), unit_id: 8))
  assert first == [told_stun(instance_id: 28_673)]
    && second == [told_stun(instance_id: 32_769)]
    as "7 x 4096 + 1 and 8 x 4096 + 1: no id is shared, and none is 0"
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
  assert tell.controls == [told_stun(instance_id: 28_673)]
  let landed =
    strike_tell.ControlLanded(
      tell: told_stun(instance_id: 28_673),
      ends_at_ms: 4250,
    )
  let #(_, closed) =
    answer(
      state:,
      key: Key(cast_id: 5, phase: 0, unit_id: 11),
      outcome: Landed(descriptions: [], controls: [landed]),
      now_ms: 1050,
    )
  assert went(effects: closed)
    == [
      #(5, 0, [
        cast.Hit(unit_id: 10, descriptions: [], controls: []),
        cast.Hit(unit_id: 11, descriptions: [], controls: [landed]),
      ]),
    ]
    as "the go names the states that landed, as the creature answered them"
}
