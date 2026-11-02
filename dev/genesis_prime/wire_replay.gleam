//// Replays a recorded session (genesis_prime/wire_recording) against the real
//// server tree and compares the bytes the server writes with the bytes
//// recorded.
////
//// ```
//// a test database ── every migration, then the session's fixture (`prepare`)
//// the server tree ── started on that database; each listener's `Served` has
////                    `scripts` from `serve_from`, which hands the connection
////                    accepted n-th the script of the recording with the n-th
////                    accept ordinal: its seed, its `Now`s in a queue, the
////                    byte count of each recorded read (`next_read`) and a
////                    scheduler whose timers wait for the replay client
//// the replay client ─ `play` walks the plan (`plan`) of every connection's
////                    lines, sorted by sequence number:
////                      connect: at its place in the order (at the connection's
////                        accepted line), so a listener's connection limit
////                        holds as it did in the session; connects stay in
////                        accept order, and each waits only until the server
////                        has handed out the script of its ordinal
////                      an input line the client causes (a read, a timer, the
////                        client's close): first waits until that connection's
////                        shell has taken every earlier recorded input
////                        (`taken`, how many recorded input lines its script
////                        has given a `Now`),
////                        then sends the bytes, fires the timer at the
////                        scheduler or closes the socket
////                      an input line the server causes (an answer, a
////                        message, a watch's end): waits until the shell has
////                        taken it
////                      a write line: waits until the server has written the
////                        bytes recorded, then compares them (`compare`)
////                      the closing line: the client's close was sent at its
////                        input line; a server close is awaited
//// ```
////
//// What is compared is the byte stream the server writes, not how the socket
//// cut it into writes, so a replay gives the same result when the server cuts
//// its writes differently. The client's bytes are sent as the recording holds
//// them, one send for each read line, each only after the shell has taken the
//// input before it. Each recorded read reaches the rule as one input: the
//// script gives the shell the byte count of the next recorded read, and the
//// shell reads on until it holds that many bytes, so a socket that delivers one
//// recorded read in two parts (a loopback split after a complete request, say)
//// lets no answer or message be taken between the parts. The script's clock is
//// told what each input is (`Taking`) as a second guard: a read gets the `Now`
//// of the recorded read line in which its last byte falls, any other input takes
//// the next recorded input of its kind, and one that is not the kind of the
//// next recorded input is an ordering failure (`TookOutOfOrder`), so an input
//// that arrives earlier or later than recorded is named and never shows up as a
//// difference in bytes.
////
//// Every wait of the replay client is bounded by `wait_ms` of real time, and
//// so is the shell's wait for an ask (genesis_prime/connection/shell): a replay
//// ends, and says what it waited for. A refusal, a difference, a silence or a
//// shell that never takes an input ends the replay with a `Failure` that names
//// the connection and the recorded line.

import genesis_prime/client_connection
import genesis_prime/connection/frame
import genesis_prime/connection/script.{
  type Clock, type Scheduler, type Scripts, type Taking, Issued, Script,
}
import genesis_prime/server
import genesis_prime/step.{TimerId}
import genesis_prime/wire_recording.{
  type Input, type ReadFailure, type Recording, type Side, NoAnswerInTime, Took,
  Wrote,
}
import genesis_prime/wire_recording/fixture.{type FixtureError}
import genesis_prime/wire_replay/table.{type Recorded, Recorded} as replay_table
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import log_capture.{type Capture}
import mug
import pog
import simplifile

/// How long every wait of the replay client, and every ask's wait in the
/// shell, lasts in real milliseconds. A replay that waits this long fails.
pub const wait_ms = 5000

/// One recorded connection: the name of its file and what it holds.
pub type Connection {
  Connection(name: String, recording: Recording)
}

/// A recorded session: the connections of its folder in the order the server
/// accepted them (by the accept ordinal of each header), and the path of the
/// fixture beside them.
pub type Session {
  Session(folder: String, connections: List(Connection), fixture: String)
}

/// Why a session is not played at all.
pub type Refusal {
  /// A connection's file is not a recording that can be played; a cut
  /// recording is `Unreadable(_, Cut(_))`.
  Unreadable(connection: String, failure: ReadFailure)
  /// The recording was made on another client build than the one the replay is
  /// for, so the session must be recorded again.
  ClientBuildDiffers(connection: String, recorded: Int, current: Int)
  /// The recording was made on other game table files than the ones loaded
  /// now, so the session must be recorded again.
  TablesDiffer(
    connection: String,
    recorded: Option(String),
    current: Option(String),
  )
  /// The folder holds no fixture.
  NoFixture(path: String)
  /// An ask of the recording ended with no answer in time. Whether the asked
  /// process would have answered is a matter of time, so a replay cannot
  /// bring the outcome about, and the session must be recorded again.
  AskTimedOut(connection: String, line: Int)
  /// A connection was accepted more than the hand-off keys' lifetime after the
  /// connection before it was last read from, in recorded time, so a key the
  /// one put could not be taken by the other. A replay runs no slower than the
  /// recording and would take the key, so the session must be recorded again.
  /// This is the one expiry the wire shows: a key that expired within a
  /// connection, or between connections closer than the lifetime, is not seen
  /// here and shows as `Differs` where the server's bytes then differ.
  HandOffKeyExpired(
    earlier: String,
    later: String,
    gap_ms: Int,
    lifetime_ms: Int,
  )
}

