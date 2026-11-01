//// The readiness ask and what the server says of it. Expected values come
//// from these places.
//// - The card's tests: the ready line is printed only after one `select 1`
////   returned; with the database unreachable until the deadline the server
////   logs a warning "the database is unreachable", prints no ready line and
////   answers a login `Unavailable`, as it did before the ask existed; the
////   ask watches the server's tree, so a tree that ends is no unreachable
////   database.
//// - The store's answer for a database that is away is `Unavailable`
////   (`genesis_prime/store`), which the login maps to the client's refusal.
//// - The times are the server's choice (`genesis_prime`): the tests use shorter
////   ones so a database that never answers ends the ask in a fraction of a
////   second.

import application_support
import ask_support
import database_support
import genesis_prime
import genesis_prime/application
import genesis_prime/migration.{Migration, NotApplied, Recorded}
import genesis_prime/readiness
import genesis_prime/server
import genesis_prime/service.{type Sent, ToWorker}
import genesis_prime/step/runtime
import genesis_prime/store.{FindAccount, Login, Unavailable}
import genesis_prime/store/worker.{type Probed, Reached, Unreached}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/string
import log_capture
import login_support
import mailbox_support
import owned_test
import pog
import readiness_support

/// What a test sends the process that holds the probe's answer back: let it go.
type Release {
  Release
}

/// The ask's times in these tests: a quarter of a second in all.
fn short() -> readiness.Settings {
  readiness.Settings(within_ms: 250, attempt_ms: 100, pause_ms: 20)
}

pub fn the_ask_gives_ready_only_after_the_probe_is_answered_test() -> Nil {
  use <- owned_test.run(30_000)
  let held = process.new_subject()
  let outcomes = process.new_subject()
  let tree = process.spawn_unlinked(process.sleep_forever)
  let _asker =
    process.spawn_unlinked(fn() {
      process.send(
        outcomes,
        readiness.await(
          probe: fn(reply) { Ok(held_probe(held:, reply:)) },
          tree: process.monitor(tree),
          settings: patient(),
          files: [],
        ),
      )
    })
  let assert Ok(release) = process.receive(held, ask_support.event_wait_ms)
    as "the ask made its probe"
  assert process.receive(outcomes, 0) == Error(Nil)
    as "an unanswered probe gives no outcome"
  process.send(release, Release)
  assert process.receive(outcomes, ask_support.event_wait_ms)
    == Ok(readiness.Ready)
    as "the answer Reached gives Ready"
}

pub fn a_probe_that_reached_a_database_missing_a_migration_ends_the_ask_with_a_refusal_test() -> Nil {
  use <- owned_test.run(30_000)
  let tree = process.spawn_unlinked(process.sleep_forever)
  let first = Migration(name: "0000_first", sha256: string.repeat("a", 64))
  let second = Migration(name: "0001_second", sha256: string.repeat("b", 64))
  assert readiness.await(
      probe: fn(reply) {
        Ok(answering(
          reply:,
          probed: Reached(recorded: Recorded([first])),
          times: 1,
        ))
      },
      tree: process.monitor(tree),
      settings: short(),
      files: [first, second],
    )
    == readiness.MigrationsRefused(NotApplied("0001_second"))
    as "the database answered but lacks the second file's migration: the ask ends with the refusal, and does not ask again"
}

/// The ask's times when the test decides when the probe answers: the server's
/// own, 30 s in all.
fn patient() -> readiness.Settings {
  readiness.Settings(within_ms: 30_000, attempt_ms: 30_000, pause_ms: 20)
}

/// A probe worker that sends `held` the subject that lets it go, then answers
/// `Reached` once it has been let go.
fn held_probe(
  held held: Subject(Subject(Release)),
  reply reply: fn(Probed) -> Nil,
) -> Sent {
  let worker =
    process.spawn(fn() {
      let release = process.new_subject()
      process.send(held, release)
      let assert Ok(Release) = process.receive(release, 30_000)
        as "the test let the probe go"
      reply(Reached(recorded: Recorded([])))
    })
  ToWorker(pid: worker)
}

