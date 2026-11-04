//// A player's strikes, a feature of the game connection's rule as the cast rule
//// is: when a go asks for its targets, which units it strikes, the tell each one is
//// sent with the caster's rolls, the answers that come back and the round that
//// closes when each is in or its deadline has passed. The creature that owns a
//// struck unit decides what the strike does to it (genesis_prime/world_map/creature_life);
//// this rule decides who is struck and when the go is written.
////
//// ```
//// cast rule                      this rule (the caster's connection)                       creature Ci
//// go timer ─▶ Effect Strike(GoAsked k, phase, spell, primary)
////   select(asked, attacker, picture, areas) ─▶ Selection: the units, nearest first
////   the connection draws 12 bytes of its seed for each unit
////   begin: a round for (k, phase), its deadline now + 1 s
////     for each unit in selection order, the spell having damage:
////       TellStrike(Ci, Strike(key, from, offence, rolls)) ─────────────────────────────▶ hit rule
////     StartTimer(strike timer) to the earliest open deadline, when it is not set
////   ◀──────────────────────────── Answered(key, Landed | Deflected | Refused) ◀─────────┘
////   answered: the unit's place in the round is filled
////   the round closes: all answered, or the deadline passed, and every earlier round of k closed
////     Went(asked, struck) ─▶ the connection calls cast.went(k, phase, struck)
////     Released(unit, news) for the health news held for the round's units
//// ```
////
//// - **Selection** reads the picture of the units the client shows
////   (genesis_prime/game/shown) and the spell's area (genesis_prime/game/spell_area): the
////   phase's centre is the caster's place and facing, or, for a child cast on a struck
////   unit (Crush's 42297), that unit's shown place; the primary target is added for an
////   effect aimed at it, and a unit is struck once for a go. A phase that selects no
////   unit has an empty round, which waits behind the cast's earlier rounds like any.
//// - **One round for each go.** The key of a strike is (cast, phase, unit). A round
////   holds a place for each selected unit, filled in the order of the selection
////   whatever order the answers arrive in; the go lists them in that order.
//// - **A selected creature that refuses** (it died after the picture was taken) or
////   never answers is left out of the go, and the count is not refilled from the
////   candidates that were not selected.
//// - **Rounds of one cast close in phase order.** A round waits for every earlier round
////   of its cast, empty ones included, so a later phase is never written first (Stagger's
////   gos).
//// - **The deadline** is 1 second for each round. One strike timer for the connection
////   is set to the earliest open deadline and set again only after it fired or the round
////   it waited for closed: the shell refuses to start a timer that is running.
//// - **An answer for a round that is closed** is dropped, and a creature's 0x937 shows
////   its health with no number: the client never saw the hit.
//// - **The caster's 0x801 while a round is open** ends the cast; the round closes as
////   always and `cast.went` finds no live cast, so nothing is written and the hits stand.
//// - **The caster's rolls** come from its seeded random, 12 bytes for each selected unit,
////   so a recording replays them and the creature keeps no random state.
//// - **A creature's health news for a unit of an open round** is held until that round's
////   go is written, so the caster's client shows the number before the death or the
////   health bar it caused: a creature sends its answer before its news, one sender in
////   one order. Another watcher's connection is told the news and the cast's 0x7f4 by two
////   senders, which no order holds (a gap, which the live sitting checks).

import genesis_prime/client_connection.{type News}
import genesis_prime/game/area.{type Pose, Point, Pose}
import genesis_prime/game/cast.{type GoAsked, type Struck}
import genesis_prime/game/damage
import genesis_prime/game/hit
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/shown.{type Picture, type PlayerFaction}
import genesis_prime/game/spell_area.{type Areas}
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell.{type Answered, type Tell}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, TimerId,
}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The one strike timer of a connection: the connection's own timers are below the
/// cast rule's, which start at 1000 (genesis_prime/game/cast `first_timer`).
pub const strike_timer = TimerId(3)

/// How long a round waits for its answers, in milliseconds.
const deadline_ms = 1000

