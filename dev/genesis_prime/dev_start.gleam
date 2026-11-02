//// Starts the server for a live session, as `gleam run` does, with two
//// changes only a developer makes: each STS, auth and game connection is
//// recorded on the wire into a folder, for replay, and the auth server can
//// plant one frame the client does not handle right after its hello, to prove
//// the client's failure log brings back its id.
////
//// `gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]`
////
//// - `recording folder`: where each connection's recording
////   (genesis_prime/wire_recording) is written, made when it is missing, with
////   the fixture of the rows the database holds when the session starts
////   (genesis_prime/wire_recording/fixture); by convention
////   `test/wire_recording/<date>-<flow>`.
//// - `planted message id`: a message id, such as `0x0914`, sent once with an
////   empty body in the auth wrapper after the hello. Left out, nothing is
////   planted.
////
//// The environment is the one `gleam run` reads (genesis_prime).

import argv
import genesis_prime
import genesis_prime/client_archive
import genesis_prime/connection/frame.{Frame}
import genesis_prime/dev_database
import genesis_prime/login/auth_connection
import genesis_prime/server
import genesis_prime/table/loader/store
import genesis_prime/wire_recording/fixture
import genesis_prime/wire_recording/recorder.{type WireRecorder}
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// Why the dev start cannot begin.
type Failure {
  WrongArguments
  NotAMessageId(text: String)
  FolderNotMade(path: String, reason: String)
  FixtureNotSaved(error: fixture.FixtureError)
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
  use #(folder, planted) <- result.try(arguments())
  use _ <- result.try(
    simplifile.create_directory_all(folder)
    |> result.map_error(fn(error) {
      FolderNotMade(path: folder, reason: simplifile.describe_error(error))
    }),
  )
  let #(tables, loaded) = genesis_prime.load_tables()
  let settings = genesis_prime.settings(tables:)
  use Nil <- result.try(save_fixture(folder))
  let auth =
    server.Served(
      ..settings.login.auth,
      settings: planted_after_hello(settings.login.auth.settings, planted),
    )
  genesis_prime.start(
    settings: recorded(
      settings: server.Settings(
        ..settings,
        login: server.Login(..settings.login, auth:),
      ),
      recorder: recorder.new(
        folder:,
        client_build: client_archive.target_build,
        tables_digest: Some(store.digest(tables)),
      ),
    ),
    tables: loaded,
  )
  Ok(Nil)
}

/// The settings with `recorder` on the STS, auth and game listeners: each
/// connection of them is recorded into its folder, the header naming the
/// client's build and the digest of the game tables the server loaded. Nothing
/// else changes.
pub fn recorded(
  settings settings: server.Settings,
  recorder recorder: WireRecorder,
) -> server.Settings {
  let login = settings.login
  server.Settings(
    ..settings,
    login: server.Login(
      sts: server.Served(..login.sts, wire_recorder: Some(recorder)),
      auth: server.Served(..login.auth, wire_recorder: Some(recorder)),
    ),
    game: server.Served(..settings.game, wire_recorder: Some(recorder)),
  )
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

/// Saves the rows the database holds into the folder's fixture before the
/// server accepts a connection, from a pool of its own on the database the
/// server's settings name.
fn save_fixture(folder: String) -> Result(Nil, Failure) {
  use database <- result.try(
    dev_database.connect()
    |> result.map_error(fn(failure) {
      FixtureNotSaved(
        error: fixture.DatabaseFailed(reason: dev_database.describe(
          failure:,
          change: "read the rows",
        )),
      )
    }),
  )
  fixture.write(database, folder <> "/" <> fixture.file_name)
  |> result.map_error(fn(error) { FixtureNotSaved(error:) })
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
    FolderNotMade(path:, reason:) ->
      "the recording folder " <> path <> " could not be made: " <> reason
    FixtureNotSaved(error:) ->
      "the fixture could not be saved: " <> describe_fixture(error)
  }
}

fn describe_fixture(error: fixture.FixtureError) -> String {
  case error {
    fixture.FileFailed(path:, reason:) -> path <> ": " <> reason
    fixture.StatementFailed(statement:, reason:) -> statement <> ": " <> reason
    fixture.DatabaseFailed(reason:) -> reason
  }
}
