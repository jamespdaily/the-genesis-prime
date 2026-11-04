//// Where the connections are found: OTP's `pg` (process groups). A group is
//// named by an address (genesis_prime/step `Address`), and there are three
//// kinds, each joined by connections only:
//// - `Connection(id)`: one member, the connection, joined as the shell accepts
////   it;
//// - `CharacterNamed(folded name)`: one member, the connection whose player
////   is in the world under that name, joined and left by the rule's
////   `JoinGroup` and `LeaveGroup` effects;
//// - `ZoneChannel(map, incarnation, top zone)`: every connection in that run
////   of the map whose player stands under that top zone, joined and left the
////   same way.
//// A member leaves a group by ending, which `pg` notices by itself; no process
//// keeps a list of connections and no atom is made per connection.
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
////   join_group(CharacterNamed(n)) ─▶ member of the group
////                          find_named(n)       ◀─ the group's first member
////   join_group(ZoneChannel(..)) ─▶ member of the group
////                          deliver_group(..)   ─▶ {woken, message} to each member
//// ```
////
//// - **Lookup.** `find` reads the scope's local members of the group: none
////   when the connection has ended or was never accepted, one otherwise. It
////   reads the scope's table and sends the scope no message.
//// - **A connection ending.** The scope monitors each member and drops it from
////   its groups; a `find` just after the end may still give the pid, and a
////   `deliver` to it is then dropped like any message to a process that ended.
//// - **A group of a name or a zone channel.** `find_named` gives the newest
////   member (`pg` lists the latest join first), none when no connection holds the
////   name. A takeover
////   can leave two members of one name for a moment, since the older login
////   leaves its group only as it ends; either may be found, and the older
////   one's end is its watcher's. `deliver_group` sends each member the message,
////   and none when the group is empty. A `leave_group` of a group the process
////   is not in does nothing.
//// - **The scope restarting.** The restarted scope has no members, so no
////   connection could be found. The supervisor is `rest_for_one`, with the
////   scope first, so the game listener restarts with it and every game client
////   is dropped and logs in again; the sessions watch each connection, so each
////   slot is freed (genesis_prime/account_session).
////
//// The scope is `genesis_prime/group_registry`'s, which holds the lookup, the
//// delivery and the name of the scope; this module names the groups of
//// connections and joins and leaves them for a connection's shell.

import genesis_prime/group_registry.{type Scope}
import genesis_prime/step.{type Address, type ConnectionId, Connection}
import gleam/erlang/process.{type Pid, type Selector}
import gleam/otp/supervision.{type ChildSpecification}

/// The scope connections are found in: made once, with `new`, and given to the
/// tree and to the shells that join it and look in it. `message` is the type
/// of what `deliver` sends to a connection and its shell's selector takes
/// (`select_delivered`), the message type of the connections' rule, so a
/// sender and a receiver of different types do not compile.
pub opaque type Registry(message) {
  Registry(scope: Scope(message))
}

/// A new registry, with a scope name no other registry has.
pub fn new() -> Registry(message) {
  Registry(scope: group_registry.new("connections"))
}

/// The scope as a permanent child of a supervisor.
pub fn supervised(registry: Registry(message)) -> ChildSpecification(Nil) {
  group_registry.supervised(registry.scope)
}

/// Makes the calling process the member of the connection's group; the
/// connection shell calls it once, as it accepts the connection.
pub fn join(
  registry registry: Registry(message),
  connection connection: ConnectionId,
) -> Nil {
  group_registry.join(registry.scope, Connection(connection:), process.self())
}

/// Makes the calling process a member of the group at `address`, a
/// `CharacterNamed` or a `ZoneChannel`; a process that is a member already stays
/// one, so a group holds it once. The connection shell calls it for the rule's
/// `JoinGroup`.
pub fn join_group(
  registry registry: Registry(message),
  address address: Address,
) -> Nil {
  group_registry.join(registry.scope, address, process.self())
}

/// Removes the calling process from the group at `address`; nothing happens
/// when it is not a member. The connection shell calls it for the rule's
/// `LeaveGroup`.
pub fn leave_group(
  registry registry: Registry(message),
  address address: Address,
) -> Nil {
  group_registry.leave(registry.scope, address, process.self())
}

/// The process of the connection whose player is in the world under the folded
/// name: the newest member of the group, or `Error(Nil)` when none is.
pub fn find_named(
  registry registry: Registry(message),
  folded_name folded_name: String,
) -> Result(Pid, Nil) {
  case
    group_registry.members(registry.scope, step.CharacterNamed(folded_name:))
  {
    [pid, ..] -> Ok(pid)
    [] -> Error(Nil)
  }
}

/// Sends every member of the group at `address` the message, each as a
/// `Woken` input of its shell; `Error(Nil)` when the group has no member, and
/// nothing is sent.
pub fn deliver_group(
  registry registry: Registry(message),
  address address: Address,
  message message: message,
) -> Result(Nil, Nil) {
  group_registry.deliver_all(registry.scope, address, message)
}

/// Sends the process `message` as `deliver` does, for a process `find_named`
/// gave.
pub fn deliver_to(pid pid: Pid, message message: message) -> Nil {
  group_registry.deliver_to(pid:, message:)
}

/// The process of a connection, or `Error(Nil)` when none is a member.
pub fn find(
  registry registry: Registry(message),
  connection connection: ConnectionId,
) -> Result(Pid, Nil) {
  group_registry.find(registry.scope, Connection(connection:))
}

/// Sends the connection's process `message`, which its shell takes as a
/// `Woken` input; `Error(Nil)` when no process is a member, and nothing is
/// sent.
pub fn deliver(
  registry registry: Registry(message),
  connection connection: ConnectionId,
  message message: message,
) -> Result(Nil, Nil) {
  group_registry.deliver_one(registry.scope, Connection(connection:), message)
}

/// Adds to a selector the messages `deliver` sends through the registry to the
/// process, each taken as `mapping(message)`, in the order it arrived among the
/// others the selector takes.
pub fn select_delivered(
  registry registry: Registry(message),
  selector selector: Selector(payload),
  mapping mapping: fn(message) -> payload,
) -> Selector(payload) {
  group_registry.select_delivered(registry.scope, selector, mapping)
}
