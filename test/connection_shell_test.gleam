//// The connection shell and its listener, proven on the hello rule. Expected values come from these places.
//// - The hello's bytes: `vector.opcode.0x3.body`, the client's own 47 bytes
////   for the values below, in a frame of 53 bytes (length 35 00 00 00, id
////   03 00; record `0x1403355e0`, WriteMessageFrame).
//// - A ping and its pong: `opcode.0x0` and `opcode.0x1`, 07 00 00 00 00 00 then
////   the number, and 07 00 00 00 01 00 then the same number.
//// - The frame size limit, 131,070 bytes (MessageSizeLimit `0x140335ec0`).
//// - The shell's contract in the doc comment of `genesis_prime/connection/
////   shell`, as approved on the shell card.
//// - FILETIME: 100-nanosecond intervals since 1601, 116,444,736,000,000,000 of
////   them at the Unix epoch (opcode.0x117 carries the server's time so).
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import driven_time
import event_wait
import genesis_prime/connection/registry
import genesis_prime/connection/script.{Elapsed, Issued, Script}
import genesis_prime/connection/shell
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionInput, type ConnectionRule,
  type ConnectionStep, Accepted, ConnectionId, Effects, Input, Log, Now,
  OwnEffect, OwnEvent, Peer, PeerClosed, Read, ReadFailed, Rule, StartTimer,
  Stop, Stopping, TimerFired, TimerId, Write, WriteFailed,
}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import hello_rule
import mailbox_support
import mug
import open_wait
import owned_test
import replay_rule

// ---- the hello rule, pure ----

pub fn on_accept_the_rule_writes_the_server_hello_frame_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, step) = accept()
  assert step == Effects([OwnEffect(Write(hello_frame()))])
    as "vector.opcode.0x3.body in its 53-byte frame"
}

pub fn a_ping_split_across_two_reads_gets_one_pong_with_its_number_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  let #(state, first) = take(state, OwnEvent(Read(<<7, 0, 0, 0, 0, 0>>)))
  assert first == Effects([]) as "half a ping is not answered yet"
  let #(_, second) = take(state, OwnEvent(Read(<<13>>)))
  assert second == Effects([OwnEffect(Write(<<7, 0, 0, 0, 1, 0, 13>>))])
    as "opcode.0x1: the pong carries the ping's number"
}

pub fn two_pings_in_one_read_get_two_pongs_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  let #(_, step) =
    take(state, OwnEvent(Read(<<7, 0, 0, 0, 0, 0, 1, 7, 0, 0, 0, 0, 0, 2>>)))
  assert step
    == Effects([
      OwnEffect(Write(<<7, 0, 0, 0, 1, 0, 1>>)),
      OwnEffect(Write(<<7, 0, 0, 0, 1, 0, 2>>)),
    ])
    as "one pong for each ping, in the order they came"
}

pub fn a_peer_close_stops_and_a_read_failure_logs_and_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  assert take(state, OwnEvent(PeerClosed)).1 == Effects([Stop])
    as "the client closed, so the rule stops"
  let assert Effects([Log(_), Stop]) =
    take(state, OwnEvent(ReadFailed(step.Reset))).1
    as "a read failure is logged, then the rule stops"
  Nil
}

pub fn a_frame_over_the_size_limit_logs_and_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  // 131,071 is one byte over the limit, little-endian: ff ff 01 00.
  let assert Effects([Log(_), Stop]) =
    take(state, OwnEvent(Read(<<0xFF, 0xFF, 0x01, 0x00, 0, 0>>))).1
    as "0x140335ec0: no frame is over 131,070 bytes"
  Nil
}

// ---- the shell, on a real socket ----

pub fn a_client_gets_the_hello_and_a_pong_for_its_ping_test() -> Nil {
  use <- owned_test.run(30_000)
  use server <- serving(hello_rule_as_rule(), 1000)
  let client = ask_support.connect(server)
  assert ask_support.read_bytes(client, 53) == hello_frame()
    as "the hello comes first"
  assert mug.send(client, <<7, 0, 0, 0>>) == Ok(Nil) as "first half sent"
  assert mug.send(client, <<0, 0, 9>>) == Ok(Nil) as "second half sent"
  assert ask_support.read_bytes(client, 7) == <<7, 0, 0, 0, 1, 0, 9>>
    as "the pong for 9"
}

