//// The scripted client's `read`: it gives the messages a test asks for however
//// the server's bytes were split across socket reads. A peer that writes three
//// messages in one send makes one read hold more than the test asks for; the
//// message beyond the count belongs to the next read (a game message arrives
//// inside 0x03DC with every byte after its length enciphered: opcode.0x3dc).

import frame_peer
import game_client
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/unit_destroyed
import gleam/bit_array
import gleam/list
import login_client
import owned_test

fn destroyed(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_destroyed.encode(unit_destroyed.UnitDestroyed(unit_id:, field_2: 0))
  Frame(0x0355, body)
}

pub fn a_poll_after_a_read_gives_the_messages_the_read_kept_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(listener, port) = frame_peer.listen()
  let cipher = game_client.session_cipher(session_key: <<1:128>>)
  let assert Ok(wrapped) =
    list.try_map(
      [destroyed(unit_id: 1), destroyed(unit_id: 2)],
      encrypted_frame.wrap(GameWrapper, _, cipher),
    )
    as "the messages wrap"
  frame_peer.write_once_accepted(listener, bit_array.concat(wrapped))
  let game = game_client.new(socket: login_client.connect(port), cipher:)
  assert game_client.read(game:, count: 1) == [destroyed(unit_id: 1)]
  assert game_client.poll(game:, have: <<>>, wait_ms: 0)
    == Ok(#([destroyed(unit_id: 2)], <<>>))
    as "the message the read kept, though the socket holds no more"
  game_client.close(game:)
}

pub fn a_read_that_holds_more_messages_than_asked_for_keeps_the_rest_for_the_next_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(listener, port) = frame_peer.listen()
  let cipher = game_client.session_cipher(session_key: <<1:128>>)
  let sent = [
    destroyed(unit_id: 1),
    destroyed(unit_id: 2),
    destroyed(unit_id: 3),
  ]
  let assert Ok(wrapped) =
    list.try_map(sent, encrypted_frame.wrap(GameWrapper, _, cipher))
    as "the messages wrap"
  frame_peer.write_once_accepted(listener, bit_array.concat(wrapped))
  let socket = login_client.connect(port)
  let game = game_client.new(socket:, cipher:)
  assert game_client.read(game:, count: 2)
    == [destroyed(unit_id: 1), destroyed(unit_id: 2)]
    as "the first two messages, though the one read held a third"
  assert game_client.read(game:, count: 1) == [destroyed(unit_id: 3)]
    as "the third message, which the first read kept"
  game_client.close(game:)
}
