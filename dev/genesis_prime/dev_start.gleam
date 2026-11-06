//// Starts the server for a live session, as `gleam run` does, with two
//// changes: the recording folder is given as an argument, which sets
//// `GENESIS_RECORD_DIR` for the server's own start (genesis_prime/sitting), and
//// the auth server can plant one frame the client does not handle right after
//// its hello, to prove the client's failure log brings back its id, which only
//// a developer asks for.
////
//// `gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]`
////
//// - `recording folder`: where each connection's recording
////   (genesis_prime/wire_recording) is written, with the fixture of the
////   session's account (genesis_prime/sitting); by convention
////   `test/wire_recording/<date>-<flow>`.
//// - `planted message id`: a message id, such as `0x0914`, sent once with an
////   empty body in the auth wrapper after the hello. Left out, nothing is
////   planted.
////
//// The environment is the one `gleam run` reads (genesis_prime), and
//// `GENESIS_PLAY_ACCOUNT`, the login name of the account the session's client
//// logs in with (the playing-live skill), whose rows the fixture keeps.

import argv
import envoy
import genesis_prime
import genesis_prime/connection/frame.{Frame}
import genesis_prime/dev_exit
import genesis_prime/login/auth_connection
import genesis_prime/server
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/string

/// Why the dev start cannot begin.
type Failure {
  WrongArguments
  NotAMessageId(text: String)
}

pub fn main() -> Nil {
  case arguments() {
    Ok(#(folder, planted)) -> {
      envoy.set("GENESIS_RECORD_DIR", folder)
      genesis_prime.run(change: fn(settings) {
        let auth =
          server.Served(
            ..settings.login.auth,
            settings: planted_after_hello(settings.login.auth.settings, planted),
          )
        server.Settings(
          ..settings,
          login: server.Login(..settings.login, auth:),
        )
      })
    }
    Error(failure) -> {
      io.println_error(describe(failure))
      dev_exit.halt(1)
    }
  }
}

/// The auth rule's settings with the frame to plant, when there is one.
fn planted_after_hello(
  settings: auth_connection.Settings,
  planted: Option(Int),
) -> auth_connection.Settings {
  auth_connection.Settings(
    ..settings,
    planted: option.map(planted, fn(message_id) {
      Frame(message_id:, body: <<>>)
    }),
  )
}

fn arguments() -> Result(#(String, Option(Int)), Failure) {
  case argv.load().arguments {
    [folder] -> Ok(#(folder, None))
    [folder, text] -> {
      let digits = case string.starts_with(string.lowercase(text), "0x") {
        True -> string.drop_start(text, 2)
        False -> text
      }
      case int.base_parse(digits, 16) {
        Ok(message_id) if message_id >= 0 && message_id <= 0xFFFF ->
          Ok(#(folder, Some(message_id)))
        _ -> Error(NotAMessageId(text:))
      }
    }
    _ -> Error(WrongArguments)
  }
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]"
    NotAMessageId(text:) ->
      text <> " is not a message id: write it as 0x0914, 16 bits in hexadecimal"
  }
}