/// The seed bytes a strike takes for each selected unit: 4 for each of the three
/// rolls (genesis_prime/game/hit `rolls_of`).
const bytes_per_unit = hit.roll_bytes

/// The caster as a selection and a strike take it: who it is, where it stands and
/// faces, its player faction and what its formulas read.
pub type Attacker {
  Attacker(
    unit_id: Int,
    connection: ConnectionId,
    pose: Pose,
    faction: PlayerFaction,
    stats: damage.Attacker,
  )
}

/// A unit a go selected: its id and the life its address needs.
pub type Aimed {
  Aimed(unit_id: Int, life: Int)
}

/// What a go strikes: the units, nearest first with the primary target after the
/// area's, and the damage each is struck with. A spell with no damage effect in the
/// phase selects units and tells none of them.
pub type Selection {
  Selection(
    asked: GoAsked,
    units: List(Aimed),
    blows: List(spell_area.DamageEffect),
  )
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// Tell the creature the strike, through the creature registry with no watch
  /// (genesis_prime/world_map/creature_registry `tell`): the connection builds the
  /// address from the caster's map and run and the unit and life here.
  TellStrike(unit_id: Int, life: Int, tell: Tell)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
  /// A round closed: the connection answers the cast rule with `cast.went`.
  Went(asked: GoAsked, struck: List(Struck))
  /// A news of a unit of a round that closed, held until now: the connection takes it
  /// as it would have when it came.
  Released(unit_id: Int, news: News)
  Log(level: LogLevel, text: String)
}

