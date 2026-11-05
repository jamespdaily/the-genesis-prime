//// The wire recording's file format (genesis_prime/wire_recording): one JSON
//// line for the header, one for each input the shell took and each write, and
//// a closing line saying which side closed. Expected values come from these
//// places.
//// - The layout in the module's doc comment: the keys of each line, their
////   order, the bytes as lower-case hex, one line feed ending each line, and
////   the sequence number growing from line to line.
//// - The time an input carries: the monotonic clock in milliseconds, which can
////   be negative, and a FILETIME of 100 ns intervals, which is above 2^53
////   (opcode.0x117 carries it in 64 bits).
//// - The rule that a file is whole only with its closing line: a file that
////   ends before it, or inside a line, is cut.
//// - The seed's size: the 32 bytes the server draws for each connection
////   (`step.Accepted`).

import genesis_prime/seed
import genesis_prime/step.{Now}
import genesis_prime/wire_recording.{
  Accepted, Answer, Answered, Client, Closing, Cut, EndedBeforeAnswer, Header,
  NoAnswerInTime, NotALine, NotRunning, OtherFormat, PeerClosed, Read,
  ReadFailed, Recording, Server, StoppedWaiting, Stopping, TimerFired, Took,
  WatchEnded, Woken, WriteFailed, Wrote,
}
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

/// The 32 bytes `00 01 FE FF` and 28 times `AB`.
fn seed_bytes() -> BitArray {
  <<0, 1, 254, 255, bit_array.concat(list.repeat(<<0xAB>>, 28)):bits>>
}

/// The same 32 bytes in lower-case hexadecimal.
fn seed_hex() -> String {
  "0001feff" <> string.repeat("ab", 28)
}

fn header() -> wire_recording.Header {
  let assert Ok(seed) = seed.from_bytes(seed_bytes()) as "32 bytes are a seed"
  Header(
    format: 1,
    rule: "genesis_prime/login/sts_connection",
    client_build: 16_042,
    tables_digest: Some("52E6"),
    seed:,
    accept_ordinal: 3,
    realm: None,
  )
}

/// A time as the 2026-11-01 session's first inputs carried it: a negative
/// monotonic reading and a FILETIME above 2^53.
fn at() -> step.Now {
  Now(monotonic_ms: -576_460_743_128, filetime: 134_380_604_412_280_090)
}

pub fn the_header_is_one_json_line_with_its_keys_in_order_test() -> Nil {
  use <- owned_test.run(30_000)
  assert wire_recording.encode_header(header())
    == "{\"format\":1,\"rule\":\"genesis_prime/login/sts_connection\",\"client_build\":16042,\"tables_digest\":\"52E6\",\"seed\":\""
    <> seed_hex()
    <> "\",\"accept_ordinal\":3,\"realm\":null}\n"
    as "the header's keys are format, rule, client_build, tables_digest, seed, accept_ordinal and realm, the seed in lower-case hex"
}

pub fn the_realm_a_rule_writes_is_in_its_header_and_reads_back_test() -> Nil {
  use <- owned_test.run(30_000)
  let with_realm =
    Header(
      ..header(),
      realm: Some(wire_recording.Realm(
        id: 1,
        name: "Genesis",
        address: 3_232_237_696,
        port: 24_000,
      )),
    )
  let text = wire_recording.encode_header(with_realm)
  assert string.contains(
    text,
    "\"realm\":{\"id\":1,\"name\":\"Genesis\",\"address\":3232237696,\"port\":24000}",
  )
    as "the realm's id, name, address and port, in that order"
  let closing = Closing(sequence: 2, by: Client)
  assert wire_recording.read(text <> wire_recording.encode_closing(closing))
    == Ok(Recording(with_realm, [], Some(closing)))
    as "the header with its realm reads back as written"
}

pub fn a_seed_that_is_not_32_bytes_is_no_header_of_the_format_test() -> Nil {
  use <- owned_test.run(30_000)
  let closing = wire_recording.encode_closing(Closing(sequence: 2, by: Client))
  let header_with = fn(seed_text) {
    "{\"format\":1,\"rule\":\"x\",\"client_build\":16042,\"tables_digest\":null,\"seed\":\""
    <> seed_text
    <> "\",\"accept_ordinal\":1,\"realm\":null}\n"
    <> closing
  }
  let assert Ok(_) = wire_recording.read(header_with(seed_hex()))
    as "32 bytes are a seed"
  let assert Error(NotALine(line: 0, reason:)) =
    wire_recording.read(header_with("0001feff"))
    as "4 bytes are no seed"
  assert string.contains(reason, "a seed of 32 bytes")
    as "the reason says what the line should hold"
  let assert Error(NotALine(line: 0, ..)) =
    wire_recording.read(header_with(seed_hex() <> "ab"))
    as "33 bytes are no seed"
  let assert Error(NotALine(line: 0, ..)) = wire_recording.read(header_with(""))
    as "no bytes are no seed"
  Nil
}

