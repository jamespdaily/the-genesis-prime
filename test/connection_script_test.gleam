//// What a connection takes from its script (genesis_prime/connection/script):
//// the seed, the time of each input and the timers, and, under a replay, the
//// byte count of the next recorded read. Expected values come from these
//// places.
//// - The shell's contract in the doc comments of `genesis_prime/connection/shell`
////   and `genesis_prime/connection/script`: the seed of `Accepted` and the
////   time of each input are the script's, a timer starts through the script's
////   scheduler, and a script whose `next_read` gives a byte count has the shell
////   hold what the socket delivers, taking no other input, until it holds that
////   many bytes.
//// - The script the test hands the listener: its seed and times are the values
////   the rule (`script_rule`) writes back, so the bytes the client reads are a
////   record of what the shell took from the script.
//// - The operating system's own script: 32 bytes from the strong random
////   source, the node's monotonic clock and `process.send_after`.
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches; the one test of the 5 s bound waits that long, as the bound
//// is what it proves.

import ask_support
import event_wait
import genesis_prime/connection/registry
import genesis_prime/connection/script.{type Scripts, Issued, Script}
import genesis_prime/step.{
  type Address, type Now, ConnectionId, Now, Sessions, TimerId,
}
import genesis_prime/step/runtime
import genesis_prime/wire_recording.{
  Accepted, PeerClosed, Read, Recording, Server, Took, Wrote,
}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/erlang/reference
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import mug
import owned_test
import recording_support
import script_rule
import signalling_rule

// ---- the server's own script ----

pub fn the_servers_script_draws_each_seed_from_the_system_and_numbers_the_connections_in_order_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(first) = script.operating_system() as "the server's script"
  let assert Ok(second) = script.operating_system() as "and another"
  assert bit_array.byte_size(first.script.seed) == 32
    && bit_array.byte_size(second.script.seed) == 32
    as "32 bytes, as the STS cipher's key is drawn"
  assert first.script.seed != second.script.seed
    as "a seed is drawn for each connection"
  assert second.ordinal > first.ordinal
    as "the ordinal grows with each connection, so the order of accepts is recorded and never inferred from times"
  let before = runtime.monotonic_ms()
  let Now(monotonic_ms:, ..) = first.script.clock(script.Accepted)
  let after = runtime.monotonic_ms()
  assert monotonic_ms >= before && monotonic_ms <= after
    as "the clock is the node's own monotonic clock"
  assert first.script.next_read() == None
    as "the server fixes no size for a read: what arrived is the input"
}

pub fn the_servers_scheduler_sends_the_timer_to_the_subject_after_its_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(issued) = script.operating_system() as "the server's script"
  let fired = process.new_subject()
  let reference = reference.new()
  let _cancel = issued.script.schedule(fired, TimerId(4), reference, 1)
  assert process.receive(fired, within: ask_support.event_wait_ms)
    == Ok(script.Elapsed(timer: TimerId(4), reference:))
    as "the timer's message names the timer and the reference of its start"
}

// ---- a given script ----

/// A script with the seed `0..31`, the same time for every input and no timer.
fn fixed(now: Now) -> Scripts {
  fn() {
    Ok(Issued(
      ordinal: 1,
      script: Script(
        seed: seed(),
        clock: fn(_taking) { now },
        schedule: fn(_subject, _timer, _reference, _after_ms) { fn() { Nil } },
        next_read: fn() { None },
      ),
    ))
  }
}

fn seed() -> BitArray {
  list.repeat(Nil, 32)
  |> list.index_map(fn(_, byte) { <<byte>> })
  |> bit_array.concat
}

fn start_script_rule(scripts: Scripts) -> ask_support.Server {
  ask_support.start_scripted(
    rule: script_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    recorder: None,
    wire_recorder: None,
    scripts:,
    registry: None,
    locate: fn(_address) { Error(Nil) },
    with: fn(builder) { builder },
  )
}

/// The bytes a client reads from a connection of the script rule whose script
/// is `scripts`: the accept's record and the record of one read.
fn one_session(server: ask_support.Server) -> BitArray {
  let client = ask_support.connect(server)
  let accepted = ask_support.read_bytes(client, 49)
  assert mug.send(client, <<1, 2, 3>>) == Ok(Nil) as "bytes"
  let read = ask_support.read_bytes(client, 17)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  <<accepted:bits, read:bits>>
}

pub fn a_given_script_gives_the_same_bytes_twice_test() -> Nil {
  use <- owned_test.run(30_000)
  let now = Now(monotonic_ms: -9, filetime: 123_456_789_012_345_678)
  let server = start_script_rule(fixed(now))
  let first = one_session(server)
  let second = one_session(server)
  assert first == second
    as "the same seed and the same times give the same bytes, whichever connection takes them"
  assert first
    == <<
      script_rule.accepted,
      seed():bits,
      now.monotonic_ms:64,
      now.filetime:64,
      script_rule.read,
      now.monotonic_ms:64,
      now.filetime:64,
    >>
    as "the bytes are the seed and the time the script gave, in the rule's records"
  ask_support.stop(server)
}

