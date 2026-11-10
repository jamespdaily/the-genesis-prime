//// What the tests of the wire replay share: a session written by hand into a
//// folder (a fixture and one recording for each connection), and a replay of
//// it against a listener whose connections run a test rule, which stands in for
//// the server's own so a session can be small and every byte of it known.

import ask_support
import client_tables
import genesis_prime/client_archive
import genesis_prime/connection/script.{type Scripts}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/zone_welcome
import genesis_prime/login/auth_connection
import genesis_prime/login/recorded_realm
import genesis_prime/login/sts_connection
import genesis_prime/seed.{type Seed}
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{type Now}
import genesis_prime/table/loader/store as table_store
import genesis_prime/wire_recording.{
  type Input, type Side, Closing, Header, Took, Wrote,
}
import genesis_prime/wire_recording/fixture
import genesis_prime/wire_recording/recorder
import genesis_prime/wire_replay.{type Action, type Failure, type Session}
import gleam/bit_array
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import login_support
import pog
import simplifile
import zone_welcome_support

/// One connection of a session written by hand: the rule it ran, its seed and
/// its place in the order the server accepted connections.
pub type Planted {
  Planted(rule: String, seed: Seed, ordinal: Int)
}

/// One line of a session written by hand, in the order the node saw them: the
/// connection it belongs to is the number of its place in the list of
/// `Planted`.
pub type Step {
  In(connection: Int, at: Now, input: Input)
  Out(connection: Int, bytes: BitArray)
  Closed(connection: Int, by: Side)
}

/// The clock reading `n` milliseconds in, as a recording writes it: the file
/// time is ten times the monotonic time.
pub fn now_at(n: Int) -> Now {
  step.Now(monotonic_ms: n, filetime: n * 10)
}

/// The file the test rule's recording of its first connection is written to.
pub fn rule_recording_file() -> String {
  "replay_rule-0.jsonl"
}

/// The seed of 32 bytes all `byte`.
pub fn seed(byte: Int) -> Seed {
  let assert Ok(seed) =
    seed.from_bytes(bit_array.concat(list.repeat(<<byte>>, seed.byte_count)))
    as "32 bytes are a seed"
  seed
}

/// Writes the session into `folder`: an empty fixture and a recording for each
/// connection. The steps are numbered in the order they are given, one number
/// for each, so they are the order the node saw the lines in. A connection with
/// no `Closed` step is a cut recording.
pub fn write(
  folder folder: String,
  connections connections: List(Planted),
  steps steps: List(Step),
) -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
    as "the session's folder was made"
  empty_fixture(folder:)
  list.index_map(connections, fn(planted, index) {
    let header =
      wire_recording.encode_header(Header(
        format: wire_recording.format,
        rule: planted.rule,
        client_build: 16_042,
        tables_digest: None,
        seed: planted.seed,
        accept_ordinal: planted.ordinal,
        realm: None,
      ))
    let lines =
      list.index_map(steps, fn(step, sequence) {
        let sequence = sequence + 1
        case step {
          In(connection:, at:, input:) if connection == index -> [
            wire_recording.encode_line(Took(sequence:, at:, input:)),
          ]
          Out(connection:, bytes:) if connection == index -> [
            wire_recording.encode_line(Wrote(sequence:, bytes:)),
          ]
          Closed(connection:, by:) if connection == index -> [
            wire_recording.encode_closing(Closing(sequence:, by:)),
          ]
          In(..) | Out(..) | Closed(..) -> []
        }
      })
      |> list.flatten
    let path =
      folder
      <> "/"
      <> recorder.file_name(rule_name: planted.rule, connection: index)
    let assert Ok(Nil) = simplifile.write(path, header <> string.concat(lines))
      as "a recording was written"
    Nil
  })
  Nil
}

/// The session in `folder`, which must load.
pub fn load(folder: String) -> Session {
  let assert Ok(session) = wire_replay.load(folder)
    as "the session written by hand loads"
  session
}

