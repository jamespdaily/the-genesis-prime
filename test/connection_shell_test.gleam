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
import event_wait
import genesis_prime/connection/script.{Elapsed, Issued, Script}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionInput, type ConnectionRule,
  type ConnectionStep, Accepted, ConnectionId, Effects, Input, Log, Now,
  OwnEffect, OwnEvent, Peer, PeerClosed, Read, ReadFailed, Rule, StartTimer,
  Stop, Stopping, TimerFired, TimerId, Write, WriteFailed,
}
import gleam/bit_array
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{None}
import hello_rule
import mailbox_support
import mug
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
  use server <- serving(hello_rule_as_rule(), 1000)
  let client = ask_support.connect(server)
  let _hello = ask_support.read_bytes(client, 53)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  assert ask_support.ended(watched) == process.Normal as "a normal end"
}

pub fn a_failed_write_reaches_the_rule_and_the_steps_later_effects_are_not_carried_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // The rule writes 64 MiB to a client that never reads, then 1 KiB, then
  // stops. The BEAM queues the first write whole; the second waits for the
  // queue and cannot finish within the 300 ms send deadline. Had the shell
  // carried out the Stop after the failed write, no WriteFailed input would
  // follow it. The inputs are read as the shell hands them to the rule.
  let inputs = process.new_subject()
  let writing = big_write_rule()
  let rule =
    Rule(..writing, step: fn(state, input: ConnectionInput(Nil, Nil)) {
      process.send(inputs, input.event)
      writing.step(state, input)
    })
  use server <- serving(rule, 1000)
  let client = ask_support.connect(server)
  // The first byte shows the connection's process has started.
  let _first_byte = ask_support.read_bytes(client, 1)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  assert ask_support.ended(process.monitor(connection)) == process.Normal
    as "the rule stopped after the failed write"
  let _still_open = client
  let assert [OwnEvent(Accepted(..)), OwnEvent(WriteFailed(step.SendTimedOut))] =
    mailbox_support.drain(inputs)
    as "the failed write came back as the next input, before anything else"
  Nil
}

pub fn a_rule_that_crashes_ends_only_its_connection_test() -> Nil {
  use <- owned_test.run(30_000)
  use server <- serving(crash_on_0xee_rule(), 1000)
  let first = ask_support.connect(server)
  let _hello = ask_support.read_bytes(first, 53)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  assert mug.send(first, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  let assert process.Abnormal(_) = ask_support.ended(watched)
    as "the connection crashed"
  let second = ask_support.connect(server)
  assert ask_support.read_bytes(second, 53) == hello_frame()
    as "the listener still accepts and greets"
}

pub fn a_connection_that_crashes_leaves_another_open_connection_running_unchanged_test() -> Nil {
  use <- owned_test.run(30_000)
  use server <- serving(crash_on_0xee_rule(), 1000)
  let crashing = ask_support.connect(server)
  let _hello = ask_support.read_bytes(crashing, 53)
  let assert [crashing_process] = ask_support.connections(server)
    as "one connection process"
  let staying = ask_support.connect(server)
  let _hello = ask_support.read_bytes(staying, 53)
  let assert [staying_process] =
    list.filter(ask_support.connections(server), fn(connection) {
      connection != crashing_process
    })
    as "a second connection process, open beside the first"
  let watched = process.monitor(crashing_process)
  assert mug.send(crashing, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  let assert process.Abnormal(_) = ask_support.ended(watched)
    as "the first connection crashed"
  assert mug.send(staying, <<7, 0, 0, 0, 0, 0, 9>>) == Ok(Nil)
    as "a ping on the connection that stayed"
  assert ask_support.read_bytes(staying, 7) == <<7, 0, 0, 0, 1, 0, 9>>
    as "opcode.0x1: the connection that stayed answers its ping after the other crashed"
  assert ask_support.connections(server) == [staying_process]
    as "the BEAM isolates a crash to its process: the connection that stayed is the same process it was before"
}

// ---- helpers ----

fn hello() -> server_hello.ServerHello {
  ServerHello(
    build: 16_042,
    realm_id: 0x11223344,
    field_3: 0x55667788,
    field_4: 0x99AABBCC,
    field_5: 0x0102030405060708,
    field_6: 0xBEEF,
    field_7: 0x1F,
    message_table_checksum: 0x097998A0,
    field_9: 0xCAFEBABE,
    field_10: 0x1112131415161718,
    field_11: 0x21222324,
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
                let assert Ok(Nil) = process.receive(release, 5000)
                  as "the test let the shell go on"
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
  let assert Ok(Stalled(shell:, release:)) = process.receive(stalled, 5000)
    as "the shell wrote for timer 1 and started timer 2"
  assert ask_support.read_bytes(client, 9) == <<replay_rule.timer_fired, 1:64>>
    as "the record the rule wrote for timer 1"
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  event_wait.until("the close reached the shell's mailbox", fn() {
    mailbox_support.tagged(shell, atom.create("tcp_closed")) == 1
  })
  process.send(release, Nil)
  let assert Ok(OwnEvent(Accepted(..))) = process.receive(inputs, 5000)
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
  let assert Ok(event) = process.receive(inputs, 5000)
    as "the rule took another input"
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