pub fn two_connections_of_one_listener_each_take_a_script_of_their_own_test() -> Nil {
  use <- owned_test.run(30_000)
  // Each call of `scripts` makes a script whose time is the number it drew,
  // so which script a connection took shows in the time its records hold.
  let server =
    start_script_rule(fn() {
      let drawn = unique()
      fixed(Now(monotonic_ms: drawn, filetime: drawn * 10))()
    })
  let client_one = ask_support.connect(server)
  let one = accepted_script(ask_support.read_bytes(client_one, 49))
  let client_two = ask_support.connect(server)
  let two = accepted_script(ask_support.read_bytes(client_two, 49))
  assert one.0 == seed() && two.0 == seed()
    as "each script's seed is the one it was made with"
  assert one.1.filetime == one.1.monotonic_ms * 10
    && two.1.filetime == two.1.monotonic_ms * 10
    as "each connection's time is of one script: its two numbers go together"
  assert one.1.monotonic_ms < two.1.monotonic_ms
    as "the second connection took the script made second"
  ask_support.stop(server)
}

/// The seed and the time of an accept's record of the script rule.
fn accepted_script(record: BitArray) -> #(BitArray, Now) {
  let assert <<
    letter,
    seed:bytes-size(32),
    monotonic_ms:64-signed,
    filetime:64,
  >> = record
    as "an accept's record is a letter, 32 bytes and two 64-bit numbers"
  assert letter == script_rule.accepted
  #(seed, Now(monotonic_ms:, filetime:))
}

@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(UniqueOption)) -> Int

type UniqueOption {
  Positive
  Monotonic
}

fn unique() -> Int {
  unique_integer([Positive, Monotonic])
}

pub fn a_connection_with_no_script_to_take_is_closed_and_takes_no_input_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start_script_rule(fn() { Error(Nil) })
  let client = ask_support.connect(server)
  assert mug.receive(client, timeout_milliseconds: ask_support.event_wait_ms)
    == Error(mug.Closed)
    as "the connection closes with no accept's write"
  ask_support.stop(server)
}

// ---- timers through the script's scheduler ----

pub fn a_timer_starts_through_the_scripts_scheduler_and_fires_when_the_script_says_test() -> Nil {
  use <- owned_test.run(30_000)
  let started = process.new_subject()
  let scripts = fn() {
    let assert Ok(issued) = script.operating_system()
    Ok(
      Issued(
        ..issued,
        script: Script(
          ..issued.script,
          schedule: fn(subject, timer, reference, after_ms) {
            process.send(started, #(timer, after_ms))
            process.send(subject, script.Elapsed(timer:, reference:))
            fn() { Nil }
          },
        ),
      ),
    )
  }
  let server =
    ask_support.start_scripted(
      rule: signalling_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 1000,
      recorder: None,
      wire_recorder: None,
      scripts:,
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  let _accepted = read_record(client)
  // A timer of a minute: the test never waits it out, since the script's
  // scheduler is what the shell started it through.
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 5,
    wait_ms: 60_000,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 5)
    as "the timer fired when the script's scheduler sent its message"
  assert process.receive(started, 0) == Ok(#(TimerId(5), 60_000))
    as "the shell asked the script's scheduler for timer 5 and 60 s"
  ask_support.stop(server)
}

// ---- a read in parts, under a script that fixes its size ----

/// The operating system's script with `next_read` fixed at `wanted` bytes, which
/// tells `looked` each time the shell asks.
fn reading(wanted: Int, looked: Subject(Nil)) -> Scripts {
  fn() {
    let assert Ok(issued) = script.operating_system()
    Ok(
      Issued(
        ..issued,
        script: Script(..issued.script, next_read: fn() {
          process.send(looked, Nil)
          Some(wanted)
        }),
      ),
    )
  }
}

type Record {
  Record(letter: Int, number: Int)
}

fn read_record(client: mug.Socket) -> Record {
  read_record_within(client, ask_support.event_wait_ms)
}

fn read_record_within(client: mug.Socket, within_ms: Int) -> Record {
  let assert Ok(<<letter, number:64>>) =
    mug.receive_exact(client, byte_size: 9, timeout_milliseconds: within_ms)
    as "a record arrived"
  Record(letter:, number:)
}

fn start_signalling(
  scope: registry.Registry(Int),
  scripts: Scripts,
) -> ask_support.Server {
  ask_support.start_scripted(
    rule: signalling_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    recorder: None,
    wire_recorder: None,
    scripts:,
    registry: Some(scope),
    locate: fn(address: Address) {
      case address {
        Sessions
        | step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
        | step.Connection(..) -> Error(Nil)
      }
    },
    with: fn(builder) { supervisor.add(builder, registry.supervised(scope)) },
  )
}

/// The id the connection's rule was accepted with.
fn accepted_id(client: mug.Socket) -> Int {
  let Record(letter:, number:) = read_record(client)
  assert letter == signalling_rule.accepted
    as "the first record is the accept's"
  number
}

pub fn a_message_delivered_between_the_parts_of_a_recorded_read_is_taken_after_the_read_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let looked = process.new_subject()
  let server = start_signalling(scope, reading(8, looked))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  // The read is two commands of four bytes, delivered in two parts: the first
  // part is a whole command, so a shell that took it as an input would run it.
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 1,
    wait_ms: 0,
  )
  let assert Ok(Nil) = process.receive(looked, ask_support.event_wait_ms)
    as "the shell took the first part and asked the script how many bytes the read holds"
  // The shell now holds the first part. The message goes to its mailbox before
  // the second part is sent, so it is there before the second part can be.
  assert registry.deliver(scope, ConnectionId(id), 9) == Ok(Nil)
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 2,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 1)
    as "the read's first command runs first"
  assert read_record(client) == Record(signalling_rule.pong, 2)
    as "and its second, in the same input"
  assert read_record(client) == Record(signalling_rule.woken, 9)
    as "the message waited in the mailbox until the whole read was taken"
  ask_support.stop(server)
}

