//// The top supervisor owns every process the server starts. Expected values
//// are the designing-processes skill's rule that every process is started
//// under a supervisor: a test starts the top supervisor, then every process
//// started since is in its tree, found through its children. The check is
//// `spawn_watch.unsupervised`, shown first on planted supervisors, one whose
//// child also starts an unlinked process and one whose child does not.

import genesis_prime/server
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import owned_test
import spawn_watch
import template_database

pub fn every_process_the_server_starts_is_in_the_top_supervisors_tree_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("server_test_pool"),
      pool_size: 2,
    )
  let watch = spawn_watch.begin()
  let assert Ok(started) = server.start(settings)
    as "the top supervisor did not start"
  assert spawn_watch.unsupervised(watch, started.pid) == []
}

pub fn a_process_started_beside_the_tree_is_found_outside_it_test() -> Nil {
  use <- owned_test.run(5000)
  let strays = process.new_subject()
  let watch = spawn_watch.begin()
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(
      supervision.worker(fn() { start_child_with_stray(strays) }),
    )
    |> static_supervisor.start
    as "the planted supervisor did not start"
  let assert Ok(stray) = process.receive(strays, 0)
    as "the planted child did not report its stray"
  assert spawn_watch.unsupervised(watch, started.pid) == [stray]
  process.kill(stray)
}

pub fn a_tree_whose_children_start_nothing_beside_it_has_no_stray_test() -> Nil {
  use <- owned_test.run(5000)
  let watch = spawn_watch.begin()
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(supervision.worker(start_child))
    |> static_supervisor.add(supervision.worker(start_child))
    |> static_supervisor.start
    as "the planted supervisor did not start"
  assert spawn_watch.unsupervised(watch, started.pid) == []
}

pub fn a_process_in_a_nested_supervisors_tree_is_not_a_stray_test() -> Nil {
  use <- owned_test.run(5000)
  let watch = spawn_watch.begin()
  let inner =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(supervision.worker(start_child))
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(static_supervisor.supervised(inner))
    |> static_supervisor.start
    as "the planted supervisor did not start"
  assert spawn_watch.unsupervised(watch, started.pid) == []
}

pub fn a_supervision_tree_a_worker_owns_is_not_a_stray_test() -> Nil {
  use <- owned_test.run(5000)
  let watch = spawn_watch.begin()
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(supervision.worker(start_child_with_own_tree))
    |> static_supervisor.start
    as "the planted supervisor did not start"
  assert spawn_watch.unsupervised(watch, started.pid) == []
}

fn start_child() -> Result(actor.Started(Subject(Nil)), actor.StartError) {
  actor.new(Nil)
  |> actor.on_message(fn(state, _message: Nil) { actor.continue(state) })
  |> actor.start
}

/// A child that is supervised, and that also starts a process nothing owns,
/// reporting its pid to the test so the test can stop it.
fn start_child_with_stray(
  strays: Subject(Pid),
) -> Result(actor.Started(Subject(Nil)), actor.StartError) {
  process.send(strays, process.spawn_unlinked(fn() { process.sleep_forever() }))
  start_child()
}

/// A worker that is not a supervisor and that starts a supervisor of its own,
/// with a child, from its initialiser, as the database pool does.
fn start_child_with_own_tree() -> Result(
  actor.Started(Subject(Nil)),
  actor.StartError,
) {
  actor.new_with_initialiser(1000, fn(subject) {
    let assert Ok(_) =
      static_supervisor.new(static_supervisor.OneForOne)
      |> static_supervisor.add(supervision.worker(start_child))
      |> static_supervisor.start
      as "the worker's own supervisor did not start"
    Ok(actor.initialised(Nil) |> actor.returning(subject))
  })
  |> actor.on_message(fn(state, _message: Nil) { actor.continue(state) })
  |> actor.start
}
