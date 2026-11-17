//// A creature's held unit states: the feature of the creature's rule
//// (genesis_prime/world_map/creature) that takes the unit states a caster's go holds on it
//// (genesis_prime/game/unit_state), keeps each until its end, tells the creature's viewers
//// when one takes hold and when it ends, and tells the strike whether the creature takes a
//// hostile one. The creature's process owns its unit, its viewers and its timer, so the news
//// of a hold and its end come from one owner, in the order the holds began and ended.
////
//// ```
//// caster's connection          creature (this feature)                               viewers
//// go: TellUnitStates ─▶ UnitStates ─▶ `set`
////                                 each row due after now: a Held with the next number
////                                 UnitStateHeld(state, number) ─────────────────────▶ picture
////                                 one timer, for the earliest end
//// ... the timer fires ─▶ `ended`
////                                 each Held whose end has come is dropped
////                                 UnitStateEnded(number) ───────────────────────────▶ picture
////                                 one timer for the next end, if any is left
//// death, removal ─▶ `cleared`     every Held dropped, the timer cancelled, no news
//// ```
////
//// - **When a state ends** is the go's time plus the row's delay and duration: the creature
////   holds the end so the caster's leaving or dying changes nothing. A row whose end is
////   already past is not held.
//// - **One timer** serves every held state, armed for the earliest end: the creature's other
////   timers take all the ids a number could make, so no state has an id of its own.
//// - **Whether a strike is refused** reads the held states through `unit_state.blocks_hostile`
////   (`blocks_hostile`): the strike then answers `Immune`.
//// - A hold's number is the creature's own for its life, so two casters' holds of one state
////   are two holds that each end by their own end.

import genesis_prime/client_connection
import genesis_prime/game/unit_state
import gleam/list

/// One state a creature holds: its number for the creature's life, which the news that ends
/// it names, the state, and the monotonic time it ends at.
pub type Held {
  Held(number: Int, state: Int, ends_at_ms: Int)
}

/// The states a creature holds and the number of its next hold.
pub opaque type State {
  State(held: List(Held), next_number: Int)
}

/// What the feature asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer: its `UnitStateHeld` or `UnitStateEnded`.
  ToViewers(news: client_connection.News)
  /// The one timer of the held states, which the creature's rule makes an id of
  /// (genesis_prime/world_map/creature): it fires `ended`.
  StartTimer(after_ms: Int)
  CancelTimer
}

/// A creature that holds no state.
pub fn new() -> State {
  State(held: [], next_number: 1)
}

/// The creature takes the `rows` a go holds on it at `went_at_ms`: each row whose end
/// (`went_at_ms` plus its delay and duration) is after `now_ms` is held under the next
/// number and told to the viewers in row order, and the timer is armed again when the earliest
/// end changed. A row whose end has passed is not held and nothing is sent for it.
pub fn set(
  state _state: State,
  rows _rows: List(unit_state.Row),
  went_at_ms _went_at_ms: Int,
  now_ms _now_ms: Int,
) -> #(State, List(Effect)) {
  panic as "shape: holding a unit state is built in the step's code commit"
}

/// The timer fired: each hold whose end is at or before `now_ms` is dropped and told to the
/// viewers as ended, and the timer is armed for the next end when a hold is left. A fire for
/// a hold not yet due drops nothing.
pub fn ended(
  state _state: State,
  now_ms _now_ms: Int,
) -> #(State, List(Effect)) {
  panic as "shape: the end of a unit state is built in the step's code commit"
}

/// The creature dies, is removed or stands again: every hold is dropped and the timer
/// cancelled, with no news; the viewers' pictures clear on the creature's own news.
pub fn cleared(state _state: State) -> #(State, List(Effect)) {
  panic as "shape: clearing the unit states is built in the step's code commit"
}

/// Whether a held state makes the creature take no hostile strike
/// (genesis_prime/game/unit_state `blocks_hostile`).
pub fn blocks_hostile(state state: State) -> Bool {
  unit_state.blocks_hostile(held: list.map(state.held, fn(held) { held.state }))
}

/// The holds, in the order they began.
pub fn held(state state: State) -> List(Held) {
  state.held
}