/// Starts a replay's table under a supervisor of its own, which stops when the
/// calling process ends, and gives the replay of `session`.
pub fn start_replay(session: Session) -> wire_replay.Replay {
  let table = wire_replay.new_table()
  let assert Ok(tables) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(wire_replay.table_supervised(table))
    |> supervisor.start
    as "the replay's table started"
  process.unlink(tables.pid)
  ask_support.guard(tables.pid)
  wire_replay.replay(session, table)
}

/// Writes the empty fixture a recording made by a listener of a test lacks: a
/// session whose rule reads no row needs none.
pub fn empty_fixture(folder folder: String) -> Nil {
  let assert Ok(Nil) = simplifile.write(folder <> "/" <> fixture.file_name, "")
    as "the fixture was written"
  Nil
}

/// Replays the session in `folder` as `run` does, and gives the log lines each
/// connection wrote while it ran with the result.
pub fn run_logged(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
) -> #(Result(Nil, Failure), List(wire_replay.Logged)) {
  run_planned(
    folder:,
    rule:,
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    with: fn(builder) { builder },
    actions: wire_replay.plan,
  )
}

/// The welcomes the live server read from its zone_welcome table, as the table's seed
/// states them, selected over the client's whole table set: the connection's own tables
/// hold no Tutorial table (it is a content table), and the committed fixture lacks the
/// WorldZone rows a recording lands in.
fn recorded_welcomes() -> zone_welcome.ZoneWelcomes {
  let assert Ok(welcomes) =
    zone_welcome.select(
      rows: zone_welcome_support.rows(),
      tables: client_tables.every_table(),
    )
    as "each seed row names a WorldZone and a Tutorial row of category 29 in the client's tables"
  welcomes
}

/// Replays the session in `folder` against a listener whose connections run
/// `rule`, with no ask to answer.
pub fn run(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
) -> Result(Nil, Failure) {
  run_actions(folder:, rule:, actions: wire_replay.plan).0
}

/// As `run`, with the steps of the replay client that `actions` makes of the
/// session.
pub fn run_actions(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
  actions actions: fn(Session) -> List(Action),
) -> #(Result(Nil, Failure), List(wire_replay.Logged)) {
  run_planned(
    folder:,
    rule:,
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    with: fn(builder) { builder },
    actions:,
  )
}

/// Replays the session in `folder` against a listener whose connections run
/// `rule`, with the asks it makes going through `directory`, beside what `with`
/// adds to the listener's supervisor.
pub fn run_with(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
) -> Result(Nil, Failure) {
  run_planned(folder:, rule:, directory:, with:, actions: wire_replay.plan).0
}

fn run_planned(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
  actions actions: fn(Session) -> List(Action),
) -> #(Result(Nil, Failure), List(wire_replay.Logged)) {
  run_scripted(
    folder:,
    rule:,
    directory:,
    with:,
    actions:,
    scripts: fn(replay) { replay.scripts },
    after_start: fn(_server, _replay) { Nil },
  )
}

