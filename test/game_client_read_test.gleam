//// The scripted client's reads: they give the messages a test asks for however
//// the server's bytes were split across socket reads. A peer that writes
//// several messages in one send makes one read hold more than the test asks
//// for; the message beyond the count belongs to the next read (a game message
//// arrives inside 0x03DC with every byte after its length enciphered:
//// opcode.0x3dc; the pong answering a ping arrives bare: opcode.0x1).

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
  game_client.new(socket: login_client.connect(port), cipher:)
}

/// Whether `body` crashed, run in a process of its own so the test goes on.
fn crashes(body: fn() -> Nil) -> Bool {
  let monitor = process.spawn_unlinked(body) |> process.monitor
  let assert Ok(down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 10_000)
    as "the process ended"
  case down.reason {
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