pub fn the_ask_ends_with_the_trees_end_when_the_tree_ends_while_it_waits_test() -> Nil {
  use <- owned_test.run(30_000)
  let tree = process.spawn_unlinked(process.sleep_forever)
  let asked = process.new_subject()
  let outcomes = process.new_subject()
  let _asker =
    process.spawn_unlinked(fn() {
      process.send(
        outcomes,
        readiness.await(
          probe: fn(_reply) {
            // A worker that never answers.
            let worker = process.spawn_unlinked(process.sleep_forever)
            process.send(asked, worker)
            Ok(ToWorker(pid: worker))
          },
          tree: process.monitor(tree),
          settings: readiness.Settings(
            within_ms: 30_000,
            attempt_ms: 30_000,
            pause_ms: 20,
          ),
          files: [],
        ),
      )
    })
  let assert Ok(worker) = process.receive(asked, ask_support.event_wait_ms)
    as "the ask made its probe"
  let worker_ended = process.monitor(worker)
  process.kill(tree)
  let assert Ok(readiness.TreeEnded(reason: process.Killed)) =
    process.receive(outcomes, ask_support.event_wait_ms)
    as "the tree's end, with its reason, ends the ask at once"
  let _reason = ask_support.ended(worker_ended)
  Nil
}

pub fn an_ask_the_database_never_answers_keeps_asking_until_its_time_runs_out_test() -> Nil {
  use <- owned_test.run(30_000)
  let asked = process.new_subject()
  let outcomes = process.new_subject()
  let tree = process.spawn_unlinked(process.sleep_forever)
  let started_ms = runtime.now().monotonic_ms
  let _asker =
    process.spawn_unlinked(fn() {
      process.send(
        outcomes,
        readiness.await(
          probe: fn(reply) {
            process.send(asked, Nil)
            Ok(answering(reply:, probed: Unreached, times: 1))
          },
          tree: process.monitor(tree),
          settings: short(),
          files: [],
        ),
      )
    })
  assert process.receive(outcomes, ask_support.event_wait_ms)
    == Ok(readiness.DatabaseUnreachable)
    as "no attempt reached the database, so the ask gives up"
  assert runtime.now().monotonic_ms - started_ms >= short().within_ms
    as "and only when its time has run out"
  assert count(asked) >= 5
    as "having asked again after each failure: a pause of 20 ms in 250 ms allows many more attempts than one"
}

/// How many messages wait in the subject.
fn count(subject: Subject(Nil)) -> Int {
  case process.receive(subject, 0) {
    Ok(Nil) -> 1 + count(subject)
    Error(Nil) -> 0
  }
}

/// A probe worker that answers `probed` `times` times at once and ends.
fn answering(
  reply reply: fn(Probed) -> Nil,
  probed probed: Probed,
  times times: Int,
) -> Sent {
  let worker =
    process.spawn_unlinked(fn() {
      list.repeat(Nil, times)
      |> list.each(fn(_) { reply(probed) })
    })
  ToWorker(pid: worker)
}

