//// The server's supervision tree. Each part of the server is added as a
//// child, in the order it starts; children stop in the reverse order, so
//// what starts first stops last.
////
//// ```
//// server supervisor (one-for-one, 3 restarts in 10 s)
////  ├─ database pool: pog's pool, named                  permanent
////  ├─ store: factory supervisor, named                  permanent
////  │    └─ one worker per ask                            temporary
////  └─ hand-off: service shell + hand-off rule, named    permanent
//// ```
////
//// What a restart rebuilds, and what a client sees:
//// - **The pool** reconnects to Postgres. Asks to the store meanwhile answer
////   `Unavailable`.
//// - **The store** starts with no workers. Asks meanwhile get `NotRunning`;
////   an asker whose worker was running gets `EndedBeforeAnswer`.
//// - **The hand-off** starts with no keys. A client part-way through a login
////   is refused and logs in again.

import genesis_prime/hand_off
import genesis_prime/service/shell.{type Call} as service_shell
import genesis_prime/store/worker.{type Job}
import gleam/erlang/process.{type Name}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import pog

/// The names and settings the tree's children are started with, made once
/// at start.
pub type Settings {
  Settings(
    /// pog's pool, with its name and the database it connects to.
    pool: pog.Config,
    /// The store's factory supervisor.
    store: Name(factory_supervisor.Message(Job, Nil)),
    /// The hand-off service.
    hand_off: Name(Call(hand_off.Message, hand_off.Answer)),
    /// How long the hand-off has to stop.
    hand_off_shutdown_ms: Int,
  )
}

/// Starts the tree. A child that fails three times in ten seconds does not
/// recover by restarting, so the tree gives up, the node stops, and the
/// host starts it again.
pub fn start(
  settings settings: Settings,
) -> actor.StartResult(supervisor.Supervisor) {
  todo as "the build follows the shape commit"
}