/// The rounds of a player's strikes that are open, in the order they began, the
/// monotonic time the strike timer is set to, and the health news held for units of
/// open rounds.
pub opaque type State {
  State(
    rounds: List(Round),
    armed_for_ms: Option(Int),
    held: List(#(Int, News)),
  )
}

/// One go's open round: the go, a place for each selected unit in the order of the
/// selection, and the monotonic time its deadline passes.
pub type Round {
  Round(asked: GoAsked, places: List(Place), deadline_ms: Int)
}

/// A selected unit's place in a round.
pub type Place {
  /// The creature has not answered.
  Waiting(unit_id: Int)
  /// The creature answered, or the unit needed no strike.
  Answered(struck: Struck)
  /// The creature refused, or the deadline passed: the unit is left out of the go.
  LeftOut(unit_id: Int)
}

/// A player that has struck nothing.
pub fn new() -> State {
  State(rounds: [], armed_for_ms: None, held: [])
}

/// Whether the timer is the strike timer.
pub fn owns(timer timer: TimerId) -> Bool {
  timer == strike_timer
}

/// The units a go strikes: the spell's phase from the areas, the candidates from the
/// picture, the centre by the primary target. A spell or a phase with no area strikes
/// nobody, and so does a child cast on a unit the client no longer shows.
pub fn select(
  asked asked: GoAsked,
  attacker attacker: Attacker,
  picture picture: Picture,
  areas areas: Areas,
) -> Selection {
  let empty = Selection(asked:, units: [], blows: [])
  case
    spell_area.of_spell(areas:, spell4_id: asked.spell4_id)
    |> result.try(fn(area) {
      spell_area.phase(spell: area, phase: asked.phase)
      |> result.map(fn(phase) { #(area, phase) })
    })
  {
    Error(Nil) -> empty
    Ok(#(area, phase)) -> {
      let centre = case asked.primary_target == attacker.unit_id {
        True -> Ok(attacker.pose)
        False ->
          shown.place_of(picture:, unit_id: asked.primary_target)
          |> result.map(fn(place) {
            Pose(
              at: Point(x: start_place.x(place), z: start_place.z(place)),
              yaw: 0.0,
            )
          })
      }
      let from_area = case phase.selects_area, area.row, centre {
        True, Some(row), Ok(centre) ->
          area_selection(attacker:, picture:, area:, row:, centre:)
        _, _, _ -> []
      }
      let with_primary = case
        phase.strikes_primary_target
        && asked.primary_target != attacker.unit_id
        && !list.contains(from_area, asked.primary_target)
      {
        True -> list.append(from_area, [asked.primary_target])
        False -> from_area
      }
      Selection(
        asked:,
        units: list.filter_map(with_primary, fn(unit_id) {
          shown.life_of(picture:, unit_id:)
          |> result.map(fn(life) { Aimed(unit_id:, life:) })
        }),
        blows: phase.damage,
      )
    }
  }
}

fn area_selection(
  attacker attacker: Attacker,
  picture picture: Picture,
  area area: spell_area.SpellArea,
  row row: area.Row,
  centre centre: Pose,
) -> List(Int) {
  area.select(
    candidates: shown.candidates(
      picture:,
      faction: attacker.faction,
      caster_unit_id: attacker.unit_id,
    ),
    centre:,
    row:,
    inside: spell_area.inside(spell: area),
  )
}

/// The seed bytes the selection's strikes take.
pub fn entropy_needed(selection selection: Selection) -> Int {
  case selection.blows {
    [] -> 0
    [_, ..] -> list.length(selection.units) * bytes_per_unit
  }
}

/// A selection begins its round: a strike told to each unit with `entropy`'s rolls
/// when the phase has damage, the strike timer set to the earliest deadline when it
/// is not set, and the round closed at once when nothing waits for it and no earlier
/// round of its cast is open.
pub fn begin(
  strike strike: State,
  selection selection: Selection,
  attacker attacker: Attacker,
  formulas formulas: Formulas,
  entropy entropy: BitArray,
  now now: Now,
) -> #(State, List(Effect)) {
  let offence = offence_of(selection:, attacker:, formulas:)
  let #(places, tells) =
    list.index_fold(selection.units, #([], []), fn(so_far, aimed, index) {
      let #(places, tells) = so_far
      case selection.blows {
        [] -> #(
          [
            Answered(cast.Hit(unit_id: aimed.unit_id, descriptions: [])),
            ..places
          ],
          tells,
        )
        [_, ..] ->
          case rolls_at(entropy:, index:) {
            Ok(rolls) -> #([Waiting(unit_id: aimed.unit_id), ..places], [
              TellStrike(
                unit_id: aimed.unit_id,
                life: aimed.life,
                tell: strike_tell.Strike(
                  key: strike_tell.Key(
                    cast_id: selection.asked.cast_id,
                    phase: selection.asked.phase,
                    unit_id: aimed.unit_id,
                  ),
                  from: attacker.connection,
                  offence:,
                  rolls:,
                ),
              ),
              ..tells
            ])
            Error(Nil) -> #([LeftOut(unit_id: aimed.unit_id), ..places], [
              Log(
                level: step.LogError,
                text: "a strike had no seed bytes for its unit, which is left out",
              ),
              ..tells
            ])
          }
      }
    })
  let round =
    Round(
      asked: selection.asked,
      places: list.reverse(places),
      deadline_ms: now.monotonic_ms + deadline_ms,
    )
  let state = State(..strike, rounds: list.append(strike.rounds, [round]))
  let #(state, settled) = settle(state:, now:)
  #(state, list.append(list.reverse(tells), settled))
}

fn offence_of(
  selection selection: Selection,
  attacker attacker: Attacker,
  formulas formulas: Formulas,
) -> hit.Offence {
  let level = attacker.stats.level
  hit.Offence(
    blows: list.map(selection.blows, fn(effect) {
      hit.Blow(
        spell4_effects_id: effect.effect_id.value,
        damage_type: effect.damage_type,
        damage: damage.rounded(value: damage.value(
          formula: effect.formula,
          attacker: attacker.stats,
        )),
        delay_ms: effect.delay_ms,
      )
    }),
    crit_chance: rating.to_fraction(
      formula: formulas.crit_chance,
      level:,
      base: formulas.player_base_crit_chance,
      rating: 0.0,
    ),
    crit_severity: rating.to_fraction(
      formula: formulas.crit_severity,
      level:,
      base: formulas.player_base_crit_severity,
      rating: 0.0,
    ),
    strikethrough: rating.to_fraction(
      formula: formulas.strikethrough,
      level:,
      base: formulas.player_base_strikethrough,
      rating: 0.0,
    ),
  )
}

