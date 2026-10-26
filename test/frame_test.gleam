//// The frame on the wire. Every header value is the client's: a 32-bit length
//// then a 16-bit id, both little-endian (WriteBits 0x140336380 writes the
//// widths 0x20 and 0x10 least significant bit first, so byte-aligned fields
//// land as little-endian bytes), the length counting the whole frame
//// (WriteMessageFrame 0x1403355e0), at most 131070 bytes (MessageSizeLimit
//// 0x140335ec0). The client's own frame for message 0x7E0 is
//// `06 00 00 00 e0 07` (fact file, opcode.0x7e0) and for the 0x244 wrapper
//// header `0c 00 00 00 44 02` (vector.opcode.0x7e0.frame).

import genesis_prime/connection/frame.{Frame}
import gleam/bit_array
import gleam/int
import owned_test
import seeded
import unitest

fn encoded(message_id: Int, body: BitArray) -> BitArray {
  let assert Ok(bytes) = frame.encode(message_id:, body:)
    as "the frame is within the size limit"
  bytes
}

pub fn a_frame_with_no_body_is_the_clients_six_header_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.encode(message_id: 0x7E0, body: <<>>)
    == Ok(<<0x06, 0x00, 0x00, 0x00, 0xE0, 0x07>>)
    as "opcode.0x7e0: the frame is only the header 06 00 00 00 e0 07, length 6 counting itself"
}

pub fn a_frames_length_counts_its_whole_frame_and_the_id_is_little_endian_test() -> Nil {
  use <- owned_test.run(5000)
  assert encoded(0x0244, <<0, 1, 2, 3, 4, 5>>)
    == <<0x0C, 0x00, 0x00, 0x00, 0x44, 0x02, 0, 1, 2, 3, 4, 5>>
    as "vector.opcode.0x7e0.frame: id 0x244 then length 12 is 0c 00 00 00 44 02; 6 header bytes + 6 body bytes"
  let header = bit_array.slice(encoded(0x0102, zeroes(250)), 0, 6)
  assert header == Ok(<<0x00, 0x01, 0x00, 0x00, 0x02, 0x01>>)
    as "WriteBits 0x140336380: a 250-byte body makes length 256 = 00 01 00 00, and id 0x0102 lands as 02 01"
}

pub fn a_frame_decodes_to_the_message_it_was_encoded_from_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.decode(encoded(0x07E0, <<>>))
    == Ok(#([Frame(0x07E0, <<>>)], <<>>))
    as "0x140331990 reads the 32-bit length, then the 16-bit id, then the body"
  assert frame.decode(<<0x0C, 0, 0, 0, 0x44, 0x02, 9, 8, 7, 6, 5, 4>>)
    == Ok(#([Frame(0x0244, <<9, 8, 7, 6, 5, 4>>)], <<>>))
    as "vector.opcode.0x7e0.frame: a length of 12 and id 0x244 hold 6 body bytes"
}

pub fn encoding_then_decoding_gives_every_frame_back_test() -> Nil {
  use <- owned_test.run(20_000)
  let largest_body = frame.size_limit - frame.header_size
  let checked =
    int.range(from: 1, to: 201, with: #(1, 0), run: fn(state, _case) {
      let #(random, checked) = state
      let #(id, random) = seeded.up_to(random, 0xFFFF)
      let #(length, random) = seeded.up_to(random, largest_body)
      let #(body, random) = seeded.bytes(random, length)
      assert frame.decode(encoded(id, body)) == Ok(#([Frame(id, body)], <<>>))
        as "a frame of id and body round-trips (0x1403355e0 writes it, 0x140331990 reads it)"
      #(random, checked + 1)
    })
  assert checked.1 == 200 as "every generated frame was checked"
}

pub fn one_read_holding_several_frames_gives_all_of_them_test() -> Nil {
  use <- owned_test.run(5000)
  let received =
    bit_array.concat([
      encoded(0x0003, <<1, 2, 3>>),
      encoded(0x07E0, <<>>),
      encoded(0x0244, <<9>>),
    ])
  assert frame.decode(received)
    == Ok(
      #(
        [Frame(0x0003, <<1, 2, 3>>), Frame(0x07E0, <<>>), Frame(0x0244, <<9>>)],
        <<>>,
      ),
    )
    as "ReadConnectionMessages 0x1403321a0: one read may hold several frames, each read in turn"
}

