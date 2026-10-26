//// The workers that carry out character select's commands against the
//// database: one temporary process for each command, started under a
//// supervisor of the game subtree. The connection that asked waits for the
//// answer in two phases, so that an answer of `Unavailable` to a write is
//// never untrue. A worker tells the asker as soon as it holds a connection of
//// the pool, inside a transaction and before its first statement is sent, and
//// sends the statement only when the asker tells it to go. Until the asker has
//// told it, the asker waits up to its deadline and kills a worker that has
//// not told it: nothing was sent to Postgres, so nothing can commit, and the
//// answer is `Unavailable`. Because the worker waits for the word to go, a
//// kill at the deadline cannot come after the statement was sent. Once the
//// asker has told the worker to go, it does not kill it at the deadline, which
//// could be mid-statement, but waits for its answer up to `pool.holding_wait_ms`,
//// in which Postgres ends a transaction that is still running
//// (`pool.transaction_timeout_ms`): the answer is what happened, committed or
//// ended. A worker that has not answered by then leaves the outcome unknown:
//// the answer is `Unknown`, never `Unavailable`, which says nothing committed,
//// and the connection ends so that the client lists the store's characters
//// again. A worker that is not told to go within `go_wait_milliseconds` sends
//// nothing and gives `Unavailable`. A worker that ends without answering,
//// such as one whose statement crashed, gives `Unavailable` at once.
//// A worker holds nothing between commands, so none is restarted.
////
//// A limit that is stated and not closed: a session that a second login of its
//// account replaced is ended and its worker is not, so a write the worker is
//// carrying out can commit after the session is gone; the new session's first
//// list is read at once and may miss it, and the next list shows it
//// (`game/sessions`).

import genesis_prime/character/select.{
  type Answer, type Command, Unavailable, Unknown,
}
import genesis_prime/character/store
import genesis_prime/database/pool
import genesis_prime/telemetry/log
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision
import pog

/// How long the workers' supervisor allows 3 restarts in: the service
/// subtrees' 3 in 5 seconds. Its workers are temporary, so the limit counts the
/// restarts of the supervisor's own failures only.
const restart_intensity = 3

const restart_period_seconds = 5

/// How long a worker has to stop, in milliseconds. A worker that is mid-query
/// is killed after a second; the database finishes or rolls back the statement.
const worker_shutdown_milliseconds = 1000

/// How long a worker has to start, in milliseconds.
const start_deadline_milliseconds = 5000

/// How long a worker that holds a connection waits for its asker to tell it to
/// go, in milliseconds, before it gives the connection back and sends nothing.
/// An asker that is waiting answers at once, so this only ends a wait for an
/// asker that has gone; the pool's margin, so a connection is never held longer
/// than the wait for an answer is allowed to be. No measurement chose it.
const go_wait_milliseconds = pool.margin_ms

/// One command to carry out, with the connection to the database and where
/// the worker reports.
pub opaque type Job {
  Job(db: pog.Connection, command: Command, reply: Subject(Report))
}

/// What the asker of a worker hears. A worker says `Holding` when it has a
/// connection of the pool and is about to send its statement, with the subject
/// the asker tells it to go on, and then `Answered`; `Gone` is the asker's own
/// note that the worker ended without answering.
type Report {
  Holding(go: Subject(Nil))
  Answered(Answer)
  Gone
}

/// The name the workers' supervisor is registered under, made once by whoever
/// starts the tree.
pub type Workers {
  Workers(factory: Name(factory_supervisor.Message(Job, Nil)))
}

/// The messages a worker receives: the one that tells it to begin.
type Message {
  Begin
}

/// The workers' supervisor as a child of the game subtree.
pub fn supervised(
  workers workers: Workers,
) -> supervision.ChildSpecification(factory_supervisor.Supervisor(Job, Nil)) {
  factory_supervisor.worker_child(start)
  |> factory_supervisor.named(workers.factory)
  |> factory_supervisor.restart_strategy(supervision.Temporary)
  |> factory_supervisor.restart_tolerance(
    intensity: restart_intensity,
    period: restart_period_seconds,
  )
  |> factory_supervisor.timeout(ms: worker_shutdown_milliseconds)
  |> factory_supervisor.supervised
}

