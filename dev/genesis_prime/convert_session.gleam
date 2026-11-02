//// Converts a session recorded as rule terms (genesis_prime/rule_recording) into
//// the wire recording of the same session (genesis_prime/wire_recording): each
//// connection's reads, the bytes of its `Write` effects, the seed it was
//// accepted with and the time of each input, in one JSON-lines file for each
//// connection, and a fixture of the account and character rows the store
//// answered with. It is run once, for the session committed on 2026-11-01, and
//// removed with the term format.
////
//// `gleam run -m genesis_prime/convert_session -- <term folder> <wire folder>`
////
//// - **Order.** The term recordings hold no sequence number, so the lines of
////   the three connections are put in the order of the monotonic time of each
////   input, ties broken by the order the connections were accepted and then by
////   the input's place in its recording; a write follows the input whose step
////   wrote it, and a connection's closing line follows its last input. The
////   accept ordinals are the order of the accepts' times.
//// - **The fixture.** The account is the one the STS login's store answer
////   holds; the characters are those of the first character list the game
////   connection was answered, which is the state the session started from. The
////   rows' session epoch is not in an answer: it is written as 0.

import argv
import genesis_prime/client_connection.{type Answer, type Message, type Request}
import genesis_prime/login/guid
import genesis_prime/rule_recording.{type Record, Taken}
import genesis_prime/step.{
  type ConnectionEffect, type ConnectionEvent, type Outcome, Accepted, Answered,
  Effects, EffectsThenAsk, Input, OwnEffect, OwnEvent, PeerClosed, Write,
}
import genesis_prime/store
import genesis_prime/table/id
import genesis_prime/wire_recording
import genesis_prime/wire_recording/fixture
import genesis_prime/wire_recording/fixture/sql
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import simplifile

type Old =
  List(Record(Request, ConnectionEvent(Message, Answer), ConnectionEffect))

/// One input of one connection, with what it wrote, in the order they are put.
type Block {
  Block(
    key: #(Int, Int, Int),
    connection: Int,
    input: wire_recording.Input,
    at: step.Now,
    writes: List(BitArray),
    closes: Bool,
  )
}

pub fn main() -> Nil {
  let assert [term_folder, wire_folder] = argv.load().arguments
    as "usage: convert_session <term folder> <wire folder>"
  let assert Ok(names) = simplifile.read_directory(term_folder)
    as "the term folder reads"
  let files =
    list.filter(names, string.ends_with(_, ".recording"))
    |> list.filter(fn(name) {
      string.contains(name, "sts_connection")
      || string.contains(name, "auth_connection")
      || string.contains(name, "game.connection")
    })
    |> list.sort(string.compare)
  let recordings =
    list.map(files, fn(name) {
      let assert Ok(bytes) = simplifile.read_bits(term_folder <> "/" <> name)
        as "a recording reads"
      let assert Ok(#(header, records)) = rule_recording.read(bytes)
        as "a recording is a rule recording"
      let header: rule_recording.Header(Nil) = header
      let records: Old = records
      #(name, header, records)
    })
  // The connections in the order they were accepted.
  let accepted =
    list.map(recordings, fn(recording) {
      let #(_, _, records) = recording
      let assert [Taken(input: Input(now:, ..), ..), ..] = records
        as "a connection's first input"
      #(now.monotonic_ms, recording)
    })
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.1 })
  let numbered =
    list.index_map(accepted, fn(recording, index) { #(index + 1, recording) })
  let blocks =
    list.flat_map(numbered, fn(entry) {
      let #(ordinal, #(_, _, records)) = entry
      blocks_of(ordinal:, records:)
    })
    |> list.sort(fn(a, b) { compare_keys(a.key, b.key) })
  let sequenced = sequence(blocks, 1, [])
  let assert Ok(Nil) = simplifile.create_directory_all(wire_folder)
    as "the wire folder was made"
  list.each(numbered, fn(entry) {
    let #(ordinal, #(name, header, records)) = entry
    write_connection(
      wire_folder:,
      name:,
      header:,
      ordinal:,
      records:,
      lines: list.filter(sequenced, fn(line) { line.0 == ordinal }),
    )
  })
  let assert Ok(Nil) =
    simplifile.write(
      wire_folder <> "/" <> fixture.file_name,
      fixture_of(list.map(numbered, fn(entry) { entry.1.2 })),
    )
    as "the fixture was written"
  Nil
}

fn compare_keys(a: #(Int, Int, Int), b: #(Int, Int, Int)) -> order.Order {
  int.compare(a.0, b.0)
  |> order.break_tie(int.compare(a.1, b.1))
  |> order.break_tie(int.compare(a.2, b.2))
}

fn blocks_of(ordinal ordinal: Int, records records: Old) -> List(Block) {
  let inputs =
    list.filter(records, fn(record) {
      case record {
        Taken(..) -> True
        rule_recording.End(..) -> False
      }
    })
  let last = list.length(inputs) - 1
  list.index_map(inputs, fn(record, index) {
    case record {
      Taken(input: Input(now:, event:), step:) -> {
        let effects = case step {
          Effects(effects:) -> effects
          EffectsThenAsk(effects:, ..) -> effects
        }
        Block(
          key: #(now.monotonic_ms, ordinal, index),
          connection: ordinal,
          input: wire_input(event),
          at: now,
          writes: list.filter_map(effects, fn(effect) {
            case effect {
              OwnEffect(Write(bytes:)) -> Ok(bytes)
              _ -> Error(Nil)
            }
          }),
          closes: index == last,
        )
      }
      rule_recording.End(..) -> panic as "the end record is not an input"
    }
  })
}

fn wire_input(
  event: step.Event(ConnectionEvent(Message, Answer)),
) -> wire_recording.Input {
  case event {
    OwnEvent(Accepted(..)) -> wire_recording.Accepted
    OwnEvent(step.Read(bytes:)) -> wire_recording.Read(bytes:)
    OwnEvent(Answered(outcome:, ..)) ->
      wire_recording.Answered(outcome: wire_outcome(outcome))
    OwnEvent(PeerClosed) -> wire_recording.PeerClosed
    _ -> panic as "the session holds no other kind of input"
  }
}

fn wire_outcome(outcome: Outcome(Answer)) -> wire_recording.Outcome {
  case outcome {
    step.Answer(..) -> wire_recording.Answer
    step.NotRunning -> wire_recording.NotRunning
    step.NoAnswerInTime -> wire_recording.NoAnswerInTime
    step.EndedBeforeAnswer -> wire_recording.EndedBeforeAnswer
    step.StoppedWaiting -> wire_recording.StoppedWaiting
  }
}

/// Numbers the lines of the blocks in order: the input, its writes, and, for
/// the last input of a connection, its closing line. Each line is given with
/// its connection.
fn sequence(
  blocks: List(Block),
  next: Int,
  so_far: List(#(Int, Result(wire_recording.Line, wire_recording.Closing))),
) -> List(#(Int, Result(wire_recording.Line, wire_recording.Closing))) {
  case blocks {
    [] -> list.reverse(so_far)
    [block, ..rest] -> {
      let input = #(
        block.connection,
        Ok(wire_recording.Took(sequence: next, at: block.at, input: block.input)),
      )
      let writes =
        list.index_map(block.writes, fn(bytes, index) {
          #(
            block.connection,
            Ok(wire_recording.Wrote(sequence: next + 1 + index, bytes:)),
          )
        })
      let after = next + 1 + list.length(block.writes)
      let closing = case block.closes {
        True -> [
          #(
            block.connection,
            Error(wire_recording.Closing(
              sequence: after,
              by: wire_recording.Client,
            )),
          ),
        ]
        False -> []
      }
      sequence(
        rest,
        after + list.length(closing),
        list.append(
          list.reverse(list.flatten([[input], writes, closing])),
          so_far,
        ),
      )
    }
  }
}

