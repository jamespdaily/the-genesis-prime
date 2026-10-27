//// The released-node harness starts the server as a release does, so what a
//// child reports after its first report is what the server is, not what a
//// bare call of `genesis_prime:main()` leaves behind. Expected values come
//// from two places.
//// - The start of a release: Gleam's generated entry point
////   (`genesis_prime@@main.erl`, function `run_module`, from the Gleam
////   compiler 1.19.2) calls `application:ensure_all_started(genesis_prime)`
////   and only then `genesis_prime:main()`, so every application the
////   `genesis_prime.app` file lists, `pgo` and `pg_types` among them (`pog`
////   needs both), is running before the server's tree starts.
//// - The `pg_types` source (`pg_types.erl`, `update_map/3`): the database
////   pool's type server loads types with `application:get_key(pg_types,
////   modules)`, which is undefined unless the application is loaded, and the
////   type server crashes on it again and again until its supervisor gives up
////   (`pgo_pool_sup.erl`: `rest_for_one`, 5 restarts in 10 seconds), which
////   ends the pool and, at the top supervisor's own limit, the whole tree.
////
//// The case that must not happen is shown first on a child that starts
//// nothing (`Idle`), so the survey is seen to tell a tree that runs from one
//// that does not.

import gleam/list
import owned_test
import released_node.{
  type Failure, type Node, Answered, Idle, Running, Server, Start, Stopped,
  Unnamed,
}
import template_database
import unitest

/// How long the tests wait for a child to start, report, answer a survey and
/// end: the child's own limit on its silence, plus its database and its end.
const child_deadline_ms = 60_000

pub fn a_survey_of_a_node_that_runs_no_server_shows_no_tree_and_no_pool_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use <- unitest.tag("serial")
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Idle,
    planted_listeners: 0,
  ))
  let assert Ok(survey) = released_node.survey(unwrap(started))
    as "the child gave no survey"
  assert survey.tree == Stopped
  assert survey.query != Answered
  assert !list.contains(survey.applications, "pgo")
}

pub fn the_servers_tree_still_runs_after_its_report_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use <- unitest.tag("serial")
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Server,
    planted_listeners: 0,
  ))
  let assert Ok(survey) = released_node.survey(unwrap(started))
    as "the child gave no survey"
  assert #(survey.query, survey.tree) == #(Answered, Running)
    as "after its report the server's pool did not answer a query, or its tree had ended"
}

pub fn the_server_runs_with_the_applications_a_release_starts_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use <- unitest.tag("serial")
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Server,
    planted_listeners: 0,
  ))
  let assert Ok(survey) = released_node.survey(unwrap(started))
    as "the child gave no survey"
  list.each(["genesis_prime", "pgo", "pg_types"], fn(application) {
    assert list.contains(survey.applications, application)
      as { "the application " <> application <> " is not started" }
  })
}

/// The node of a child that reported, or a crash that shows why it did not.
fn unwrap(started: Result(Node, Failure)) -> Node {
  let assert Ok(node) = started as "the child gave no report"
  node
}