pub fn a_clients_close_ends_the_process_normally_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(rule, taken) = recording(hello_rule_as_rule())
  use server <- serving(rule, 1000)
  let client = ask_support.connect(server)
  let connection = accepted_shell(taken)
  let watched = process.monitor(connection)
  let _hello = ask_support.read_bytes(client, 53)
  assert ask_support.connections(server) == [connection]
    as "Ranch lists the one connection process"
  assert mailbox_support.drain(taken) == []
    as "nothing but Accepted reached the rule before the client closed"
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  assert ask_support.ended(
      watched: watched,
      what: "the shell to end after the client closed",
    )
    == process.Normal
    as "a normal end"
  assert events(mailbox_support.drain(taken)) == [OwnEvent(PeerClosed)]
    as "the client's close was the one input after Accepted"
}

pub fn a_failed_write_reaches_the_rule_and_the_steps_later_effects_are_not_carried_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // The rule writes 64 MiB to a client that never reads, then 1 KiB, then
  // stops. The BEAM queues the first write whole; the second waits for the
  // queue and cannot finish within the 300 ms send deadline. Had the shell
  // carried out the Stop after the failed write, no WriteFailed input would
  // follow it.
  let #(rule, taken) = recording(big_write_rule())
  use server <- serving(rule, 1000)
  let client = ask_support.connect(server)
  let connection = accepted_shell(taken)
  let watched = process.monitor(connection)
  // The first byte shows the connection's process has started.
  let _first_byte = ask_support.read_bytes(client, 1)
  assert ask_support.connections(server) == [connection]
    as "Ranch lists the one connection process"
  assert ask_support.ended(
      watched: watched,
      what: "the shell to stop after the failed write",
    )
    == process.Normal
    as "the rule stopped after the failed write"
  let _still_open = client
  assert events(mailbox_support.drain(taken))
    == [OwnEvent(WriteFailed(step.SendTimedOut))]
    as "the failed write came back as the next input after Accepted, before anything else"
}

pub fn a_rule_that_crashes_ends_only_its_connection_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(rule, taken) = recording(crash_on_0xee_rule())
  use server <- serving(rule, 1000)
  let first = ask_support.connect(server)
  let connection = accepted_shell(taken)
  let watched = process.monitor(connection)
  let _hello = ask_support.read_bytes(first, 53)
  assert ask_support.connections(server) == [connection]
    as "Ranch lists the one connection process"
  assert mug.send(first, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  crashed_by_the_plant(watched)
  let second = ask_support.connect(server)
  assert ask_support.read_bytes(second, 53) == hello_frame()
    as "the listener still accepts and greets"
}

pub fn a_connection_that_crashes_leaves_another_open_connection_running_unchanged_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(rule, taken) = recording(crash_on_0xee_rule())
  use server <- serving(rule, 1000)
  let crashing = ask_support.connect(server)
  let crashing_process = accepted_shell(taken)
  let watched = process.monitor(crashing_process)
  let _hello = ask_support.read_bytes(crashing, 53)
  let staying = ask_support.connect(server)
  let staying_process = accepted_shell(taken)
  let _hello = ask_support.read_bytes(staying, 53)
  assert list.filter(ask_support.connections(server), fn(connection) {
      connection != crashing_process
    })
    == [staying_process]
    as "a second connection process, open beside the first"
  assert mug.send(crashing, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  crashed_by_the_plant(watched)
  assert mug.send(staying, <<7, 0, 0, 0, 0, 0, 9>>) == Ok(Nil)
    as "a ping on the connection that stayed"
  assert ask_support.read_bytes(staying, 7) == <<7, 0, 0, 0, 1, 0, 9>>
    as "opcode.0x1: the connection that stayed answers its ping after the other crashed"
  event_wait.until(
    "Ranch lists only the connection that stayed, the same process it was before: the BEAM isolates a crash to its process",
    fn() { ask_support.connections(server) == [staying_process] },
  )
}

