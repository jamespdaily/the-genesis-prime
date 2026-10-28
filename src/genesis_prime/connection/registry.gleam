//// Where the connections are found: OTP's `pg` (process groups), one group
//// per connection, named by the address `Connection(id)`. A connection joins
//// its group as the shell accepts it, and leaves it by ending, which `pg`
//// notices by itself; no process keeps a list of connections and no atom is
//// made per connection.
////
//// ```
//// game supervisor (rest_for_one, 3 restarts in 10 s)
////  ├─ registry: the `pg` scope, a gen_server       permanent, 1 s to stop
////  └─ game listener: a connection shell per client
////
//// connection shell   pg scope                       another shell
////   join(Connection(id)) ─▶ member of the group
////                          find(Connection(id)) ◀─ the group's one member
////                          deliver(.., message)    ─▶ {woken, message} to it
//// ```
////
//// - **Lookup.** `find` reads the scope's local members of the group: none
////   when the connection has ended or was never accepted, one otherwise. It
////   reads the scope's table and sends the scope no message.
//// - **A connection ending.** The scope monitors each member and drops it from
////   its groups; a `find` just after the end may still give the pid, and a
////   `deliver` to it is then dropped like any message to a process that ended.
//// - **The scope restarting.** The restarted scope has no members, so no
////   connection could be found. The supervisor is `rest_for_one`, with the
////   scope first, so the game listener restarts with it and every game client
////   is dropped and logs in again; the sessions watch each connection, so each
////   slot is freed (genesis_prime/sessions).
//// - **The name.** The scope is named by an atom made once at start with
////   `process.new_name`, so each tree has its own scope and none is shared.

import genesis_prime/step.{type ConnectionId, Connection}
import gleam/erlang/process.{type Name, type Pid}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// How long the scope has to stop once the supervisor stops it.
const shutdown_ms = 1000

/// The scope connections are found in: made once, with `new`, and given to the
/// tree and to the shells that join it and look in it.
pub opaque type Registry {
  Registry(scope: Name(Nil))
}

/// Why the scope could not start, as `pg` reported it.
type StartFailure {
  CouldNotStart(reason: String)
}

/// A new registry, with a scope name no other registry has.
pub fn new() -> Registry {
  Registry(scope: process.new_name("connections"))
}

/// The scope as a permanent child of a supervisor.
pub fn supervised(registry: Registry) -> ChildSpecification(Nil) {
  supervision.worker(fn() {
    case start_scope(registry.scope) {
      Ok(pid) -> Ok(actor.Started(pid:, data: Nil))
      Error(CouldNotStart(reason:)) -> Error(actor.InitFailed(reason))
    }
  })
  |> supervision.restart(supervision.Permanent)
  |> supervision.timeout(ms: shutdown_ms)
}

/// Makes the calling process the member of the connection's group; the
/// connection shell calls it once, as it accepts the connection.
pub fn join(
  registry registry: Registry,
  connection connection: ConnectionId,
) -> Nil {
  join_group(registry.scope, Connection(connection:))
}

/// The process of a connection, or `Error(Nil)` when none is a member.
pub fn find(
  registry registry: Registry,
  connection connection: ConnectionId,
) -> Result(Pid, Nil) {
  case members(registry.scope, Connection(connection:)) {
    [pid] -> Ok(pid)
    [] -> Error(Nil)
    [_, _, ..] ->
      panic as "a connection id is joined by one process; the shell takes a fresh one for each connection"
  }
}

/// Sends the connection's process `message`, which its shell takes as a
/// `Woken` input; `Error(Nil)` when no process is a member, and nothing is
/// sent. The connection's rule fixes the message's type.
pub fn deliver(
  registry registry: Registry,
  connection connection: ConnectionId,
  message message: message,
) -> Result(Nil, Nil) {
  case find(registry:, connection:) {
    Ok(pid) -> {
      send_woken(pid, message)
      Ok(Nil)
    }
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "connection_registry_ffi", "start_scope")
fn start_scope(scope: Name(Nil)) -> Result(Pid, StartFailure)

@external(erlang, "connection_registry_ffi", "join_group")
fn join_group(scope: Name(Nil), group: step.Address) -> Nil

@external(erlang, "connection_registry_ffi", "members")
fn members(scope: Name(Nil), group: step.Address) -> List(Pid)

@external(erlang, "connection_registry_ffi", "send_woken")
fn send_woken(pid: Pid, message: message) -> Nil
