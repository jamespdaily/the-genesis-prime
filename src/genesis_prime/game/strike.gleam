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
////   the connection draws 8 bytes of its seed for each unit
////   begin: a round for (k, phase), its deadline now + 1 s
////     for each unit in selection order, the spell having damage:
////       TellStrike(Ci, Strike(key, from, offence, rolls)) ─────────────────────────────▶ hit rule
////     StartTimer(strike timer) to the earliest open deadline
////   ◀──────────────────────────── Answered(key, Landed | Deflected | Refused) ◀─────────┘
////   answered: the unit's place in the round is filled
////   the round closes: all answered, or the deadline passed, and every earlier round of k closed
////     Went(asked, struck) ─▶ the connection calls cast.went(k, phase, struck)
//// ```
////
//// - **Selection** reads the picture of the units the client shows
////   (genesis_prime/game/shown) and the spell's area (genesis_prime/game/spell_area): the
////   phase's centre is the caster's place and facing, or, for a child cast on a struck
////   unit (Crush's 42297), that unit's shown place; the primary target is added for an
////   effect aimed at it, and a unit is struck once for a go. A phase that selects no
////   unit closes at once and its go is written with no target.
//// - **One round for each go that selects.** The key of a strike is (cast, phase, unit).
////   A round holds a place for each selected unit, filled in the order of the
////   selection whatever order the answers arrive in; the go lists them in that order.
//// - **A selected creature that refuses** (it died after the picture was taken) or
////   never answers is left out of the go, and the count is not refilled from the
////   candidates that were not selected.
//// - **Rounds close in phase order.** A round of phase 1 waits for phase 0's, so a
////   later phase is never written first.
//// - **The deadline** is 1 second for each round. One strike timer for the connection
////   is set to the earliest open deadline and moves to the next when it fires.
//// - **An answer for a round that is closed** is dropped, and a creature's 0x937 shows
////   its health with no number: the client never saw the hit.
//// - **The caster's 0x801 while a round is open** ends the cast; the round closes as
////   always and `cast.went` finds no live cast, so nothing is written and the hits stand.
//// - **The caster's rolls** come from its seeded random, 8 bytes for each selected unit,
////   so a recording replays them and the creature keeps no random state.

import genesis_prime/game/area.{type Pose}
import genesis_prime/game/cast.{type GoAsked, type Struck}
import genesis_prime/game/damage
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/shown.{type Picture, type PlayerFaction}
import genesis_prime/game/spell_area.{type Areas}
import genesis_prime/game/strike_tell.{type Answered, type Tell}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, TimerId,
}
import gleam/option.{type Option, None}

/// The one strike timer of a connection: the connection's own timers are below the
/// cast rule's, which start at 1000 (genesis_prime/game/cast `first_timer`).
pub const strike_timer = TimerId(3)

/// How long a round waits for its answers, in milliseconds.
pub const deadline_ms = 1000

/// The seed bytes a strike takes for each selected unit: 4 for the critical hit
/// roll and 4 for the deflect roll (genesis_prime/game/hit `rolls_of`).
pub const bytes_per_unit = 8

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
  Log(level: LogLevel, text: String)
}

/// The rounds of a player's strikes that are open, in the order they began, and the
/// monotonic time the strike timer is set to.
pub opaque type State {
  State(rounds: List(Round), armed_for_ms: Option(Int))
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
  State(rounds: [], armed_for_ms: None)
}

/// Whether the timer is the strike timer.
pub fn owns(timer timer: TimerId) -> Bool {
  timer == strike_timer
}

/// The units a go strikes: the spell's phase from the areas, the candidates from the
/// picture, the centre by the primary target. `Error(Nil)` when the spell has no
/// area or the phase none.
pub fn select(
  asked asked: GoAsked,
  attacker attacker: Attacker,
  picture picture: Picture,
  areas areas: Areas,
) -> Result(Selection, Nil) {
  unbuilt(inputs: #(asked, attacker, picture, areas))
}

/// The seed bytes the selection's strikes take.
pub fn entropy_needed(selection selection: Selection) -> Int {
  unbuilt(inputs: selection)
}

/// A selection begins its round: a strike told to each unit with `entropy`'s rolls
/// when the phase has damage, the strike timer set to the earliest deadline, and the
/// round closed at once when it holds no strike to wait for.
pub fn begin(
  strike strike: State,
  selection selection: Selection,
  attacker attacker: Attacker,
  formulas formulas: Formulas,
  entropy entropy: BitArray,
  now now: Now,
) -> #(State, List(Effect)) {
  unbuilt(inputs: #(strike, selection, attacker, formulas, entropy, now))
}

/// A creature's answer: the unit's place in its round is filled; an answer for a
/// round that is closed is dropped. A round that has every answer closes.
pub fn answered(
  strike strike: State,
  answer answer: Answered,
  now now: Now,
) -> #(State, List(Effect)) {
  unbuilt(inputs: #(strike, answer, now))
}

/// The strike timer fired: each round whose deadline has passed closes with the
/// units that answered, and the timer moves to the next open deadline.
pub fn timer_fired(
  strike strike: State,
  now now: Now,
) -> #(State, List(Effect)) {
  unbuilt(inputs: #(strike, now))
}

/// The player left the world with rounds open: the timer is cancelled and nothing is
/// written; the creatures keep what the strikes did.
pub fn left(strike strike: State) -> #(State, List(Effect)) {
  unbuilt(inputs: strike)
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