// ---- a rule that goes on after the socket's end ----

/// What a rule that goes on after the socket's end hears, in order.
type Heard =
  step.Event(ConnectionEvent(Int, Nil))

/// A rule that writes `on_accepted`, starts a timer of 100 ms when the socket
/// ends (a peer's close, a read failure, a failed write) and stops when that
/// timer fires or the server stops. Each input is sent to `heard` as the rule
/// takes it.
fn going_on_rule(
  heard heard: Subject(Heard),
  on_accepted on_accepted: List(step.Effect(step.ConnectionEffect(Nil))),
) -> ConnectionRule(Nil, Nil, Nil, Int, Nil) {
  Rule(
    name: "going_on_rule",
    settings: Nil,
    new: fn(_settings) { Nil },
    step: fn(state, input: ConnectionInput(Int, Nil)) {
      process.send(heard, input.event)
      let effects = case input.event {
        OwnEvent(Accepted(..)) -> on_accepted
        OwnEvent(PeerClosed)
        | OwnEvent(ReadFailed(..))
        | OwnEvent(WriteFailed(..)) -> [
          OwnEffect(StartTimer(TimerId(1), 100)),
        ]
        OwnEvent(TimerFired(..)) | Stopping(..) -> [Stop]
        OwnEvent(Read(..))
        | OwnEvent(step.Answered(..))
        | OwnEvent(step.Woken(..))
        | step.WatchEnded(..) -> []
      }
      #(state, Effects(effects))
    },
  )
}

/// A listener of `going_on_rule`s whose clock and timers are `time`'s, joined to
/// `scope`, with a shutdown time no test reaches.
fn going_on(
  heard heard: Subject(Heard),
  on_accepted on_accepted: List(step.Effect(step.ConnectionEffect(Nil))),
  time time: driven_time.Time,
  scope scope: registry.Registry(Int),
) -> ask_support.Server {
  ask_support.start_scripted(
    rule: going_on_rule(heard:, on_accepted:),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: ask_support.patient,
    wire_recorder: None,
    scripts: driven_time.scripts(time),
    registry: Some(scope),
    locate: fn(_address) { Error(Nil) },
    with: fn(builder) { supervisor.add(builder, registry.supervised(scope)) },
  )
}

/// The rule's next input.
fn next_heard(heard: Subject(Heard)) -> Heard {
  open_wait.received(from: heard, what: "the rule's next input")
}

/// Waits until the connection has taken everything queued for it (its rule's
/// timer is then started on the driven clock, and the socket messages the test
/// sent are taken), advances the driven clock past the rule's timer, waits for
/// the shell to end after the timer's firing and the stop it gave, and gives
/// what the rule heard from then on. The messages are taken before the timer
/// fires: the test sends the socket's messages and the barrier's request from
/// one process, which Erlang orders, where the driver's `Elapsed` comes from
/// another.
fn timer_then_the_end(
  server server: ask_support.Server,
  time time: driven_time.Time,
  heard heard: Subject(Heard),
) -> List(Heard) {
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  driven_time.wait_until_quiet(time)
  driven_time.advance(time:, ms: 100)
  let _reason =
    ask_support.ended(
      watched:,
      what: "the shell to end after the rule's timer fired and it stopped",
    )
  mailbox_support.drain(heard)
}

/// A rule's writes that fail: 64 MiB to a client that never reads, then 1 KiB,
/// which cannot finish within the send deadline.
fn writes_that_fail() -> List(step.Effect(step.ConnectionEffect(Nil))) {
  [
    OwnEffect(Write(<<0:size(536_870_912)>>)),
    OwnEffect(Write(<<0:size(8192)>>)),
  ]
}

