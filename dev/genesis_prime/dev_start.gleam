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
////   the fixture of the session's account and its characters as the database
////   holds them when the session starts (genesis_prime/wire_recording/fixture);
////   by convention `test/wire_recording/<date>-<flow>`.
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
import genesis_prime/client_archive
import genesis_prime/connection/frame.{Frame}
import genesis_prime/dev_database
import genesis_prime/login/auth_connection
import genesis_prime/login/recorded_realm
import genesis_prime/server
import genesis_prime/table/loader/store
import genesis_prime/wire_recording/fixture
import genesis_prime/wire_recording/recorder
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
  NoPlayAccount
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
  use account <- result.try(play_account())
  let #(tables, loaded) = genesis_prime.load_tables()
  let settings = genesis_prime.settings(tables:)
  use Nil <- result.try(save_fixture(folder:, account:))
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
      folder:,
      client_build: client_archive.target_build,
      tables_digest: store.digest(tables),
    ),
    tables: loaded,
  )
  Ok(Nil)
}

/// The settings with a recorder on the STS, auth and game listeners: each
/// connection of them is recorded into `folder`, the header naming the client's
/// build. Only what a rule reads or writes is recorded in its header: the game
/// rule reads the game tables, so its header holds their digest, and the auth
/// rule writes the realm it hands the client to, so its header holds the realm;
/// the STS rule reads and writes neither. Nothing else changes.
pub fn recorded(
  settings settings: server.Settings,
  folder folder: String,
  client_build client_build: Int,
  tables_digest tables_digest: String,
) -> server.Settings {
  let login = settings.login
  let recorder_of = fn(tables_digest, realm) {
    Some(recorder.new(folder:, client_build:, tables_digest:, realm:))
  }
  server.Settings(
    ..settings,
    login: server.Login(
      sts: server.Served(..login.sts, wire_recorder: recorder_of(None, None)),
      auth: server.Served(
        ..login.auth,
        wire_recorder: recorder_of(
          None,
          Some(recorded_realm.to_header(login.auth.settings.realm)),
        ),
      ),
    ),
    game: server.Served(
      ..settings.game,
      wire_recorder: recorder_of(Some(tables_digest), None),
    ),
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

/// The login name of the account the session's client logs in with, lower case
/// as the STS login names it, from the environment.
fn play_account() -> Result(String, Failure) {
  case envoy.get("GENESIS_PLAY_ACCOUNT") {
    Ok(name) if name != "" -> Ok(string.lowercase(name))
    Ok(_) | Error(Nil) -> Error(NoPlayAccount)
  }
}

/// Saves the rows of the account and of its characters, and the state of the id
/// sequences, into the folder's fixture before the server accepts a connection,
/// from a pool of its own on the database the server's settings name.
fn save_fixture(
  folder folder: String,
  account account: String,
) -> Result(Nil, Failure) {
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
  fixture.write(database, folder <> "/" <> fixture.file_name, [account])
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
    NoPlayAccount ->
      "GENESIS_PLAY_ACCOUNT names no account: set it to the login name of the account the client logs in with"
    FixtureNotSaved(error:) ->
      "the fixture could not be saved: " <> describe_fixture(error)
  }
}

fn describe_fixture(error: fixture.FixtureError) -> String {
  case error {
    fixture.FileFailed(path:, reason:) -> path <> ": " <> reason
    fixture.StatementFailed(statement:, reason:) -> statement <> ": " <> reason
    fixture.DatabaseFailed(reason:) -> reason
    fixture.NoSuchAccount(login_name:) ->
      "the database holds no account " <> login_name
  }
}