fn rolls_at(
  entropy entropy: BitArray,
  index index: Int,
) -> Result(hit.Rolls, Nil) {
  bit_array.slice(entropy, index * bytes_per_unit, bytes_per_unit)
  |> result.try(fn(bytes) { hit.rolls_of(bytes:) })
}

/// A creature's answer: the unit's place in its round is filled; an answer for a
/// round that is closed is dropped. A round that has every answer closes.
pub fn answered(
  strike strike: State,
  answer answer: Answered,
  now now: Now,
) -> #(State, List(Effect)) {
  let key = answer.key
  let found =
    list.any(strike.rounds, fn(round) {
      is_round_of(round:, key:)
      && list.contains(round.places, Waiting(unit_id: key.unit_id))
    })
  use <- bool.guard(when: !found, return: #(strike, []))
  let rounds =
    list.map(strike.rounds, fn(round) {
      use <- bool.guard(when: !is_round_of(round:, key:), return: round)
      Round(
        ..round,
        places: list.map(round.places, fn(place) {
          fill(place:, unit_id: key.unit_id, outcome: answer.outcome)
        }),
      )
    })
  settle(state: State(..strike, rounds:), now:)
}

/// Whether the round is the go the strike's key names.
fn is_round_of(round round: Round, key key: strike_tell.Key) -> Bool {
  round.asked.cast_id == key.cast_id && round.asked.phase == key.phase
}

/// The place, filled with the outcome when it is the one waiting for this unit.
fn fill(
  place place: Place,
  unit_id unit_id: Int,
  outcome outcome: strike_tell.Outcome,
) -> Place {
  use <- bool.guard(when: place != Waiting(unit_id:), return: place)
  filled(unit_id:, outcome:)
}

fn filled(unit_id unit_id: Int, outcome outcome: strike_tell.Outcome) -> Place {
  case outcome {
    strike_tell.Landed(descriptions:) ->
      Answered(struck: cast.Hit(unit_id:, descriptions:))
    strike_tell.Deflected -> Answered(struck: cast.Deflected(unit_id:))
    strike_tell.Refused(..) -> LeftOut(unit_id:)
  }
}

/// The strike timer fired: each round whose deadline has passed closes with the
/// units that answered, and the timer is set to the next open deadline.
pub fn timer_fired(
  strike strike: State,
  now now: Now,
) -> #(State, List(Effect)) {
  let rounds =
    list.map(strike.rounds, fn(round) {
      case round.deadline_ms <= now.monotonic_ms {
        False -> round
        True ->
          Round(
            ..round,
            places: list.map(round.places, fn(place) {
              case place {
                Waiting(unit_id:) -> LeftOut(unit_id:)
                Answered(..) | LeftOut(..) -> place
              }
            }),
          )
      }
    })
  settle(state: State(..strike, rounds:, armed_for_ms: None), now:)
}

/// The player left the world with rounds open: the timer is cancelled and nothing is
/// written; the creatures keep what the strikes did.
pub fn left(strike strike: State) -> #(State, List(Effect)) {
  #(new(), case strike.armed_for_ms {
    Some(_) -> [CancelTimer(timer: strike_timer)]
    None -> []
  })
}

/// Whether a unit is in a round that is open: its health news waits for the round's
/// go.
pub fn holds(strike strike: State, unit_id unit_id: Int) -> Bool {
  list.any(strike.rounds, fn(round) { in_round(round:, unit_id:) })
}

fn in_round(round round: Round, unit_id unit_id: Int) -> Bool {
  list.any(round.places, fn(place) {
    case place {
      Waiting(unit_id: held) | LeftOut(unit_id: held) -> held == unit_id
      Answered(struck:) -> unit_of(struck) == unit_id
    }
  })
}