/// One message of a recorded or written stream, read with the current codec so
/// a person sees what differed.
pub type Decoded {
  /// A frame whose id the codec names, with its fields written out.
  Message(message_id: Int, name: String, text: String)
  /// A frame whose id has no decoder, or bytes that are not a whole frame.
  Undecoded(bytes: BitArray)
}

/// Where two byte streams first differ: the offset of the first different byte
/// and the message each stream holds there, decoded only where no cipher is on
/// (the replay client holds no session keys), else `Undecoded` with the bytes. A
/// stream that ends before the other has `Undecoded(<<>>)` where it stopped.
pub type Difference {
  Difference(offset: Int, recorded: Decoded, written: Decoded)
}

/// Why the replay of a session failed. Every variant but `Refused` and
/// `FixtureFailed` names the connection and the line of its recording (from 0,
/// the header being 0) the replay was at.
pub type Failure {
  /// The session is not played.
  Refused(refusal: Refusal)
  /// The fixture could not be applied.
  FixtureFailed(error: FixtureError)
  /// The replay client could not connect to the listener, or the server
  /// did not hand out the connection's script within `wait_ms`.
  NotConnected(connection: String, reason: String)
  /// The server wrote other bytes than the recording holds.
  Differs(connection: String, line: Int, difference: Difference)
  /// The server wrote nothing for `wait_ms` where the recording holds bytes;
  /// `expected` is the message it waited for.
  Silent(connection: String, line: Int, expected: Decoded)
  /// The server wrote bytes after the recording's last line, or while the
  /// recording expects the client to send.
  Unexpected(connection: String, line: Int, written: Decoded)
  /// The shell took fewer inputs than the recording's line needs within
  /// `wait_ms`: `taken` is how many it had taken and `input` the kind of input
  /// the line records.
  NeverTaken(connection: String, line: Int, input: Input, taken: Int)
  /// The timer the line records was not started within `wait_ms`.
  TimerNeverStarted(connection: String, line: Int, timer: Int)
  /// The shell took an input the recording does not hold, so its script's
  /// clock had no `Now` to give.
  TookUnrecordedInput(connection: String, line: Int)
  /// The shell took an input of another kind than the recording's next: its
  /// clock was told `taken` where the line records `expected`, which is a
  /// message, an answer or a timer that came earlier or later than recorded.
  /// `line` is the recorded line the replay was at.
  TookOutOfOrder(connection: String, line: Int, expected: Taking, taken: Taking)
  /// The server ended the connection where the recording goes on, with the
  /// log lines the connection wrote (its refusal of a client byte among them).
  EndedEarly(connection: String, line: Int, logged: List(String))
  /// The recording's last line says the server closed the connection, and it
  /// had not within `wait_ms`.
  StillOpen(connection: String, line: Int)
}

/// One step of the replay client, in the order it takes them.
pub type Action {
  /// Connects to the listener of the connection's rule and waits until the
  /// server has handed out the script of the connection's ordinal. It comes at
  /// the connection's accepted line, or earlier when a connection of a later
  /// ordinal would otherwise be connected first.
  Connect(connection: String)
  /// Waits until the connection's shell has taken `inputs` inputs. `input` is
  /// the kind of input of `line`, named when the wait ends in `NeverTaken`.
  AwaitTaken(connection: String, line: Int, inputs: Int, input: Input)
  /// Sends the bytes of a read line, whole, in one send.
  Send(connection: String, line: Int, bytes: BitArray)
  /// Fires the timer a timer line records, waiting for the shell to have
  /// started it.
  Fire(connection: String, line: Int, timer: Int)
  /// Closes the replay client's socket, as the recorded client did.
  CloseClientSocket(connection: String, line: Int)
  /// Waits for the server to write the bytes of a write line and compares them.
  Expect(connection: String, line: Int, bytes: BitArray)
  /// Waits for the end of the connection, which the closing line says `by`
  /// ended: a client's close has been sent, so only the shell's own end is
  /// awaited; a server's close is awaited on the socket.
  AwaitEnd(connection: String, line: Int, by: Side)
}

/// How many recorded input lines one connection's shell has taken: the lines
/// its script's clock has given a `Now`, a read line counting once its last
/// byte has been taken. The replay client reads it to know how far the shell is,
/// and the shell never writes it any other way.
pub opaque type Progress {
  Progress(table: Subject(replay_table.Command), connection: String)
}

/// The replay's table, kept by one process (genesis_prime/wire_replay/table):
/// the recorded inputs each connection's script has still to give a `Now` to,
/// how many it has taken, the timers the replay's shells have started, and the
/// process of each shell. The shells that ask it for a `Now` or start a timer,
/// and the client that waits for a shell, fires a timer or reads a shell's log
/// lines, share nothing else.
pub type Table {
  Table(name: Name(replay_table.Command))
}

