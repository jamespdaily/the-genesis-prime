//// The live check's second login: logs in to the running server as the account
//// `GENESIS_PLAY_ACCOUNT` with `GENESIS_PLAY_PASSWORD`, as the scripted client
//// does in the tests, and prints what the game server sends: the character
//// list, or the disconnect it gets when another login to the account takes
//// the session over. Run it while the real client is on the select screen:
////
//// ```
//// gleam run -m second_login
//// ```
////
//// It connects to this machine's listeners on the server's default ports (STS
//// 6600, auth 23115, game 24000), which are the ones a playable server opens
//// (the playing-live skill). A test module and not a dev tool, so it shares
//// the login and game clients of the tests, `login_client` and `game_client`.
//// Everything else is in them: the STS login, the auth login whose 0x03DB
//// hand-off holds the session key, the game hello, 0x058F and the cipher.

import envoy
import game_client
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/character_list
import genesis_prime/message/character_list_entry
import genesis_prime/message/disconnect_notice
import genesis_prime/message/disconnect_reason
import genesis_prime/message/game_server_handoff
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import login_client.{Ports}
import tcp_client

/// How long to wait for the game server's next bytes, in milliseconds.
const wait_ms = 5000

pub fn main() -> Nil {
  let account = variable("GENESIS_PLAY_ACCOUNT")
  let password = variable("GENESIS_PLAY_PASSWORD")
  let ports = Ports(sts_port: 6600, auth_port: 23_115, game_port: 24_000)
  let login = login_client.sts_login(ports:, name: account, password:, seed: 7)
  let auth = login_client.auth_login(ports:, login:, build: 16_042)
  let assert [_accepted, handoff] =
    login_client.read_frames(client: auth, have: <<>>, count: 2)
    as "the auth server answers a login with 0x0591 and 0x03DB"
  let assert Ok(handed) =
    game_server_handoff.decode(login_client.in_the_auth_wrapper(handoff).body)
    as "0x03DB decodes"
  io.println("second login: logged in, the session key is held by the hand-off")
  let game =
    game_client.connect(
      port: ports.game_port,
      session_key: handed.session_key,
      account_name: account,
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  list.each(heard(game:, have: <<>>, frames: []), describe)
}

/// The environment variable `name`, or a stop that names it.
fn variable(name: String) -> String {
  let assert Ok(value) = envoy.get(name)
    as { "set " <> name <> " (the playing-live skill)" }
  value
}

/// The messages the game server writes, until the character list or a
/// disconnect arrives, or the server stops writing.
fn heard(
  game game: game_client.Game,
  have have: BitArray,
  frames frames: List(Frame),
) -> List(Frame) {
  let assert Ok(#(outers, rest)) = frame.decode(have)
    as "the game server wrote bytes that are frames"
  let frames =
    list.append(
      frames,
      list.map(outers, game_client.in_the_game_wrapper(_, game.cipher)),
    )
  case list.any(frames, ends_the_wait) {
    True -> frames
    False ->
      case tcp_client.receive_some(game.socket, wait_ms) {
        Ok(bytes) -> heard(game:, have: <<rest:bits, bytes:bits>>, frames:)
        Error(Nil) -> frames
      }
  }
}

/// 0x0117, the character list, or 0x036A, a disconnect.
fn ends_the_wait(message: Frame) -> Bool {
  message.message_id == 0x0117 || message.message_id == 0x036A
}

fn describe(message: Frame) -> Nil {
  case message.message_id {
    0x0117 -> {
      let assert Ok(listed) = character_list.decode(message.body)
        as "0x0117 decodes"
      io.println(
        "second login: the character list, "
        <> int.to_string(list.length(listed.characters))
        <> " characters: "
        <> string.join(
          list.map(
            listed.characters,
            fn(entry: character_list_entry.CharacterListEntry) { entry.name },
          ),
          ", ",
        ),
      )
    }
    0x036A -> {
      let assert Ok(notice) = disconnect_notice.decode(message.body)
        as "0x036A decodes"
      io.println(
        "second login: disconnected, reason "
        <> int.to_string(disconnect_reason.to_value(notice.reason)),
      )
    }
    id ->
      io.println(
        "second login: message 0x" <> string.uppercase(int.to_base16(id)),
      )
  }
}
