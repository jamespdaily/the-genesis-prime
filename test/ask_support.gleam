//// What the tests of asks, of the service shell and of the account store
//// share: a listener whose connections run the asking rule, a gate service
//// the connections ask, the directory that reaches both the gate and the
//// store, and a client that sends the rule's commands and reads its records.

import asking_rule.{
  type Answer, type Request, FromGate, FromStore, OfGate, OfStore,
}
import gate_rule
import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/shell
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type Rule, Rule}
import genesis_prime/store/worker.{type Job}
import gleam/erlang/atom
import gleam/erlang/process.{type Name, type Pid}
import gleam/option.{type Option, None, Some}
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import mug

/// How long one wait for an event may take, in milliseconds. A passing test
/// never reaches it.
pub const event_wait_ms = 5000

/// The wait, in milliseconds, of an ask whose answer is expected: a deadline
/// a passing test never reaches.
pub const patient = 20_000

/// A running listener and the tree it started under.
pub type Server {
  Server(supervisor: Pid, name: Name(Nil), port: Int)
}

/// One record the asking rule wrote.
pub type Record {
  Record(letter: Int, ask: Int, code: Int, extra: Int, milliseconds: Int)
}

/// Starts a listener whose connections run `rule` with this directory, beside
/// what `with` adds to the same supervisor. A test with a recorder passes it in
/// `recorder`.
pub fn start(
  rule rule: Rule(settings, state, Nil, answer, Nil, request),
  directory directory: fn(request, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  let name = process.new_name("test_listener")
  let connection =
    shell.Settings(
      rule:,
      send_deadline_ms: 300,
      shutdown_ms:,
      recorder:,
      directory:,
      registry: None,
      locate: fn(_address) { Error(Nil) },
    )
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> with
    |> supervisor.add(
      listener.supervised(Listener(name:, port: 0, connection:)),
    )
    |> supervisor.start
    as "the tree started"
  process.unlink(started.pid)
  guard(started.pid)
  let assert Ok(port) = listener.port(name) as "the listener has a port"
  Server(supervisor: started.pid, name:, port:)
}

/// Why a guardian wakes.
type Guarded {
  OwnerEnded
  TreeEnded
}

/// Stops the tree when the calling process ends, however it ends, so a test
/// whose assertion fails leaves no supervisor, listener or service running.
/// The tree is unlinked from the caller, since the caller does not trap the
/// exit its stop gives; a guardian of its own watches both.
pub fn guard(tree: Pid) -> Nil {
  let owner = process.self()
  let _guardian =
    process.spawn_unlinked(fn() {
      let selector =
        process.new_selector()
        |> process.select_specific_monitor(process.monitor(owner), fn(_down) {
          OwnerEnded
        })
        |> process.select_specific_monitor(process.monitor(tree), fn(_down) {
          TreeEnded
        })
      case process.selector_receive_forever(selector) {
        OwnerEnded -> {
          let _reason = stop_tree(tree)
          Nil
        }
        TreeEnded -> Nil
      }
    })
  Nil
}

/// Waits until a process other than `old` holds the name, and returns it. A
/// supervisor that restarts a service does so within milliseconds; the wait
/// is bounded, so a service that is never restarted fails the test.
pub fn await_new_pid(
  name name: Name(message),
  not old: Pid,
  within_ms within_ms: Int,
) -> Pid {
  case process.named(name) {
    Ok(pid) if pid != old -> pid
    Ok(_) | Error(Nil) ->
      case within_ms > 0 {
        True -> {
          process.sleep(1)
          await_new_pid(name:, not: old, within_ms: within_ms - 1)
        }
        False -> panic as "no other process took the name in time"
      }
  }
}

/// Sends the tree the exit the server's own stop sends, and watches it.
pub fn begin_stop_tree(tree: Pid) -> process.Monitor {
  let watched = process.monitor(tree)
  process.send_abnormal_exit(tree, atom.create("shutdown"))
  watched
}

/// Stops a tree as the server's stop does, and waits for it to end.
pub fn stop_tree(tree: Pid) -> process.ExitReason {
  ended(begin_stop_tree(tree))
}

/// Stops the server's tree and waits for it to end.
pub fn stop(server: Server) -> Nil {
  let _reason = stop_tree(server.supervisor)
  Nil
}

/// Why a process the server's stop ended exits: the atom `shutdown`.
pub fn shutdown() -> process.ExitReason {
  process.Abnormal(atom.to_dynamic(atom.create("shutdown")))
}

/// Waits for a watched process to end and says how.
pub fn ended(watched: process.Monitor) -> process.ExitReason {
  let assert Ok(down) =
    process.new_selector()
    |> process.select_specific_monitor(watched, fn(down) { down })
    |> process.selector_receive(within: event_wait_ms)
    as "the process ended"
  case down {
    process.ProcessDown(reason:, ..) -> reason
    process.PortDown(reason:, ..) -> reason
  }
}

pub fn connect(server: Server) -> mug.Socket {
  let assert Ok(client) =
    mug.new("127.0.0.1", port: server.port)
    |> mug.ip_version_preference(mug.Ipv4Only)
    |> mug.timeout(event_wait_ms)
    |> mug.connect
    as "the client connected"
  client
}

/// Sends one command of the asking rule.
pub fn command(
  client client: mug.Socket,
  letter letter: Int,
  n n: Int,
  wait_ms wait_ms: Int,
) -> Nil {
  let assert Ok(Nil) = mug.send(client, <<letter, n, wait_ms:16>>)
    as "the command was sent"
  Nil
}

/// Reads the next twelve-byte record the rule wrote.
pub fn read_record(client: mug.Socket) -> Record {
  let assert Ok(<<letter, ask, code, extra, milliseconds:64-signed>>) =
    mug.receive_exact(
      client,
      byte_size: 12,
      timeout_milliseconds: event_wait_ms,
    )
    as "a record arrived"
  Record(letter:, ask:, code:, extra:, milliseconds:)
}

/// Reads the pong the rule writes for a ping, two bytes.
pub fn read_pong(client: mug.Socket) -> BitArray {
  let assert Ok(pong) =
    mug.receive_exact(client, byte_size: 2, timeout_milliseconds: event_wait_ms)
    as "a pong arrived"
  pong
}

/// The server's connection processes, as Ranch lists them.
pub fn connections(server: Server) -> List(Pid) {
  procs(server.name, atom.create("connections"))
}

/// The gate as a child of a supervisor, registered as `name`.
pub fn gate(
  name name: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder),
) -> ChildSpecification(Nil) {
  service_shell.supervised(service_shell.Settings(
    rule: gate_as_rule(),
    name:,
    reach: service.Reach(
      locate: fn(_address) { Error(Nil) },
      send: fn(_to, _message) { Error(Nil) },
    ),
    shutdown_ms:,
    recorder:,
  ))
}

