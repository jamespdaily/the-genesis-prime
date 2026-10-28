//// Starts the server for a live session, as `gleam run` does, with two
//// changes only a developer makes: each STS, auth and game connection,
//// Sessions and each map is recorded into a folder, for replay, and the auth
//// server can plant one frame the client does not handle right after its
//// hello, to prove the client's failure log brings back its id.
////
//// `gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]`
////
//// - `recording folder`: where each connection's, Sessions' and each map's
////   recording is written, made when it is missing; a map's file is named by
////   its world, instance and incarnation; by convention
////   `test/rule_recording/<date>-<flow>`.
////   The relay's recordings, a different format, are in `test/recording`.
//// - `planted message id`: a message id, such as `0x0914`, sent once with an
////   empty body in the auth wrapper after the hello. Left out, nothing is
////   planted.
////
//// The environment is the one `gleam run` reads (genesis_prime).

import argv
import genesis_prime
import genesis_prime/client_archive
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/rule_recording/file
import genesis_prime/rule_types
import genesis_prime/server
import genesis_prime/sessions
import genesis_prime/table/loader/store
import genesis_prime/world_map/map as world_map
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
  use #(folder, planted) <- result.try(arguments())
  use _ <- result.try(
    simplifile.create_directory_all(folder)
    |> result.map_error(fn(error) {
      FolderNotMade(path: folder, reason: simplifile.describe_error(error))
    }),
  )
  use sts_digest <- result.try(digest(sts_connection.rule_name))
  use auth_digest <- result.try(digest(auth_connection.rule_name))
  use game_digest <- result.try(digest(game_connection.rule_name))
  use sessions_digest <- result.try(digest(sessions.rule_name))
  use map_digest <- result.try(digest(world_map.rule_name))
  let #(tables, loaded) = genesis_prime.load_tables()
  let settings = genesis_prime.settings(tables:)
  let login = settings.login
  let auth =
    auth_connection.Settings(
      ..login.auth.settings,
      planted: option.map(planted, fn(message_id) {
        Frame(message_id:, body: <<>>)
      }),
    )
  let login =
    server.Login(
      sts: server.Served(
        ..login.sts,
        recorder: Some(recorder(folder:, tables:, types_digest: sts_digest)),
      ),
      auth: server.Served(
        ..login.auth,
        settings: auth,
        recorder: Some(recorder(folder:, tables:, types_digest: auth_digest)),
      ),
    )
  let game =
    server.Served(
      ..settings.game,
      recorder: Some(recorder(folder:, tables:, types_digest: game_digest)),
    )
  genesis_prime.start(
    settings: server.Settings(
      ..settings,
      login:,
      game:,
      sessions_recorder: Some(recorder(
        folder:,
        tables:,
        types_digest: sessions_digest,
      )),
      world: server.World(
        ..settings.world,
        map_recordings: Some(recorder(
          folder:,
          tables:,
          types_digest: map_digest,
        )),
      ),
    ),
    tables: loaded,
  )
  Ok(Nil)
}

/// The recorder of one rule's connections: a file in the folder for each,
/// with a header that names the client's build and the digest of the game
/// tables the server loaded; the shell adds the rule's name and settings.
fn recorder(
  folder folder: String,
  tables tables: store.Tables,
  types_digest types_digest: String,
) -> file.Recorder {
  file.recorder(
    folder:,
    client_build: client_archive.target_build,
    tables_digest: Some(store.digest(tables)),
    types_digest:,
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

fn digest(module: String) -> Result(String, Failure) {
  rule_types.digest(rule_module: module, source_roots: ["src"])
  |> result.replace_error(DigestFailed(module:))
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