fn unit_of(struck: Struck) -> Int {
  case struck {
    cast.Hit(unit_id:, ..) | cast.Deflected(unit_id:) -> unit_id
  }
}

/// Holds a news of a unit of an open round until the round's go is written.
pub fn hold(
  strike strike: State,
  unit_id unit_id: Int,
  news news: News,
) -> State {
  State(..strike, held: list.append(strike.held, [#(unit_id, news)]))
}

/// Closes every round that is complete and has no earlier round of its cast open,
/// in the order they began, releases the news held for the units of a closed round
/// that no open round holds, and sets the strike timer to the earliest deadline of
/// a round still waiting for an answer.
fn settle(state state: State, now now: Now) -> #(State, List(Effect)) {
  let #(open, closed) = close_ready(rounds: state.rounds, open: [], closed: [])
  let state = State(..state, rounds: open)
  let went =
    list.map(closed, fn(round) {
      Went(
        asked: round.asked,
        struck: list.filter_map(round.places, fn(place) {
          case place {
            Answered(struck:) -> Ok(struck)
            Waiting(..) | LeftOut(..) -> Error(Nil)
          }
        }),
      )
    })
  let units =
    list.flat_map(closed, fn(round) {
      list.map(round.places, fn(place) {
        case place {
          Waiting(unit_id:) | LeftOut(unit_id:) -> unit_id
          Answered(struck:) -> unit_of(struck)
        }
      })
    })
  let #(released, kept) =
    list.partition(state.held, fn(held) {
      list.contains(units, held.0) && !holds(strike: state, unit_id: held.0)
    })
  let state = State(..state, held: kept)
  let #(state, timers) = timer_effects(state:, now:)
  #(
    state,
    list.flatten([
      went,
      list.map(released, fn(held) { Released(unit_id: held.0, news: held.1) }),
      timers,
    ]),
  )
}

fn close_ready(
  rounds rounds: List(Round),
  open open: List(Round),
  closed closed: List(Round),
) -> #(List(Round), List(Round)) {
  case rounds {
    [] -> #(list.reverse(open), list.reverse(closed))
    [round, ..rest] -> {
      let complete =
        list.all(round.places, fn(place) {
          case place {
            Waiting(..) -> False
            Answered(..) | LeftOut(..) -> True
          }
        })
      let earlier_open =
        list.any(open, fn(other) { other.asked.cast_id == round.asked.cast_id })
      case complete && !earlier_open {
        True -> close_ready(rounds: rest, open:, closed: [round, ..closed])
        False -> close_ready(rounds: rest, open: [round, ..open], closed:)
      }
    }
  }
}

/// The strike timer's effects: set when a round waits and none is set, moved when
/// the round it waited for closed, cancelled when none waits.
fn timer_effects(state state: State, now now: Now) -> #(State, List(Effect)) {
  let earliest =
    list.filter(state.rounds, fn(round) {
      list.any(round.places, fn(place) {
        case place {
          Waiting(..) -> True
          Answered(..) | LeftOut(..) -> False
        }
      })
    })
    |> list.map(fn(round) { round.deadline_ms })
    |> list.reduce(int.min)
    |> option.from_result
  case state.armed_for_ms, earliest {
    None, None -> #(state, [])
    None, Some(deadline) -> #(State(..state, armed_for_ms: earliest), [
      StartTimer(
        timer: strike_timer,
        after_ms: int.max(1, deadline - now.monotonic_ms),
      ),
    ])
    Some(_), None -> #(State(..state, armed_for_ms: None), [
      CancelTimer(timer: strike_timer),
    ])
    Some(armed), Some(deadline) if armed == deadline -> #(state, [])
    Some(_), Some(deadline) -> #(State(..state, armed_for_ms: earliest), [
      CancelTimer(timer: strike_timer),
      StartTimer(
        timer: strike_timer,
        after_ms: int.max(1, deadline - now.monotonic_ms),
      ),
    ])
  }
}