pub fn a_recorded_read_the_socket_delivers_in_parts_reaches_the_rule_as_one_input_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let looked = process.new_subject()
  let server =
    ask_support.start_scripted(
      rule: script_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 1000,
      recorder: None,
      wire_recorder: Some(recording_support.wire_recorder(folder)),
      scripts: reading(3, looked),
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  let _accepted = ask_support.read_bytes(client, 49)
  assert mug.send(client, <<1>>) == Ok(Nil) as "the first part"
  let assert Ok(Nil) = process.receive(looked, ask_support.event_wait_ms)
    as "the shell took the first part and holds it"
  assert mug.send(client, <<2, 3>>) == Ok(Nil) as "the rest"
  let _read = ask_support.read_bytes(client, 17)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(watched)
  let assert Ok(Recording(lines:, ..)) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole"
  let inputs =
    list.filter_map(lines, fn(line) {
      case line {
        Took(input:, ..) -> Ok(input)
        Wrote(..) -> Error(Nil)
      }
    })
  assert inputs == [Accepted, Read(<<1, 2, 3>>), PeerClosed]
    as "the three bytes are one input: the shell took no input for the first part"
  ask_support.stop(server)
}

pub fn a_stop_while_the_shell_holds_part_of_a_read_reaches_the_rule_as_stopping_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let looked = process.new_subject()
  let server =
    ask_support.start_scripted(
      rule: script_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 2000,
      recorder: None,
      wire_recorder: Some(recording_support.wire_recorder(folder)),
      scripts: reading(3, looked),
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  let _accepted = ask_support.read_bytes(client, 49)
  assert mug.send(client, <<1>>) == Ok(Nil) as "the first part"
  let assert Ok(Nil) = process.receive(looked, ask_support.event_wait_ms)
    as "the shell took the first part and holds it"
  ask_support.stop(server)
  let assert Ok(Recording(lines:, closing:, ..)) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole: the rule stopped in time"
  let inputs =
    list.filter_map(lines, fn(line) {
      case line {
        Took(input:, ..) -> Ok(input)
        Wrote(..) -> Error(Nil)
      }
    })
  assert inputs == [Accepted, wire_recording.Stopping]
    as "the stop is the next input, and the held part never was one"
  assert closing.by == Server
}

pub fn a_shell_that_waits_for_the_rest_of_a_read_gives_up_after_5_s_and_takes_the_mailbox_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let looked = process.new_subject()
  let server = start_signalling(scope, reading(8, looked))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 1,
    wait_ms: 0,
  )
  let assert Ok(Nil) = process.receive(looked, ask_support.event_wait_ms)
    as "the shell took the first part and holds it"
  assert registry.deliver(scope, ConnectionId(id), 9) == Ok(Nil)
  // The rest of the read never comes. The wait is bounded by 5 s of real time,
  // the bound this test proves, and then the shell takes what waits.
  assert read_record_within(client, 15_000) == Record(signalling_rule.woken, 9)
    as "after the bound the message is taken, and the held part is not a read"
  event_wait.until("the connection is still open", fn() {
    ask_support.connections(server) != []
  })
  ask_support.stop(server)
}
