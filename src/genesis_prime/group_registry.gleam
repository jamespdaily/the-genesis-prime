//// OTP's `pg` (process groups) as a registry typed by the message its members
//// take: the one scope module the connection registry
//// (genesis_prime/connection/registry) and the creature registry
//// (genesis_prime/world_map/creature_registry) are made of. A group is named by an
//// address (genesis_prime/step `Address`); a process joins a group, and the scope
//// drops it from every group when it ends, so no process keeps a list of members
//// and no atom is made for a group.
////
//// ```
//// supervisor            scope                         a member's shell
////   supervised(scope) ─▶ pg scope, a gen_server
//// a member:  join(scope, group, pid) ─▶ member of the group
//// a sender:  find(scope, group)       ◀─ the group's one member
////            deliver_one(scope, group, message) ─▶ {woken, message} to it
////            deliver_all(scope, group, message) ─▶ {woken, message} to each member
//// the shell: select_delivered(scope, selector, mapping) ─▶ takes {woken, message}
//// ```
////
//// - **The message type** of a scope is the type of what `deliver_*` sends and
////   the shell's selector takes (`select_delivered`), so a sender and a receiver
////   of different types do not compile. It is a phantom type, as the message type
////   of `process.Name`.
//// - **A group of one.** `find` is for a group that holds one member by
////   construction (a connection's id, a creature's unit); two members is a bug,
////   and crashes the caller.
//// - **A member ending** leaves its groups by itself; a `find` just after the end
////   may still give the pid, and a delivery to it is then dropped like any message
////   to a process that ended.
//// - **The scope restarting.** The restarted scope has no members, so the
////   supervisor that starts it restarts what joined it before.
//// - **The name.** The scope is named by an atom made once at start with
////   `process.new_name`, so each tree has its own scope and none is shared.

import genesis_prime/step.{type Address}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Selector}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// How long the scope has to stop once the supervisor stops it.
const shutdown_ms = 1000

/// A scope of groups whose members take `message`, made once with `new` and
/// given to the tree and to the processes that join it and look in it.
pub opaque type Scope(message) {
  Scope(name: Name(Nil))
}

/// Why the scope could not start, as `pg` reported it.
type StartFailure {
  CouldNotStart(reason: String)
}

/// A new scope, with a name no other scope has; `label` names it in the logs.
pub fn new(label label: String) -> Scope(message) {
  Scope(name: process.new_name(label))
}

/// The scope as a permanent child of a supervisor.
pub fn supervised(scope scope: Scope(message)) -> ChildSpecification(Nil) {
  supervision.worker(fn() {
    case start_scope(scope.name) {
      Ok(pid) -> Ok(actor.Started(pid:, data: Nil))
      Error(CouldNotStart(reason:)) -> Error(actor.InitFailed(reason))
    }
  })
  |> supervision.restart(supervision.Permanent)
  |> supervision.timeout(ms: shutdown_ms)
}

/// Makes the process a member of the group at `group`; a process that is a member
/// already stays one, so a group holds it once.
pub fn join(
  scope scope: Scope(message),
  group group: Address,
  pid pid: Pid,
) -> Nil {
  pg_join_once(scope.name, group, pid)
}

/// Removes the process from the group at `group`; nothing happens when it is not
/// a member.
pub fn leave(
  scope scope: Scope(message),
  group group: Address,
  pid pid: Pid,
) -> Nil {
  pg_leave(scope.name, group, pid)
}

/// The members of the group on this node, the latest to join first.
pub fn members(scope scope: Scope(message), group group: Address) -> List(Pid) {
  pg_members(scope.name, group)
}

/// The process of a group that holds one, or `Error(Nil)` when none is a member.
pub fn find(
  scope scope: Scope(message),
  group group: Address,
) -> Result(Pid, Nil) {
  case members(scope:, group:) {
    [pid] -> Ok(pid)
    [] -> Error(Nil)
    [_, _, ..] ->
      panic as "a group that holds one process holds two; its address is given to one process each"
  }
}

/// Sends the member of a group of one the message, which its shell takes as a
/// delivered input; `Error(Nil)` when no process is a member, and nothing is
/// sent.
pub fn deliver_one(
  scope scope: Scope(message),
  group group: Address,
  message message: message,
) -> Result(Nil, Nil) {
  case find(scope:, group:) {
    Ok(pid) -> {
      deliver_to(pid:, message:)
      Ok(Nil)
    }
    Error(Nil) -> Error(Nil)
  }
}

/// Sends every member of the group the message; `Error(Nil)` when the group has
/// none, and nothing is sent.
pub fn deliver_all(
  scope scope: Scope(message),
  group group: Address,
  message message: message,
) -> Result(Nil, Nil) {
  case members(scope:, group:) {
    [] -> Error(Nil)
    pids -> {
      list.each(pids, fn(pid) { deliver_to(pid:, message:) })
      Ok(Nil)
    }
  }
}

/// Sends the process the message as `deliver_one` does, for a process a lookup
/// gave.
pub fn deliver_to(pid pid: Pid, message message: message) -> Nil {
  send_woken(pid, message)
}

/// Adds to a selector what `deliver_*` sends to the process, each taken as
/// `mapping(message)`, in the order it arrived among the others the selector
/// takes. The scope is not read: it fixes the message's type.
pub fn select_delivered(
  scope _scope: Scope(message),
  selector selector: Selector(payload),
  mapping mapping: fn(message) -> payload,
) -> Selector(payload) {
  process.select_record(selector, tag: Woken, fields: 1, mapping: fn(sent) {
    mapping(woken_message(sent))
  })
}

/// The first element of what `deliver_*` sends: the atom `woken`, which
/// `genesis_prime_group_registry_ffi:send_woken` writes the same way.
type DeliveryTag {
  Woken
}

@external(erlang, "genesis_prime_group_registry_ffi", "start_scope")
fn start_scope(scope: Name(Nil)) -> Result(Pid, StartFailure)

@external(erlang, "genesis_prime_group_registry_ffi", "join_once")
fn pg_join_once(scope: Name(Nil), group: Address, pid: Pid) -> Nil

@external(erlang, "genesis_prime_group_registry_ffi", "leave")
fn pg_leave(scope: Name(Nil), group: Address, pid: Pid) -> Nil

@external(erlang, "genesis_prime_group_registry_ffi", "members")
fn pg_members(scope: Name(Nil), group: Address) -> List(Pid)

@external(erlang, "genesis_prime_group_registry_ffi", "send_woken")
fn send_woken(pid: Pid, message: message) -> Nil

@external(erlang, "genesis_prime_group_registry_ffi", "woken_message")
fn woken_message(sent: Dynamic) -> message
