//// What a listener's protocol can do for a connection: write when a client
//// connects, keep a connection's own state across inputs, write bytes and close
//// from a reaction, and read raw bytes instead of frames. Expected values come
//// from:
//// - the auth server's hello: the server sends message 3 on every new
////   connection before the client sends anything (fact file opcode.0x3, and
////   `opcode.0x76`: "the only message the client accepts bare from the auth
////   server is the hello");
//// - the STS login: its requests and replies are CRLF text, then RC4, with no
////   frames (fact file `StsConnLib64.MT.dll!0x180022cb0` and `0x18003a7d0`),
////   so its socket is read as bytes;
//// - the designing-processes skill: one process owns each piece of state, so a
////   connection's state is its owner's alone;
//// - OTP's `gen_tcp`: a socket's bytes arrive in the order they were written,
////   and a read is at most the socket's buffer.
//// Every test waits for the events it needs: bytes the client receives, a
//// report of the conversation, the end of a process.

import fake_clock
import genesis_prime/connection/rate_limit.{Rate}
import genesis_prime/connection/socket_owner.{
  type Conversation, type Input, type Protocol, BytesRead, Conversation,
  FrameRead, Frames, Protocol, RawBytes, Reaction,
}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/option.{Some}
import listening
import owned_test
import serving
import tcp_client

/// How long a test waits for a read of the client that must come at once, in
/// milliseconds.
const read_wait_ms = 2000

/// A conversation that answers each input with a byte holding how many inputs
/// this connection has had, counting this one.
fn counting(count: Int) -> Conversation {
  Conversation(handle: fn(_input) {
    let counted = count + 1
    Reaction(send: [<<counted>>], close: False, next: counting(counted))
  })
}

fn client_receives(client: tcp_client.Client, count: Int) -> BitArray {
  let assert Ok(bytes) = tcp_client.receive(client, count, read_wait_ms)
    as "the server did not write the bytes"
  bytes
}

pub fn a_client_that_connects_is_written_the_connect_steps_bytes_first_test() -> Nil {
  use <- owned_test.run(10_000)
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(_peer) {
        Reaction(
          send: [<<"hel":utf8>>, <<"lo":utf8>>],
          close: False,
          next: counting(0),
        )
      }),
      fn(settings) { settings },
    )
  let client = serving.connect(running)
  assert client_receives(client, 5) == <<"hello":utf8>>
    as "opcode.0x3: a server sends its hello on a new connection, before the client sends anything, and its writes come in order"
}

pub fn the_connect_step_is_given_the_clients_peer_address_test() -> Nil {
  use <- owned_test.run(10_000)
  let peers = process.new_subject()
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(peer) {
        process.send(peers, peer)
        Reaction(send: [], close: False, next: counting(0))
      }),
      fn(settings) { settings },
    )
  let client = serving.connect(running)
  let assert Ok(peer) = process.receive(peers, serving.event_wait_ms)
    as "the connect step did not run"
  assert peer == Some(tcp_client.own_address(client))
    as "the peer address the server sees is the client's own address and port"
}

pub fn each_connection_keeps_its_own_state_test() -> Nil {
  use <- owned_test.run(10_000)
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(_peer) {
        Reaction(send: [], close: False, next: counting(0))
      }),
      fn(settings) { settings },
    )
  let first = serving.connect(running)
  let second = serving.connect(running)
  let frame = listening.frame_of(message_id: 0x0637, size: 0)
  let assert Ok(Nil) = tcp_client.send(first, <<frame:bits, frame:bits>>)
    as "the first client sends"
  assert client_receives(first, 2) == <<1, 2>>
    as "designing-processes: a connection's state is its owner's, so its second input is its second"
  let assert Ok(Nil) = tcp_client.send(second, frame)
    as "the second client sends"
  assert client_receives(second, 1) == <<1>>
    as "another connection's inputs do not count in this one's state"
  let assert Ok(Nil) = tcp_client.send(first, frame)
    as "the first client sends again"
  assert client_receives(first, 1) == <<3>>
    as "the first connection's state went on from where it was"
}

pub fn what_a_reaction_sends_is_written_in_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(_peer) {
        Reaction(
          send: [],
          close: False,
          next: Conversation(handle: fn(_input) {
            Reaction(
              send: [<<1>>, <<2, 3>>, <<4>>],
              close: False,
              next: counting(0),
            )
          }),
        )
      }),
      fn(settings) { settings },
    )
  let client = serving.connect(running)
  let assert Ok(Nil) =
    tcp_client.send(client, listening.frame_of(message_id: 0x0637, size: 0))
    as "the client sends"
  assert client_receives(client, 4) == <<1, 2, 3, 4>>
    as "gen_tcp: bytes arrive in the order they were written"
}

