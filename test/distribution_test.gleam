//// The server runs as one node, so Erlang distribution is off, epmd is not
//// started, and the only ports that listen are the game's own. Each test
//// starts the entry point in a child operating system process the way a
//// release starts it (`released_node`) and asks the child what it is. Expected
//// values come from three places.
//// - The Erlang documentation: `erlang:node/0` returns `nonode@nohost` on a
////   node that is not alive, and a node is alive only when it is started with
////   `-name` or `-sname`, which starts the processes `net_kernel` and
////   `erl_epmd` (Erlang reference manual, "Distributed Erlang").
//// - The epmd documentation (`erl_epmd`, `epmd`): a node started with `-name`
////   or `-sname` starts an epmd if none runs and registers its name with it,
////   at the port in `ERL_EPMD_PORT`; `epmd -names` lists the registered names.
//// - The client: the ports the server's own listeners hold are auth 23115
////   (the code at `0x140c3adbc`), STS 6600 (`0x14000d3ca`) and the game
////   listener, whose port the auth hand-off `0x3DB` names and a start argument
////   sets.
////
//// Each case that must not happen is shown first on a child started the way
//// that makes it happen: a short name, an extra listener. Each child has a
//// database, an epmd port and listeners of its own, so the tests share
//// nothing.

import database_support
import gleam/int
import gleam/list
import gleam/string
import owned_test
import released_node.{
  type Failure, type Node, Difference, Exited, Idle, Lingering, Running, Server,
  ShortName, Start, Stopped, Unnamed,
}
import template_database

/// How long the tests wait for a child to start, report and end: the child's
/// own limit on its silence, plus its database and its end.
const child_deadline_ms = 60_000

/// The ports the server's own listeners hold in a test, in any order. Each
/// listener the server starts adds its port here, with the client address
/// that names it, as the test starts the child with the port as its start
/// argument; a port the server holds that is not here, or listed here and not
/// held, fails `only_the_games_ports_listen_test`. The server's tree starts
/// no listener, so the list is empty.
fn expected_listening_ports() -> List(Int) {
  []
}

pub fn a_node_started_as_a_release_starts_it_has_no_distribution_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Server,
    planted_listeners: 0,
  ))
  let node = unwrap(started)
  assert node.report.node == "nonode@nohost"
  assert node.report.net_kernel == Stopped
  assert node.report.epmd_client == Stopped
}

pub fn a_node_started_with_a_short_name_is_seen_to_run_distribution_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  let name = unique_name()
  use started <- released_node.run(Start(
    database:,
    naming: ShortName(name),
    program: Idle,
    planted_listeners: 0,
  ))
  let node = unwrap(started)
  assert string.starts_with(node.report.node, name <> "@")
    as "a node with a short name is not named by it"
  assert node.report.net_kernel == Running
  assert node.report.epmd_client == Running
}

pub fn the_server_refuses_to_start_with_distribution_on_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: ShortName(unique_name()),
    program: Server,
    planted_listeners: 0,
  ))
  let assert Error(Exited(status:, output:)) = started
    as "a server started with a short name gave a report"
  assert status == 1
  assert list.any(output, string.contains(_, "Erlang distribution is on"))
    as "the server did not say why it stopped"
}

pub fn only_the_games_ports_listen_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Server,
    planted_listeners: 0,
  ))
  let node = unwrap(started)
  assert released_node.compare_ports(
      observed: node.report.listening_ports,
      expected: expected_listening_ports(),
    )
    == Difference(unexpected: [], missing: [])
}

pub fn a_listener_the_server_did_not_start_is_caught_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Server,
    planted_listeners: 2,
  ))
  let node = unwrap(started)
  let Difference(unexpected:, missing:) =
    released_node.compare_ports(
      observed: node.report.listening_ports,
      expected: expected_listening_ports(),
    )
  assert list.length(unexpected) == 2
    as "the two planted listeners are not both seen"
  assert unexpected == node.report.listening_ports
  assert missing == []
}

pub fn a_game_port_that_does_not_listen_is_caught_test() -> Nil {
  use <- owned_test.run(5000)
  assert released_node.compare_ports(observed: [6600], expected: [23_115, 6600])
    == Difference(unexpected: [], missing: [23_115])
  assert released_node.compare_ports(observed: [], expected: [])
    == Difference(unexpected: [], missing: [])
}

pub fn the_server_does_not_start_or_register_with_epmd_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use started <- released_node.run(Start(
    database:,
    naming: Unnamed,
    program: Server,
    planted_listeners: 0,
  ))
  let node = unwrap(started)
  assert node.report.epmd_client == Stopped
  assert !released_node.epmd_answers(node)
    as "something started an epmd on the child's epmd port"
  assert released_node.epmd_names(node) == []
}

pub fn a_node_with_a_short_name_starts_epmd_and_is_listed_by_it_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  let name = unique_name()
  use started <- released_node.run(Start(
    database:,
    naming: ShortName(name),
    program: Idle,
    planted_listeners: 0,
  ))
  let node = unwrap(started)
  assert released_node.epmd_answers(node)
    as "a node with a short name did not start an epmd"
  assert released_node.epmd_names(node) == [name]
}

/// Issue 95: the harness's cleanup ran while a named child was still registered
/// with its epmd, and crashed on epmd's refusal ("Killing not allowed - living
/// nodes in database", the epmd documentation of `-kill`). The child here does
/// not end when its input closes, so it is registered whenever the cleanup
/// asks epmd to die; the cleanup must end it, wait for its exit and end its
/// epmd without a crash.
pub fn cleaning_up_while_a_named_child_is_registered_leaves_no_epmd_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  let name = unique_name()
  use started <- released_node.run(Start(
    database:,
    naming: ShortName(name),
    program: Lingering,
    planted_listeners: 0,
  ))
  let node = unwrap(started)
  assert released_node.epmd_names(node) == [name]
    as "the child is not registered with its epmd before the cleanup"
  released_node.clean_up(process: node.process, epmd_port: node.epmd_port)
  assert !released_node.epmd_answers(node)
    as "an epmd is left on the child's epmd port after the cleanup"
}

/// The node of a child that reported, or a crash that shows why it did not.
fn unwrap(started: Result(Node, Failure)) -> Node {
  let assert Ok(node) = started as "the child gave no report"
  node
}

/// A node name no other test uses.
fn unique_name() -> String {
  "released_" <> int.to_string(database_support.unique())
}
