//// The socket owner and its four limits, through a real listener and client
//// sockets on this machine. Expected values come from:
//// - the client's framing: at most 131,070 bytes a frame (MessageSizeLimit
////   0x140335ec0, `frame.size_limit`), a decode failure ending the connection
////   (the project rules: the connection rejects bad input and a decode failure
////   ends it);
//// - the client's sending rates: the movement send interval of `0x140c3a004`,
////   125 ms until server message `0xf1` sets it, and between 25 and 1000 ms
////   after (`opcode.0xf1`, `opcode.0x637`);
//// - OTP's `inet` options: `{active, once}` hands the owner one read and
////   sends no more until it asks again, and `{active, N}` hands it N reads,
////   then a `tcp_passive` notice, and a read is at most the socket's `buffer`
////   bytes;
//// - `erlang:process_flag(max_heap_size, ...)`: with `kill` a process whose
////   heap needs more than the limit is killed, shared binaries counted when
////   `include_shared_binaries` is set, which closes its socket.
////
//// Every test waits for the events it needs: a frame the handler reports, a
//// message the runtime sends, the end of a process, a closed socket.

import fake_clock
import genesis_prime/connection/frame
import genesis_prime/connection/rate_limit.{Rate}
import genesis_prime/connection/socket
import genesis_prime/connection/socket_owner.{Settings}
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import listening.{type Received, Config, Received}
import log_capture
import owned_test
import socket_watch
import tcp_client

/// How long a test waits for a socket to be closed by the server, in
/// milliseconds.
const close_wait_ms = 2000

/// The bytes of a frame that claims `length` bytes and holds `held` body
/// bytes of them.
fn claiming(length length: Int, held held: Int) -> BitArray {
  <<
    length:size(32)-little,
    0x0244:size(16)-little,
    bit_array.from_string(string.repeat("a", held)):bits,
  >>
}

fn send(client: tcp_client.Client, bytes: BitArray) -> Nil {
  let assert Ok(Nil) = tcp_client.send(client, bytes)
    as "the server closed the connection before the test finished sending"
  Nil
}

pub fn a_frame_at_the_size_limit_is_handed_on_and_the_connection_stays_open_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(listening.config())
  let client = listening.connect(running)
  let largest_body = frame.size_limit - frame.header_size
  send(client, listening.frame_of(message_id: 0x0244, size: largest_body))
  let assert Ok(Received(owner: owner, frame: largest, ..)) =
    listening.next(running)
    as "the frame of exactly 131,070 bytes was not handed on"
  assert bit_array.byte_size(largest.body) == 131_064
    as "MessageSizeLimit 0x140335ec0: the largest frame is 131,070 bytes, 6 of them its header"
  send(client, listening.frame_of(message_id: 0x0637, size: 4))
  let assert Ok(Received(owner: same_owner, frame: next, ..)) =
    listening.next(running)
    as "the connection ended after a frame at the size limit"
  assert same_owner == owner
    as "a frame at the size limit leaves the connection with its owner"
  assert next.message_id == 0x0637
}

pub fn a_frame_one_byte_over_the_size_limit_ends_the_connection_and_closes_the_socket_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(listening.config())
  let client = listening.connect(running)
  // A frame claiming 131,071 bytes, whole: one more than the client's limit.
  let _ = tcp_client.send(client, claiming(length: 131_071, held: 131_065))
  assert tcp_client.await_close(client, close_wait_ms)
    as "MessageSizeLimit 0x140335ec0: 131,071 is over the limit, so the server closes the connection"
  assert process.receive(running.frames, 0) == Error(Nil)
    as "a frame over the limit is never handed on"
}

pub fn a_burst_one_over_the_bucket_ends_the_connection_and_closes_the_socket_test() -> Nil {
  use <- owned_test.run(10_000)
  let clock = fake_clock.new(-1_000_000)
  let running =
    listening.start(
      Config(..listening.config(), owner: fn(settings) {
        Settings(
          ..settings,
          rate: Rate(frames_per_second: 10, burst: 3),
          clock: fake_clock.as_clock(clock),
        )
      }),
    )
  let client = listening.connect(running)
  let one = listening.frame_of(message_id: 0x0637, size: 0)
  let _ = tcp_client.send(client, bit_array.concat([one, one, one, one]))
  assert list.length(received(running, 3)) == 3
    as "token bucket: a burst of 3 passes a bucket of 3"
  assert tcp_client.await_close(client, close_wait_ms)
    as "token bucket: the 4th frame at the same instant is one over the burst, so the connection ends"
  assert process.receive(running.frames, 0) == Error(Nil)
    as "the frame over the burst is never handed on"
}

