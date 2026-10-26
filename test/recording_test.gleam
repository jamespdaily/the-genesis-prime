//// The recording relay and the recording file. Expected values come from three
//// places.
//// - The issue of the recording step: the relay forwards every chunk both ways
////   unchanged, writes each with its direction and its time from the
////   connection's start in microseconds, and a recording reads back as it was
////   written; one file for each connection.
//// - The layout written in the doc comment of `genesis_prime/recording`, for
////   the bytes of the vector in the last test.
//// - The Erlang documentation of `erlang:monotonic_time/1`: the monotonic
////   clock's values are not related to the wall clock and can be negative, so
////   a chunk's time is a difference of two readings, never below 0 and never
////   above what the test itself measured around the connection.
////
//// The test is the client and, through the planted server's listening socket,
//// the server too, and it waits for each event: a connection, a chunk. The relay
//// writes a chunk to its file before it passes the chunk on, so once the
//// receiving end has the bytes the file holds them.

import genesis_prime/recording.{
  type Recording, Auth, Chunk, ClientToServer, Game, Header, Recording,
  ServerToClient, Sts,
}
import genesis_prime/recording/clock
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar.{Date}
import message_support
import owned_test
import recording_support
import seeded
import simplifile

/// How long one wait for an event may take, in milliseconds.
const event_wait_ms = 5000

pub fn the_relay_passes_every_chunk_both_ways_unchanged_and_records_each_with_its_direction_test() -> Nil {
  use <- owned_test.run(30_000)
  use session <- recording_support.run
  let ends = recording_support.connect(session:, wait_ms: event_wait_ms)

  // `exchange` asserts that each side receives exactly the bytes the other
  // sent, one round after another.
  let played =
    recording_support.exchange(
      ends,
      seed: 72,
      rounds: 8,
      wait_ms: event_wait_ms,
    )
  assert list.length(played) == 8 as "every round was played"

  let assert [recorded] = recording_support.recordings(session)
    as "one connection is one recording file"
  assert recorded.header == session.header
    as "the header holds the build, the date, the role and the commit"
  let expected =
    list.flat_map(played, fn(round) {
      [#(ClientToServer, round.0), #(ServerToClient, round.1)]
    })
  assert recording_support.runs(recorded.chunks) == expected
    as "the recording holds every byte each way, in the order it crossed"
}

pub fn a_chunks_time_is_microseconds_from_its_connections_start_on_the_monotonic_clock_test() -> Nil {
  use <- owned_test.run(30_000)
  use session <- recording_support.run

  let before_first = clock.microseconds()
  let first = recording_support.connect(session:, wait_ms: event_wait_ms)
  let first_rounds =
    recording_support.exchange(
      first,
      seed: 3,
      rounds: 6,
      wait_ms: event_wait_ms,
    )
  let first_elapsed = clock.microseconds() - before_first
  assert list.length(first_rounds) == 6 as "every round of the first was played"

  let before_second = clock.microseconds()
  let second = recording_support.connect(session:, wait_ms: event_wait_ms)
  let second_rounds =
    recording_support.exchange(
      second,
      seed: 4,
      rounds: 1,
      wait_ms: event_wait_ms,
    )
  let second_elapsed = clock.microseconds() - before_second
  assert list.length(second_rounds) == 1 as "the round of the second was played"

  let assert [first_recording, second_recording] =
    recording_support.recordings(session)
    as "each connection is a recording file of its own, in the order they opened"
  assert_timed_within(first_recording, first_elapsed)
  assert_timed_within(second_recording, second_elapsed)
}

/// Every chunk's time is from 0 up to `elapsed`, the time the test measured
/// around the whole connection, and no time is below the one before it.
fn assert_timed_within(recording: Recording, elapsed: Int) -> Nil {
  let times = list.map(recording.chunks, fn(chunk) { chunk.microseconds })
  assert times != [] as "the connection recorded chunks"
  assert list.all(times, fn(time) { time >= 0 && time <= elapsed })
    as "every chunk's time is from the connection's start, within what the test measured"
  assert times == list.sort(times, int.compare)
    as "a chunk is never timed before the chunk before it"
}

pub fn a_recording_reads_back_as_it_was_written_test() -> Nil {
  use <- owned_test.run(60_000)

  // The layout, written out by hand from the doc comment of the recording
  // module: magic, version 1, build 16042 (0x3EAA), year 2026 (0x07EA), month
  // 10, day 26, the role `auth`, the commit `abc`, then a client-to-server
  // chunk at 258 microseconds holding 1, 2, 3 and an empty server-to-client
  // chunk at 0.
  let vector =
    Recording(
      header: Header(
        build: 16_042,
        date: Date(2026, calendar.October, 26),
        role: Auth,
        commit: "abc",
        seed: None,
      ),
      chunks: [
        Chunk(ClientToServer, 258, <<1, 2, 3>>),
        Chunk(ServerToClient, 0, <<>>),
      ],
    )
  let layout = <<
    "GREC":utf8, 1, 0x00, 0x00, 0x3E, 0xAA, 0x07, 0xEA, 10, 26, 0, 4,
    "auth":utf8, 0, 3, "abc":utf8, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x02, 0, 0, 0, 3,
    1, 2, 3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  >>
  assert recording.encode(vector) == Ok(layout)
    as "the bytes are the documented layout"
  assert recording.decode(layout) == Ok(vector)
    as "the documented layout reads as the recording"

  // Random recordings, each through the pure functions and through a file.
  let folder = recording_support.new_folder()
  let cases = 200
  let checked =
    int.range(from: 0, to: cases, with: #(72, 0), run: fn(state, number) {
      let #(random, checked) = state
      let #(written, random) = random_recording(random)
      let label = "case " <> int.to_string(number)
      let assert Ok(bytes) = recording.encode(written)
        as { label <> ": every field is within its width, so it encodes" }
      assert recording.decode(bytes) == Ok(written)
        as { label <> ": the bytes read back as the recording" }
      // A file is written the way the relay writes it: the header when the
      // connection opens, and then each chunk as it comes.
      let path = folder <> "/case-" <> int.to_string(number) <> ".recording"
      assert recording.create(at: path, header: written.header) == Ok(Nil)
        as { label <> ": the file was created" }
      list.each(written.chunks, fn(chunk) {
        assert recording.append(to: path, chunk:) == Ok(Nil)
          as { label <> ": a chunk was appended" }
      })
      assert recording.read(from: path) == Ok(written)
        as { label <> ": the file reads back as the recording" }
      assert simplifile.read_bits(path) == Ok(bytes)
        as { label <> ": the file holds the same bytes as the encoding" }
      #(random, checked + 1)
    })
  assert checked.1 == cases as "every generated case was checked"
  let assert Ok(Nil) = simplifile.delete(folder)
    as "the test's folder was not removed"
  Nil
}

