//// What a sitting (genesis_prime/sitting) changes in the server's settings: each
//// STS, auth and game connection is recorded on the wire when
//// `GENESIS_RECORD_DIR` names a folder, and nothing is recorded when it is not
//// set. Expected values come from these places.
//// - The switch's contract: `GENESIS_RECORD_DIR` names the folder, `GENESIS_PLAY_ACCOUNT`
////   the account whose rows the fixture keeps; the lookup is planted here, since the
////   environment is shared by every test.
//// - The recording's layout in `genesis_prime/wire_recording`: one file for
////   each connection, named after its rule, whose header names the rule and
////   whose closing line ends it when the server stops. A header holds what its
////   rule reads or writes: the game rule reads the game tables (their digest),
////   the auth rule writes the realm it hands the client to (the auth settings'
////   own `realm`), and the STS rule reads and writes neither.
//// - The rules' names (`rule_name` of each connection rule) and the three
////   listeners the server opens: the STS, the auth and the game server.
//// - The scripted client's login (`login_client`, `game_client`), written from
////   the fact file's records, which is what puts a connection on each listener.

import character_tables
import content_support
import database_support
import event_wait
import game_client
import genesis_prime
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/game_server_handoff
import genesis_prime/server
import genesis_prime/sitting
import genesis_prime/wire_recording.{Recording}
import genesis_prime/wire_recording/fixture
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import login_client
import login_support
import login_vectors as vector
import mug
import owned_test
import pog
import recording_support
import simplifile

pub fn a_sitting_records_each_sts_auth_and_game_connection_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let started =
    login_support.start_with(change: fn(settings) {
      sitting.recorded(
        settings:,
        folder:,
        client_build: 16_042,
        tables_digest: "C3D4",
      )
    })
  let ports = login_support.ports(started)
  let _account = login_support.insert_jim(started)
  let login =
    login_client.sts_login(
      ports:,
      name: vector.name,
      password: vector.password,
      seed: 7,
    )
  let auth = login_client.auth_login(ports:, login:, build: 16_042)
  let assert [_accepted, handoff] =
    login_client.read_frames(client: auth, have: <<>>, count: 2)
    as "the auth server answers a login with 0x0591 and 0x03DB"
  let assert Ok(handed) =
    game_server_handoff.decode(login_client.in_the_auth_wrapper(handoff).body)
    as "0x03DB decodes"
  let game =
    game_client.connect(
      port: ports.game_port,
      session_key: handed.session_key,
      account_name: vector.name,
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let answer = game_client.read(game:, count: 4)
  assert list.map(answer, fn(message) { message.message_id })
    == [0x097F, 0x0968, 0x0036, 0x0117]
    as "opcode.0x97f, opcode.0x968, opcode.0x36 and opcode.0x117 answer 0x07E0, the last the account's character list"
  game_client.nothing_more(game:)
  game_client.close(game:)
  // The tree's stop ends every connection, so each file has its closing line.
  login_support.stop(started)
  let assert Ok(names) = simplifile.read_directory(folder)
    as "the recording folder reads"
  let headers =
    list.map(list.sort(names, string.compare), fn(name) {
      let assert Ok(text) = simplifile.read(folder <> "/" <> name)
        as "a recording reads"
      let assert Ok(Recording(header:, ..)) = wire_recording.read(text)
        as { name <> " is a whole recording" }
      assert header.client_build == 16_042
        as "each header names the build the recorder was given"
      header
    })
  assert list.map(headers, fn(header) { header.rule })
    == [
      game_connection.rule_name,
      auth_connection.rule_name,
      sts_connection.rule_name,
    ]
    as "one file for each of the three connections, named after its rule"
  assert list.map(headers, fn(header) { header.tables_digest })
    == [Some("C3D4"), None, None]
    as "the game rule reads the tables and its header holds their digest; the auth and the STS rules read none"
  let realm = started.settings.login.auth.settings.realm
  assert list.map(headers, fn(header) { header.realm })
    == [
      None,
      Some(wire_recording.Realm(
        id: realm.id,
        name: realm.name,
        address: realm.game_server.address,
        port: realm.game_server.port,
      )),
      None,
    ]
    as "the auth rule writes the realm its settings hold, so its header holds it"
}

pub fn the_servers_own_settings_record_nothing_and_a_sitting_turns_it_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let settings = login_support.servers_settings()
  assert settings.login.sts.wire_recorder == None
    && settings.login.auth.wire_recorder == None
    && settings.game.wire_recorder == None
    as "the server's own settings turn no wire recording on"
  let recorded =
    sitting.recorded(
      settings:,
      folder: "unused",
      client_build: 16_042,
      tables_digest: "C3D4",
    )
  assert option.is_some(recorded.login.sts.wire_recorder)
    && option.is_some(recorded.login.auth.wire_recorder)
    && option.is_some(recorded.game.wire_recorder)
    as "a sitting turns it on for the STS, the auth and the game listener"
  assert server.Settings(..recorded, login: settings.login, game: settings.game)
    == settings
    as "and changes nothing but those three listeners"
}

