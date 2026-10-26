//// The test client's frame reader. Its expected values are the client's own
//// framing: a frame may span reads and one read may hold several
//// (ReadConnectionMessages 0x1403321a0, ReadMessageFrame 0x140331990; the
//// module doc of `genesis_prime/connection/frame`), so the frames a server
//// wrote are the same however the network cut its bytes. A server that writes
//// two frames in two writes is read in two reads on a machine that is slower
//// than the one that wrote the test, which is how login_tcp_test failed on CI.

import frame_reader
import genesis_prime/connection/frame.{type Frame, Frame}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/result
import owned_test

fn first() -> Frame {
  Frame(message_id: 0x0591, body: <<1, 2, 3, 4>>)
}

fn second() -> Frame {
  Frame(message_id: 0x03DB, body: <<9, 8, 7, 6, 5, 4, 3, 2, 1>>)
}

fn encoded(sent: Frame) -> BitArray {
  let assert Ok(bytes) = frame.encode(sent.message_id, sent.body)
    as "the frame is within the size limit"
  bytes
}

/// A reader of the reads queued on the subject: what is there, and an error
/// once nothing is left, as a connection that went quiet.
fn reads_from(reads: Subject(BitArray)) -> fn() -> Result(BitArray, Nil) {
  fn() { process.receive(reads, 0) |> result.replace_error(Nil) }
}

fn queue(reads: List(BitArray)) -> fn() -> Result(BitArray, Nil) {
  let subject = process.new_subject()
  list.each(reads, process.send(subject, _))
  reads_from(subject)
}

/// The bytes cut into reads of `size` bytes, the last one the rest.
fn cut(bytes: BitArray, size: Int) -> List(BitArray) {
  case bit_array.byte_size(bytes) <= size {
    True -> [bytes]
    False -> {
      let assert Ok(head) = bit_array.slice(bytes, 0, size) as "a prefix"
      let assert Ok(rest) =
        bit_array.slice(bytes, size, bit_array.byte_size(bytes) - size)
        as "the rest"
      [head, ..cut(rest, size)]
    }
  }
}

fn sizes_up_to(most: Int) -> List(Int) {
  list.repeat(Nil, most) |> list.index_map(fn(_, index) { index + 1 })
}

pub fn two_frames_in_one_read_are_both_read_test() -> Nil {
  use <- owned_test.run(5000)
  let reads = [<<encoded(first()):bits, encoded(second()):bits>>]
  assert frame_reader.read(have: <<>>, count: 2, next: queue(reads))
    == Ok([first(), second()])
    as "frame.gleam: one read may hold several frames"
}

pub fn two_frames_in_two_reads_are_both_read_test() -> Nil {
  use <- owned_test.run(5000)
  let reads = [encoded(first()), encoded(second())]
  assert frame_reader.read(have: <<>>, count: 2, next: queue(reads))
    == Ok([first(), second()])
    as "the client's frame reader keeps the frames of every read: the server's two writes may arrive as two reads"
}

pub fn frames_that_arrive_a_byte_at_a_time_are_all_read_test() -> Nil {
  use <- owned_test.run(5000)
  let bytes = <<encoded(first()):bits, encoded(second()):bits>>
  assert frame_reader.read(have: <<>>, count: 2, next: queue(cut(bytes, 1)))
    == Ok([first(), second()])
    as "frame.gleam: a frame may span reads, however small"
}

pub fn a_read_that_ends_inside_a_frame_is_completed_by_the_next_test() -> Nil {
  use <- owned_test.run(5000)
  let bytes = <<encoded(first()):bits, encoded(second()):bits>>
  // Every cut size from 1 to the whole, so each boundary falls inside a
  // header, inside a body and between the frames.
  list.each(sizes_up_to(bit_array.byte_size(bytes)), fn(size) {
    assert frame_reader.read(
        have: <<>>,
        count: 2,
        next: queue(cut(bytes, size)),
      )
      == Ok([first(), second()])
      as { "reads of " <> int.to_string(size) <> " bytes" }
  })
}

pub fn bytes_already_read_count_toward_the_frames_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame_reader.read(
      have: encoded(first()),
      count: 2,
      next: queue([encoded(second())]),
    )
    == Ok([first(), second()])
    as "the bytes read before the call are the start of the frames"
}

pub fn a_connection_that_goes_quiet_before_the_count_is_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame_reader.read(
      have: <<>>,
      count: 2,
      next: queue([encoded(first())]),
    )
    == Error(Nil)
    as "one frame is not two: the wait ends when nothing more arrives"
}
