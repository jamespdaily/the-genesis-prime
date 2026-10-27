//// Starts the server for a live session, as `gleam run` does, with two
//// changes only a developer makes: each STS and auth connection is recorded
//// into a folder, for replay, and the auth server can plant one frame the
//// client does not handle right after its hello, to prove the client's
//// failure log brings back its id.
////
//// `gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]`
////
//// - `recording folder`: where each connection's recording is written, made
////   when it is missing; by convention `test/recording/<date>-<flow>`.
//// - `planted message id`: a message id, such as `0x0914`, sent once with an
////   empty body in the auth wrapper after the hello. Left out, nothing is
////   planted.
////
//// The environment is the one `gleam run` reads (genesis_prime).

import argv
import genesis_prime
import genesis_prime/connection/frame.{Frame}
import genesis_prime/login/auth_connection
import genesis_prime/rule_recording.{Header}
import genesis_prime/rule_recording/file
import genesis_prime/rule_types
import genesis_prime/server
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile

/// The client's build: the build of the archive index and of the auth server's
/// version check (fact `archive_index.header`).
const client_build = 16_042

/// Why the dev start cannot begin.
type Failure {
  WrongArguments
  NotAMessageId(text: String)
  FolderNotMade(path: String, reason: String)
  DigestFailed(module: String)
}

pub fn main() -> Nil {
  case start() {
    Ok(Nil) -> Nil
    Error(failure) -> {
      io.println_error(describe(failure))
      halt(1)
    }
  }
}

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

fn start() -> Result(Nil, Failure) {
  use #(folder, planted) <- try(arguments())
  use _ <- try(
    simplifile.create_directory_all(folder)
    |> map_error(fn(error) {
      FolderNotMade(path: folder, reason: simplifile.describe_error(error))
    }),
  )
  let tables = genesis_prime.load_tables()
  let settings = genesis_prime.settings()
  let login = settings.login
  let auth =
    auth_connection.Settings(
      ..login.auth,
      planted: option.map(planted, fn(message_id) {
        Frame(message_id:, body: <<>>)
      }),
    )
  use sts_digest <- try(digest("genesis_prime/login/sts_connection"))
  use auth_digest <- try(digest("genesis_prime/login/auth_connection"))
  let login =
    server.Login(
      ..login,
      auth:,
      sts_recorder: Some(file.recorder(
        folder:,
        header: Header(
          format: rule_recording.format,
          rule: "genesis_prime/login/sts_connection",
          client_build:,
          tables_digest: None,
          settings: login.sts,
          types_digest: sts_digest,
        ),
      )),
      auth_recorder: Some(file.recorder(
        folder:,
        header: Header(
          format: rule_recording.format,
          rule: "genesis_prime/login/auth_connection",
          client_build:,
          tables_digest: None,
          settings: auth,
          types_digest: auth_digest,
        ),
      )),
    )
  genesis_prime.start(settings: server.Settings(..settings, login:), tables:)
  Ok(Nil)
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

fn digest(module: String) -> Result(String, Failure) {
  rule_types.digest(rule_module: module, source_roots: ["src"])
  |> map_error(fn(_) { DigestFailed(module:) })
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]"
    NotAMessageId(text:) ->
      text <> " is not a message id: write it as 0x0914, 16 bits in hexadecimal"
    FolderNotMade(path:, reason:) ->
      "the recording folder " <> path <> " could not be made: " <> reason
    DigestFailed(module:) ->
      "the types of "
      <> module
      <> " could not be read for the recording's header"
  }
}

fn try(
  result: Result(a, Failure),
  next: fn(a) -> Result(b, Failure),
) -> Result(b, Failure) {
  case result {
    Ok(value) -> next(value)
    Error(failure) -> Error(failure)
  }
}

fn map_error(
  result: Result(a, e),
  with: fn(e) -> Failure,
) -> Result(a, Failure) {
  case result {
    Ok(value) -> Ok(value)
    Error(error) -> Error(with(error))
  }
}
