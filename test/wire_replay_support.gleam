//// What the tests of the wire replay share: a session written by hand into a
//// folder (a fixture and one recording for each connection), and a replay of
//// it against a listener whose connections run a test rule, which stands in for
//// the server's own so a session can be small and every byte of it known.

import ask_support
import genesis_prime/service
import genesis_prime/step.{type Now}
import genesis_prime/wire_recording.{
  type Input, type Side, Closing, Header, Took, Wrote,
}
import genesis_prime/wire_recording/fixture
import genesis_prime/wire_replay.{type Action, type Failure, type Session}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import simplifile

/// One connection of a session written by hand: the rule it ran, its seed and
/// its place in the order the server accepted connections.
pub type Planted {
  Planted(rule: String, seed: BitArray, ordinal: Int)
}

/// One line of a session written by hand, in the order the node saw them: the
/// connection it belongs to is the number of its place in the list of
/// `Planted`.
pub type Step {
  In(connection: Int, at: Now, input: Input)
  Out(connection: Int, bytes: BitArray)
  Closed(connection: Int, by: Side)
}

/// The seed of 32 bytes all `byte`.
pub fn seed(byte: Int) -> BitArray {
  list.repeat(<<byte>>, 32) |> bit_array_concat
}

fn bit_array_concat(parts: List(BitArray)) -> BitArray {
  list.fold(parts, <<>>, fn(whole, part) { <<whole:bits, part:bits>> })
}

/// The name of the file of connection `connection` of a session written by hand.
pub fn file_of(planted: Planted, connection connection: Int) -> String {
  string.replace(planted.rule, "/", ".")
  <> "-"
  <> int.to_string(connection)
  <> ".jsonl"
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
  let assert Ok(Nil) = simplifile.write(folder <> "/" <> fixture.file_name, "")
    as "the fixture was written"
  list.index_map(connections, fn(planted, index) {
    let header =
      wire_recording.encode_header(Header(
        format: wire_recording.format,
        rule: planted.rule,
        client_build: 16_042,
        tables_digest: None,
        seed: planted.seed,
        accept_ordinal: planted.ordinal,
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
    let path = folder <> "/" <> file_of(planted, connection: index)
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

/// Replays the session in `folder` against a listener whose connections run
/// `rule`, with no ask to answer.
pub fn run(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, Nil, message, answer),
) -> Result(Nil, Failure) {
  run_actions(folder:, rule:, actions: wire_replay.plan)
}

/// As `run`, with the steps of the replay client that `actions` makes of the
/// session.
pub fn run_actions(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, Nil, message, answer),
  actions actions: fn(Session) -> List(Action),
) -> Result(Nil, Failure) {
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
  run_planned(folder:, rule:, directory:, with:, actions: wire_replay.plan)
}

fn run_planned(
  folder folder: String,
  rule rule: step.ConnectionRule(settings, state, request, message, answer),
  directory directory: fn(request, Int, fn(answer) -> Nil) ->
    Result(service.Sent, Nil),
  with with: fn(supervisor.Builder) -> supervisor.Builder,
  actions actions: fn(Session) -> List(Action),
) -> Result(Nil, Failure) {
  let session = load(folder)
  let replay = start_replay(session)
  let server =
    ask_support.start_scripted(
      rule:,
      directory:,
      shutdown_ms: 1000,
      recorder: None,
      wire_recorder: None,
      scripts: replay.scripts,
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with:,
    )
  let result =
    wire_replay.play_actions(
      session:,
      replay:,
      ports: dict.from_list([#(rule.name, server.port)]),
      actions: actions(session),
    )
  ask_support.stop(server)
  let _lines = wire_replay.finish(replay)
  result
}