/// As `run_planned`, for a test that stands between the replay and the
/// listener: `scripts` makes what the listener hands each connection from the
/// replay (the replay's own, or those wrapped), and `after_start` is called
/// with the running listener and the replay before the client plays.
pub fn run_scripted(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
  actions actions: fn(Session) -> List(Action),
  scripts scripts: fn(wire_replay.Replay) -> Scripts,
  after_start after_start: fn(ask_support.Server, wire_replay.Replay) -> Nil,
) -> #(Result(Nil, Failure), List(wire_replay.Logged)) {
  let session = load(folder)
  let replay = start_replay(session)
  let server =
    ask_support.start_scripted(
      rule:,
      directory:,
      shutdown_ms: 1000,
      wire_recorder: None,
      scripts: scripts(replay),
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with:,
    )
  after_start(server, replay)
  let result =
    wire_replay.play_actions(
      session:,
      replay:,
      ports: dict.from_list([#(rule.name, server.port)]),
      actions: actions(session),
    )
  ask_support.stop(server)
  #(result, wire_replay.finish(replay))
}

/// The folder of the session recorded live: the real client's
/// login through the STS, auth and game servers, played into the world with a
/// level-3 Veteran character (`session.sh` of the playing-live skill), with the
/// server taking the client's movement messages and saving the player's place.
pub const committed_session =
  "test/wire_recording/2026-11-10-gear-budget-session"

/// The folder every recorded session is kept in.
const recordings_folder = "test/wire_recording"

/// The folder of each recorded session in the repository, sorted: every folder
/// under `test/wire_recording`.
pub fn recorded_sessions() -> List(String) {
  let assert Ok(names) = simplifile.read_directory(recordings_folder)
    as "the folder of recorded sessions reads"
  list.sort(names, string.compare)
  |> list.map(fn(name) { recordings_folder <> "/" <> name })
  |> list.filter(fn(path) { simplifile.is_directory(path) == Ok(True) })
}

/// The realm the session's auth connection recorded in its header: the server
/// settings that show in the bytes the auth server wrote are the recording's, so
/// no machine's address lives in this repository.
fn recorded_auth_realm(session: Session) -> auth_connection.Realm {
  let assert Ok(connection) =
    list.find(session.connections, fn(connection) {
      connection.recording.header.rule == auth_connection.rule_name
    })
    as "the session holds an auth connection"
  let assert Some(realm) = connection.recording.header.realm
    as "the auth connection's header records the realm it hands the client to"
  recorded_realm.from_header(realm)
}

/// What the committed session was recorded under, which the replay's tree is
/// made with: the auth server's realm is the one the auth header records, the
/// game server holds the welcomes of the zones the session lands in (the live
/// server read them from the zone_welcome table), and every other setting is
/// the server's own.
fn session_settings(
  settings settings: server.Settings,
  replay replay: wire_replay.Replay,
  realm realm: auth_connection.Realm,
) -> server.Settings {
  let servers = login_support.servers_settings()
  server.Settings(
    ..settings,
    login: server.Login(
      sts: wire_replay.serve_from(
        server.Served(
          ..settings.login.sts,
          settings: servers.login.sts.settings,
        ),
        replay,
      ),
      auth: wire_replay.serve_from(
        server.Served(
          ..settings.login.auth,
          settings: auth_connection.Settings(
            ..servers.login.auth.settings,
            realm:,
          ),
        ),
        replay,
      ),
    ),
    game: wire_replay.serve_from(
      server.Served(
        ..settings.game,
        settings: connection_state.Settings(
          ..servers.game.settings,
          tables: client_tables.shared(),
          zone_welcomes: recorded_welcomes(),
        ),
      ),
      replay,
    ),
  )
}

/// Replays the session in `folder` against the real server tree on a database
/// of its own, with the fixture applied: the result, and the log lines each
/// connection wrote.
pub fn replay_tree(
  folder folder: String,
) -> #(Result(Nil, Failure), List(wire_replay.Logged)) {
  let session = load(folder)
  let digest = Some(table_store.digest(client_tables.shared()))
  let refused = case
    wire_replay.refuse_stale(session, client_archive.target_build, digest)
  {
    Ok(Nil) -> wire_replay.refuse_unreproducible(session, 60_000)
    Error(refusal) -> Error(refusal)
  }
  case refused {
    Error(refusal) -> #(Error(wire_replay.Refused(refusal)), [])
    Ok(Nil) -> {
      let replay = start_replay(session)
      let started =
        login_support.start_with(change: session_settings(
          _,
          replay,
          recorded_auth_realm(session),
        ))
      let ports = login_support.ports(started)
      let result = case
        wire_replay.prepare(
          session,
          pog.named_connection(started.settings.pool.pool_name),
        )
      {
        Error(failure) -> Error(failure)
        Ok(Nil) ->
          wire_replay.play(
            session:,
            replay:,
            ports: dict.from_list([
              #(sts_connection.rule_name, ports.sts_port),
              #(auth_connection.rule_name, ports.auth_port),
              #(game_connection.rule_name, ports.game_port),
            ]),
          )
      }
      login_support.stop(started)
      #(result, wire_replay.finish(replay))
    }
  }
}
