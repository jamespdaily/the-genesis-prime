//// What the dev start changes in the server's settings for a live session
//// (dev/genesis_prime/dev_start): each STS, auth and game connection is
//// recorded on the wire, and the server's own start records nothing. Expected
//// values come from these places.
//// - The recording's layout in `genesis_prime/wire_recording`: one file for
////   each connection, named after its rule, whose header names the rule and
////   whose closing line ends it when the server stops.
//// - The rules' names (`rule_name` of each connection rule) and the three
////   listeners the server opens: the STS, the auth and the game server.
//// - The scripted client's login (`login_client`, `game_client`), written from
////   the fact file's records, which is what puts a connection on each listener.

import game_client
import genesis_prime/dev_start
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/game_server_handoff
import genesis_prime/server
import genesis_prime/wire_recording.{Recording}
import genesis_prime/wire_recording/recorder
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import login_client
import login_support
import login_vectors as vector
import owned_test
import recording_support
import simplifile

pub fn the_dev_start_records_each_sts_auth_and_game_connection_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let started =
    login_support.start_with(change: fn(settings) {
      dev_start.recorded(
        settings:,
        recorder: recorder.new(
          folder:,
          client_build: 16_042,
          tables_digest: Some("C3D4"),
        ),
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
  let assert [_level, _listed] = game_client.read(game:, count: 2)
    as "the game server lists the account's characters"
  game_client.close(game:)
  // The tree's stop ends every connection, so each file has its closing line.
  login_support.stop(started)
  let assert Ok(names) = simplifile.read_directory(folder)
    as "the recording folder reads"
  let rules =
    list.map(list.sort(names, string.compare), fn(name) {
      let assert Ok(text) = simplifile.read(folder <> "/" <> name)
        as "a recording reads"
      let assert Ok(Recording(header:, ..)) = wire_recording.read(text)
        as { name <> " is a whole recording" }
      assert header.client_build == 16_042
        && header.tables_digest == Some("C3D4")
        as "each header names the build and the tables the recorder was given"
      header.rule
    })
  assert rules
    == [
      game_connection.rule_name,
      auth_connection.rule_name,
      sts_connection.rule_name,
    ]
    as "one file for each of the three connections, named after its rule"
}

pub fn the_servers_own_settings_record_nothing_and_the_dev_start_turns_it_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let settings = login_support.servers_settings()
  assert settings.login.sts.wire_recorder == None
    && settings.login.auth.wire_recorder == None
    && settings.game.wire_recorder == None
    as "the server's own start turns no wire recording on"
  let wire =
    recorder.new(folder: "unused", client_build: 16_042, tables_digest: None)
  let recorded = dev_start.recorded(settings:, recorder: wire)
  assert recorded.login.sts.wire_recorder == Some(wire)
    && recorded.login.auth.wire_recorder == Some(wire)
    && recorded.game.wire_recorder == Some(wire)
    as "the dev start turns it on for the STS, the auth and the game listener"
  assert server.Settings(..recorded, login: settings.login, game: settings.game)
    == settings
    as "and changes nothing but those three listeners"
}