pub fn a_rule_that_reads_no_table_has_a_null_tables_digest_test() -> Nil {
  use <- owned_test.run(30_000)
  let text =
    wire_recording.encode_header(Header(..header(), tables_digest: None))
  assert string.contains(text, "\"tables_digest\":null")
    as "no digest is null, never an empty string"
}

pub fn an_input_line_holds_its_sequence_its_whole_time_and_its_kind_test() -> Nil {
  use <- owned_test.run(30_000)
  assert wire_recording.encode_line(Took(41, at(), Read(<<1, 255>>)))
    == "{\"sequence\":41,\"monotonic_ms\":-576460743128,\"filetime\":134380604412280090,\"in\":\"read\",\"bytes\":\"01ff\"}\n"
    as "a read line: sequence, monotonic_ms, filetime, in and the bytes in hex"
  assert wire_recording.encode_line(Took(
      43,
      at(),
      Answered(outcome: NoAnswerInTime),
    ))
    == "{\"sequence\":43,\"monotonic_ms\":-576460743128,\"filetime\":134380604412280090,\"in\":\"answered\",\"outcome\":\"no_answer_in_time\"}\n"
    as "an answered line names how the ask ended and never the answer"
  assert wire_recording.encode_line(Took(47, at(), TimerFired(timer: 2)))
    == "{\"sequence\":47,\"monotonic_ms\":-576460743128,\"filetime\":134380604412280090,\"in\":\"timer_fired\",\"timer\":2}\n"
    as "a timer line names the timer's number"
  assert wire_recording.encode_line(Took(48, at(), PeerClosed))
    == "{\"sequence\":48,\"monotonic_ms\":-576460743128,\"filetime\":134380604412280090,\"in\":\"peer_closed\"}\n"
    as "an input with nothing more to keep is its kind alone"
}

pub fn a_write_line_holds_its_sequence_and_bytes_and_no_time_test() -> Nil {
  use <- owned_test.run(30_000)
  assert wire_recording.encode_line(Wrote(42, <<0, 171>>))
    == "{\"sequence\":42,\"out\":\"00ab\"}\n"
    as "the bytes depend on the time of the input whose step wrote them, so a write holds none"
}

pub fn the_closing_line_names_the_side_that_closed_test() -> Nil {
  use <- owned_test.run(30_000)
  assert wire_recording.encode_closing(Closing(52, Client))
    == "{\"sequence\":52,\"closed\":\"client\"}\n"
  assert wire_recording.encode_closing(Closing(53, Server))
    == "{\"sequence\":53,\"closed\":\"server\"}\n"
}

/// A line of every kind of input, each with a time of its own.
fn every_input() -> List(wire_recording.Input) {
  [
    Accepted,
    Read(<<>>),
    Read(<<0, 1, 2, 255>>),
    Answered(outcome: Answer),
    Answered(outcome: NotRunning),
    Answered(outcome: EndedBeforeAnswer),
    Answered(outcome: NoAnswerInTime),
    Answered(outcome: StoppedWaiting),
    TimerFired(timer: 7),
    PeerClosed,
    ReadFailed,
    WriteFailed,
    Woken,
    WatchEnded,
    Stopping,
  ]
}

pub fn a_recording_of_every_kind_of_line_reads_back_as_written_test() -> Nil {
  use <- owned_test.run(30_000)
  let lines =
    list.index_map(every_input(), fn(input, index) {
      Took(
        sequence: 10 + 2 * index,
        at: Now(
          monotonic_ms: -5 + index,
          filetime: 9_000_000_000_000_000 + index,
        ),
        input:,
      )
    })
  let written =
    list.flat_map(lines, fn(line) {
      case line {
        Took(sequence:, ..) -> [
          line,
          Wrote(sequence: sequence + 1, bytes: <<7>>),
        ]
        Wrote(..) -> [line]
      }
    })
  let closing = Closing(sequence: 100, by: Client)
  let text =
    wire_recording.encode_header(header())
    <> string.concat(list.map(written, wire_recording.encode_line))
    <> wire_recording.encode_closing(closing)
  assert wire_recording.read(text)
    == Ok(Recording(header(), written, Some(closing)))
    as "the header, every input kind with its outcome or number, the writes and the closing line read back as written"
}

pub fn a_file_without_its_closing_line_is_cut_and_counts_its_whole_lines_test() -> Nil {
  use <- owned_test.run(30_000)
  let text =
    wire_recording.encode_header(header())
    <> wire_recording.encode_line(Took(1, at(), Accepted))
    <> wire_recording.encode_line(Wrote(2, <<1>>))
  assert wire_recording.read(text) == Error(Cut(lines: 3))
    as "the header and two lines are whole, and no closing line follows"
  assert wire_recording.read(wire_recording.encode_header(header()))
    == Error(Cut(lines: 1))
    as "a header alone is a cut recording"
  assert wire_recording.read("") == Error(Cut(lines: 0))
    as "an empty file is cut before its header"
}