pub fn a_rule_that_goes_on_after_a_peer_close_is_given_the_close_once_test() -> Nil {
  use <- owned_test.run(20_000)
  let time = driven_time.new()
  let heard = process.new_subject()
  let server = going_on(heard:, on_accepted: [], time:, scope: registry.new())
  let client = ask_support.connect(server)
  let assert OwnEvent(Accepted(..)) = next_heard(heard) as "Accepted first"
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  assert next_heard(heard) == OwnEvent(PeerClosed) as "the close, once"
  assert timer_then_the_end(server:, time:, heard:)
    == [OwnEvent(TimerFired(TimerId(1)))]
    as "then the timer; the shell does not arm a socket it knows is closed"
  ask_support.stop(server)
}

pub fn a_rule_that_goes_on_after_a_failed_write_is_given_the_failure_once_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let heard = process.new_subject()
  let server =
    going_on(
      heard:,
      on_accepted: writes_that_fail(),
      time:,
      scope: registry.new(),
    )
  let _client = ask_support.connect(server)
  let assert OwnEvent(Accepted(..)) = next_heard(heard) as "Accepted first"
  assert next_heard(heard) == OwnEvent(WriteFailed(step.SendTimedOut))
    as "the failed write, once"
  assert timer_then_the_end(server:, time:, heard:)
    == [OwnEvent(TimerFired(TimerId(1)))]
    as "then the timer; the shell does not arm the socket its failed write closed"
  ask_support.stop(server)
}

pub fn a_close_or_an_error_that_arrives_after_a_failed_write_is_ignored_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let heard = process.new_subject()
  let server =
    going_on(
      heard:,
      on_accepted: writes_that_fail(),
      time:,
      scope: registry.new(),
    )
  let _client = ask_support.connect(server)
  let assert OwnEvent(Accepted(..)) = next_heard(heard) as "Accepted first"
  assert next_heard(heard) == OwnEvent(WriteFailed(step.SendTimedOut))
  let assert [connection] = ask_support.connections(server)
  // What a socket whose peer is gone sends after the write failed, a close
  // then an error and an error then a close.
  let socket = atom.create("a_socket")
  let closed = #(atom.create("tcp_closed"), socket)
  let failed = #(atom.create("tcp_error"), socket, atom.create("closed"))
  mailbox_support.send_raw(connection, closed)
  mailbox_support.send_raw(connection, failed)
  mailbox_support.send_raw(connection, failed)
  mailbox_support.send_raw(connection, closed)
  assert timer_then_the_end(server:, time:, heard:)
    == [OwnEvent(TimerFired(TimerId(1)))]
    as "a socket message after the end the shell took is no input, in either order"
  ask_support.stop(server)
}

