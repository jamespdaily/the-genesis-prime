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
//// - **A worker's start does no work.** It spawns the worker and returns, and
////   the worker runs its query after, so `start_child`, a supervisor call with
////   no timeout, waits only for the starts queued before it.
//// - **The store not running.** `start_child` on a name no process holds
////   exits the caller with `noproc` rather than returning an error; `ask`
////   catches that exit, and only that one, as `Error(Nil)`.
//// - **Failures.** pog's `ConnectionUnavailable` and `QueryTimeout` answer
////   `Unavailable`, and so does the pool not running: pgo's checkout exits
////   with `{noproc, {pgo_pool, checkout, _}}` then, which the worker catches,
////   and only that exit. Any other error is a bug in the query or the schema:
////   the worker crashes with it, and the asker gets `EndedBeforeAnswer`.
//// - **The supervisor stopping.** Its workers get its shutdown timeout to end;
////   an asker waiting on one gets `EndedBeforeAnswer`.

import genesis_prime/login/guid
import genesis_prime/service/shell.{type Sent, ToWorker}
import genesis_prime/store.{
  type Answer, type Request, Account, AccountFound, AccountId, FindAccount,
  NoSuchAccount, Unavailable,
}
import genesis_prime/store/sql
import gleam/erlang/process.{type Name}
import gleam/otp/actor
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
  factory_supervisor.worker_child(fn(job: Job) { start_worker(job, pool) })
  |> factory_supervisor.named(name)
  |> factory_supervisor.restart_strategy(supervision.Temporary)
  // A temporary worker is never restarted, so this limit is never reached.
  |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
  // A worker traps no exits, so it ends the moment it is told to.
  |> factory_supervisor.timeout(ms: 1000)
  |> factory_supervisor.supervised
  |> supervision.restart(supervision.Permanent)
}

/// Starts a worker for one ask, for an asker's directory: `Error(Nil)` when
/// the store's supervisor is not running or will not start the worker, else
/// `ToWorker` with the worker the asker monitors and ends at its deadline.
pub fn ask(
  store store: Name(factory_supervisor.Message(Job, Nil)),
  request request: Request,
  reply reply: fn(Answer) -> Nil,
) -> Result(Sent, Nil) {
  case
    unless_not_running(fn() {
      factory_supervisor.start_child(
        factory_supervisor.get_by_name(store),
        Job(request:, reply:),
      )
    })
  {
    Ok(Ok(started)) -> Ok(ToWorker(pid: started.pid))
    Ok(Error(_)) | Error(Nil) -> Error(Nil)
  }
}

/// Spawns the worker and returns at once, so the supervisor's start call
/// waits for no work; the worker runs its query after.
fn start_worker(job: Job, pool: pog.Connection) -> actor.StartResult(Nil) {
  let pid = process.spawn(fn() { run(job, pool) })
  Ok(actor.Started(pid:, data: Nil))
}

/// Runs the query on the pool, answers the asker and ends.
fn run(job: Job, pool: pog.Connection) -> Nil {
  let FindAccount(login_name:) = job.request
  let answer = case
    unless_not_running(fn() { sql.find_account(pool, login_name) })
  {
    // The pool is not running, as when it restarts.
    Error(Nil) -> Unavailable
    Ok(Error(pog.ConnectionUnavailable)) | Ok(Error(pog.QueryTimeout)) ->
      Unavailable
    Ok(Ok(pog.Returned(rows: [], ..))) -> NoSuchAccount
    Ok(Ok(pog.Returned(rows: [row], ..))) -> {
      let assert Ok(game_account_id) = guid.from_text(row.game_account_id)
        as "the database holds game account ids that are GUIDs"
      AccountFound(Account(
        account_id: AccountId(row.account_id),
        login_name: row.login_name,
        srp_salt: row.srp_salt,
        srp_verifier: row.srp_verifier,
        game_account_id:,
      ))
    }
    Ok(Ok(pog.Returned(..))) ->
      panic as "a login name is unique, so the query returns at most one account"
    Ok(Error(pog.ConstraintViolated(..) as error))
    | Ok(Error(pog.PostgresqlError(..) as error))
    | Ok(Error(pog.UnexpectedArgumentCount(..) as error))
    | Ok(Error(pog.UnexpectedArgumentType(..) as error))
    | Ok(Error(pog.UnexpectedResultType(..) as error)) -> exit_with(error)
  }
  job.reply(answer)
}

@external(erlang, "store_worker_ffi", "unless_not_running")
fn unless_not_running(run: fn() -> a) -> Result(a, Nil)

/// Ends the worker with the error as its exit reason. The account query
/// failing in the database or in decoding its rows is a bug in the query or the
/// schema, and the asker gets `EndedBeforeAnswer`.
@external(erlang, "erlang", "exit")
fn exit_with(reason: pog.QueryError) -> a
