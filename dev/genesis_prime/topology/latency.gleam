//// A histogram of delays in microseconds with fixed log-scale buckets, small
//// enough for every player to keep one and cheap to merge into one for the
//// run. Pure.

import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result

/// Counts of delays, by bucket. The buckets are fixed, so histograms from
/// different players merge by adding their counts. The largest delay seen is
/// kept exactly.
pub opaque type Histogram {
  Histogram(buckets: Dict(Int, Int), count: Int, maximum: Int)
}

/// A histogram with no delays in it.
pub fn new() -> Histogram {
  Histogram(buckets: dict.new(), count: 0, maximum: 0)
}

/// Adds one delay, in microseconds. A negative delay counts as 0.
pub fn record(
  histogram histogram: Histogram,
  microseconds microseconds: Int,
) -> Histogram {
  let microseconds = int.max(0, microseconds)
  Histogram(
    buckets: dict.upsert(histogram.buckets, bucket_top(microseconds), fn(count) {
      option.unwrap(count, 0) + 1
    }),
    count: histogram.count + 1,
    maximum: int.max(histogram.maximum, microseconds),
  )
}

/// One histogram holding the delays of both.
pub fn merge(a a: Histogram, b b: Histogram) -> Histogram {
  Histogram(
    buckets: dict.fold(b.buckets, a.buckets, fn(buckets, top, count) {
      dict.upsert(buckets, top, fn(existing) {
        option.unwrap(existing, 0) + count
      })
    }),
    count: a.count + b.count,
    maximum: int.max(a.maximum, b.maximum),
  )
}

/// The delay in microseconds that `percent` percent of the recorded delays are
/// at or under, as the top of the bucket that holds it. 50.0 is the median and
/// 99.0 the 99th percentile. An empty histogram gives 0.
pub fn percentile(
  histogram histogram: Histogram,
  percent percent: Float,
) -> Int {
  let wanted =
    int.max(
      1,
      float.ceiling(percent /. 100.0 *. int.to_float(histogram.count))
        |> float.truncate,
    )
  let tops = dict.keys(histogram.buckets) |> list.sort(int.compare)
  top_holding(buckets: histogram.buckets, tops:, wanted:, counted: 0)
}

/// The largest delay recorded, exactly, in microseconds. An empty histogram
/// gives 0.
pub fn maximum(histogram: Histogram) -> Int {
  histogram.maximum
}

/// How many delays are recorded.
pub fn count(histogram: Histogram) -> Int {
  histogram.count
}

/// How many delays are kept apart exactly, at the bottom of the scale; above
/// this every bucket is as wide as 1/8 of its power of two.
const exact_below = 16

/// The largest value of the bucket that holds `microseconds`. Values below 16
/// have a bucket each; above that a bucket spans 1/8 of a power of two.
fn bucket_top(microseconds: Int) -> Int {
  use <- bool.guard(microseconds < exact_below, microseconds)
  let shift = shift_into_scale(microseconds, 0)
  let next_bucket_start =
    int.bitwise_shift_left(
      int.bitwise_shift_right(microseconds, shift) + 1,
      shift,
    )
  next_bucket_start - 1
}

/// The smallest shift that brings a value below 16.
fn shift_into_scale(value: Int, shift: Int) -> Int {
  use <- bool.guard(int.bitwise_shift_right(value, shift) < exact_below, shift)
  shift_into_scale(value, shift + 1)
}

/// The top of the bucket in which the `wanted`th smallest delay falls, given
/// the bucket tops in ascending order and the delays counted so far.
fn top_holding(
  buckets buckets: Dict(Int, Int),
  tops tops: List(Int),
  wanted wanted: Int,
  counted counted: Int,
) -> Int {
  case tops {
    [] -> 0
    [top, ..rest] -> {
      let counted = counted + result.unwrap(dict.get(buckets, top), 0)
      use <- bool.guard(counted >= wanted, top)
      top_holding(buckets:, tops: rest, wanted:, counted:)
    }
  }
}