pub fn a_read_or_an_error_that_arrives_after_a_peer_close_is_ignored_test() -> Nil {
  use <- owned_test.run(20_000)
  let time = driven_time.new()
  let heard = process.new_subject()
  let server = going_on(heard:, on_accepted: [], time:, scope: registry.new())
  let client = ask_support.connect(server)
  let assert OwnEvent(Accepted(..)) = next_heard(heard) as "Accepted first"
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  assert next_heard(heard) == OwnEvent(PeerClosed)
  let assert [connection] = ask_support.connections(server)
  let socket = atom.create("a_socket")
  mailbox_support.send_raw(connection, #(
    atom.create("tcp_error"),
    socket,
    atom.create("closed"),
  ))
  mailbox_support.send_raw(connection, #(atom.create("tcp"), socket, <<1, 2>>))
  mailbox_support.send_raw(connection, #(atom.create("tcp_closed"), socket))
  assert timer_then_the_end(server:, time:, heard:)
    == [OwnEvent(TimerFired(TimerId(1)))]
    as "a read, an error or a second close after the close the shell took is no input"
  ask_support.stop(server)
}

pub fn a_stop_taken_late_behind_a_queue_of_map_messages_is_taken_before_them_test() -> Nil {
  use <- owned_test.run(30_000)
  // The shell is held while three messages and then the parent's exit reach
  // its mailbox. It takes the first message (one step) and then the exit,
  // before the other two, so the stop is late by one step, not by the queue.
  let scope = registry.new()
  let heard = process.new_subject()
  let server =
    going_on(heard:, on_accepted: [], time: driven_time.new(), scope:)
  let client = ask_support.connect(server)
  let assert OwnEvent(Accepted(connection: ConnectionId(id), ..)) =
    next_heard(heard)
    as "Accepted first"
  let assert [connection] = ask_support.connections(server)
  let watched = process.monitor(connection)
  let stopped =
    ask_support.while_suspended(connection, fn() {
      list.each([1, 2, 3], fn(number) {
        assert registry.deliver(scope, ConnectionId(id), number) == Ok(Nil)
          as "the message reached the connection"
      })
      let stopped = ask_support.begin_stop_tree(server.supervisor)
      event_wait.until(
        "the parent's exit reached the connection's mailbox",
        fn() { mailbox_support.tagged(connection, atom.create("EXIT")) == 1 },
      )
      stopped
    })
  let _reason =
    ask_support.ended(watched:, what: "the connection to end at the stop")
  let _tree = ask_support.ended(watched: stopped, what: "the tree to end")
  let _client = client
  let assert [OwnEvent(step.Woken(1)), Stopping(..)] =
    mailbox_support.drain(heard)
    as "one message, then the stop, before the two queued after the first"
  Nil
}

// ---- the stop deadline ----

pub fn the_shells_stop_deadline_is_the_time_it_takes_the_exit_plus_the_shutdown_time_less_the_reserve_test() -> Nil {
  use <- owned_test.run(5000)
  let settings = fn(reserve_ms) {
    shell.Settings(
      ..shell_settings(),
      shutdown_ms: 25_000,
      stop_reserve_ms: reserve_ms,
    )
  }
  let now = Now(monotonic_ms: 1000, filetime: 0)
  assert shell.stop_deadline(now:, settings: settings(5000)) == 21_000
    as "1000 + 25000 - 5000"
  assert shell.stop_deadline(now:, settings: settings(7000)) == 19_000
    as "the production reserve: taken + 18 s"
  assert shell.stop_deadline(now:, settings: settings(300)) == 25_700
    as "a reserve equal to the test settings' send deadline gives the shutdown time less the send deadline"
}

fn shell_settings() -> shell.Settings(Nil, Nil, Int, Nil, Nil) {
  shell.Settings(
    rule: going_on_rule(heard: process.new_subject(), on_accepted: []),
    send_deadline_ms: 300,
    shutdown_ms: 1000,
    stop_reserve_ms: 300,
    wire_recorder: None,
    scripts: script.operating_system,
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    registry: None,
    locate: fn(_address) { Error(Nil) },
    deliver: fn(_address, _request) { Error(Nil) },
  )
}

// ---- helpers ----

fn hello() -> server_hello.ServerHello {
  ServerHello(
    build: 16_042,
    realm_id: 0x11223344,
    unread_3: 0x55667788,
    unread_4: 0x99AABBCC,
    unread_5: 0x0102030405060708,
    unread_6: 0xBEEF,
    unread_7: 0x1F,
    message_table_checksum: 0x097998A0,
    unread_9: 0xCAFEBABE,
    unread_10: 0x1112131415161718,
    unread_11: 0x21222324,
  )
}

fn hello_frame() -> BitArray {
  let assert Ok(body) =
    bit_array.base16_decode(
      "AA3E00004433221188776655CCBBAA990807060504030201EFBE1F14332FC157D75F19E3C2A2826242228264442404",
    )
    as "vector.opcode.0x3.body is hex"
  <<0x35, 0, 0, 0, 0x03, 0, body:bits>>
}

/// The hello rule as its shell runs it.
type HelloRule =
  ConnectionRule(hello_rule.Settings, hello_rule.State, Nil, Nil, Nil)

fn hello_rule_as_rule() -> HelloRule {
  Rule(
    name: "hello_rule",
    settings: hello_rule.Settings(hello: hello()),
    new: hello_rule.new,
    step: hello_rule.step,
  )
}

/// An input the shell handed its rule, and the shell's process that took it.
type Taken {
  Taken(shell: Pid, event: step.Event(ConnectionEvent(Nil, Nil)))
}

/// The rule, and the subject that receives each input as the shell's process
/// takes it, before the rule's step runs. A test watches the shell from its
/// first input, so a shell that ended early is told from one that never
/// started: a process listed by Ranch and watched only afterwards says
/// `noproc` however it ended.
fn recording(rule: HelloRule) -> #(HelloRule, Subject(Taken)) {
  let taken = process.new_subject()
  #(
    Rule(..rule, step: fn(state, input: ConnectionInput(Nil, Nil)) {
      process.send(taken, Taken(shell: process.self(), event: input.event))
      rule.step(state, input)
    }),
    taken,
  )
}