pub fn a_file_without_its_closing_line_reads_so_far_up_to_its_last_whole_line_test() -> Nil {
  use <- owned_test.run(30_000)
  let whole_lines =
    wire_recording.encode_header(header())
    <> wire_recording.encode_line(Took(1, at(), Accepted))
  let cut_line = string.drop_end(wire_recording.encode_line(Wrote(2, <<1>>)), 3)
  assert wire_recording.read_so_far(whole_lines)
    == Ok(Recording(header(), [Took(1, at(), Accepted)], None))
    as "no closing line yet"
  assert wire_recording.read_so_far(whole_lines <> cut_line)
    == Ok(Recording(header(), [Took(1, at(), Accepted)], None))
    as "a line the writer had not finished is not read, and is no malformed line"
  assert wire_recording.read(whole_lines <> cut_line) == Error(Cut(lines: 2))
    as "`read` still refuses a recording that is not closed"
  assert wire_recording.read_so_far("") == Error(Cut(lines: 0))
    as "a file with no whole line has no header"
}

pub fn a_file_cut_inside_a_line_is_cut_even_when_the_part_reads_as_json_test() -> Nil {
  use <- owned_test.run(30_000)
  let whole =
    wire_recording.encode_header(header())
    <> wire_recording.encode_line(Took(1, at(), Accepted))
    <> wire_recording.encode_closing(Closing(2, Server))
  // Without the final line feed the closing line is whole JSON but was never
  // finished by the writer.
  let cut = string.drop_end(whole, 1)
  assert wire_recording.read(cut) == Error(Cut(lines: 2))
    as "a line is whole only with its line feed"
  let inside =
    wire_recording.encode_header(header())
    <> string.drop_end(wire_recording.encode_line(Took(1, at(), Accepted)), 6)
  assert wire_recording.read(inside) == Error(Cut(lines: 1))
    as "a line cut in the middle is not counted"
}

pub fn a_file_of_another_format_is_refused_by_its_header_alone_test() -> Nil {
  use <- owned_test.run(30_000)
  let text =
    "{\"format\":2,\"rule\":\"x\",\"unknown_key\":true}\nnot json at all\n"
  assert wire_recording.read(text) == Error(OtherFormat(found: 2))
    as "the header's format is read first, so a later format's other lines are never read"
}

pub fn a_line_that_is_no_line_of_the_format_names_its_number_test() -> Nil {
  use <- owned_test.run(30_000)
  let head = wire_recording.encode_header(header())
  let line = wire_recording.encode_line(Took(5, at(), Accepted))
  let closing = wire_recording.encode_closing(Closing(9, Client))
  let assert Error(NotALine(line: 0, ..)) = wire_recording.read("not json\n")
    as "line 0 is the header"
  let assert Error(NotALine(line: 2, ..)) =
    wire_recording.read(head <> line <> "{\"sequence\":6,\"in\":\"smell\"}\n")
    as "an input kind the format does not list"
  let assert Error(NotALine(line: 2, ..)) =
    wire_recording.read(head <> line <> "{\"sequence\":6,\"out\":\"zz\"}\n")
    as "bytes that are not hex"
  let assert Error(NotALine(line: 2, ..)) =
    wire_recording.read(
      head <> line <> "{\"sequence\":6,\"in\":\"accepted\"}\n" <> closing,
    )
    as "an input line with no time"
  let assert Error(NotALine(line: 3, ..)) =
    wire_recording.read(head <> line <> closing <> line)
    as "no line follows the closing line"
  Nil
}

pub fn a_sequence_number_that_does_not_grow_is_no_line_of_the_format_test() -> Nil {
  use <- owned_test.run(30_000)
  let head = wire_recording.encode_header(header())
  let assert Error(NotALine(line: 2, ..)) =
    wire_recording.read(
      head
      <> wire_recording.encode_line(Took(5, at(), Accepted))
      <> wire_recording.encode_line(Wrote(5, <<1>>))
      <> wire_recording.encode_closing(Closing(9, Client)),
    )
    as "the second line repeats the sequence number of the first"
  let assert Error(NotALine(line: 3, ..)) =
    wire_recording.read(
      head
      <> wire_recording.encode_line(Took(5, at(), Accepted))
      <> wire_recording.encode_line(Wrote(6, <<1>>))
      <> wire_recording.encode_closing(Closing(4, Client)),
    )
    as "the closing line's number is below the line before it"
  Nil
}

pub fn the_bytes_of_a_line_are_lower_case_hex_of_every_byte_value_test() -> Nil {
  use <- owned_test.run(30_000)
  let every_byte =
    list.repeat(Nil, 256)
    |> list.index_map(fn(_, byte) { <<byte>> })
    |> bit_array.concat
  let text = wire_recording.encode_line(Wrote(1, every_byte))
  assert string.contains(
    text,
    string.lowercase(bit_array.base16_encode(every_byte)),
  )
    as "two lower-case hex digits for each byte"
  let recording =
    wire_recording.encode_header(header())
    <> text
    <> wire_recording.encode_closing(Closing(2, Server))
  assert wire_recording.read(recording)
    == Ok(Recording(header(), [Wrote(1, every_byte)], Some(Closing(2, Server))))
}
