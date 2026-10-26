//// How fast one connection may send frames: a token bucket. Each frame takes
//// one token, tokens come back at a steady rate up to a burst, and a frame
//// that finds the bucket empty is over the limit. A fixed window is not used,
//// because it lets twice the rate through at a window's edge.
////
//// A bucket holds thousandths of a token, so refilling by whole milliseconds
//// is exact integer arithmetic: a rate of `n` frames a second gives `n`
//// thousandths a millisecond. Time is an input, never read here.

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

/// The rate of a legitimate client with the margin applied.
pub fn client_rate() -> Rate {
  todo as "the client's fastest legitimate sending, times the margin"
}

/// A connection's tokens and the time they were last counted.
pub opaque type Bucket {
  Bucket(rate: Rate, thousandths: Int, counted_at: Int)
}

/// A full bucket of this rate at the given time, in milliseconds.
pub fn new(rate rate: Rate, now_milliseconds now_milliseconds: Int) -> Bucket {
  todo as "a full bucket"
}

/// Takes one token for a frame arriving at `now_milliseconds`, after the
/// tokens that came back since the last time. A bucket with less than a whole
/// token refuses the frame and the connection ends.
pub fn take(
  bucket bucket: Bucket,
  now_milliseconds now_milliseconds: Int,
) -> Result(Bucket, RateExceeded) {
  todo as "refill, then take one token"
}
