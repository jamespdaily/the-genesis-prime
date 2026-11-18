//// The rule of one kept save: the state machine that tries a handed-over final
//// save on the ladder until the store takes it or its deadline passes. Pure: a
//// time is the monotonic milliseconds the input carries, and the shell
//// (genesis_prime/leaving_saver/shell) starts the timers, asks the store and
//// turns what it sees into these inputs.
////
//// ```
//// Started        ─▶ failed 0: Ask               failed 1: Wait(first rung)
//// Answered(Stored(PlaceSaved))        ─▶ Finish (an info line when it took a retry)
//// Answered(Stored(NothingSaved))      ─▶ a note, Finish
//// Answered(Stored(a refusal))         ─▶ a fault line, Finish
//// Answered(Failed(why))               ─▶ a warning, Wait(rung)        or the give-up row
//// WaitEnded                           ─▶ Ask, cut to what the deadline leaves, or the give-up row
//// Stopping                            ─▶ nothing: the deadline already bounds the save
//// the give-up row                     ─▶ one error line, Finish
//// ```
////
//// - The deadline is a time held by the rule: `within_ms` after the hand-over
////   (genesis_prime/game/leaving_save.Retries), so the save ends with its own
////   error line and not by a kill.
//// - A retry is made only when its wait ends before the deadline; the last ask is
////   cut to what the deadline leaves (`leaving_save.ask_within_ms`).
//// - Each try is numbered one above the last (`leaving_save.request`), so a late
////   write of an ended try is fenced by the store.
//// - The answers of the save's own kind are `movement.saved`'s lines, so a
////   leaving save's outcome reads as any other save's.
//// - An input that cannot come (an answer while waiting, a wait's end while
////   asking, a second start) is an error line and changes nothing.

import genesis_prime/game/leaving_save.{type Handover, type Retries}
import genesis_prime/step.{type LogLine}
import genesis_prime/store.{type MoveAnswer, type Request}
import gleam/option.{type Option, None}

/// Why a try got no answer from the store. The shell maps the store's
/// `Unavailable` answer and the asker's outcomes (genesis_prime/step.Outcome)
/// to these four.
pub type Why {
  /// The store answered that the database could not be reached.
  Unavailable
  /// No process runs the store's supervisor.
  NotRunning
  /// The ask's deadline passed with no answer; its worker was ended.
  NoAnswerInTime
  /// The store's worker ended before it answered.
  EndedBeforeAnswer
}

/// What the store's worker came back with for one try.
pub type Attempt {
  /// The store answered the save.
  Stored(answer: MoveAnswer)
  /// The store gave no answer.
  Failed(why: Why)
  /// An answer no save asks for: the store answered another group.
  Unexpected
}

/// What reaches the rule. The shell turns its timer's firing into `WaitEnded`,
/// a store worker's reply, its death, its ask's deadline and a store that is not
/// running into `Answered`, and the parent's exit into `Stopping`.
pub type Input {
  Started
  WaitEnded
  Answered(attempt: Attempt)
  Stopping
}

/// What the shell carries out, in order.
pub type Effect {
  /// Ask the store, and end the ask's worker at `within_ms`.
  Ask(request: Request, within_ms: Int)
  /// Start the retry timer.
  Wait(after_ms: Int)
  Log(line: LogLine)
  /// End the actor: the save landed, was refused, or is given up.
  Finish
}

/// One kept save: the hand-over, the ladder and the deadline, how many asks were
/// made and how many failed, and whether an ask is out or a wait runs.
pub opaque type State {
  State(
    handover: Handover,
    retries: Retries,
    ask_deadline_ms: Int,
    deadline_ms: Int,
    tries: Int,
    failed: Int,
    phase: Phase,
    last_why: Option(Why),
  )
}

/// Where a kept save is: handed over and not started, an ask out, a retry
/// timer running, or finished.
pub type Phase {
  NotStarted
  Asking
  Waiting
  Ended
}

/// The state of a save handed over at `now_ms`: its deadline is `now_ms` plus
/// the ladder's window, and no try was made yet by the saver.
pub fn new(
  handover handover: Handover,
  retries retries: Retries,
  ask_deadline_ms ask_deadline_ms: Int,
  now_ms now_ms: Int,
) -> State {
  State(
    handover:,
    retries:,
    ask_deadline_ms:,
    deadline_ms: now_ms + retries.within_ms,
    tries: 0,
    failed: handover.failed,
    phase: NotStarted,
    last_why: None,
  )
}

/// The state and effects after the input at `now_ms`. After `Finish` no input
/// has an effect.
pub fn step(
  state _state: State,
  now_ms _now_ms: Int,
  input _input: Input,
) -> #(State, List(Effect)) {
  panic as "the rule's steps are built in the build phase"
}
