//// A player's strikes (`genesis_prime/game/strike`), run as the pure rule it is on
//// a driven clock: a go's round, the answers, the deadline and the timer. Expected
//// values come from these places.
//// - The rule's doc comment: a strike is told to each selected unit in selection
////   order with the caster's rolls (8 seed bytes for each unit, 4 for the critical
////   hit roll and 4 for the deflect roll, each a fraction of 2^32); a round closes
////   when each answer is in or its 1 s deadline has passed; the go lists the units in
////   selection order; a refusal or a silent creature is left out and the count is not
////   refilled; an answer for a closed round is dropped; rounds close in phase order;
////   one strike timer is set to the earliest open deadline.
//// - Design 274 section 2: the deadline is 1 second.
//// - The cast and phase of Stagger's second go: `Spell4.38791.area`.

import genesis_prime/game/area.{Point, Pose}
import genesis_prime/game/cast.{type GoAsked, GoAsked}
import genesis_prime/game/damage
import genesis_prime/game/hit.{Rolls}
import genesis_prime/game/rating.{Formula, Formulas}
import genesis_prime/game/shown.{Exile}
import genesis_prime/game/spell_area.{AimsAtArea, DamageEffect}
import genesis_prime/game/strike.{
  type Attacker, type Effect, type Selection, type State, Aimed, Attacker,
  Selection,
}
import genesis_prime/game/strike_tell.{
  Answered, Dead, Deflected, Key, Landed, Refused,
}
import genesis_prime/step.{ConnectionId, Now}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/list
import owned_test

fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

fn attacker() -> Attacker {
  Attacker(
    unit_id: 7,
    connection: ConnectionId(2),
    pose: Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0),
    faction: Exile,
    stats: damage.Attacker(level: 1, assault_rating: 0.0, support_rating: 0.0),
  )
}

/// GameFormula rows 1231, 1232 and 1235 as the fact file records them
/// (`0x140463700`, `0x140463e80`, `0x140463340`).
fn formulas() -> rating.Formulas {
  Formulas(
    crit_chance: Formula(
      f0: 50.0,
      f01: 0.0025,
      f02: 30.0,
      f03: 7000.0,
      int0: 0,
      int01: 100,
    ),
    crit_severity: Formula(
      f0: 50.0,
      f01: 0.01,
      f02: 250.0,
      f03: 5500.0,
      int0: 0,
      int01: 300,
    ),
    deflect_chance: Formula(
      f0: 50.0,
      f01: 0.0015,
      f02: 30.0,
      f03: 7000.0,
      int0: 0,
      int01: 100,
    ),
    player_base_crit_chance: 0.05,
    player_base_crit_severity: 1.5,
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
  )
}

fn asked(cast_id cast_id: Int, phase phase: Int) -> GoAsked {
  GoAsked(cast_id:, phase:, spell4_id: Spell4Id(58_591), primary_target: 7)
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
  )
}

/// 8 seed bytes for each unit: the critical hit roll's 4 bytes, then the deflect
/// roll's, from the numbers of each (a number n is the fraction n / 2^32).
fn entropy(rolls rolls: List(#(Int, Int))) -> BitArray {
  list.fold(rolls, <<>>, fn(bytes, pair) {
    <<bytes:bits, pair.0:size(32), pair.1:size(32)>>
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
    formulas: formulas(),
    entropy: entropy(rolls: list.map(selection.units, fn(_) { #(0, 0) })),
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
  Landed(descriptions: [])
}

fn tells(effects effects: List(Effect)) -> List(strike.Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      strike.TellStrike(..) -> True
      strike.StartTimer(..)
      | strike.CancelTimer(..)
      | strike.Went(..)
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
      | strike.Log(..) -> Error(Nil)
    }
  })
}

fn timers(effects effects: List(Effect)) -> List(strike.Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      strike.StartTimer(..) | strike.CancelTimer(..) -> True
      strike.TellStrike(..) | strike.Went(..) | strike.Log(..) -> False
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
      formulas: formulas(),
      entropy: entropy(rolls: [
        #(0, 2_147_483_648),
        #(1_073_741_824, 3_221_225_472),
        #(0, 0),
      ]),
      now: at(ms: 1000),
    )
  let told =
    list.filter_map(tells(effects:), fn(effect) {
      case effect {
        strike.TellStrike(unit_id:, life:, tell:) ->
          Ok(#(unit_id, life, tell.key, tell.from, tell.rolls))
        strike.StartTimer(..)
        | strike.CancelTimer(..)
        | strike.Went(..)
        | strike.Log(..) -> Error(Nil)
      }
    })
  assert told
    == [
      #(
        10,
        3,
        Key(cast_id: 5, phase: 0, unit_id: 10),
        ConnectionId(2),
        Rolls(crit: 0.0, deflect: 0.5),
      ),
      #(
        11,
        3,
        Key(cast_id: 5, phase: 0, unit_id: 11),
        ConnectionId(2),
        Rolls(crit: 0.25, deflect: 0.75),
      ),
      #(
        12,
        3,
        Key(cast_id: 5, phase: 0, unit_id: 12),
        ConnectionId(2),
        Rolls(crit: 0.0, deflect: 0.0),
      ),
    ]
    as "one strike for each selected unit in selection order, each with its own 8 bytes of the caster's seed as two fractions of 2^32, answered to the caster's connection"
  assert timers(effects:)
    == [strike.StartTimer(timer: strike.strike_timer, after_ms: 1000)]
    as "one strike timer for the round's deadline, 1 s after the go"
  assert went(effects:) == [] as "the go is written when its round closes"
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
        cast.Hit(unit_id: 11, descriptions: []),
        cast.Hit(unit_id: 12, descriptions: []),
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
        cast.Hit(unit_id: 11, descriptions: []),
        cast.Hit(unit_id: 12, descriptions: []),
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
    == [#(5, 0, [cast.Hit(unit_id: 10, descriptions: [])])]
    as "the creature that never answered is left out at its round's deadline"
  assert timers(effects: due) == []
    as "the timer that fired is no longer running and no round is open, so none is set or cancelled"
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
    as "the timer already waits for the earlier deadline, 2000 ms"
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
  assert went(effects:) == [#(5, 0, [cast.Hit(unit_id: 10, descriptions: [])])]
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
