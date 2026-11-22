//// How a page's runtime subscribes to the process it shows (the Overview's
//// poller, a log follower) so that what that process answers at once is never
//// lost. A process hands a joining page what it already has the moment it
//// joins, and the runtime hears a subject only once its selector is merged.
////
//// ```text
//// init ──► select effect ──► Joining(join) to the runtime ──► (selector merged)
////                                   │
////                                   └──► update ──► joined effect ──► join(subject)
////                                                                       │
//// the process ──── what it has, at once ──► subject ◄───────────────────┘
//// ```
////
//// - The select effect only dispatches the join to the runtime; the runtime
////   queues the merge of the subject's selector after that message and before
////   any answer to the join can be queued (lustre's server runtime,
////   `handle_effect`).
//// - A message that reaches an actor before its selector knows the subject is
////   discarded with a warning (gleam_otp `actor`, `Unexpected`), so a join made
////   inside the select effect loses an answer that comes back at once.

import gleam/erlang/process.{type Subject}
import lustre/effect.{type Effect}
import lustre/server_component

/// The effect a page's `init` returns: it makes a subject for what the page is
/// sent (`received` makes the page's message of it) and asks the page to join
/// with it, as the page's own message `joining` carries.
pub fn open(
  join join: fn(Subject(item)) -> Nil,
  received received: fn(item) -> message,
  joining joining: fn(fn() -> Nil) -> message,
) -> Effect(message) {
  server_component.select(fn(dispatch, subject) {
    dispatch(joining(fn() { join(subject) }))
    process.new_selector() |> process.select_map(subject, received)
  })
}

/// The effect a page's `update` returns for its `joining` message: the join,
/// made once the runtime hears the subject.
pub fn joined(join join: fn() -> Nil) -> Effect(message) {
  effect.from(fn(_dispatch) { join() })
}
