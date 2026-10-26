//// The workers that carry out character select's commands against the
//// database: one temporary process for each command, started under a
//// supervisor of the game subtree. The connection that asked waits for the
//// answer up to its deadline; a worker that has not answered by then is
//// killed and the answer is `Unavailable`. A worker that ends without
//// answering, such as one whose statement crashed, gives `Unavailable` at once.
//// A worker holds nothing between commands, so none is restarted.

import genesis_prime/character/select.{type Answer, type Command, Unavailable}
import genesis_prime/character/store
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

/// One command to carry out, with the connection to the database and where
/// the answer goes.
pub opaque type Job {
  Job(db: pog.Connection, command: Command, reply: Subject(Answer))
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
  process.send(job.reply, store.run(job.db, job.command))
  actor.stop()
}

fn describe(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "it did not start in time"
    actor.InitFailed(reason) -> reason
    actor.InitExited(_) -> "it ended as it started"
  }
}

/// Carries out the command in a worker and waits up to `within_ms`
/// milliseconds for the answer. A worker that does not start, ends without
/// answering or is too slow gives `Unavailable`.
pub fn run(
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
      let outcome =
        process.new_selector()
        |> process.select(reply)
        |> process.select_specific_monitor(monitor, fn(_down) { Unavailable })
        |> process.selector_receive(within: within_ms)
      process.demonitor_process(monitor)
      case outcome {
        Ok(answer) -> answer
        Error(Nil) -> {
          process.kill(started.pid)
          Unavailable
        }
      }
    }
  }
}