pub fn an_ask_leaves_no_answer_behind_in_its_mailbox_test() -> Nil {
  use <- owned_test.run(30_000)
  let outcomes = process.new_subject()
  let tree = process.spawn_unlinked(process.sleep_forever)
  let _asker =
    process.spawn_unlinked(fn() {
      let outcome =
        readiness.await(
          probe: fn(reply) {
            Ok(answering(reply:, probed: Unreached, times: 3))
          },
          tree: process.monitor(tree),
          settings: short(),
          files: [],
        )
      process.send(outcomes, #(outcome, mailbox_support.queued(process.self())))
    })
  assert process.receive(outcomes, ask_support.event_wait_ms)
    == Ok(#(readiness.DatabaseUnreachable, 0))
    as "the answers of each attempt beyond the one the ask took are dropped, so none stays in the mailbox of the process that asked"
}

/// A server on a database that does not exist as a server: its pool's port has
/// no Postgres, and its connection waits are short.
fn unreachable_settings() -> server.Settings {
  let shared = database_support.shared()
  login_support.settings(
    pool: database_support.config(
      for: shared.settings,
      database: "unreachable",
      pool_name: process.new_name("pool"),
      pool_size: 1,
    )
    |> pog.port(1)
    |> pog.queue_target(50)
    |> pog.queue_interval(100),
  )
}

/// What a process that serves a tree under the application's root sends the
/// test.
type Serving {
  Serving(serving: Pid, tree: Pid, said: Subject(String))
}

/// Starts the tree under the application's root with `settings` in a process
/// of its own, which serves it with the ask `ready` and the real probe,
/// saying the lines to the subject, and logs what it logs to `logged`.
fn serve_in_a_process(
  settings settings: server.Settings,
  ready ready: readiness.Settings,
  logged logged: Subject(#(String, String)),
) -> Serving {
  let said = process.new_subject()
  let started = process.new_subject()
  let waiting = process.new_subject()
  let serving =
    process.spawn_unlinked(fn() {
      let go = process.new_subject()
      process.send(waiting, go)
      let assert Ok(Nil) = process.receive(go, 5000) as "the test is ready"
      let assert Ok(tree) = application.start_server(settings:)
        as "the tree started under the application's root"
      process.send(started, tree.pid)
      genesis_prime.serve(
        tree:,
        settings:,
        tables: 7,
        ready:,
        probe: fn(reply) { worker.probe(store: settings.store, reply:) },
        migrations: genesis_prime.load_migrations(),
        say: fn(line) { process.send(said, line) },
      )
    })
  let assert Ok(go) = process.receive(waiting, ask_support.event_wait_ms)
    as "the process waits for the capture"
  let _capture = log_capture.start(from: serving, into: logged)
  process.send(go, Nil)
  let assert Ok(tree) = process.receive(started, ask_support.event_wait_ms)
    as "the process started the tree"
  application_support.guard(tree)
  Serving(serving:, tree:, said:)
}

/// Ends the process that serves, then stops the tree it started.
fn stop(serving: Serving) -> Nil {
  process.kill(serving.serving)
  application_support.stop(serving.tree)
}

pub fn a_database_that_does_not_answer_gets_a_warning_no_ready_line_and_a_login_answered_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  let settings = unreachable_settings()
  let logged = process.new_subject()
  let serving = serve_in_a_process(settings:, ready: short(), logged:)
  let assert Ok(#("warning", line)) =
    process.receive(logged, ask_support.event_wait_ms)
    as "the server logged a warning when the ask's time ran out"
  assert string.contains(line, "the database is unreachable")
  assert process.receive(serving.said, 0) == Error(Nil)
    as "no ready line was said: the ask gave up, and the line is said only on Ready"
  let #(_sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      worker.ask(
        settings.store,
        Login(request: FindAccount(login_name: "jim")),
        reply,
      )
    })
  assert answer == Unavailable
    as "a login's read of the store is answered Unavailable, as it was before the ask"
  stop(serving)
}

pub fn a_database_that_answers_gets_the_ready_line_once_the_probe_returns_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let settings =
    login_support.settings(pool: database_support.config(
      for: shared.settings,
      database: database_support.new_database(on: shared),
      pool_name: process.new_name("pool"),
      pool_size: 2,
    ))
  let serving =
    serve_in_a_process(
      settings:,
      ready: readiness_support.settings(),
      logged: process.new_subject(),
    )
  let assert Ok(line) = process.receive(serving.said, 30_000)
    as "the server said its ready line once the database answered"
  assert string.starts_with(line, "the server loaded 7 game tables and serves")
    as "the line names the tables the server loaded, as the live-play scripts read it"
  stop(serving)
}