pub fn a_recording_names_its_seed_and_one_without_a_seed_reads_as_unseeded_test() -> Nil {
  use <- owned_test.run(30_000)

  // The layout of a seeded recording, written out by hand from the doc comment
  // of the recording module: magic, version 2, build 16042, the date, the role
  // `sts`, the commit `abc`, the seed 0x0102030405060708 in 64 bits, then one
  // client-to-server chunk at 258 microseconds holding 1, 2, 3.
  let seeded_vector =
    Recording(
      header: Header(
        build: 16_042,
        date: Date(2026, calendar.October, 26),
        role: Sts,
        commit: "abc",
        seed: Some(0x0102030405060708),
      ),
      chunks: [Chunk(ClientToServer, 258, <<1, 2, 3>>)],
    )
  let seeded_layout = <<
    "GREC":utf8, 2, 0x00, 0x00, 0x3E, 0xAA, 0x07, 0xEA, 10, 26, 0, 3, "sts":utf8,
    0, 3, "abc":utf8, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x02, 0,
    0, 0, 3, 1, 2, 3,
  >>
  assert recording.encode(seeded_vector) == Ok(seeded_layout)
    as "the bytes are the documented layout, the seed after the commit"
  assert recording.decode(seeded_layout) == Ok(seeded_vector)
    as "the documented layout reads as the seeded recording"

  // The ends of the seed's range, 0 and 64 bits of ones, are seeds; one bit
  // more or a negative number does not fit the header.
  let with_seed = fn(seed) {
    Recording(..seeded_vector, header: Header(..seeded_vector.header, seed:))
  }
  list.each([0, 0xFFFF_FFFF_FFFF_FFFF], fn(seed) {
    let written = with_seed(Some(seed))
    let assert Ok(bytes) = recording.encode(written)
      as "a seed of 64 bits encodes"
    assert recording.decode(bytes) == Ok(written)
      as "the seed reads back as it was written"
  })
  assert recording.encode(with_seed(Some(0x1_0000_0000_0000_0000)))
    == Error(recording.OutOfRange("seed", 0x1_0000_0000_0000_0000))
    as "a seed of more than 64 bits does not fit"
  assert recording.encode(with_seed(Some(-1)))
    == Error(recording.OutOfRange("seed", -1))
    as "a negative seed does not fit"

  // A recording made without a seed is the version-1 layout, byte for byte,
  // and reads as unseeded.
  let unseeded = with_seed(None)
  let assert Ok(unseeded_bytes) = recording.encode(unseeded)
    as "an unseeded recording encodes"
  let assert <<"GREC":utf8, 1, _:bytes>> = unseeded_bytes
    as "an unseeded recording is written as format version 1"
  assert recording.decode(unseeded_bytes) == Ok(unseeded)
    as "a recording without a seed reads as unseeded"

  // The live recording of the first session with the real client (the relay's
  // own header: build 16042, role, the commit that was checked
  // out) was made before a seed existed, and still reads, as unseeded.
  let folder = "test/recording/2026-10-26-login/"
  let assert Ok(sts) = recording.read(from: folder <> "sts-001.recording")
    as "the live STS recording reads"
  assert sts.header
    == Header(
      build: 16_042,
      date: Date(2026, calendar.October, 26),
      role: Sts,
      commit: "3c630b8e0a5287f7757bee4795d4a805605828f9",
      seed: None,
    )
    as "the live STS recording is unseeded"
}