/// Starts a worker for a job. The worker does its database work after it has
/// started, never in its initialiser.
fn start(job: Job) -> actor.StartResult(Nil) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    process.send(self, Begin)
    actor.initialised(job) |> actor.returning(Nil) |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(job: Job, message: Message) -> actor.Next(Job, Message) {
  let Begin = message
  let answer =
    store.run_held(db: job.db, command: job.command, connection_held: fn() {
      let go = process.new_subject()
      process.send(job.reply, Holding(go:))
      case process.receive(go, within: go_wait_milliseconds) {
        Ok(Nil) -> store.Go
        Error(Nil) -> store.Withheld
      }
    })
  process.send(job.reply, Answered(answer))
  actor.stop()
}

fn describe(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "it did not start in time"
    actor.InitFailed(reason) -> reason
    actor.InitExited(_) -> "it ended as it started"
  }
}

/// Carries out the command in a worker and waits for the answer: up to
/// `within_ms` milliseconds for the worker to hold a connection, and from then
/// on up to `pool.holding_wait_ms` for its answer. A worker that does not start,
/// ends without answering or holds no connection by the deadline gives
/// `Unavailable`, and so does a supervisor of workers that is not running, as
/// while it is being rebuilt. A worker that held a connection is never killed
/// at the deadline, so a write answered `Unavailable` committed nothing; one
/// that has no answer within `pool.holding_wait_ms` is `Unknown`.
pub fn run(
  workers workers: Workers,
  db db: pog.Connection,
  command command: Command,
  within_ms within_ms: Int,
) -> Answer {
  case process.named(workers.factory) {
    Error(Nil) -> {
      log.warning(
        log.Who(
          account: None,
          actor: None,
          place: Some(log.Process("store_worker")),
          message: None,
          peer: None,
        ),
        "the supervisor of the store workers is not running, so the command is not carried out",
      )
      Unavailable
    }
    Ok(_) -> start_and_wait(workers:, db:, command:, within_ms:)
  }
}

fn start_and_wait(
  workers workers: Workers,
  db db: pog.Connection,
  command command: Command,
  within_ms within_ms: Int,
) -> Answer {
  let reply = process.new_subject()
  case
    factory_supervisor.start_child(
      factory_supervisor.get_by_name(workers.factory),
      Job(db:, command:, reply:),
    )
  {
    Error(why) -> {
      log.error(
        log.Who(
          account: None,
          actor: None,
          place: Some(log.Process("store_worker")),
          message: None,
          peer: None,
        ),
        "a store worker did not start: " <> describe(why),
      )
      Unavailable
    }
    Ok(started) -> {
      let monitor = process.monitor(started.pid)
      let selector =
        process.new_selector()
        |> process.select(reply)
        |> process.select_specific_monitor(monitor, fn(_down) { Gone })
      let answer = wait_for_connection(selector:, pid: started.pid, within_ms:)
      process.demonitor_process(monitor)
      answer
    }
  }
}

/// Waits for the worker's report within `within_ms`: its answer, its end, or
/// the word that it holds a connection, which is answered with the word to go.
/// A worker that has said nothing at the deadline has sent nothing to Postgres,
/// because it sends nothing before it is told to go, so it is killed.
fn wait_for_connection(
  selector selector: process.Selector(Report),
  pid pid: process.Pid,
  within_ms within_ms: Int,
) -> Answer {
  case process.selector_receive(selector, within: within_ms) {
    Ok(Answered(answer)) -> answer
    Ok(Gone) -> Unavailable
    Ok(Holding(go:)) -> {
      process.send(go, Nil)
      wait_for_answer(selector:)
    }
    Error(Nil) -> {
      process.kill(pid)
      Unavailable
    }
  }
}

/// Waits up to `pool.holding_wait_ms` for the answer of a worker that was told
/// to go. The worker is not killed when the time is up: its transaction may be
/// at its commit, and it ends by itself when Postgres ends the transaction. An
/// answer that has not come by then is `Unknown`.
fn wait_for_answer(selector selector: process.Selector(Report)) -> Answer {
  case process.selector_receive(selector, within: pool.holding_wait_ms()) {
    Ok(Answered(answer)) -> answer
    Ok(Gone) | Ok(Holding(..)) -> Unavailable
    Error(Nil) -> Unknown
  }
}
