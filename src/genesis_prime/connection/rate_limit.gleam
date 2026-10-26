//// How fast one connection may send frames: a token bucket. Each frame takes
//// one token, tokens come back at a steady rate up to a burst, and a frame
//// that finds the bucket empty is over the limit. A fixed window is not used,
//// because it lets twice the rate through at a window's edge.
////
//// A bucket holds thousandths of a token, so refilling by whole milliseconds
//// is exact integer arithmetic: a rate of `n` frames a second gives `n`
//// thousandths a millisecond. Time is an input, never read here.

import gleam/int

/// The most frames a connection may send: `frames_per_second` on average, and
/// at most `burst` at once.
pub type Rate {
  Rate(frames_per_second: Int, burst: Int)
}

/// Why a frame is refused: the bucket of this rate had no token left.
pub type RateExceeded {
  RateExceeded(rate: Rate)
}

/// The margin over the client's fastest legitimate sending that the rate
/// allows, 4, the margin the heap ceilings use.
pub const margin = 4

/// The most frames a second a client sends while it dashes: one movement
/// frame (message 0x637) per game update (`opcode.0x637`, 0x1403a25c0), and
/// the client runs at most `video.framerateMax` game updates a second
/// (0x1400094f0), a setting of 15 to 180 with every set clamped to it, 120 by
/// default (0x140c3fea0). With vertical sync on the client sets no limit of
/// its own (0x140c3b1c0, 0x1400094f0).
const fastest_frames_per_second = 180

/// The rate of a legitimate client with the margin applied: 4 times the
/// fastest sending, and a burst of one second of it, the most a delayed
/// network can deliver together, since the client caps the time of a frame at
/// one second (0x1400097d0).
pub fn client_rate() -> Rate {
  let frames_per_second = fastest_frames_per_second * margin
  Rate(frames_per_second:, burst: frames_per_second)
}

const thousandths_per_token = 1000

/// A connection's tokens, in thousandths, and the time they were last counted.
pub opaque type Bucket {
  Bucket(rate: Rate, thousandths: Int, counted_at: Int)
}

/// A full bucket of this rate at the given time, in milliseconds.
pub fn new(rate rate: Rate, now_milliseconds now_milliseconds: Int) -> Bucket {
  Bucket(
    rate:,
    thousandths: rate.burst * thousandths_per_token,
    counted_at: now_milliseconds,
  )
}

/// Takes one token for a frame arriving at `now_milliseconds`, after the
/// tokens that came back since the last time. A bucket with less than a whole
/// token refuses the frame and the connection ends. A time before the last
/// count brings no tokens back.
pub fn take(
  bucket bucket: Bucket,
  now_milliseconds now_milliseconds: Int,
) -> Result(Bucket, RateExceeded) {
  let elapsed = int.max(now_milliseconds - bucket.counted_at, 0)
  let thousandths =
    int.min(
      bucket.thousandths + elapsed * bucket.rate.frames_per_second,
      bucket.rate.burst * thousandths_per_token,
    )
  case thousandths >= thousandths_per_token {
    True ->
      Ok(
        Bucket(
          ..bucket,
          thousandths: thousandths - thousandths_per_token,
          counted_at: int.max(now_milliseconds, bucket.counted_at),
        ),
      )
    False -> Error(RateExceeded(rate: bucket.rate))
  }
}