fn write_connection(
  wire_folder wire_folder: String,
  name name: String,
  header header: rule_recording.Header(Nil),
  ordinal ordinal: Int,
  records records: Old,
  lines lines: List(#(Int, Result(wire_recording.Line, wire_recording.Closing))),
) -> Nil {
  let assert [
    Taken(
      input: Input(event: OwnEvent(Accepted(connection:, seed:, ..)), ..),
      ..,
    ),
    ..
  ] = records
    as "the first input is the accept"
  let step.ConnectionId(old_id) = connection
  let text =
    wire_recording.encode_header(wire_recording.Header(
      format: wire_recording.format,
      rule: header.rule,
      client_build: header.client_build,
      tables_digest: header.tables_digest,
      seed:,
      accept_ordinal: ordinal,
    ))
    <> string.concat(
      list.map(lines, fn(line) {
        case line.1 {
          Ok(line) -> wire_recording.encode_line(line)
          Error(closing) -> wire_recording.encode_closing(closing)
        }
      }),
    )
  let file =
    string.replace(header.rule, "/", ".")
    <> "-"
    <> int.to_string(old_id)
    <> ".jsonl"
  let assert Ok(Nil) = simplifile.write(wire_folder <> "/" <> file, text)
    as "a wire recording was written"
  let _ = name
  Nil
}

/// The fixture the store's answers make: the account of the STS login's answer
/// and the characters of the first list the game connection was answered.
fn fixture_of(all: List(Old)) -> String {
  let answers =
    list.flat_map(all, fn(records) {
      list.filter_map(records, fn(record) {
        case record {
          Taken(
            input: Input(
              event: OwnEvent(Answered(
                outcome: step.Answer(client_connection.FromStore(answer)),
                ..,
              )),
              ..,
            ),
            ..,
          ) -> Ok(answer)
          _ -> Error(Nil)
        }
      })
    })
  let assert Ok(account) =
    list.find_map(answers, fn(answer) {
      case answer {
        store.ForLogin(store.AccountFound(account:)) -> Ok(account)
        _ -> Error(Nil)
      }
    })
    as "the session's store answers hold the account"
  let assert Ok(characters) =
    list.find_map(answers, fn(answer) {
      case answer {
        store.ForSelect(store.Listed(characters:)) -> Ok(characters)
        _ -> Error(Nil)
      }
    })
    as "the session's store answers hold a character list"
  let store.AccountId(account_id) = account.account_id
  fixture.render(
    accounts: [
      sql.AllAccountsRow(
        account_id:,
        login_name: account.login_name,
        srp_salt: account.srp_salt,
        srp_verifier: account.srp_verifier,
        game_account_id: guid.to_text(account.game_account_id),
      ),
    ],
    characters: list.map(characters, fn(character) {
      let store.CharacterId(character_id) = character.character_id
      let id.RaceId(race_id) = character.race_id
      let id.ClassId(class_id) = character.class_id
      sql.AllCharactersRow(
        character_id:,
        account_id:,
        session_epoch: 0,
        name: character.name,
        gender: character.gender,
        race_id:,
        class_id:,
        faction_id: character.faction_id,
        level: character.level,
        path: character.path,
        world_id: character.world_id,
        world_zone_id: character.world_zone_id,
        position_x: character.position_x,
        position_y: character.position_y,
        position_z: character.position_z,
        look_labels: list.map(character.look, fn(entry) {
          let id.CharacterCustomizationLabelId(label) = entry.label
          label
        }),
        look_values: list.map(character.look, fn(entry) { entry.value }),
        bones: character.bones,
        needs_rename: character.naming == store.NeedsRename,
      )
    }),
  )
}