/// What a replay gives the server and keeps for the replay client.
pub type Replay {
  Replay(
    /// Hands out the script of each connection in the order of the accept
    /// ordinals, each once, and `Error(Nil)` after the last, whatever listener
    /// asks and however often a listener restarts.
    scripts: Scripts,
    /// How far each connection's shell is, by the name of its file.
    progress: Dict(String, Progress),
    table: Table,
    /// The log lines of every process of the node since the replay was made,
    /// which `logged` and `finish` sort by connection.
    logs: Subject(#(String, String, List(#(String, String)))),
    capture: Capture,
  )
}

/// One log line a connection's shell wrote: its level in lower case and its
/// text.
pub type Logged {
  Logged(connection: String, level: String, text: String)
}

/// A table of a name of its own, made now.
pub fn new_table() -> Table {
  Table(name: process.new_name("wire_replay_table"))
}

/// The table as a child of the replay's own supervisor, started before the
/// server tree and stopped after it.
pub fn table_supervised(of of: Table) -> ChildSpecification(Nil) {
  replay_table.supervised(of.name)
}

/// The suffix of the file of a recording: one JSON-lines file for each
/// connection of the session.
const recording_suffix = ".jsonl"

/// Reads every recording of the folder, and the fixture beside them, and
/// orders the connections by the accept ordinal of their headers.
pub fn load(folder folder: String) -> Result(Session, Refusal) {
  let fixture_path = folder <> "/" <> fixture.file_name
  case simplifile.is_file(fixture_path) {
    Ok(True) -> {
      let names = case simplifile.read_directory(folder) {
        Ok(names) ->
          list.filter(names, string.ends_with(_, recording_suffix))
          |> list.sort(string.compare)
        Error(_) -> []
      }
      use connections <- result.map(
        list.try_map(names, fn(name) { read_connection(folder:, name:) }),
      )
      Session(
        folder:,
        connections: list.sort(connections, fn(a, b) {
          int.compare(
            a.recording.header.accept_ordinal,
            b.recording.header.accept_ordinal,
          )
        }),
        fixture: fixture_path,
      )
    }
    Ok(False) | Error(_) -> Error(NoFixture(path: fixture_path))
  }
}

fn read_connection(
  folder folder: String,
  name name: String,
) -> Result(Connection, Refusal) {
  let text = case simplifile.read(folder <> "/" <> name) {
    Ok(text) -> text
    Error(_) -> ""
  }
  wire_recording.read(text)
  |> result.map(fn(recording) { Connection(name:, recording:) })
  |> result.map_error(fn(failure) { Unreadable(connection: name, failure:) })
}

/// Refuses a session whose recordings were made on another client build or on
/// other game table files than the ones given.
pub fn refuse_stale(
  session session: Session,
  client_build client_build: Int,
  tables_digest tables_digest: Option(String),
) -> Result(Nil, Refusal) {
  list.try_each(session.connections, fn(connection) {
    let header = connection.recording.header
    case header.client_build == client_build, header.tables_digest {
      False, _ ->
        Error(ClientBuildDiffers(
          connection: connection.name,
          recorded: header.client_build,
          current: client_build,
        ))
      True, recorded if recorded != tables_digest ->
        Error(TablesDiffer(
          connection: connection.name,
          recorded:,
          current: tables_digest,
        ))
      True, _ -> Ok(Nil)
    }
  })
}

/// Refuses a session a replay cannot bring about: an ask that timed out, or a
/// hand-off key that outlived `hand_off_lifetime_ms` between two connections.
pub fn refuse_unreproducible(
  session session: Session,
  hand_off_lifetime_ms hand_off_lifetime_ms: Int,
) -> Result(Nil, Refusal) {
  use Nil <- result.try(
    list.try_each(session.connections, fn(connection) {
      case
        list.index_map(connection.recording.lines, fn(line, index) {
          #(index + 1, line)
        })
        |> list.find(fn(numbered) {
          case numbered.1 {
            Took(input: wire_recording.Answered(outcome: NoAnswerInTime), ..) ->
              True
            Took(..) | Wrote(..) -> False
          }
        })
      {
        Ok(#(line, _)) -> Error(AskTimedOut(connection: connection.name, line:))
        Error(Nil) -> Ok(Nil)
      }
    }),
  )
  list.zip(session.connections, list.drop(session.connections, 1))
  |> list.try_each(fn(pair) {
    let #(earlier, later) = pair
    let gap_ms = accepted_at(later) - last_read_at(earlier)
    case gap_ms > hand_off_lifetime_ms {
      True ->
        Error(HandOffKeyExpired(
          earlier: earlier.name,
          later: later.name,
          gap_ms:,
          lifetime_ms: hand_off_lifetime_ms,
        ))
      False -> Ok(Nil)
    }
  })
}

/// The monotonic time of the first input of a connection, which is its accept.
fn accepted_at(connection: Connection) -> Int {
  case inputs_of(connection) {
    [Recorded(at:, ..), ..] -> at.monotonic_ms
    [] -> 0
  }
}

/// The monotonic time of the last read of a connection, or of its first input
/// when it read nothing.
fn last_read_at(connection: Connection) -> Int {
  let reads =
    list.filter(inputs_of(connection), fn(recorded) {
      case recorded.input {
        wire_recording.Read(..) -> True
        _ -> False
      }
    })
  case list.last(reads), inputs_of(connection) {
    Ok(Recorded(at:, ..)), _ -> at.monotonic_ms
    Error(Nil), [Recorded(at:, ..), ..] -> at.monotonic_ms
    Error(Nil), [] -> 0
  }
}

/// The inputs a connection's recording holds, each with its line.
fn inputs_of(connection: Connection) -> List(Recorded) {
  list.index_map(connection.recording.lines, fn(line, index) {
    case line {
      Took(at:, input:, ..) -> [Recorded(line: index + 1, input:, at:)]
      Wrote(..) -> []
    }
  })
  |> list.flatten
}

/// Applies the session's fixture to a database that holds the schema and no
/// rows.
pub fn prepare(
  session session: Session,
  database database: pog.Connection,
) -> Result(Nil, Failure) {
  fixture.apply(database, session.fixture)
  |> result.map_error(fn(error) { FixtureFailed(error:) })
}

/// What the session's connections are given: one script for each, with the
/// recording's seed, the byte count of each recorded read (`next_read`), a clock
/// that matches each input the shell takes with a recorded line by the `Taking`
/// it is told (a read by its byte count against the recorded read lines' sizes,
/// any other input by kind against the next recorded input) and gives that
/// line's `Now`, and a scheduler that starts its timers in the table and fires
/// them when the replay client asks. The capture of log lines starts here, owned
/// by the calling process, which is the one that plays.
pub fn replay(session session: Session, table table: Table) -> Replay {
  let subject = process.named_subject(table.name)
  replay_table.load(
    subject,
    list.map(session.connections, fn(connection) {
      replay_table.Prepared(
        name: connection.name,
        ordinal: connection.recording.header.accept_ordinal,
        seed: connection.recording.header.seed,
        inputs: inputs_of(connection),
        closing_line: list.length(connection.recording.lines) + 1,
      )
    }),
  )
  let logs = process.new_subject()
  Replay(
    scripts: scripts(subject),
    progress: dict.from_list(
      list.map(session.connections, fn(connection) {
        #(
          connection.name,
          Progress(table: subject, connection: connection.name),
        )
      }),
    ),
    table:,
    logs:,
    capture: log_capture.start_all(into: logs),
  )
}

/// Hands out the script of the connection accepted next, which is the next of
/// the recording's connections by accept ordinal.
fn scripts(table: Subject(replay_table.Command)) -> Scripts {
  fn() {
    use handed <- result.map(replay_table.handout(table))
    Issued(
      ordinal: handed.ordinal,
      script: Script(
        seed: handed.seed,
        clock: clock(table, handed.name),
        schedule: scheduler(table, handed.name),
        next_read: fn() {
          replay_table.next_read(table:, connection: handed.name)
        },
      ),
    )
  }
}

/// A connection's clock: the recorded `Now` of the input its shell took. An
/// input that matches no recorded one has no `Now`: the mismatch is kept in the
/// table for the replay client, and the shell ends, so the connection takes no
/// more inputs.
fn clock(table: Subject(replay_table.Command), connection: String) -> Clock {
  fn(taking) {
    case replay_table.take(table:, connection:, taking:) {
      Ok(now) -> now
      Error(_mismatch) ->
        panic as "the replay has no recorded time for the input the shell took"
    }
  }
}

/// A connection's scheduler: a timer it starts is kept in the table until the
/// replay client reaches its line and fires it.
fn scheduler(
  table: Subject(replay_table.Command),
  connection: String,
) -> Scheduler {
  fn(subject, timer, reference, _after_ms) {
    let TimerId(number) = timer
    replay_table.timer_started(
      table:,
      connection:,
      timer: number,
      started: replay_table.Started(subject:, reference:),
    )
    fn() {
      replay_table.timer_cancelled(
        table:,
        connection:,
        timer: number,
        reference:,
      )
    }
  }
}

/// The log lines the replay's shells wrote, each with the connection it came
/// from, since the last call; the capture goes on.
pub fn logged(replay replay: Replay) -> List(Logged) {
  let subject = process.named_subject(replay.table.name)
  let shells =
    list.filter_map(dict.keys(replay.progress), fn(connection) {
      case replay_table.shell_of(table: subject, connection:) {
        Some(pid) -> Ok(#(pid_text(pid), connection))
        None -> Error(Nil)
      }
    })
  drain(replay.logs)
  |> list.filter_map(fn(line) {
    let #(level, text, metadata) = line
    use pid <- result.try(list.key_find(metadata, "pid"))
    use connection <- result.map(list.key_find(shells, pid))
    Logged(connection:, level:, text:)
  })
}

fn drain(
  logs: Subject(#(String, String, List(#(String, String)))),
) -> List(#(String, String, List(#(String, String)))) {
  case process.receive(logs, within: 0) {
    Ok(line) -> [line, ..drain(logs)]
    Error(Nil) -> []
  }
}

/// A process id as the logger writes it into a line's metadata.
fn pid_text(pid: Pid) -> String {
  charlist.to_string(pid_to_list(pid))
}

@external(erlang, "erlang", "pid_to_list")
fn pid_to_list(pid: Pid) -> Charlist

/// Ends the capture of log lines, and gives those not yet given by `logged`.
pub fn finish(replay replay: Replay) -> List(Logged) {
  let lines = logged(replay)
  log_capture.stop(replay.capture)
  lines
}

/// The listener's settings with the replay's scripts; its recorders stay off.
pub fn serve_from(
  served served: server.Served(settings),
  replay replay: Replay,
) -> server.Served(settings) {
  server.Served(
    ..served,
    recorder: None,
    wire_recorder: None,
    scripts: replay.scripts,
  )
}

/// How many inputs the shell of a connection has taken.
pub fn taken(progress progress: Progress) -> Int {
  replay_table.taken(table: progress.table, connection: progress.connection)
}

/// The replay client's steps for the session: the lines of every connection
/// sorted by sequence number, with a `Connect` for each connection placed before
/// its accepted line, moved earlier only as far as keeps the connects in accept
/// order (a connect comes before the accepted line of any connection of its
/// ordinal or a later one).
/// - the accepted line: `AwaitTaken` of the one input;
/// - a read line: `AwaitTaken` of the inputs before it, then `Send`;
/// - a timer line: `AwaitTaken` of the inputs before it, then `Fire`;
/// - a client's close line: `AwaitTaken` of the inputs before it, then
///   `CloseClientSocket`;
/// - any other input line (answered, woken, watch ended, a failure,
///   stopping): `AwaitTaken` of the inputs up to and including it;
/// - a write line: `Expect`;
/// - the closing line: `AwaitEnd`.
pub fn plan(session session: Session) -> List(Action) {
  let items =
    list.flat_map(session.connections, items_of)
    |> list.sort(fn(a, b) { int.compare(a.sequence, b.sequence) })
  let first_lines =
    list.index_map(items, fn(item, position) { #(item, position) })
  // The place of each connection's accepted line (the first input it has, when
  // it has no accept) among the items, by the connection's place in accept
  // order.
  let accepted_positions =
    list.map(session.connections, fn(connection) {
      let own =
        list.filter(first_lines, fn(entry) {
          { entry.0 }.connection == connection.name
        })
      let accepted =
        list.find(own, fn(entry) {
          case { entry.0 }.what {
            InputLine(input: wire_recording.Accepted, ..) -> True
            InputLine(..) | WriteLine(..) | ClosingLine(..) -> False
          }
        })
      case accepted, own {
        Ok(#(_, position)), _ -> position
        Error(Nil), [#(_, position), ..] -> position
        Error(Nil), [] -> 0
      }
    })
  // A connect comes before the accepted line of its connection and of any
  // connection accepted after it, so it is at the first of those places.
  let connect_positions =
    list.index_map(session.connections, fn(connection, index) {
      let from_here = list.drop(accepted_positions, index)
      let assert Ok(position) = list.reduce(from_here, int.min)
        as "a connection has an accepted line position"
      #(connection.name, position)
    })
  list.index_map(items, fn(item, position) {
    let connects =
      list.filter_map(connect_positions, fn(connect) {
        case connect.1 == position {
          True -> Ok(Connect(connection: connect.0))
          False -> Error(Nil)
        }
      })
    list.append(connects, actions_of(item))
  })
  |> list.flatten
}

/// One line of the session as `plan` sorts and acts on it.
type Item {
  Item(sequence: Int, connection: String, line: Int, what: What)
}

type What {
  /// An input, with how many inputs came before it on its connection.
  InputLine(input: Input, before: Int)
  WriteLine(bytes: BitArray)
  /// The closing line, with how many inputs the connection took in all.
  ClosingLine(by: Side, inputs: Int)
}

fn items_of(connection: Connection) -> List(Item) {
  let #(items, inputs) =
    list.index_fold(
      connection.recording.lines,
      #([], 0),
      fn(so_far, line, index) {
        let #(items, inputs) = so_far
        case line {
          Took(sequence:, input:, ..) -> #(
            [
              Item(
                sequence:,
                connection: connection.name,
                line: index + 1,
                what: InputLine(input:, before: inputs),
              ),
              ..items
            ],
            inputs + 1,
          )
          Wrote(sequence:, bytes:) -> #(
            [
              Item(
                sequence:,
                connection: connection.name,
                line: index + 1,
                what: WriteLine(bytes:),
              ),
              ..items
            ],
            inputs,
          )
        }
      },
    )
  let closing = connection.recording.closing
  list.reverse([
    Item(
      sequence: closing.sequence,
      connection: connection.name,
      line: list.length(connection.recording.lines) + 1,
      what: ClosingLine(by: closing.by, inputs:),
    ),
    ..items
  ])
}

fn actions_of(item: Item) -> List(Action) {
  let Item(connection:, line:, what:, ..) = item
  case what {
    InputLine(input:, before:) ->
      case input {
        wire_recording.Accepted -> [
          AwaitTaken(connection:, line:, inputs: before + 1, input:),
        ]
        wire_recording.Read(bytes:) -> [
          AwaitTaken(connection:, line:, inputs: before, input:),
          Send(connection:, line:, bytes:),
        ]
        wire_recording.TimerFired(timer:) -> [
          AwaitTaken(connection:, line:, inputs: before, input:),
          Fire(connection:, line:, timer:),
        ]
        wire_recording.PeerClosed -> [
          AwaitTaken(connection:, line:, inputs: before, input:),
          CloseClientSocket(connection:, line:),
        ]
        wire_recording.Answered(..)
        | wire_recording.ReadFailed
        | wire_recording.WriteFailed
        | wire_recording.Woken
        | wire_recording.WatchEnded
        | wire_recording.Stopping -> [
          AwaitTaken(connection:, line:, inputs: before + 1, input:),
        ]
      }
    WriteLine(bytes:) -> [Expect(connection:, line:, bytes:)]
    ClosingLine(by:, ..) -> [AwaitEnd(connection:, line:, by:)]
  }
}

/// The replay client: carries out the plan of the session, connecting each
/// connection to the port of its rule's listener (`ports`, by the rule's name),
/// and ends at the first failure. It returns when the plan has been carried
/// out.
pub fn play(
  session session: Session,
  replay replay: Replay,
  ports ports: Dict(String, Int),
) -> Result(Nil, Failure) {
  play_actions(session:, replay:, ports:, actions: plan(session))
}

/// What the replay client holds while it plays: a socket for each connection it
/// has made, the bytes the server wrote that no `Expect` has taken yet, and
/// how many bytes of each stream the `Expect`s have taken.
type Client {
  Client(
    sockets: Dict(String, mug.Socket),
    buffers: Dict(String, BitArray),
    written: Dict(String, Int),
  )
}

/// The replay client as `play` runs it, given the steps to take: the plan, or
/// the plan a test has changed. Every socket it made is closed when it ends.
pub fn play_actions(
  session session: Session,
  replay replay: Replay,
  ports ports: Dict(String, Int),
  actions actions: List(Action),
) -> Result(Nil, Failure) {
  let client =
    Client(sockets: dict.new(), buffers: dict.new(), written: dict.new())
  let #(result, client) =
    run_actions(session:, replay:, ports:, actions:, client:)
  dict.each(client.sockets, fn(_name, socket) {
    let _closed = mug.shutdown(socket)
    Nil
  })
  case result {
    Ok(Nil) -> final_check(session:, replay:)
    Error(failure) -> Error(failure)
  }
}

/// After the last action: a mismatch the table kept against any connection, which
/// no wait of the client happened to meet.
fn final_check(
  session session: Session,
  replay replay: Replay,
) -> Result(Nil, Failure) {
  let table = process.named_subject(replay.table.name)
  list.try_each(session.connections, fn(connection) {
    case replay_table.failure_of(table:, connection: connection.name) {
      Some(mismatch) -> Error(mismatch_failure(connection.name, mismatch))
      None -> Ok(Nil)
    }
  })
}

fn run_actions(
  session session: Session,
  replay replay: Replay,
  ports ports: Dict(String, Int),
  actions actions: List(Action),
  client client: Client,
) -> #(Result(Nil, Failure), Client) {
  case actions {
    [] -> #(Ok(Nil), client)
    [action, ..rest] ->
      case act(session:, replay:, ports:, action:, client:) {
        Ok(client) ->
          run_actions(session:, replay:, ports:, actions: rest, client:)
        Error(failure) -> #(Error(failure), client)
      }
  }
}

fn act(
  session session: Session,
  replay replay: Replay,
  ports ports: Dict(String, Int),
  action action: Action,
  client client: Client,
) -> Result(Client, Failure) {
  let table = process.named_subject(replay.table.name)
  case action {
    Connect(connection:) ->
      connect(session:, table:, ports:, connection:, client:)
    AwaitTaken(connection:, line:, inputs:, input:) ->
      case
        replay_table.await_taken(
          table:,
          connection:,
          inputs:,
          within_ms: wait_ms,
        )
      {
        Ok(Nil) -> Ok(client)
        Error(replay_table.Mismatched(mismatch:)) ->
          Error(mismatch_failure(connection, mismatch))
        Error(replay_table.TimedOut(taken:)) ->
          Error(ended_or(
            replay:,
            client:,
            connection:,
            line:,
            otherwise: NeverTaken(connection:, line:, input:, taken:),
          ))
      }
    Send(connection:, line:, bytes:) ->
      case dict.get(client.buffers, connection) {
        Ok(unexpected) if unexpected != <<>> ->
          Error(Unexpected(connection:, line:, written: decode(unexpected)))
        Ok(_) | Error(Nil) ->
          case mug.send(socket_of(client, connection), bytes) {
            Ok(Nil) -> Ok(client)
            Error(_) -> Error(ended(replay:, connection:, line:))
          }
      }
    Fire(connection:, line:, timer:) ->
      case
        replay_table.await_timer(
          table:,
          connection:,
          timer:,
          within_ms: wait_ms,
        )
      {
        Ok(replay_table.Started(subject:, reference:)) -> {
          process.send(
            subject,
            script.Elapsed(timer: TimerId(timer), reference:),
          )
          Ok(client)
        }
        Error(Nil) -> Error(TimerNeverStarted(connection:, line:, timer:))
      }
    CloseClientSocket(connection:, ..) -> {
      let _closed = mug.shutdown(socket_of(client, connection))
      Ok(client)
    }
    Expect(connection:, line:, bytes:) ->
      expect(replay:, client:, connection:, line:, expected: bytes)
    AwaitEnd(connection:, line:, by:) ->
      await_end(session:, replay:, client:, connection:, line:, by:)
  }
}

fn socket_of(client: Client, connection: String) -> mug.Socket {
  let assert Ok(socket) = dict.get(client.sockets, connection)
    as "the plan connects a connection before it acts on it"
  socket
}

/// Connects to the listener that runs the connection's rule and waits until the
/// server has handed out the connection's script.
fn connect(
  session session: Session,
  table table: Subject(replay_table.Command),
  ports ports: Dict(String, Int),
  connection connection: String,
  client client: Client,
) -> Result(Client, Failure) {
  let assert Ok(recorded) =
    list.find(session.connections, fn(candidate) {
      candidate.name == connection
    })
    as "the plan names a connection of the session"
  let rule = recorded.recording.header.rule
  case dict.get(ports, rule) {
    Error(Nil) ->
      Error(NotConnected(
        connection:,
        reason: "no listener runs the rule " <> rule,
      ))
    Ok(port) ->
      case
        mug.new("127.0.0.1", port:)
        |> mug.ip_version_preference(mug.Ipv4Only)
        |> mug.timeout(wait_ms)
        |> mug.connect
      {
        Error(_) ->
          Error(NotConnected(
            connection:,
            reason: "the listener of " <> rule <> " refused the connection",
          ))
        Ok(socket) ->
          case
            replay_table.await_handed(table:, connection:, within_ms: wait_ms)
          {
            Ok(Nil) ->
              Ok(Client(
                sockets: dict.insert(client.sockets, connection, socket),
                buffers: dict.insert(client.buffers, connection, <<>>),
                written: dict.insert(client.written, connection, 0),
              ))
            Error(Nil) ->
              Error(NotConnected(
                connection:,
                reason: "the server did not hand out the connection's script",
              ))
          }
      }
  }
}

/// Waits for the server to write the bytes of a write line, comparing them with
/// the stream as they arrive: a byte that differs ends the wait at once, and
/// bytes of the next write line that arrive with these stay for it.
fn expect(
  replay replay: Replay,
  client client: Client,
  connection connection: String,
  line line: Int,
  expected expected: BitArray,
) -> Result(Client, Failure) {
  let buffer = result.unwrap(dict.get(client.buffers, connection), <<>>)
  let have = bit_array.byte_size(buffer)
  let want = bit_array.byte_size(expected)
  let common = int.min(have, want)
  let assert Ok(written) = bit_array.slice(buffer, 0, common)
    as "the common length is within the buffer"
  let assert Ok(recorded) = bit_array.slice(expected, 0, common)
    as "the common length is within the expected bytes"
  case written == recorded, have >= want {
    False, _ -> {
      let assert Error(difference) = compare(recorded: expected, written:)
        as "bytes that are not equal differ"
      let base = result.unwrap(dict.get(client.written, connection), 0)
      Error(Differs(
        connection:,
        line:,
        difference: Difference(..difference, offset: base + difference.offset),
      ))
    }
    True, True -> {
      let assert Ok(rest) = bit_array.slice(buffer, want, have - want)
        as "the buffer holds the expected bytes"
      let base = result.unwrap(dict.get(client.written, connection), 0)
      Ok(
        Client(
          ..client,
          buffers: dict.insert(client.buffers, connection, rest),
          written: dict.insert(client.written, connection, base + want),
        ),
      )
    }
    True, False ->
      case
        mug.receive(
          socket_of(client, connection),
          timeout_milliseconds: wait_ms,
        )
      {
        Ok(more) ->
          expect(
            replay:,
            client: Client(
              ..client,
              buffers: dict.insert(client.buffers, connection, <<
                buffer:bits,
                more:bits,
              >>),
            ),
            connection:,
            line:,
            expected:,
          )
        Error(mug.Timeout) ->
          Error(ended_or(
            replay:,
            client:,
            connection:,
            line:,
            otherwise: Silent(connection:, line:, expected: decode(expected)),
          ))
        Error(_) -> Error(ended(replay:, connection:, line:))
      }
  }
}

/// Waits for the end of the connection: a close of the client's is awaited in
/// the shell, which must have taken every input, the close among them; a close
/// of the server's is awaited on the socket, and no byte may come before it.
fn await_end(
  session session: Session,
  replay replay: Replay,
  client client: Client,
  connection connection: String,
  line line: Int,
  by by: Side,
) -> Result(Client, Failure) {
  let table = process.named_subject(replay.table.name)
  let assert Ok(recorded) =
    list.find(session.connections, fn(candidate) {
      candidate.name == connection
    })
    as "the plan names a connection of the session"
  let leftover = result.unwrap(dict.get(client.buffers, connection), <<>>)
  use Nil <- result.try(case leftover {
    <<>> -> Ok(Nil)
    _ -> Error(Unexpected(connection:, line:, written: decode(leftover)))
  })
  case by {
    wire_recording.Client -> {
      let inputs = list.length(inputs_of(recorded))
      case
        replay_table.await_taken(
          table:,
          connection:,
          inputs:,
          within_ms: wait_ms,
        )
      {
        Ok(Nil) -> Ok(client)
        Error(replay_table.Mismatched(mismatch:)) ->
          Error(mismatch_failure(connection, mismatch))
        Error(replay_table.TimedOut(taken:)) ->
          Error(NeverTaken(
            connection:,
            line:,
            input: wire_recording.PeerClosed,
            taken:,
          ))
      }
    }
    wire_recording.Server ->
      case
        mug.receive(
          socket_of(client, connection),
          timeout_milliseconds: wait_ms,
        )
      {
        Ok(written) ->
          Error(Unexpected(connection:, line:, written: decode(written)))
        Error(mug.Timeout) -> Error(StillOpen(connection:, line:))
        Error(_) ->
          case replay_table.failure_of(table:, connection:) {
            Some(mismatch) -> Error(mismatch_failure(connection, mismatch))
            None -> Ok(client)
          }
      }
  }
}

/// The failure of an input the shell took that matches no recorded one.
fn mismatch_failure(
  connection: String,
  mismatch: replay_table.Mismatch,
) -> Failure {
  case mismatch {
    replay_table.Unrecorded(line:) -> TookUnrecordedInput(connection:, line:)
    replay_table.OutOfOrder(line:, expected:, taken:) ->
      TookOutOfOrder(connection:, line:, expected:, taken:)
  }
}

/// The failure of a connection that ended where the recording goes on: the
/// mismatch that ended it when its shell met one, else what it logged.
fn ended(
  replay replay: Replay,
  connection connection: String,
  line line: Int,
) -> Failure {
  let table = process.named_subject(replay.table.name)
  case replay_table.failure_of(table:, connection:) {
    Some(mismatch) -> mismatch_failure(connection, mismatch)
    None ->
      EndedEarly(
        connection:,
        line:,
        logged: list.filter_map(logged(replay), fn(entry) {
          case entry.connection == connection, entry.level {
            True, "warning" | True, "error" -> Ok(entry.text)
            _, _ -> Error(Nil)
          }
        }),
      )
  }
}

/// `otherwise` when the connection is still open; the failure of one that has
/// ended otherwise.
fn ended_or(
  replay replay: Replay,
  client client: Client,
  connection connection: String,
  line line: Int,
  otherwise otherwise: Failure,
) -> Failure {
  let table = process.named_subject(replay.table.name)
  case replay_table.failure_of(table:, connection:) {
    Some(mismatch) -> mismatch_failure(connection, mismatch)
    None ->
      case mug.receive(socket_of(client, connection), timeout_milliseconds: 0) {
        Ok(_) | Error(mug.Timeout) -> otherwise
        Error(_) -> ended(replay:, connection:, line:)
      }
  }
}

/// Compares the bytes recorded with the bytes written, as streams, and says
/// where they first differ, with the message each holds there decoded.
pub fn compare(
  recorded recorded: BitArray,
  written written: BitArray,
) -> Result(Nil, Difference) {
  case first_difference(recorded, written, 0) {
    Some(offset) ->
      Error(Difference(
        offset:,
        recorded: decode_at(recorded, offset),
        written: decode_at(written, offset),
      ))
    None -> Ok(Nil)
  }
}

/// The offset of the first byte at which the streams differ, or at which the
/// shorter ends before the longer.
fn first_difference(
  recorded: BitArray,
  written: BitArray,
  offset: Int,
) -> Option(Int) {
  case recorded, written {
    <<>>, <<>> -> None
    <<a, rest_recorded:bytes>>, <<b, rest_written:bytes>> if a == b ->
      first_difference(rest_recorded, rest_written, offset + 1)
    _, _ -> Some(offset)
  }
}

/// What a stream holds at `offset`: nothing when it ended there, else its first
/// message.
fn decode_at(stream: BitArray, offset: Int) -> Decoded {
  case bit_array.byte_size(stream) <= offset {
    True -> Undecoded(<<>>)
    False -> decode(stream)
  }
}

/// Reads the first message of `bytes` with the current codec: a whole frame
/// gives its id, named as the client names it (four hex digits) and its body in
/// hexadecimal; bytes that are no whole frame are left as they are. It reads
/// no cipher, which the replay client does not hold, so a ciphered stream is
/// bytes.
pub fn decode(bytes bytes: BitArray) -> Decoded {
  case frame.take(bytes) {
    Ok(Some(#(found, _rest))) ->
      Message(
        message_id: found.message_id,
        name: client_connection.message_text(message_id: found.message_id),
        text: string.lowercase(bit_array.base16_encode(found.body)),
      )
    Ok(None) | Error(_) -> Undecoded(bytes)
  }
}