/// The gate's rule as its shell runs it.
fn gate_as_rule() -> Rule(
  Nil,
  gate_rule.State,
  gate_rule.Message,
  Nil,
  gate_rule.Answer,
  Nil,
) {
  Rule(
    name: "gate_rule",
    settings: Nil,
    new: gate_rule.new,
    step: gate_rule.step,
  )
}

/// How a connection reaches what its rule asks: the gate by `service.call`
/// and the store by `worker.ask`. A store that is `None` is not running. Each
/// request that reaches a process is reported to `sent`.
pub fn directory(
  gate gate: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  store store: Option(Name(factory_supervisor.Message(Job, Nil))),
  sent sent: fn(service.Sent) -> Nil,
) -> fn(Request, fn(Answer) -> Nil) -> Result(service.Sent, Nil) {
  fn(request, reply) {
    let reached = case request, store {
      OfGate(message), _ ->
        service.call(gate, message, fn(answer) { reply(FromGate(answer)) })
      OfStore(request), Some(name) ->
        worker.ask(name, request, fn(answer) { reply(FromStore(answer)) })
      OfStore(_), None -> Error(Nil)
    }
    case reached {
      Ok(reached) -> sent(reached)
      Error(Nil) -> Nil
    }
    reached
  }
}

/// Asks from the test and waits for the answer. `send` hands the reply to the
/// process asked, as a directory does, and says where it went; returns that
/// and the answer.
pub fn ask_and_wait(
  send send: fn(fn(answer) -> Nil) -> Result(service.Sent, Nil),
) -> #(service.Sent, answer) {
  let replies = process.new_subject()
  let assert Ok(sent) = send(fn(answer) { process.send(replies, answer) })
    as "the ask reached a process"
  let assert Ok(answer) = process.receive(replies, within: event_wait_ms)
    as "the process answered"
  #(sent, answer)
}

/// Asks the gate from the test, and waits for its answer.
pub fn call_gate(
  gate gate: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  message message: gate_rule.Message,
) -> gate_rule.Answer {
  let #(sent, answer) =
    ask_and_wait(send: fn(reply) { service.call(gate, message, reply) })
  let assert service.ToService(_) = sent as "the gate is a service"
  answer
}

/// Opens a key of the gate from the test, and returns how many callers were
/// waiting for it.
pub fn open_key(
  gate gate: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  key key: Int,
) -> Int {
  let assert gate_rule.Echoed(waiting) =
    call_gate(gate:, message: gate_rule.Open(key))
    as "opening a key is answered with the count of waiting callers"
  waiting
}

/// A directory that reports nothing.
pub fn unreported(_sent: service.Sent) -> Nil {
  Nil
}

@external(erlang, "ranch", "procs")
fn procs(ref: Name(Nil), kind: atom.Atom) -> List(Pid)

/// The test's own reading of the monotonic clock, in milliseconds, to set
/// beside the readings a shell takes.
pub fn monotonic_ms() -> Int {
  monotonic_time(atom.create("millisecond"))
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: atom.Atom) -> Int