pub fn a_reaction_that_closes_has_its_bytes_written_and_then_the_socket_closed_test() -> Nil {
  use <- owned_test.run(10_000)
  let owners = process.new_subject()
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(_peer) {
        process.send(owners, process.self())
        Reaction(
          send: [],
          close: False,
          next: Conversation(handle: fn(_input) {
            Reaction(send: [<<9>>], close: True, next: counting(0))
          }),
        )
      }),
      fn(settings) { settings },
    )
  let client = serving.connect(running)
  let assert Ok(owner) = process.receive(owners, serving.event_wait_ms)
    as "the connect step did not run"
  let monitor = process.monitor(owner)
  let assert Ok(Nil) =
    tcp_client.send(client, listening.frame_of(message_id: 0x0637, size: 0))
    as "the client sends"
  assert client_receives(client, 1) == <<9>>
    as "a refusal is written before the socket closes"
  assert tcp_client.await_close(client, read_wait_ms)
    as "a reaction that closes closes the socket"
  assert listening.await_down(monitor) == Ok(process.Normal)
    as "the owner of a connection that its conversation closed ends normally"
}

pub fn a_connect_step_that_closes_writes_its_bytes_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(_peer) {
        Reaction(send: [<<7>>], close: True, next: counting(0))
      }),
      fn(settings) { settings },
    )
  let client = serving.connect(running)
  assert client_receives(client, 1) == <<7>>
    as "a connect step that refuses a client still writes why"
  assert tcp_client.await_close(client, read_wait_ms) as "and the socket closes"
}

/// A raw-mode protocol whose conversation reports each read.
fn reporting(reads: Subject(BitArray)) -> Protocol {
  Protocol(mode: RawBytes, connect: fn(_peer) {
    Reaction(send: [], close: False, next: reporter(reads))
  })
}

fn reporter(reads: Subject(BitArray)) -> Conversation {
  Conversation(handle: fn(input: Input) {
    case input {
      BytesRead(bytes:) -> process.send(reads, bytes)
      FrameRead(..) -> Nil
    }
    Reaction(send: [], close: False, next: reporter(reads))
  })
}

pub fn raw_mode_hands_over_a_read_uncut_and_not_as_a_frame_test() -> Nil {
  use <- owned_test.run(10_000)
  let reads = process.new_subject()
  let running = serving.start(reporting(reads), fn(settings) { settings })
  let client = serving.connect(running)
  let request = <<"POST /Sts/Ping STS/1.0\r\nl:0\r\n\r\n":utf8>>
  let assert Ok(Nil) = tcp_client.send(client, request) as "the client sends"
  assert process.receive(reads, serving.event_wait_ms) == Ok(request)
    as "StsConnLib64.MT.dll!0x180022cb0: an STS request is text, which in frame mode would be read as a length and end the connection"
  let assert Ok(Nil) = tcp_client.send(client, <<"more":utf8>>)
    as "the connection is still open"
  assert process.receive(reads, serving.event_wait_ms) == Ok(<<"more":utf8>>)
    as "each later read is handed on as it came"
}

pub fn a_raw_read_takes_a_token_and_the_read_over_the_bucket_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let clock = fake_clock.new(-1_000_000)
  let reads = process.new_subject()
  let running =
    serving.start(reporting(reads), fn(settings) {
      socket_owner.Settings(
        ..settings,
        rate: Rate(frames_per_second: 10, burst: 2),
        clock: fake_clock.as_clock(clock),
      )
    })
  let client = serving.connect(running)
  let assert Ok(Nil) = tcp_client.send(client, <<"a":utf8>>) as "first read"
  let assert Ok(_) = process.receive(reads, serving.event_wait_ms)
    as "the first read was not handed on"
  let assert Ok(Nil) = tcp_client.send(client, <<"b":utf8>>) as "second read"
  let assert Ok(_) = process.receive(reads, serving.event_wait_ms)
    as "the second read was not handed on"
  tcp_client.send_if_open(client, <<"c":utf8>>)
  assert tcp_client.await_close(client, read_wait_ms)
    as "token bucket: the third read at the same instant is one over the burst of 2, so the connection ends"
  assert process.receive(reads, 0) == Error(Nil)
    as "the read over the burst is never handed on"
}

pub fn a_frame_mode_connection_is_handed_frames_and_never_raw_bytes_test() -> Nil {
  use <- owned_test.run(10_000)
  let inputs = process.new_subject()
  let running =
    serving.start(
      Protocol(mode: Frames, connect: fn(_peer) {
        Reaction(send: [], close: False, next: recorder(inputs))
      }),
      fn(settings) { settings },
    )
  let client = serving.connect(running)
  let frame = listening.frame_of(message_id: 0x0637, size: 3)
  // The frame arrives in two reads and is handed on once, whole.
  let assert Ok(first_half) = bit_array.slice(frame, 0, 4) as "a prefix"
  let assert Ok(rest) =
    bit_array.slice(frame, 4, bit_array.byte_size(frame) - 4)
    as "the rest"
  let assert Ok(Nil) = tcp_client.send(client, first_half) as "the first half"
  let assert Ok(Nil) = tcp_client.send(client, rest) as "the rest"
  let assert Ok(kind) = process.receive(inputs, serving.event_wait_ms)
    as "the frame was not handed on"
  assert kind == "frame"
    as "in frame mode a conversation is handed whole frames"
}

fn recorder(inputs: Subject(String)) -> Conversation {
  Conversation(handle: fn(input: Input) {
    case input {
      FrameRead(..) -> process.send(inputs, "frame")
      BytesRead(..) -> process.send(inputs, "bytes")
    }
    Reaction(send: [], close: False, next: recorder(inputs))
  })
}
