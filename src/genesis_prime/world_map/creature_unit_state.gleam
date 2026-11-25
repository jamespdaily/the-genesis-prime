//// A creature's held unit states: the feature of the creature's rule
//// (genesis_prime/world_map/creature) that takes the unit states a caster's go holds on it
//// (genesis_prime/game/unit_state), starts each at its time, keeps it until its end, tells
//// the creature's viewers when one takes hold and when it ends, and tells the strike whether
//// the creature takes a hostile one. The creature's process owns its unit, its viewers and
//// its timer, so the news of a hold and its end come from one owner, in the order the holds
//// began and ended.
////
//// ```
//// caster's connection          creature (this feature)                               viewers
//// go: TellUnitStates ─▶ UnitStates ─▶ `set`
////                                 each row not yet past: a Held with the next number
////                                 a row due now: UnitStateHeld(state, number) ──────▶ picture
////                                 one timer, for the earliest start or end
//// ... the timer fires ─▶ `due`
////                                 each Held whose start has come is told as held
////                                 each Held whose end has come is dropped
////                                 UnitStateEnded(number) ───────────────────────────▶ picture
////                                 one timer for the next start or end, if any is left
//// death, removal ─▶ `cleared`     every Held dropped, the timer cancelled, no news
//// ```
////
//// - **When a state is held** is from the go's time plus the row's delay to that plus the
////   row's duration: the creature holds both times so the caster's leaving or dying changes
////   nothing. A row whose end is already past, or whose duration is 0, is not held.
//// - **A row's delay delays the hold**, a server guess: the client reads no row of the type
////   (`Spell4Effects.effectType.15`), so a retail time for the start does not exist; a state
////   blocks, is told and is shown from its start only.
//// - **One timer** serves every held state, armed for the earliest start or end: the
////   creature's other timers take all the ids a number could make, so no state has an id of
////   its own.
//// - **Whether a strike is refused** reads the held states through `unit_state.blocks_hostile`
////   (`blocks_hostile`): the strike then answers `Immune`. A hold whose start has not come, or
////   whose end has passed but whose timer has not yet fired, blocks nothing.
//// - **A viewer that arrives later** is told each hold already told and still running
////   (`shown`), after the creature's own appearance.
//// - A hold's number is the creature's own for its life, so two casters' holds of one state
////   are two holds that each end by their own end.

import genesis_prime/game/unit_news
import genesis_prime/game/unit_state
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// One state a creature holds: its number for the creature's life, which the news that ends
/// it names, the state, the monotonic times it starts and ends at, and whether the viewers
/// have been told it.
type Held {
  Held(number: Int, state: Int, starts_at_ms: Int, ends_at_ms: Int, told: Bool)
}

/// The states a creature holds, the number of its next hold, and the time the timer runs
/// for, when it runs.
pub opaque type State {
  State(held: List(Held), next_number: Int, timer_ends_at_ms: Option(Int))
}

/// What the feature asks the creature's rule to do, in order.
pub type Effect {
  /// News of the creature's own unit for each viewer: its `UnitStateHeld` or `UnitStateEnded`.
  ToViewers(news: unit_news.News)
  /// The one timer of the held states, which the creature's rule makes an id of
  /// (genesis_prime/world_map/creature): it fires `due`. A start is asked only when
  /// no timer runs, since a timer id already running cannot be started.
  StartTimer(after_ms: Int)
  CancelTimer
}

/// A creature that holds no state.
pub fn new() -> State {
  State(held: [], next_number: 1, timer_ends_at_ms: None)
}

/// The creature takes the `rows` a go holds on it at `went_at_ms`: each row whose end
/// (`went_at_ms` plus its delay and duration) is after `now_ms` is held under the next
/// number. A row whose start (`went_at_ms` plus its delay) has come is told to the viewers in
/// row order; a later one is told by `due` at its start. The timer is armed again when the
/// earliest start or end changed. A row with no duration, or whose end has passed, is not
/// held and nothing is sent for it.
pub fn set(
  state state: State,
  rows rows: List(unit_state.Row),
  went_at_ms went_at_ms: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(taken, next_number) =
    list.fold(rows, #([], state.next_number), fn(so_far, row) {
      let starts_at_ms = went_at_ms + row.delay_ms
      let ends_at_ms = starts_at_ms + row.duration_ms
      case row.duration_ms <= 0 || ends_at_ms <= now_ms {
        True -> so_far
        False -> #(
          [
            Held(
              number: so_far.1,
              state: row.state,
              starts_at_ms:,
              ends_at_ms:,
              told: starts_at_ms <= now_ms,
            ),
            ..so_far.0
          ],
          so_far.1 + 1,
        )
      }
    })
  let taken = list.reverse(taken)
  let held = list.append(state.held, taken)
  let told =
    list.filter_map(taken, fn(held) {
      case held.told {
        True -> Ok(held_effect(held:))
        False -> Error(Nil)
      }
    })
  let #(timer_ends_at_ms, timer) =
    timer_for(held:, running: state.timer_ends_at_ms, now_ms:)
  #(State(held:, next_number:, timer_ends_at_ms:), list.append(told, timer))
}

