//// The leaving saver: a service that outlives the connections and keeps a
//// player's final save until the store takes it or 20 s have passed from the
//// hand-over. A factory supervisor of one actor per pending save, each a shell
//// (genesis_prime/leaving_saver/shell) running one rule
//// (genesis_prime/leaving_saver/rule).
////
//// ```
//// server supervisor ─ ... login ─ leaving saver (factory, permanent, shutdown window + 1 s) ─ game ─ closer
////                                   └─ one temporary actor per pending save, never restarted
//// a connection's end ─ hand_over(name, handover) ─ start_child ─▶ Ok(Nil) | Error(Nil): not running
//// ```
////
//// - **Starts just before the game subtree**, so it stops after the game
////   connections have handed over and before login, the world, Sessions, the
////   hand-off, the store and the pool, which it needs only by name at each ask.
//// - **A crash loses what it holds.** An actor's crash loses its one save; the
////   supervisor's crash loses every pending save and it restarts empty. Each
////   loss is at most what a failed single try loses.
//// - **The shutdown time is the window plus one second.** The supervisor sends
////   every actor its exit at once and each goes on to its own deadline, at most
////   the window after its hand-over.

import genesis_prime/game/leaving_save.{type Handover}
import genesis_prime/leaving_saver/shell
import genesis_prime/service
import gleam/erlang/process.{type Name}
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// The saver's factory supervisor as a permanent child of the server's tree,
/// named `settings.name`, whose temporary children are the actors that
/// `shell.start` makes, given `settings.shutdown_ms` to stop.
pub fn supervised(
  settings settings: shell.Settings,
) -> ChildSpecification(factory_supervisor.Supervisor(Handover, Nil)) {
  service.temporary_factory(
    name: settings.name,
    shutdown_ms: settings.shutdown_ms,
    start: fn(handover) { shell.start(settings:, handover:) },
  )
}

/// Hands a save to the saver: one actor starts for it and takes it from there.
/// `Error(Nil)` when no supervisor runs under the name, or it ended while the
/// call waited, or it would not start the actor; the caller logs it and goes
/// on. A call with no timeout, which waits only for the starts queued before it.
pub fn hand_over(
  name name: Name(factory_supervisor.Message(Handover, Nil)),
  handover handover: Handover,
) -> Result(Nil, Nil) {
  service.start_child(supervisor: name, argument: handover)
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}
