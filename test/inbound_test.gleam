//// What a connection does with the bytes it reads: the rule of the socket
//// owner. The expected values come from the client's framing (a 32-bit
//// little-endian length counting the whole frame, a 16-bit id, at most 131,070
//// bytes: `frame.size_limit`, MessageSizeLimit 0x140335ec0) and from the token
//// bucket's rule (`rate_limit`).

import genesis_prime/connection/frame.{Frame}
import genesis_prime/connection/inbound.{BadFrame, Deliver, End, TooFast}
import genesis_prime/connection/rate_limit.{Rate}
import gleam/bit_array
import gleam/list
import gleam/string
import owned_test

const start = -5000

/// A rate that never refuses what these tests send, except where a test says.
const plenty = Rate(frames_per_second: 1000, burst: 1000)

fn encoded(message_id: Int, size: Int) -> BitArray {
  let assert Ok(bytes) =
    frame.encode(
      message_id:,
      body: bit_array.from_string(string.repeat("a", size)),
    )
    as "the frame is within the size limit"
  bytes
}

pub fn frames_in_one_read_are_delivered_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let state = inbound.new(rate: plenty, now_milliseconds: start)
  let read = bit_array.concat([encoded(0x0244, 3), encoded(0x0637, 0)])
  let #(_, effects) =
    inbound.receive(inbound: state, received: read, now_milliseconds: start)
  assert effects
    == [
      Deliver(Frame(0x0244, <<"aaa":utf8>>)),
      Deliver(Frame(0x0637, <<>>)),
    ]
    as "frame.decode: one read may hold several frames (ReadConnectionMessages 0x1403321a0), handed on in the order they arrived"
}

pub fn a_frame_split_across_reads_is_delivered_when_it_is_whole_test() -> Nil {
  use <- owned_test.run(5000)
  let state = inbound.new(rate: plenty, now_milliseconds: start)
  let whole = encoded(0x0244, 10)
  let assert Ok(first) = bit_array.slice(whole, 0, 7)
  let assert Ok(second) = bit_array.slice(whole, 7, 9)
  let #(state, effects) =
    inbound.receive(inbound: state, received: first, now_milliseconds: start)
  assert effects == []
    as "frame.decode: a frame whose end has not arrived is held, and nothing is handed on"
  let #(_, effects) =
    inbound.receive(inbound: state, received: second, now_milliseconds: start)
  assert effects == [Deliver(Frame(0x0244, <<"aaaaaaaaaa":utf8>>))]
    as "the bytes that arrive later complete the held start into the frame"
}

pub fn a_frame_at_the_size_limit_is_delivered_test() -> Nil {
  use <- owned_test.run(5000)
  let state = inbound.new(rate: plenty, now_milliseconds: start)
  let largest = encoded(0x0244, frame.size_limit - frame.header_size)
  assert bit_array.byte_size(largest) == 131_070
    as "MessageSizeLimit 0x140335ec0: the largest frame is 131,070 bytes"
  let #(_, effects) =
    inbound.receive(inbound: state, received: largest, now_milliseconds: start)
  assert list.length(effects) == 1
  assert case effects {
    [Deliver(Frame(0x0244, body))] -> bit_array.byte_size(body) == 131_064
    _ -> False
  }
    as "a frame of exactly 131,070 bytes is within the client's size limit"
}

pub fn a_frame_one_byte_over_the_size_limit_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let state = inbound.new(rate: plenty, now_milliseconds: start)
  // Only the 4 bytes of the length arrive: a huge claimed length is refused
  // at once and never waited for.
  let #(_, effects) =
    inbound.receive(
      inbound: state,
      received: <<131_071:size(32)-little>>,
      now_milliseconds: start,
    )
  assert effects == [End(BadFrame(frame.LengthOverLimit(131_071)))]
    as "MessageSizeLimit 0x140335ec0: 131,070 is the most, so 131,071 ends the connection as soon as its length has arrived"
}

pub fn a_length_below_the_header_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let state = inbound.new(rate: plenty, now_milliseconds: start)
  let #(_, effects) =
    inbound.receive(
      inbound: state,
      received: <<5:size(32)-little, 0, 0>>,
      now_milliseconds: start,
    )
  assert effects == [End(BadFrame(frame.LengthBelowHeader(5)))]
    as "ParseWrappedMessage 0x140331620 refuses a length under 6"
}

pub fn the_frames_before_a_bad_frame_are_still_delivered_test() -> Nil {
  use <- owned_test.run(5000)
  let state = inbound.new(rate: plenty, now_milliseconds: start)
  let read =
    bit_array.concat([
      encoded(0x0244, 1),
      encoded(0x0637, 2),
      <<131_071:size(32)-little>>,
    ])
  let #(_, effects) =
    inbound.receive(inbound: state, received: read, now_milliseconds: start)
  assert effects
    == [
      Deliver(Frame(0x0244, <<"a":utf8>>)),
      Deliver(Frame(0x0637, <<"aa":utf8>>)),
      End(BadFrame(frame.LengthOverLimit(131_071))),
    ]
    as "frames that arrived whole before the bad length were the client's, so they are handed on, then the connection ends"
}

pub fn a_burst_one_over_the_bucket_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 3)
  let state = inbound.new(rate:, now_milliseconds: start)
  let read =
    bit_array.concat([
      encoded(1, 0),
      encoded(2, 0),
      encoded(3, 0),
      encoded(4, 0),
    ])
  let #(_, effects) =
    inbound.receive(inbound: state, received: read, now_milliseconds: start)
  assert effects
    == [
      Deliver(Frame(1, <<>>)),
      Deliver(Frame(2, <<>>)),
      Deliver(Frame(3, <<>>)),
      End(TooFast(rate_limit.RateExceeded(rate:))),
    ]
    as "token bucket: a burst of 3 passes and the 4th frame, one over, is refused and ends the connection"
}

pub fn the_bucket_carries_over_between_reads_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 2)
  let state = inbound.new(rate:, now_milliseconds: start)
  let #(state, first) =
    inbound.receive(
      inbound: state,
      received: bit_array.concat([encoded(1, 0), encoded(2, 0)]),
      now_milliseconds: start,
    )
  assert list.length(first) == 2
  let #(_, second) =
    inbound.receive(
      inbound: state,
      received: encoded(3, 0),
      now_milliseconds: start + 50,
    )
  assert second == [End(TooFast(rate_limit.RateExceeded(rate:)))]
    as "token bucket: 10 frames a second is 1 token per 100 ms, so 50 ms after the burst there is no token for a third frame"
}

pub fn the_reasons_say_what_was_broken_test() -> Nil {
  use <- owned_test.run(5000)
  assert inbound.describe(BadFrame(frame.LengthOverLimit(131_071)))
    == "frame length 131071 is over the limit of 131070 bytes"
    as "the log line of a decode failure names the length and the limit (MessageSizeLimit 0x140335ec0)"
  assert inbound.describe(BadFrame(frame.LengthBelowHeader(5)))
    == "frame length 5 is below the 6 bytes of its header"
    as "the log line names the length and the header (ParseWrappedMessage 0x140331620)"
  assert inbound.describe(
      TooFast(rate_limit.RateExceeded(Rate(frames_per_second: 160, burst: 16))),
    )
    == "frames came faster than 160 a second with a burst of 16"
    as "the log line of the rate limit names the rate"
}
