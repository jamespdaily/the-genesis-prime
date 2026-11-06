//// A sitting: one run of the server whose STS, auth and game connections are
//// recorded on the wire (genesis_prime/wire_recording) into a folder, for
//// replay. The server records when `GENESIS_RECORD_DIR` names the folder, and
//// records nothing when it is not set.
////
//// ```
//// GENESIS_RECORD_DIR --> record_folder --> begin (the folder, the account's
////                                          fixture) --> recorded settings
//// ```
////
//// - The folder is made when it is missing, and holds the fixture of the
////   account `GENESIS_PLAY_ACCOUNT` names and its characters as the database
////   holds them when the sitting starts (genesis_prime/wire_recording/fixture),
////   which a replay starts from. A sitting with no account to keep is refused.
//// - A header holds only what its rule reads or writes: the game rule reads the
////   game tables, so its header holds their digest, and the auth rule writes the
////   realm it hands the client to, so its header holds the realm; the STS rule
////   reads and writes neither.

import genesis_prime/login/recorded_realm
import genesis_prime/server
import genesis_prime/store/ready_pool
import genesis_prime/wire_recording/fixture
import genesis_prime/wire_recording/recorder
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pog
import simplifile

/// Why a sitting cannot begin.
pub type Failure {
  /// The recording folder could not be made.
  FolderNotMade(path: String, reason: String)
  /// `GENESIS_PLAY_ACCOUNT` is not set, so the fixture would keep no account.
  NoPlayAccount
  /// The pool for the fixture could not be started or never had a connection.
  DatabaseUnreachable
  /// The fixture could not be saved.
  FixtureNotSaved(error: fixture.FixtureError)
}

/// The folder `GENESIS_RECORD_DIR` names, read through `read` (the
/// environment's own lookup, in the server): `None` when it is not set or is
/// empty, which is no recording.
pub fn record_folder(
  read read: fn(String) -> Result(String, Nil),
) -> Option(String) {
  case read("GENESIS_RECORD_DIR") {
    Ok(folder) if folder != "" -> Some(folder)
    Ok(_) | Error(Nil) -> None
  }
}

/// Makes the recording folder and saves the fixture into it, before the server
/// accepts a connection: the rows of the account `GENESIS_PLAY_ACCOUNT` names
/// (lower case, as the STS login names it, read through `read`) and of its
/// characters, from a pool of its own on `database`.
pub fn begin(
  folder folder: String,
  database database: pog.Config,
  read read: fn(String) -> Result(String, Nil),
) -> Result(Nil, Failure) {
  use _ <- result.try(
    simplifile.create_directory_all(folder)
    |> result.map_error(fn(error) {
      FolderNotMade(path: folder, reason: simplifile.describe_error(error))
    }),
  )
  use account <- result.try(case read("GENESIS_PLAY_ACCOUNT") {
    Ok(name) if name != "" -> Ok(string.lowercase(name))
    Ok(_) | Error(Nil) -> Error(NoPlayAccount)
  })
  use pool <- result.try(
    ready_pool.connect(database)
    |> result.replace_error(DatabaseUnreachable),
  )
  fixture.write(pool, folder <> "/" <> fixture.file_name, [account])
  |> result.map_error(fn(error) { FixtureNotSaved(error:) })
}

/// The settings with a recorder on the STS, auth and game listeners: each
/// connection of them is recorded into `folder`, the header naming the client's
/// build. Nothing else changes.
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

/// A sentence that says why the sitting cannot begin.
pub fn describe(failure: Failure) -> String {
  case failure {
    FolderNotMade(path:, reason:) ->
      "the recording folder " <> path <> " could not be made: " <> reason
    NoPlayAccount ->
      "GENESIS_PLAY_ACCOUNT names no account: set it to the login name of the account the client logs in with"
    DatabaseUnreachable ->
      "the fixture could not be saved: the database could not be reached: check PGHOST, PGPORT, PGUSER, PGPASSWORD and PGDATABASE"
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
