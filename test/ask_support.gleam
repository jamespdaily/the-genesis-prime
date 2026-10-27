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
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type Rule, Rule}
import genesis_prime/store/worker.{type Job}
import gleam/bit_array
import gleam/crypto
import gleam/erlang/atom
import gleam/erlang/process.{type Name, type Pid}
import gleam/option.{type Option, None, Some}
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/string
import mug

/// How long one wait for an event may take, in milliseconds. A passing test
/// never reaches it.
pub const event_wait_ms = 5000

/// The wait, in milliseconds, of an ask whose answer is expected: a deadline
/// a passing test never reaches.
pub const patient = 20_000

/// The letters of the asking rule's commands.
pub const echo_command = 0x45

pub const await_command = 0x57

pub const open_command = 0x4F

pub const ignore_command = 0x49

pub const crash_command = 0x43

pub const store_command = 0x53

pub const ping_command = 0x50

/// A running listener and the tree it started under.
pub type Server {
  Server(supervisor: Pid, name: String, port: Int)
}

/// One record the asking rule wrote.
pub type Record {
  Record(letter: Int, ask: Int, code: Int, extra: Int, milliseconds: Int)
}

/// Starts a listener whose connections run the asking rule with this
/// directory, beside what `with` adds to the same supervisor. A test with
/// another recorder passes it in `recorder`.
pub fn start(
  directory directory: fn(Request, fn(Answer) -> Nil) ->
    Result(service_shell.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder(Nil)),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  let name =
    "test-"
    <> string.lowercase(bit_array.base16_encode(crypto.strong_random_bytes(8)))
  let connection =
    shell.Settings(
      rule: asking_rule.rule(),
      send_deadline_ms: 300,
      shutdown_ms:,
      recorder:,
      directory:,
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
  let assert Ok(port) = listener.port(name) as "the listener has a port"
  Server(supervisor: started.pid, name:, port:)
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

/// Sends the server's tree the exit the server's own stop sends, and watches
/// it.
pub fn begin_stop(server: Server) -> process.Monitor {
  begin_stop_tree(server.supervisor)
}

/// Stops the server's tree and waits for it to end.
pub fn stop(server: Server) -> Nil {
  let _reason = stop_tree(server.supervisor)
  Nil
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
  name name: Name(service_shell.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder(Nil)),
) -> ChildSpecification(Nil) {
  service_shell.supervised(service_shell.Settings(
    rule: gate_as_rule(),
    name:,
    shutdown_ms:,
    recorder:,
  ))
}

/// The gate's rule as its shell runs it.
pub fn gate_as_rule() -> Rule(
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

/// How a connection reaches what its rule asks: the gate by `service_shell.call`
/// and the store by `worker.ask`. A store that is `None` is not running. Each
/// request that reaches a process is reported to `sent`.
pub fn directory(
  gate gate: Name(service_shell.Call(gate_rule.Message, gate_rule.Answer)),
  store store: Option(Name(factory_supervisor.Message(Job, Nil))),
  sent sent: fn(service_shell.Sent) -> Nil,
) -> fn(Request, fn(Answer) -> Nil) -> Result(service_shell.Sent, Nil) {
  fn(request, reply) {
    let reached = case request, store {
      OfGate(message), _ ->
        service_shell.call(gate, message, fn(answer) { reply(FromGate(answer)) })
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

/// Asks the gate from the test, and waits for its answer.
pub fn call_gate(
  gate gate: Name(service_shell.Call(gate_rule.Message, gate_rule.Answer)),
  message message: gate_rule.Message,
) -> gate_rule.Answer {
  let replies = process.new_subject()
  let assert Ok(service_shell.ToService(_)) =
    service_shell.call(gate, message, fn(answer) {
      process.send(replies, answer)
    })
    as "the gate runs"
  let assert Ok(answer) = process.receive(replies, within: event_wait_ms)
    as "the gate answered"
  answer
}

/// Opens a key of the gate from the test, and returns how many callers were
/// waiting for it.
pub fn open_key(
  gate gate: Name(service_shell.Call(gate_rule.Message, gate_rule.Answer)),
  key key: Int,
) -> Int {
  let assert gate_rule.Echoed(waiting) =
    call_gate(gate:, message: gate_rule.Open(key))
    as "opening a key is answered with the count of waiting callers"
  waiting
}

/// A directory that reports nothing.
pub fn unreported(_sent: service_shell.Sent) -> Nil {
  Nil
}

@external(erlang, "ranch", "procs")
fn procs(ref: String, kind: atom.Atom) -> List(Pid)