pub fn a_frame_split_across_reads_waits_for_its_end_test() -> Nil {
  use <- owned_test.run(5000)
  let whole = encoded(0x0244, <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>)
  let size = bit_array.byte_size(whole)
  int.range(from: 0, to: size, with: Nil, run: fn(_, cut) {
    let assert Ok(first) = bit_array.slice(whole, 0, cut)
      as "the cut is inside the frame"
    let assert Ok(second) = bit_array.slice(whole, cut, size - cut)
      as "the cut is inside the frame"
    assert frame.decode(first) == Ok(#([], first))
      as "0x1403321a0 stops and waits while fewer bytes than the length have arrived"
    assert frame.decode(bit_array.append(first, second))
      == Ok(#([Frame(0x0244, <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>)], <<>>))
      as "0x1403321a0 reads the frame once its last byte has arrived"
  })
}

pub fn a_whole_frame_then_the_start_of_the_next_gives_the_first_and_keeps_the_rest_test() -> Nil {
  use <- owned_test.run(5000)
  let second = encoded(0x07E0, <<4, 5>>)
  let assert Ok(start) = bit_array.slice(second, 0, 5)
    as "the second frame is longer than 5 bytes"
  assert frame.decode(bit_array.append(encoded(0x0003, <<1>>), start))
    == Ok(#([Frame(0x0003, <<1>>)], start))
    as "0x1403321a0 reads each frame whose bytes have all arrived and waits on the next"
  assert frame.decode(<<>>) == Ok(#([], <<>>))
    as "0x1403321a0 reads nothing when nothing has arrived"
}

pub fn a_length_below_the_six_header_bytes_is_an_error_as_soon_as_it_arrives_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.decode(<<5, 0, 0, 0, 0, 0>>) == Error(frame.LengthBelowHeader(5))
    as "0x140331620: a frame length under 6 is refused (cmp *buffer, 6 -> error 5)"
  assert frame.decode(<<0, 0, 0, 0>>) == Error(frame.LengthBelowHeader(0))
    as "0x140331620: a length of 0 is under 6; its 4 bytes are enough to refuse it"
}

pub fn a_length_over_131070_is_an_error_without_waiting_for_its_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.decode(<<0xFF, 0xFF, 0x01, 0x00>>)
    == Error(frame.LengthOverLimit(131_071))
    as "MessageSizeLimit 0x140335ec0: 131070 (0x1FFFE) is the most, so 131071 is over"
  assert frame.decode(<<0xFF, 0xFF, 0xFF, 0xFF, 0, 0>>)
    == Error(frame.LengthOverLimit(0xFFFFFFFF))
    as "MessageSizeLimit 0x140335ec0: a claimed length of 4 GiB is over the limit"
}

pub fn a_frame_of_exactly_131070_bytes_is_read_test() -> Nil {
  use <- owned_test.run(5000)
  let body = zeroes(131_070 - frame.header_size)
  let whole = encoded(0x0244, body)
  assert bit_array.byte_size(whole) == 131_070
    as "WriteMessageFrame 0x1403355e0: the frame's length counts its header"
  assert frame.decode(whole) == Ok(#([Frame(0x0244, body)], <<>>))
    as "MessageSizeLimit 0x140335ec0: 131070 bytes are within the limit"
  let assert Ok(missing_last_byte) = bit_array.slice(whole, 0, 131_069)
    as "the frame is 131070 bytes"
  assert frame.decode(missing_last_byte) == Ok(#([], missing_last_byte))
    as "0x1403321a0 waits while one byte of a frame within the limit is missing"
}

pub fn a_frame_that_would_be_over_131070_bytes_is_not_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.encode(0x0244, zeroes(131_071 - frame.header_size))
    == Error(frame.LengthOverLimit(131_071))
    as "WriteMessageFrame 0x1403355e0 logs a frame over the message's size limit and does not write it"
}

pub fn a_message_id_that_does_not_fit_16_bits_is_not_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.encode(0x10000, <<>>)
    == Error(frame.MessageIdOutOfRange(0x10000))
    as "WriteMessageFrame 0x1403355e0 writes the id with width 0x10"
  assert frame.encode(-1, <<>>) == Error(frame.MessageIdOutOfRange(-1))
    as "WriteMessageFrame 0x1403355e0 writes the id as an unsigned 16-bit value"
}

pub fn a_frame_held_whole_must_have_its_header_and_its_length_test() -> Nil {
  use <- owned_test.run(5000)
  assert frame.parse(<<6, 0, 0, 0, 0xE0>>) == Error(frame.ShorterThanHeader(5))
    as "0x140331620 reads the 32-bit length then the 16-bit id, 6 bytes"
  assert frame.parse(<<6, 0, 0, 0, 0xE0, 0x07>>) == Ok(Frame(0x07E0, <<>>))
    as "opcode.0x7e0: 06 00 00 00 e0 07 is message 0x7e0 with no body"
  assert frame.parse(<<8, 0, 0, 0, 0xE0, 0x07, 1>>)
    == Error(frame.LengthDisagrees(8, 7))
    as "0x140331620 builds its stream over exactly the length the frame names"
  assert frame.parse(<<5, 0, 0, 0, 0xE0, 0x07>>)
    == Error(frame.LengthBelowHeader(5))
    as "0x140331620: a length under 6 is refused"
}

fn zeroes(length: Int) -> BitArray {
  <<0:size({ length * 8 })>>
}
