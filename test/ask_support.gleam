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
import genesis_prime/connection/script.{type Scripts}
import genesis_prime/connection/shell
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{
  type Address, type ConnectionRule, type ServiceRule, Rule,
}
import genesis_prime/step/watch
import genesis_prime/store/worker.{type Job}
import genesis_prime/wire_recording/recorder.{type WireRecorder}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import mug
import open_wait
import socket_read

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
/// what `with` adds to the same supervisor.
pub fn start(
  rule rule: ConnectionRule(settings, state, request, Nil, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  start_joined(
    rule:,
    directory:,
    shutdown_ms:,
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
  registry registry: Option(Registry(message)),
  locate locate: service.Locate,
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  start_scripted(
    rule:,
    directory:,
    shutdown_ms:,
    wire_recorder: None,
    scripts: script.operating_system,
    registry:,
    locate:,
    with:,
  )
}

/// Starts a listener as `start_joined` does, whose connections are recorded on
/// the wire by `wire_recorder` and are given their scripts (seed, clock, timers)
/// by `scripts`.
pub fn start_scripted(
  rule rule: ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  wire_recorder wire_recorder: Option(WireRecorder),
  scripts scripts: Scripts,
  registry registry: Option(Registry(message)),
  locate locate: service.Locate,
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  start_telling(
    rule:,
    directory:,
    shutdown_ms:,
    wire_recorder:,
    scripts:,
    registry:,
    locate: fn(address) { result.map(locate(address), watch.Watched) },
    deliver: fn(_address, _request) { Error(Nil) },
    with:,
  )
}

/// Starts a listener as `start_scripted` does, whose connections find what
/// their rule watches with `locate`, which also gives the way to tell a
/// process the rule tells (`Tellable`), and send the connections their rule
/// tells with `deliver`.
pub fn start_telling(
  rule rule: ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  shutdown_ms shutdown_ms: Int,
  wire_recorder wire_recorder: Option(WireRecorder),
  scripts scripts: Scripts,
  registry registry: Option(Registry(message)),
  locate locate: fn(Address) -> Result(watch.Found(fn(request) -> Nil), Nil),
  deliver deliver: fn(Address, request) -> Result(Nil, Nil),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Server {
  let name = process.new_name("test_listener")
  let connection =
    shell.Settings(
      rule:,
      send_deadline_ms: 300,
      shutdown_ms:,
      wire_recorder:,
      scripts:,
      directory:,
      registry:,
      locate:,
      deliver:,
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
/// supervisor that restarts a service does so within milliseconds; the name has
/// no event to wait for, so it is read every millisecond. The wait has no limit
/// of its own: a service that is never restarted ends the test at its deadline,
/// naming this wait (`open_wait`).
pub fn await_new_pid(name name: Name(message), not old: Pid) -> Pid {
  open_wait.named("a process other than the old one to take its name", fn() {
    poll_for_new_pid(name:, not: old)
  })
}

fn poll_for_new_pid(name name: Name(message), not old: Pid) -> Pid {
  case process.named(name) {
    Ok(pid) if pid != old -> pid
    Ok(_) | Error(Nil) -> {
      process.sleep(1)
      poll_for_new_pid(name:, not: old)
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
  ended(watched: begin_stop_tree(tree), what: "the tree to end at its stop")
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

/// Waits for a watched process to end and says how. The wait has no limit of its
/// own: a process that does not end ends the test at its deadline, naming it
/// as `what` says (`open_wait`).
pub fn ended(
  watched watched: process.Monitor,
  what what: String,
) -> process.ExitReason {
  let down =
    open_wait.named(what, fn() {
      process.new_selector()
      |> process.select_specific_monitor(watched, fn(down) { down })
      |> process.selector_receive_forever
    })
  case down {
    process.ProcessDown(reason:, ..) -> reason
    process.PortDown(reason:, ..) -> reason
  }
}

/// Runs `work` in a process of its own that starts only once this process is
/// watching it, and says how it ended: a process that ended before the watch
/// began would end with `noproc`, whatever `work` does.
pub fn ended_running(work: fn() -> Nil) -> process.ExitReason {
  let ready = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      let go = process.new_subject()
      process.send(ready, go)
      let Nil =
        open_wait.received(from: go, what: "the test to release the process")
      work()
    })
  let go =
    open_wait.received(from: ready, what: "the process to wait to be released")
  let watched = process.monitor(worker)
  process.send(go, Nil)
  ended(watched:, what: "the process to end after its work")
}

/// What a process raised when it crashed: the error of the `{Error, Stacktrace}`
/// its exit carries. A panic's is the map of its `message`, `module`, `function`
/// and `line`; an Erlang `error(Term)`'s is the term.
pub fn raised(reason: process.ExitReason) -> Dynamic {
  let assert process.Abnormal(exit) = reason as "the process crashed"
  let assert Ok(error) =
    decode.run(exit, decode.field(0, decode.dynamic, decode.success))
    as "the exit of a crash holds its error first"
  error
}

/// The text a panic gave.
pub fn panic_message(raised: Dynamic) -> String {
  let message = atom.to_dynamic(atom.create("message"))
  let assert Ok(text) =
    decode.run(raised, decode.field(message, decode.string, decode.success))
    as "a panic's error holds its message"
  text
}

/// A client's connect to the listener on this machine at `port`, with a limit
/// far beyond the test's deadline (`beyond_the_test_ms`): the test's deadline
/// ends a connect that is never answered, and names it (`open_wait`).
pub fn connecting(port port: Int) -> Result(mug.Socket, mug.ConnectError) {
  open_wait.named("the listener's answer to the connect", fn() {
    mug.new("127.0.0.1", port:)
    |> mug.ip_version_preference(mug.Ipv4Only)
    |> mug.timeout(beyond_the_test_ms)
    |> mug.connect
  })
}

/// A client connected to the server's listener.
pub fn connect(server: Server) -> mug.Socket {
  let assert Ok(client) = connecting(port: server.port)
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
    socket_read.receive_exactly(
      socket: client,
      byte_size: 12,
      what: "the next record the server wrote",
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
    socket_read.receive_exactly(
      socket: client,
      byte_size: bytes,
      what: "the bytes the server wrote",
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
) -> ChildSpecification(Nil) {
  reaching(name:, shutdown_ms:, reach: reaching_nothing())
}

/// The gate as a child of a supervisor, registered as `name`, that finds and
/// sends to the processes `reach` gives.
pub fn reaching(
  name name: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  reach reach: service.Reach(gate_rule.Answer),
) -> ChildSpecification(Nil) {
  service_shell.supervised(name:, settings: gate_settings(shutdown_ms:, reach:))
}

/// What the gate's shell is started with: the gate's rule, the processes it
/// reaches and how long it has to stop.
fn gate_settings(
  shutdown_ms shutdown_ms: Int,
  reach reach: service.Reach(gate_rule.Answer),
) -> service_shell.Settings(
  Nil,
  gate_rule.State,
  gate_rule.Message,
  gate_rule.Answer,
) {
  service_shell.Settings(
    rule: gate_as_rule(),
    reach:,
    shutdown_ms:,
    found_at: None,
    time: service_shell.real_time(),
  )
}

/// A reach that finds no process and sends to none.
fn reaching_nothing() -> service.Reach(gate_rule.Answer) {
  service.watch_only(locate: fn(_address) { Error(Nil) })
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

/// The gate as `gate` makes it, whose shell hands each input it takes to `into`
/// as it takes it: a test's own reading of what the shell fed the rule, in the
/// order it took the inputs.
pub fn observed_gate(
  name name: Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  into into: Subject(step.Event(step.ServiceEvent(gate_rule.Message))),
) -> ChildSpecification(Nil) {
  let settings = gate_settings(shutdown_ms:, reach: reaching_nothing())
  service_shell.supervised(
    name:,
    settings: service_shell.Settings(
      ..settings,
      rule: Rule(
        ..settings.rule,
        step: fn(state, input: step.ServiceInput(gate_rule.Message)) {
          process.send(into, input.event)
          gate_rule.step(state, input)
        },
      ),
    ),
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
  let answer = open_wait.received(from: replies, what: "the process's answer")
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

/// How long, in milliseconds, a limit that a test is not about lasts: an hour,
/// far beyond any test's deadline (`owned_test.run`), so the test's own
/// deadline ends a connect, a statement or a find that is never answered.
pub const beyond_the_test_ms = 3_600_000

/// The moment, on the monotonic clock, of a server deadline that the test is
/// not about (`beyond_the_test_ms`).
pub fn deadline_far_beyond_the_tests_deadline() -> Int {
  monotonic_ms() + beyond_the_test_ms
}

/// Starts a supervisor tree of one child, unlinked from the test and ended with
/// it, and gives the supervisor's pid.
pub fn start_tree(child: ChildSpecification(Nil)) -> process.Pid {
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.restart_tolerance(intensity: 10, period: 5)
    |> supervisor.add(child)
    |> supervisor.start
    as "the tree started"
  process.unlink(started.pid)
  guard(started.pid)
  started.pid
}

/// A listener whose rule asks nothing of a directory and shuts down in a second.
pub fn started_listener() -> Server {
  start(
    rule: asking_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    with: fn(builder) { builder },
  )
}

/// A process that runs and never ends by itself, which a test ends.
pub fn idle_process() -> Pid {
  process.spawn_unlinked(process.sleep_forever)
}
