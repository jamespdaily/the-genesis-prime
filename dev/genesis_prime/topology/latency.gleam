//// A histogram of delays in microseconds with fixed log-scale buckets, small
//// enough for every player to keep one and cheap to merge into one for the
//// run. Pure.

import gleam/dict.{type Dict}

/// Counts of delays, by bucket. The buckets are fixed, so histograms from
/// different players merge by adding their counts. The largest delay seen is
/// kept exactly.
pub opaque type Histogram {
  Histogram(buckets: Dict(Int, Int), count: Int, maximum: Int)
}

/// A histogram with no delays in it.
pub fn new() -> Histogram {
  todo as "body in the build commit"
}

/// Adds one delay, in microseconds. A negative delay counts as 0.
pub fn record(histogram: Histogram, microseconds: Int) -> Histogram {
  todo as "body in the build commit"
}

/// One histogram holding the delays of both.
pub fn merge(a: Histogram, b: Histogram) -> Histogram {
  todo as "body in the build commit"
}

/// The delay in microseconds that `percent` percent of the recorded delays are
/// at or under, as the top of the bucket that holds it. 50.0 is the median and
/// 99.0 the 99th percentile. An empty histogram gives 0.
pub fn percentile(histogram: Histogram, percent: Float) -> Int {
  todo as "body in the build commit"
}

/// The largest delay recorded, exactly, in microseconds. An empty histogram
/// gives 0.
pub fn maximum(histogram: Histogram) -> Int {
  todo as "body in the build commit"
}

/// How many delays are recorded.
pub fn count(histogram: Histogram) -> Int {
  todo as "body in the build commit"
}
