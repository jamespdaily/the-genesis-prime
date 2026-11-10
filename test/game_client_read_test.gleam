//// The scripted client's reads: they give the messages a test asks for however
//// the server's bytes were split across socket reads. A peer that writes
//// several messages in one send makes one read hold more than the test asks
//// for; the message beyond the count belongs to the next read (a game message
//// arrives inside 0x03DC with every byte after its length enciphered:
//// opcode.0x3dc; the pong answering a ping arrives bare: opcode.0x1).

import ask_support
import event_wait
import frame_peer
import game_client.{type Game}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/unit_destroyed
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import login_client
import owned_test
import socket_read

fn destroyed(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_destroyed.encode(unit_destroyed.UnitDestroyed(unit_id:, field_2: 0))
  Frame(0x0355, body)
}

/// A connection to a peer that writes `messages` inside 0x03DC, then the bare
/// `after` bytes, all in one send.
fn written_in_one_send(messages: List(Frame), after after: BitArray) -> Game {
  let #(listener, port) = frame_peer.listen()
  let cipher = game_client.session_cipher(session_key: <<1:128>>)
  let assert Ok(wrapped) =
    list.try_map(messages, encrypted_frame.wrap(GameWrapper, _, cipher))
    as "the messages wrap"
  frame_peer.write_once_accepted(
    listener,
    bit_array.concat([bit_array.concat(wrapped), after]),
  )
  game_client.new(
    socket: login_client.connect(port),
    cipher:,
    limit: socket_read.Open,
  )
}

/// Whether `body` crashed, run in a process of its own so the test goes on.
fn crashes(body: fn() -> Nil) -> Bool {
  let monitor = process.spawn_unlinked(body) |> process.monitor
  case ask_support.ended(watched: monitor, what: "the process to end") {
    process.Normal -> False
    process.Killed | process.Abnormal(_) -> True
  }
}

pub fn a_poll_after_a_read_gives_the_messages_the_read_kept_test() -> Nil {
  use <- owned_test.run(60_000)
  let game =
    written_in_one_send(
      [destroyed(unit_id: 1), destroyed(unit_id: 2)],
      after: <<>>,
    )
  assert game_client.read(game:, count: 1) == [destroyed(unit_id: 1)]
  assert game_client.poll(game:, have: <<>>, wait_ms: 0)
    == Ok(#([destroyed(unit_id: 2)], <<>>))
    as "the message the read kept, though the socket holds no more"
  game_client.close(game:)
}

pub fn a_read_that_holds_more_messages_than_asked_for_keeps_the_rest_for_the_next_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let game =
    written_in_one_send(
      [destroyed(unit_id: 1), destroyed(unit_id: 2), destroyed(unit_id: 3)],
      after: <<>>,
    )
  assert game_client.read(game:, count: 2)
    == [destroyed(unit_id: 1), destroyed(unit_id: 2)]
    as "the first two messages, though the one read held a third"
  assert game_client.read(game:, count: 1) == [destroyed(unit_id: 3)]
    as "the third message, which the first read kept"
  game_client.nothing_more(game:)
  game_client.close(game:)
}

pub fn a_pong_that_arrives_with_the_message_before_it_is_read_after_that_message_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(pong) = frame.encode(0x0001, <<7:size(8)>>) as "a pong frames"
  let game = written_in_one_send([destroyed(unit_id: 1)], after: pong)
  assert game_client.read(game:, count: 1) == [destroyed(unit_id: 1)]
    as "the message, though the one read held the pong too"
  assert game_client.read_pong(game:) == 7 as "the pong, which the read kept"
  game_client.nothing_more(game:)
  game_client.close(game:)
}

pub fn nothing_more_fails_when_a_read_kept_a_message_the_test_did_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  assert crashes(fn() {
    let game =
      written_in_one_send(
        [destroyed(unit_id: 1), destroyed(unit_id: 2)],
        after: <<>>,
      )
    assert game_client.read(game:, count: 1) == [destroyed(unit_id: 1)]
    game_client.nothing_more(game:)
  })
    as "the second message was written and not read"
}

fn bare(message_id: Int) -> Frame {
  Frame(message_id, <<>>)
}

pub fn the_innate_passives_cast_is_dropped_only_after_the_0x61_of_an_entry_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x7FF, 0x7F4 and 0x7FE before 0x61 are not the passive's cast (the entry's
  // last effect writes it after 0x61, `world_entry.StartPassive`).
  let frames = [
    bare(0x00AD),
    bare(0x07FF),
    bare(0x07F4),
    bare(0x0061),
    bare(0x07FF),
    bare(0x07F4),
    bare(0x07FE),
    bare(0x01DA),
    bare(0x01BC),
  ]
  let kept = [
    bare(0x00AD),
    bare(0x07FF),
    bare(0x07F4),
    bare(0x0061),
    bare(0x01DA),
    bare(0x01BC),
  ]
  let game = written_in_one_send(frames, after: <<>>)
  assert game_client.read_entry(game:) == kept
    as "the entry read drops the cast after 0x61 and keeps the same ids before it"
  game_client.close(game:)
  assert game_client.frames_without_passive_cast(frames:) == kept
    as "the frames drop the cast after 0x61 alike"
  assert game_client.without_passive_cast(
      ids: list.map(frames, fn(frame) { frame.message_id }),
    )
    == list.map(kept, fn(frame) { frame.message_id })
    as "the ids drop the cast after 0x61 alike"
}

pub fn a_read_returns_its_message_after_any_number_of_other_frames_test() -> Nil {
  use <- owned_test.run(60_000)
  // Three hundred other messages come first: the read drops each and goes on, with
  // no count of reads or time that ends it before the wanted message.
  let others =
    list.repeat(Nil, times: 300)
    |> list.index_map(fn(_, index) { destroyed(unit_id: index + 1) })
  let wanted = bare(0x01C8)
  let game = written_in_one_send(list.append(others, [wanted]), after: <<>>)
  assert game_client.read_message(game:, have: <<>>, message_id: 0x01C8)
    == #(wanted, <<>>)
    as "the wanted message, with nothing kept beyond it"
  game_client.nothing_more(game:)
  game_client.close(game:)
}

pub fn a_read_until_waits_for_the_rest_of_a_message_that_arrives_in_parts_test() -> Nil {
  use <- owned_test.run(60_000)
  // One socket read gives at most the system's buffer (9216 bytes on macOS), so
  // a message the server wrote whole can reach the client in parts. The peer
  // writes the rest only once the client has taken the first part.
  let #(listener, port) = frame_peer.listen()
  let client = login_client.connect(port)
  let peer = frame_peer.accept(listener)
  let cipher = game_client.session_cipher(session_key: <<1:128>>)
  let assert Ok(whole) =
    encrypted_frame.wrap(GameWrapper, destroyed(unit_id: 5), cipher)
    as "the message wraps"
  let assert Ok(first) = bit_array.slice(whole, 0, 5)
  let assert Ok(rest) =
    bit_array.slice(whole, 5, bit_array.byte_size(whole) - 5)
  frame_peer.write(peer, first)
  let _writer =
    process.spawn(fn() {
      event_wait.until("the client to have taken the first part", fn() {
        frame_peer.bytes_received(client) >= bit_array.byte_size(first)
      })
      frame_peer.write(peer, rest)
    })
  let game = game_client.new(socket: client, cipher:, limit: socket_read.Open)
  assert game_client.read_until(game:, have: <<>>, found: fn(frames) {
      frames != []
    })
    == #([destroyed(unit_id: 5)], <<>>)
    as "the message, though its bytes came in two reads"
  game_client.close(game:)
}
