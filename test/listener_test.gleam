//// A listener's port and its closing to new sockets
//// (`genesis_prime/connection/listener`). Expected values come from these
//// places.
//// - Ranch: `ranch:get_port/1` gives the listener's port, and `undefined` once
////   `ranch:suspend_listener/1` has closed its socket (the address is set to
////   `{undefined, undefined}`); a name no listener holds is not in Ranch's
////   table, so both calls fail with `badarg`. `suspend_listener` of a listener
////   already suspended is `ok`.
//// - The listener's contract in its doc comment: `stop_accepting` refuses a new
////   connect, and its connections end within the connection settings'
////   `shutdown_ms`, which Ranch holds as its `shutdown` transport option.

import ask_support
import driven_time
import genesis_prime/connection/listener.{
  ListenerNotListening, ListenerNotRunning,
}
import gleam/erlang/process
import mug
import owned_test

pub fn a_name_no_listener_holds_has_no_port_and_cannot_be_closed_test() -> Nil {
  use <- owned_test.run(10_000)
  let nobody = process.new_name("no_listener")
  assert listener.port(nobody) == Error(ListenerNotRunning)
    as "Ranch has no listener under a fresh name"
  assert listener.stop_accepting(nobody) == Error(ListenerNotRunning)
    as "Ranch has no listener under a fresh name"
}

pub fn a_listener_that_stopped_accepting_has_no_port_and_closing_it_again_is_ok_test() -> Nil {
  use <- owned_test.run(10_000)
  let server = ask_support.started_listener(time: driven_time.new())
  assert listener.port(server.name) == Ok(server.port)
    as "a running listener gives the port it listens on"
  assert listener.stop_accepting(server.name) == Ok(Nil)
    as "Ranch closes the listener's socket"
  assert listener.port(server.name) == Error(ListenerNotListening)
    as "ranch:get_port gives undefined for a closed socket, which is no port"
  assert listener.stop_accepting(server.name) == Ok(Nil)
    as "a listener already closed is closed"
  ask_support.stop(server)
}

pub fn a_listener_ends_its_connections_within_the_shutdown_time_of_its_connection_settings_test() -> Nil {
  use <- owned_test.run(10_000)
  let server = ask_support.started_listener(time: driven_time.new())
  assert ask_support.shutdown_ms_of(server.name)
    == 2 * ask_support.beyond_the_test_ms
    as "Ranch's connection supervisor kills a connection that has not stopped by the shutdown time the listener's connection settings give (ask_support.driven_settings: twice beyond_the_test_ms)"
  ask_support.stop(server)
}

pub fn a_listener_that_stopped_accepting_refuses_a_new_connect_test() -> Nil {
  use <- owned_test.run(10_000)
  let server = ask_support.started_listener(time: driven_time.new())
  assert listener.stop_accepting(server.name) == Ok(Nil)
  let refused = ask_support.connecting(port: server.port)
  assert refused == Error(mug.ConnectFailedIpv4(mug.Econnrefused))
    as "the listening socket is closed, so the system refuses the connect"
  ask_support.stop(server)
}