/// The shell's process, from the Accepted input every connection takes first.
fn accepted_shell(taken: Subject(Taken)) -> Pid {
  let assert Taken(shell:, event: OwnEvent(Accepted(..))) =
    open_wait.received(
      from: taken,
      what: "the connection to take Accepted first",
    )
  shell
}

fn events(inputs: List(Taken)) -> List(step.Event(ConnectionEvent(Nil, Nil))) {
  list.map(inputs, fn(input) { input.event })
}

/// Waits for the watched shell to end and says it ended by the rule's planted
/// crash: any other end, `noproc` included, fails with its reason.
fn crashed_by_the_plant(watched: process.Monitor) -> Nil {
  let reason =
    ask_support.ended(
      watched: watched,
      what: "the shell to end by the rule's planted crash",
    )
  let assert process.Abnormal(abnormal) = reason
    as { "the connection crashed, not " <> string.inspect(reason) }
  assert decode.run(abnormal, crash_message()) == Ok("the planted crash")
    as { "the crash was the rule's: " <> string.inspect(abnormal) }
}

/// The message of a process's crash: its exit reason is the pair of the panic's
/// map, which holds `message`, and the stack.
fn crash_message() -> decode.Decoder(String) {
  use message <- decode.field(0, {
    use message <- decode.field(
      atom.to_dynamic(atom.create("message")),
      decode.string,
    )
    decode.success(message)
  })
  decode.success(message)
}

/// The hello rule, except that a read starting with 0xEE crashes it.
fn crash_on_0xee_rule() -> HelloRule {
  Rule(
    ..hello_rule_as_rule(),
    step: fn(state, input: ConnectionInput(Nil, Nil)) {
      case input.event {
        OwnEvent(Read(<<0xEE, _:bits>>)) -> panic as "the planted crash"
        OwnEvent(..) | Stopping(..) | step.WatchEnded(..) ->
          hello_rule.step(state, input)
      }
    },
  )
}

/// On accept, writes 64 MiB, then 1 KiB, then stops; on a failed write, stops.
fn big_write_rule() -> HelloRule {
  Rule(
    ..hello_rule_as_rule(),
    step: fn(state, input: ConnectionInput(Nil, Nil)) {
      case input.event {
        OwnEvent(Accepted(..)) -> #(
          state,
          Effects([
            OwnEffect(Write(<<0:size(536_870_912)>>)),
            OwnEffect(Write(<<0:size(8192)>>)),
            Stop,
          ]),
        )
        OwnEvent(WriteFailed(..)) -> #(state, Effects([Stop]))
        OwnEvent(..) | Stopping(..) | step.WatchEnded(..) ->
          hello_rule.step(state, input)
      }
    },
  )
}

fn accept() -> #(hello_rule.State, ConnectionStep(Nil)) {
  take(
    hello_rule.new(hello_rule.Settings(hello: hello())),
    OwnEvent(
      Accepted(ConnectionId(1), Peer(address: "127.0.0.1", port: 1), <<
        0:size(256),
      >>),
    ),
  )
}

fn take(
  state: hello_rule.State,
  event: step.Event(ConnectionEvent(Nil, Nil)),
) -> #(hello_rule.State, ConnectionStep(Nil)) {
  hello_rule.step(state, Input(now: Now(monotonic_ms: 0, filetime: 0), event:))
}

/// Starts a listener whose connections run `rule` and ask no one.
fn start(
  rule rule: ConnectionRule(settings, state, Nil, Nil, Nil),
  shutdown_ms shutdown_ms: Int,
) -> ask_support.Server {
  ask_support.start(
    rule:,
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms:,
    with: fn(builder) { builder },
  )
}