/// A recording of random fields, each within its width in the file, and the
/// advanced state: any build of 32 bits, any year of 16 bits, a day up to the
/// 28th, any role, a commit of up to 60 characters of any width in UTF-8, a
/// seed of up to 64 bits or none, and up to 12 chunks of up to 300 bytes, of
/// any direction, none timed before the one before it.
fn random_recording(state: Int) -> #(Recording, Int) {
  let #(build, state) = message_support.unsigned(state:, bits: 32)
  let #(year, state) = message_support.unsigned(state:, bits: 16)
  let #(month_number, state) = seeded.up_to(state:, most: 11)
  let assert Ok(month) = calendar.month_from_int(month_number + 1)
    as "the month number is 1 to 12"
  let #(day, state) = seeded.up_to(state:, most: 27)
  let #(role_number, state) = seeded.up_to(state:, most: 2)
  let role = case role_number {
    0 -> Sts
    1 -> Auth
    _ -> Game
  }
  let #(commit, state) = message_support.text(state:, longest: 60)
  let #(chunk_count, state) = seeded.up_to(state:, most: 12)
  let #(chunks, state) = random_chunks(state:, count: chunk_count)
  let #(seeded_number, state) = seeded.up_to(state:, most: 1)
  let #(seed_value, state) = message_support.unsigned(state:, bits: 64)
  let seed = case seeded_number {
    0 -> None
    _ -> Some(seed_value)
  }
  let header =
    Header(build:, date: Date(year, month, day + 1), role:, commit:, seed:)
  #(Recording(header:, chunks:), state)
}

fn random_chunks(
  state state: Int,
  count count: Int,
) -> #(List(recording.Chunk), Int) {
  let #(chunks, _, state) =
    int.range(from: 0, to: count, with: #([], 0, state), run: fn(built, _) {
      let #(chunks, time, state) = built
      let #(direction_number, state) = seeded.up_to(state:, most: 1)
      let direction = case direction_number {
        0 -> ClientToServer
        _ -> ServerToClient
      }
      let #(later, state) = seeded.up_to(state:, most: 1_000_000_000_000)
      let #(length, state) = seeded.up_to(state:, most: 300)
      let #(bytes, state) = seeded.bytes(state:, count: length)
      let time = time + later
      #([Chunk(direction:, microseconds: time, bytes:), ..chunks], time, state)
    })
  #(list.reverse(chunks), state)
}