fn received(running: listening.Running, count: Int) -> List(Received) {
  numbers(1, count)
  |> list.map(fn(_) {
    let assert Ok(one) = listening.next(running) as "a frame was not handed on"
    one
  })
}

pub fn a_sender_at_the_clients_fastest_legitimate_rate_for_ten_seconds_is_never_ended_test() -> Nil {
  use <- owned_test.run(30_000)
  let clock = fake_clock.new(-1_000_000)
  let running =
    listening.start(
      Config(..listening.config(), owner: fn(settings) {
        Settings(..settings, clock: fake_clock.as_clock(clock))
      }),
    )
  let client = listening.connect(running)
  // video.framerateMax is at most 180 and a dash sends one movement frame per
  // game update, so 180 frames a second is the client's fastest legitimate
  // sending: frame number n is sent at n * 1000 / 180 ms.
  let frames_in_ten_seconds = 1800
  numbers(1, frames_in_ten_seconds + 1)
  |> list.fold(0, fn(sent_at, number) {
    let due = number * 1000 / 180
    fake_clock.advance(clock, due - sent_at)
    send(client, listening.frame_of(message_id: 0x0637, size: 0))
    let assert Ok(_) = listening.next(running)
      as "the connection ended at the client's own fastest legitimate rate"
    due
  })
  Nil
}

pub fn an_owner_in_active_once_mode_holds_at_most_one_read_while_it_is_busy_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(Config(..listening.config(), hold: True))
  let client = listening.connect(running)
  send(client, listening.frame_of(message_id: 1, size: 1000))
  let assert Ok(Received(owner: owner, release: release_first, ..)) =
    listening.next(running)
    as "the first frame was not handed on"
  let assert Ok(Nil) = socket_watch.trace_reads(owner)
    as "the owner owns no socket"
  // The owner is busy with the first frame. Three more arrive from the client.
  list.each([2, 3, 4], fn(message_id) {
    send(client, listening.frame_of(message_id:, size: 1000))
  })
  assert 3 * 1006 < socket_watch.read_buffer_bytes(owner)
    as "the three frames fit in one read of the socket, so one read holds them all"
  assert socket_watch.mailbox_length(owner) <= 1
    as "{active, once}: the runtime sends one read and no more until the owner asks again"
  process.send(release_first, Nil)
  assert socket_watch.await_reads(1, close_wait_ms) == Ok([socket_watch.Read])
    as "{active, once}: when the owner asks again the runtime sends the waiting bytes as one read"
  let second = next_frame(running)
  assert second.frame.message_id == 2
  let third = reply_after(running, second, 3)
  let fourth = reply_after(running, third, 4)
  assert socket_watch.await_reads(1, 0) == Error(Nil)
    as "{active, once}: the three frames came in the one read, and the runtime sent no other while the owner was busy"
  process.send(fourth.release, Nil)
}

fn next_frame(running: listening.Running) -> Received {
  let assert Ok(received) = listening.next(running)
    as "a frame was not handed on"
  received
}

/// Frees the owner from `previous` and returns the next frame, which must be
/// the message with this id.
fn reply_after(
  running: listening.Running,
  previous: Received,
  message_id: Int,
) -> Received {
  process.send(previous.release, Nil)
  let received = next_frame(running)
  assert received.frame.message_id == message_id
    as "frames are handed on in the order they were sent"
  received
}