pub fn a_set_record_directory_is_the_folder_a_sitting_records_into_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting.record_folder(read: list.key_find(
      [#("GENESIS_RECORD_DIR", "/sittings/one")],
      _,
    ))
    == Some("/sittings/one")
    as "GENESIS_RECORD_DIR names the folder"
}

pub fn an_unset_or_empty_record_directory_records_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  assert sitting.record_folder(read: list.key_find([], _)) == None
    as "no GENESIS_RECORD_DIR, no recording"
  assert sitting.record_folder(read: list.key_find(
      [#("GENESIS_RECORD_DIR", "")],
      _,
    ))
    == None
    as "an empty GENESIS_RECORD_DIR is no folder"
}

/// A sitting's configuration for a pool on `database`.
fn pool_config(
  shared: database_support.Shared,
  database: String,
) -> pog.Config {
  database_support.config(
    for: shared.settings,
    database:,
    pool_name: process.new_name("sitting_pool"),
    pool_size: 2,
  )
}

pub fn a_sitting_keeps_the_play_accounts_rows_in_a_folder_it_makes_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let _inserted =
    content_support.psql(
      database:,
      sql: "insert into account (login_name, srp_salt, srp_verifier, game_account_id) values ('genesis', '\\x01'::bytea, '\\x02'::bytea, '01234567-89ab-cdef-0123-456789abcdef')",
    )
  let sitting_folder = folder <> "/a/sitting"
  let assert Ok(Nil) =
    sitting.begin(
      folder: sitting_folder,
      database: pool_config(shared, database),
      read: list.key_find([#("GENESIS_PLAY_ACCOUNT", "Genesis")], _),
    )
    as "a sitting begins when the account is in the database"
  let assert Ok(text) =
    simplifile.read(sitting_folder <> "/" <> fixture.file_name)
    as "the fixture was saved into the folder the sitting made"
  assert string.contains(text, "'genesis'")
    as "the fixture holds the account, named in lower case as the STS login names it"
}

pub fn a_sitting_with_no_play_account_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let started =
    sitting.begin(
      folder:,
      database: pool_config(shared, database),
      read: list.key_find([], _),
    )
  assert started == Error(sitting.NoPlayAccount)
    as "the fixture would keep no account, so the sitting does not begin"
}

pub fn a_sitting_whose_account_the_database_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let started =
    sitting.begin(
      folder:,
      database: pool_config(shared, database),
      read: list.key_find([#("GENESIS_PLAY_ACCOUNT", "nobody")], _),
    )
  assert started
    == Error(
      sitting.FixtureNotSaved(fixture.NoSuchAccount(login_name: "nobody")),
    )
    as "the fixture's own refusal of an account the database has none of"
}

pub fn the_servers_start_records_a_connection_when_the_record_directory_is_set_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let _inserted =
    content_support.psql(
      database:,
      sql: "insert into account (login_name, srp_salt, srp_verifier, game_account_id) values ('genesis', '\\x01'::bytea, '\\x02'::bytea, '01234567-89ab-cdef-0123-456789abcdef')",
    )
  let sitting_folder = folder <> "/sitting"
  let started =
    login_support.start_on(shared:, database:, change: fn(settings) {
      genesis_prime.with_sitting(
        settings:,
        tables: character_tables.shared(),
        database: pool_config(shared, database),
        read: list.key_find(
          [
            #("GENESIS_RECORD_DIR", sitting_folder),
            #("GENESIS_PLAY_ACCOUNT", "genesis"),
          ],
          _,
        ),
      )
    })
  let client = login_client.connect(login_support.ports(started).sts_port)
  // The connection is recorded once the listener has accepted it.
  event_wait.until("the connection's recording is made", fn() {
    simplifile.read_directory(sitting_folder)
    |> result.map(list.any(_, string.ends_with(_, ".jsonl")))
    |> result.unwrap(False)
  })
  let _closed = mug.shutdown(client)
  // The tree's stop ends the connection, so its file has its closing line.
  login_support.stop(started)
  let assert Ok(names) = simplifile.read_directory(sitting_folder)
    as "the server's start made the sitting's folder"
  assert list.contains(names, fixture.file_name)
    as "the fixture of the play account was saved before the first connection"
  let recordings = list.filter(names, string.ends_with(_, ".jsonl"))
  assert list.length(recordings) == 1
    as "the one connection made was recorded, into the folder GENESIS_RECORD_DIR named"
  let assert [name] = recordings
  let assert Ok(text) = simplifile.read(sitting_folder <> "/" <> name)
    as "the recording reads"
  let assert Ok(Recording(header:, ..)) = wire_recording.read(text)
    as "the recording is whole"
  assert header.rule == sts_connection.rule_name as "it is the STS connection's"
}

pub fn the_servers_start_records_nothing_when_the_record_directory_is_not_set_test() -> Nil {
  use <- owned_test.run(60_000)
  let settings = login_support.servers_settings()
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  assert genesis_prime.with_sitting(
      settings:,
      tables: character_tables.shared(),
      database: pool_config(shared, database),
      read: list.key_find([], _),
    )
    == settings
    as "the settings are the server's own, with no recorder on any listener"
}
