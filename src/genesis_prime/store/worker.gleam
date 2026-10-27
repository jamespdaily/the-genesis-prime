//// The store's workers: one process per ask, started under the store's
//// factory supervisor, which runs one query on pog's pool, answers the asker
//// and ends. pog's pool caps how many queries reach the database at once.
////
//// ```
//// asker (a shell)                 store supervisor            worker
////   ask(store, pool, request, reply)
////     not running ─▶ Error(Nil): NotRunning
////     start_child ─────────────▶ starts ─────────────────▶ runs the query
////   ◀── Ok(ToWorker(pid)); monitors it
////   ◀──────────────────────────────────────────────────── reply(answer), ends
////   at the deadline, no answer: ends the worker (exit shutdown) ─▶ NoAnswerInTime
////   the worker crashes ─▶ EndedBeforeAnswer
//// ```
////
//// - **Workers are temporary.** The supervisor never restarts one, and a
////   worker the asker ends at its deadline exits with `shutdown`, which the
////   supervisor does not report as a failure.
//// - **Failures.** pog's `ConnectionUnavailable` and `QueryTimeout` answer
////   `Unavailable`. Any other error is a bug in the query or the schema: the
////   worker crashes with it, and the asker gets `EndedBeforeAnswer`.
//// - **The supervisor stopping.** Its workers get its shutdown timeout to end;
////   an asker waiting on one gets `EndedBeforeAnswer`.

import genesis_prime/service/shell.{type Sent}
import genesis_prime/store.{type Answer, type Request}
import gleam/erlang/process.{type Name}
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import pog

/// What one worker is started with: the ask, and how to answer it.
pub type Job {
  Job(request: Request, reply: fn(Answer) -> Nil)
}

/// The store's factory supervisor as a permanent child of the server's
/// supervisor, registered as `name`, its workers running on `pool`.
pub fn supervised(
  name name: Name(factory_supervisor.Message(Job, Nil)),
  pool pool: pog.Connection,
) -> ChildSpecification(factory_supervisor.Supervisor(Job, Nil)) {
  todo as "the build follows the shape commit"
}

/// Starts a worker for one ask, for an asker's directory: `Error(Nil)` when
/// the store's supervisor is not running or will not start the worker, else
/// `ToWorker` with the worker the asker monitors and ends at its deadline.
pub fn ask(
  store store: Name(factory_supervisor.Message(Job, Nil)),
  request request: Request,
  reply reply: fn(Answer) -> Nil,
) -> Result(Sent, Nil) {
  todo as "the build follows the shape commit"
}
