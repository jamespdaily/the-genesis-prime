//// What the tests of asks, of the service shell and of the account store
//// share: a listener whose connections run the asking rule, a gate service
//// the connections ask, the directory that reaches both the gate and the
//// store, and a client that sends the rule's commands and reads its records.

import asking_rule.{
  type Answer, type Request, FromGate, FromStore, OfGate, OfStore,
}
import gate_rule
import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/connection/script
import genesis_prime/connection/shell
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type ConnectionRule, type ServiceRule, Rule}
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
  rule rule: ConnectionRule(settings, state, request, Nil, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  start_joined(
    rule:,
    directory:,
    shutdown_ms:,
    recorder:,
    registry: None,
    locate: fn(_address) { Error(Nil) },
    with:,
  )
}

/// Starts a listener as `start` does, whose connections also join `registry`
/// when there is one, and find what their rule watches with `locate`.
pub fn start_joined(
  rule rule: ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder),
  registry registry: Option(Registry),
  locate locate: service.Locate,
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  let name = process.new_name("test_listener")
  let connection =
    shell.Settings(
      rule:,
      send_deadline_ms: 300,
      shutdown_ms:,
      recorder:,
      wire_recorder: None,
      scripts: script.operating_system,
      directory:,
      registry:,
      locate:,
    )
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> with
    |> supervisor.add(
      listener.supervised(Listener(
        name:,
        port: 0,
        max_connections: 1000,
        connection:,
      )),
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
  guard_with(tree, fn() {
    let _reason = stop_tree(tree)
    Nil
  })
}

/// As `guard`, for a tree that is not the caller's child, which `stop` ends in
/// the way its parent does.
pub fn guard_with(tree: Pid, stop: fn() -> Nil) -> Nil {
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
        OwnerEnded -> stop()
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

/// Runs `body` with the process suspended, so what `body` sends it queues in
/// the order it is sent and nothing is taken until `body` returns, when the
/// process is resumed.
pub fn while_suspended(process process: Pid, body body: fn() -> a) -> a {
  let assert True = suspend_process(process) as "the process was suspended"
  let result = body()
  let assert True = resume_process(process) as "the process was resumed"
  result
}

/// Stops the process from running until it is resumed.
@external(erlang, "erlang", "suspend_process")
pub fn suspend_process(process: Pid) -> Bool

@external(erlang, "erlang", "resume_process")
fn resume_process(process: Pid) -> Bool

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
  read_bytes(client:, bytes: 2)
}

/// Reads exactly `bytes` bytes the server wrote.
pub fn read_bytes(client client: mug.Socket, bytes bytes: Int) -> BitArray {
  let assert Ok(received) =
    mug.receive_exact(
      client,
      byte_size: bytes,
      timeout_milliseconds: event_wait_ms,
    )
    as "the bytes arrived"
  received
}

/// The server's connection processes, as Ranch lists them.
pub fn connections(server: Server) -> List(Pid) {
  connections_of(server.name)
}

/// The connection processes of the listener Ranch knows by `listener`.
pub fn connections_of(listener: Name(Nil)) -> List(Pid) {
  procs(listener, atom.create("connections"))
}

/// The acceptor processes of the listener Ranch knows by `listener`.
pub fn acceptors_of(listener: Name(Nil)) -> List(Pid) {
  procs(listener, atom.create("acceptors"))
}

/// The most connections the listener Ranch knows by `listener` holds.
@external(erlang, "ranch", "get_max_connections")
pub fn max_connections_of(listener: Name(Nil)) -> Int

/// The gate as a child of a supervisor, registered as `name`, that reaches
/// no process.
pub fn gate(
  name name: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder),
) -> ChildSpecification(Nil) {
  reaching(
    name:,
    shutdown_ms:,
    recorder:,
    reach: service.Reach(
      locate: fn(_address) { Error(Nil) },
      send: fn(_to, _message) { Error(Nil) },
    ),
  )
}

/// The gate as a child of a supervisor, registered as `name`, that finds and
/// sends to the processes `reach` gives.
pub fn reaching(
  name name: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  recorder recorder: Option(Recorder),
  reach reach: service.Reach(gate_rule.Answer),
) -> ChildSpecification(Nil) {
  service_shell.supervised(
    name:,
    settings: service_shell.Settings(
      rule: gate_as_rule(),
      reach:,
      shutdown_ms:,
      recorder:,
    ),
  )
}

/// The gate's rule as its shell runs it.
fn gate_as_rule() -> ServiceRule(
  Nil,
  gate_rule.State,
  gate_rule.Message,
  gate_rule.Answer,
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
) -> fn(Request, Int, fn(Answer) -> Nil) -> Result(service.Sent, Nil) {
  fn(request, _deadline_ms, reply) {
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
