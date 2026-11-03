//// The scripted client's poll (`game_client.poll`): what it gives of the bytes
//// it already holds before it waits for the server. Expected values come from
//// the wire: a game message arrives inside 0x03DC with every byte after its
//// length enciphered (opcode.0x3dc, `genesis_prime/connection/encrypted_frame`),
//// and a read that held more than one message keeps the bytes beyond them
//// (`game_client.read_kept`), which a later read must use.

import game_client.{Game}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/message/unit_destroyed
import gleam/bit_array
import login_client
import login_support
import owned_test

pub fn a_poll_gives_the_whole_messages_it_already_holds_without_waiting_for_the_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let started = login_support.start()
  // A socket the server writes nothing to: the STS listener answers only what
  // a client sends it.
  let socket = login_client.connect(login_support.ports(started).sts_port)
  let cipher = game_client.session_cipher(session_key: <<1:128>>)
  let game = Game(socket:, cipher:)
  let assert Ok(body) =
    unit_destroyed.encode(unit_destroyed.UnitDestroyed(unit_id: 9, field_2: 0))
  let assert Ok(whole) =
    encrypted_frame.wrap(GameWrapper, Frame(0x0355, body), cipher)
  let assert Ok(next) =
    encrypted_frame.wrap(GameWrapper, Frame(0x0355, body), cipher)
  let assert Ok(partial) = bit_array.slice(next, 0, 5)
  assert game_client.poll(
      game:,
      have: bit_array.append(whole, partial),
      wait_ms: 0,
    )
    == Ok(#([Frame(0x0355, body)], partial))
    as "the message held whole is given, and the start of the next kept"
  game_client.close(game:)
  login_support.stop(started)
}