pub fn an_owner_in_active_n_mode_holds_at_most_n_reads_while_it_is_busy_test() -> Nil {
  use <- owned_test.run(10_000)
  let running =
    listening.start(
      Config(..listening.config(), hold: True, owner: fn(settings) {
        Settings(..settings, flow_control: socket.ActiveCount(reads: 2))
      }),
    )
  let client = listening.connect(running)
  send(client, listening.frame_of(message_id: 1, size: 10))
  let assert Ok(Received(owner: owner, release: release_first, ..)) =
    listening.next(running)
    as "the first frame was not handed on"
  let assert Ok(Nil) = socket_watch.trace_reads(owner)
    as "the owner owns no socket"
  list.each([2, 3, 4], fn(message_id) {
    send(client, listening.frame_of(message_id:, size: 10))
  })
  assert socket_watch.await_reads(2, close_wait_ms)
    == Ok([socket_watch.Read, socket_watch.ReadsUsedUp])
    as "{active, 2}: after the first read the runtime sends one more read, then the notice that the 2 reads are used up, and no read after it"
  assert socket_watch.mailbox_length(owner) == 2
    as "the owner's mailbox holds that read and the notice, and no more of the client's bytes"
  process.send(release_first, Nil)
  let second = next_frame(running)
  assert second.frame.message_id == 2
  let third = reply_after(running, second, 3)
  let fourth = reply_after(running, third, 4)
  process.send(fourth.release, Nil)
}

pub fn an_owner_whose_heap_passes_its_ceiling_is_killed_and_its_socket_closed_test() -> Nil {
  use <- owned_test.run(10_000)
  let running =
    listening.start(
      Config(..listening.config(), owner: fn(settings) {
        Settings(..settings, heap_ceiling_words: 4096)
      }),
    )
  let client = listening.connect(running)
  send(client, listening.frame_of(message_id: 1, size: 4))
  let assert Ok(Received(owner: owner, ..)) = listening.next(running)
    as "the first frame was not handed on"
  let monitor = process.monitor(owner)
  // The start of a frame that is within the size limit and never ends: its
  // bytes stay with the owner, about 12,000 words of shared binary against a
  // ceiling of 4,096.
  let _ = tcp_client.send(client, claiming(length: 131_070, held: 100_000))
  assert listening.await_down(monitor) == Ok(process.Killed)
    as "max_heap_size with kill: a process that needs more than its ceiling is killed, shared binaries counted"
  assert tcp_client.await_close(client, close_wait_ms)
    as "the socket closes when its owner is killed"
  // The listener is untouched: a new client gets a new owner.
  let second_client = listening.connect(running)
  send(second_client, listening.frame_of(message_id: 2, size: 4))
  let assert Ok(Received(owner: new_owner, ..)) = listening.next(running)
    as "the listener did not accept a client after a connection was killed"
  assert new_owner != owner
    as "connections are temporary children: a killed owner is not restarted"
}

pub fn a_decode_failure_ends_the_connection_closes_the_socket_and_logs_the_reason_test() -> Nil {
  use <- owned_test.run(10_000)
  log_capture.start()
  let running = listening.start(listening.config())
  let client = listening.connect(running)
  send(client, listening.frame_of(message_id: 1, size: 4))
  let assert Ok(Received(owner: owner, ..)) = listening.next(running)
    as "the first frame was not handed on"
  let monitor = process.monitor(owner)
  let _ = tcp_client.send(client, <<131_071:size(32)-little>>)
  assert listening.await_down(monitor) == Ok(process.Normal)
    as "the project rules: a decode failure ends the connection, not the server"
  assert tcp_client.await_close(client, close_wait_ms)
    as "a decode failure closes the socket"
  assert log_capture.await(owner, close_wait_ms)
    == Ok(log_capture.Line(
      log_capture.WarningLevel,
      "connection ended: frame length 131071 is over the limit of 131070 bytes",
    ))
    as "the project rules: the reason is logged, as a warning, an outside failure the server recovered from (designing-processes, Logging)"
}

pub fn a_client_that_closes_ends_its_owner_normally_test() -> Nil {
  use <- owned_test.run(10_000)
  let running = listening.start(listening.config())
  let client = listening.connect(running)
  send(client, listening.frame_of(message_id: 1, size: 4))
  let assert Ok(Received(owner: owner, ..)) = listening.next(running)
    as "the first frame was not handed on"
  let monitor = process.monitor(owner)
  tcp_client.close(client)
  assert listening.await_down(monitor) == Ok(process.Normal)
    as "a client that closes its end is a normal end of its connection"
}

/// The whole numbers from `first` to `last`, both included.
fn numbers(first: Int, last: Int) -> List(Int) {
  int.range(from: first, to: last + 1, with: [], run: list.prepend)
  |> list.reverse
}