/// The timer fired: each hold whose start is at or before `now_ms` is told to the viewers as
/// held, in the order they began, each whose end is at or before `now_ms` is dropped and told
/// as ended, and the timer is armed for the next start or end when a hold is left. A hold
/// whose start and end have both passed is dropped with no news. A fire with nothing due
/// drops and tells nothing.
pub fn due(state state: State, now_ms now_ms: Int) -> #(State, List(Effect)) {
  let #(ended, held) =
    list.partition(state.held, fn(held) { held.ends_at_ms <= now_ms })
  let #(started, held) =
    list.fold(held, #([], []), fn(so_far, held) {
      case held.told || held.starts_at_ms > now_ms {
        True -> #(so_far.0, [held, ..so_far.1])
        False -> #([held, ..so_far.0], [Held(..held, told: True), ..so_far.1])
      }
    })
  let held = list.reverse(held)
  let told =
    list.append(
      list.map(list.reverse(started), fn(held) { held_effect(held:) }),
      list.filter_map(ended, fn(held) {
        case held.told {
          True ->
            Ok(ToViewers(news: unit_news.UnitStateEnded(number: held.number)))
          False -> Error(Nil)
        }
      }),
    )
  let #(timer_ends_at_ms, timer) = timer_for(held:, running: None, now_ms:)
  #(State(..state, held:, timer_ends_at_ms:), list.append(told, timer))
}

/// The creature dies or is removed: every hold is dropped and a running timer
/// cancelled, with no news; the viewers' pictures clear on the creature's own news.
pub fn cleared(state state: State) -> #(State, List(Effect)) {
  #(
    State(..state, held: [], timer_ends_at_ms: None),
    case state.timer_ends_at_ms {
      Some(..) -> [CancelTimer]
      None -> []
    },
  )
}

/// Whether a state held at `now_ms` makes the creature take no hostile strike
/// (genesis_prime/game/unit_state `blocks_hostile`). A hold whose start has not come does
/// not, nor one whose end has passed, though its timer has not yet fired.
pub fn blocks_hostile(state state: State, now_ms now_ms: Int) -> Bool {
  unit_state.blocks_hostile(
    held: list.filter_map(state.held, fn(held) {
      case held.starts_at_ms <= now_ms && held.ends_at_ms > now_ms {
        True -> Ok(held.state)
        False -> Error(Nil)
      }
    }),
  )
}

/// The news that tells a viewer who arrives while states are held each hold the viewers were
/// told and that still runs at `now_ms`, in the order they began.
pub fn shown(state state: State, now_ms now_ms: Int) -> List(unit_news.News) {
  list.filter_map(state.held, fn(held) {
    case held.told && held.ends_at_ms > now_ms {
      True -> Ok(held_news(held:))
      False -> Error(Nil)
    }
  })
}

fn held_news(held held: Held) -> unit_news.News {
  unit_news.UnitStateHeld(state: held.state, number: held.number)
}

fn held_effect(held held: Held) -> Effect {
  ToViewers(news: held_news(held:))
}

/// The timer for the earliest next start or end of `held`: none when no hold is left,
/// nothing to ask when the running timer is already for that time, a start when none runs,
/// else a cancel then a start.
fn timer_for(
  held held: List(Held),
  running running: Option(Int),
  now_ms now_ms: Int,
) -> #(Option(Int), List(Effect)) {
  let next_ms = fn(held: Held) {
    case held.told {
      True -> held.ends_at_ms
      False -> held.starts_at_ms
    }
  }
  case list.map(held, next_ms) |> list.reduce(int.min) {
    Error(Nil) -> #(None, case running {
      Some(..) -> [CancelTimer]
      None -> []
    })
    Ok(earliest) ->
      case running {
        Some(running_ms) if running_ms == earliest -> #(running, [])
        Some(..) -> #(Some(earliest), [
          CancelTimer,
          StartTimer(after_ms: earliest - now_ms),
        ])
        None -> #(Some(earliest), [StartTimer(after_ms: earliest - now_ms)])
      }
  }
}
