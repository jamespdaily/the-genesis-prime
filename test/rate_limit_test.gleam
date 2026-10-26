//// The rate limit of a connection, a token bucket. The expected values come
//// from the rule of a token bucket (a bucket of `burst` tokens that refills
//// at `frames_per_second`, one token a frame) and from the client's own
//// sending rates in the fact file: the movement send interval of
//// `0x140c3a004` is 125 ms until server message `0xf1` sets it, and `0xf1`
//// keeps it between 25 and 1000 ms (`opcode.0xf1`, `opcode.0x637`). A dash
//// sends one movement frame per game update, and the client's frame limiter
//// runs at most `video.framerateMax` updates a second, a setting of 15 to 180
//// that defaults to 120.

import genesis_prime/connection/rate_limit.{Rate}
import gleam/int
import gleam/list
import owned_test

/// A monotonic time that is negative, as the runtime's can be.
const start = -9_000_000

/// Takes `count` tokens in a row at one instant; the bucket after them, or the
/// number that were taken before one was refused.
fn take_at_once(
  bucket: rate_limit.Bucket,
  now: Int,
  count: Int,
) -> Result(rate_limit.Bucket, Int) {
  numbers(1, count)
  |> list.try_fold(bucket, fn(bucket, taken) {
    case rate_limit.take(bucket:, now_milliseconds: now) {
      Ok(bucket) -> Ok(bucket)
      Error(_) -> Error(taken - 1)
    }
  })
}

pub fn a_full_bucket_lets_a_burst_through_and_refuses_the_frame_after_it_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 5)
  let bucket = rate_limit.new(rate:, now_milliseconds: start)
  assert case take_at_once(bucket, start, 5) {
    Ok(_) -> True
    Error(_) -> False
  }
    as "token bucket: a full bucket holds `burst` tokens, so `burst` frames at one instant all pass"
  assert case take_at_once(bucket, start, 6) {
      Ok(_) -> -1
      Error(taken) -> taken
    }
    == 5
    as "token bucket: the frame one over the burst finds the bucket empty and is refused"
}

pub fn a_refused_frame_names_the_rate_it_broke_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 1)
  let bucket = rate_limit.new(rate:, now_milliseconds: start)
  let assert Ok(emptied) = rate_limit.take(bucket:, now_milliseconds: start)
  assert case rate_limit.take(bucket: emptied, now_milliseconds: start) {
      Ok(_) -> Ok(Nil)
      Error(rate_limit.RateExceeded(rate: broken)) -> Error(broken)
    }
    == Error(rate)
    as "the error carries the rate that was broken, for the log"
}

pub fn tokens_come_back_at_the_rate_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 3)
  let assert Ok(emptied) =
    rate_limit.new(rate:, now_milliseconds: start)
    |> take_at_once(start, 3)
  assert case rate_limit.take(bucket: emptied, now_milliseconds: start + 99) {
      Ok(_) -> True
      Error(_) -> False
    }
    == False
    as "token bucket: 10 frames a second is 1 token per 100 ms, so after 99 ms the bucket is still empty"
  assert case rate_limit.take(bucket: emptied, now_milliseconds: start + 100) {
    Ok(_) -> True
    Error(_) -> False
  }
    as "token bucket: after 100 ms one token is back"
}

pub fn a_bucket_never_holds_more_than_its_burst_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 3)
  let bucket = rate_limit.new(rate:, now_milliseconds: start)
  assert case take_at_once(bucket, start + 60_000, 4) {
      Ok(_) -> -1
      Error(taken) -> taken
    }
    == 3
    as "token bucket: a minute of idling fills the bucket to its burst and no further"
}

pub fn the_doubled_rate_at_a_windows_edge_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 10)
  let bucket = rate_limit.new(rate:, now_milliseconds: start)
  let assert Ok(after_first_second) = take_at_once(bucket, start + 999, 10)
  assert case take_at_once(after_first_second, start + 1001, 10) {
      Ok(_) -> -1
      Error(taken) -> taken
    }
    == 0
    as "the bucket, unlike a fixed window, refunds 2 ms of tokens at a window's edge, not a whole window's, so the next 10 are refused"
}

pub fn a_time_before_the_last_count_takes_no_tokens_back_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 10, burst: 2)
  let assert Ok(emptied) =
    rate_limit.new(rate:, now_milliseconds: start)
    |> take_at_once(start, 2)
  assert case rate_limit.take(bucket: emptied, now_milliseconds: start - 500) {
      Ok(_) -> True
      Error(_) -> False
    }
    == False
    as "the monotonic clock never runs back, so an earlier time refills nothing and a bucket can never gain tokens from it"
}

pub fn sending_at_exactly_the_rate_for_ten_seconds_is_never_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rate = Rate(frames_per_second: 40, burst: 1)
  let bucket = rate_limit.new(rate:, now_milliseconds: start)
  // 25 ms is the shortest movement send interval (opcode.0xf1: values below
  // 25 become 25), so 40 frames a second, for 10 s.
  let outcome =
    numbers(0, 399)
    |> list.try_fold(bucket, fn(bucket, frame_number) {
      rate_limit.take(bucket:, now_milliseconds: start + frame_number * 25)
    })
  assert case outcome {
    Ok(_) -> True
    Error(_) -> False
  }
    as "a sender that keeps to the rate exactly is never refused"
}

pub fn the_clients_rate_is_the_margin_times_its_fastest_sending_test() -> Nil {
  use <- owned_test.run(5000)
  assert rate_limit.margin == 4
    as "the margin of the heap ceilings, four times (the heap-ceiling rule, `heap_limit.for_peak`)"
  assert rate_limit.client_rate() == Rate(frames_per_second: 720, burst: 720)
    as "the client's setting video.framerateMax is at most 180 (default 120) and a dash sends one movement frame per game update, so 180 a second, times the margin 4; the burst is a second of that, the most a delayed network can deliver at once, since the client caps a frame's time at one second"
}

/// The whole numbers from `first` to `last`, both included.
fn numbers(first: Int, last: Int) -> List(Int) {
  int.range(from: first, to: last + 1, with: [], run: list.prepend)
  |> list.reverse
}