fn serving(
  rule: ConnectionRule(settings, state, Nil, Nil, Nil),
  shutdown_ms: Int,
  body: fn(ask_support.Server) -> a,
) -> a {
  let server = start(rule:, shutdown_ms:)
  let result = body(server)
  ask_support.stop(server)
  result
}

// ---- a close that arrives between the shell's write and its next read ----

/// What the stalled scheduler tells the test when timer 2 starts: the shell's
/// process, and the subject that lets the shell go on.
type Stalled {
  Stalled(shell: Pid, release: Subject(Nil))
}

pub fn a_close_between_the_shells_write_for_a_timer_and_its_next_read_reaches_the_rule_as_a_close_test() -> Nil {
  use <- owned_test.run(30_000)
  // The replay rule answers timer 1 with a record; this rule also starts timer
  // 2 after that write, and the scheduler holds the shell there, between the
  // write and the next read. The socket is armed from the read before, so the
  // client's close reaches it while the shell is held.
  let inputs = process.new_subject()
  let stalled = process.new_subject()
  let answering = replay_rule.rule()
  let rule =
    Rule(..answering, step: fn(state, input: ConnectionInput(Nil, Nil)) {
      process.send(inputs, input.event)
      let assert #(state, Effects(effects)) = answering.step(state, input)
      let effects = case
        input.event == OwnEvent(TimerFired(timer: TimerId(1)))
      {
        True -> list.append(effects, [OwnEffect(StartTimer(TimerId(2), 1))])
        False -> effects
      }
      #(state, Effects(effects))
    })
  let scripts = fn() {
    let assert Ok(issued) = script.operating_system()
    Ok(
      Issued(
        ..issued,
        script: Script(
          ..issued.script,
          schedule: fn(subject, timer, reference, _after_ms) {
            case timer == TimerId(1) {
              True -> process.send(subject, Elapsed(timer:, reference:))
              False -> {
                let release = process.new_subject()
                process.send(stalled, Stalled(shell: process.self(), release:))
                let Nil =
                  open_wait.received(
                    from: release,
                    what: "the test to let the shell go on",
                  )
                Nil
              }
            }
            fn() { Nil }
          },
        ),
      ),
    )
  }
  let server =
    ask_support.start_scripted(
      rule:,
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 1000,
      wire_recorder: None,
      scripts:,
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client:,
    letter: replay_rule.timer_command,
    n: 1,
    wait_ms: 0,
  )
  let Stalled(shell:, release:) =
    open_wait.received(
      from: stalled,
      what: "the shell's write for timer 1 and start of timer 2",
    )
  assert ask_support.read_bytes(client, 9) == <<replay_rule.timer_fired, 1:64>>
    as "the record the rule wrote for timer 1"
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  event_wait.until("the close reached the shell's mailbox", fn() {
    mailbox_support.tagged(shell, atom.create("tcp_closed")) == 1
  })
  process.send(release, Nil)
  let assert OwnEvent(Accepted(..)) =
    open_wait.received(from: inputs, what: "the connection's accept event")
  assert after_reads(inputs) == OwnEvent(TimerFired(timer: TimerId(1)))
    as "the command's reads, however the socket split its bytes, then timer 1"
  assert after_reads(inputs) == OwnEvent(PeerClosed)
    as "the client closed its socket: the rule takes a close, as the shell's contract says"
  ask_support.stop(server)
}

/// The next input the rule took that is not a read of the command's bytes.
fn after_reads(
  inputs: Subject(step.Event(ConnectionEvent(Nil, Nil))),
) -> step.Event(ConnectionEvent(Nil, Nil)) {
  let event = open_wait.received(from: inputs, what: "the rule's next input")
  case event {
    OwnEvent(Read(..)) -> after_reads(inputs)
    OwnEvent(Accepted(..))
    | OwnEvent(PeerClosed)
    | OwnEvent(ReadFailed(..))
    | OwnEvent(WriteFailed(..))
    | OwnEvent(step.Woken(..))
    | OwnEvent(TimerFired(..))
    | OwnEvent(step.Answered(..))
    | step.WatchEnded(..)
    | Stopping(..) -> event
  }
}
