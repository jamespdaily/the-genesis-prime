//// The map's message queue as the load runs read it (`load_moves_ffi`
//// samples it in the server's node): which second of a run held the longest queue, and
//// what the messages waiting in one mailbox were. Pure: a test plants the samples.
////
//// ```
//// the probe's Probe ─▶ summary, lines ─▶ what a run prints of the map's queue
//// (ms, queue) every 10 ms ─▶ by_second ─▶ the longest queue of each second ─▶ peak
//// the names of a mailbox's messages ─▶ kinds ─▶ each name and its count, the most first
//// (ms, reductions) every 10 ms ─▶ reductions_between ─▶ what the map spent in a window
//// ```
////
//// - A second is the sample's millisecond divided by 1,000, the run's first sample at 0.
//// - The reductions of a window are the last sample at or before its end less the first at
////   or after its start.
//// - The kind of a message is the name of its variant, which the probe reads from the
////   first element of its tuple (`load_moves_ffi`).

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string

/// What the probe read of the map in the server's node (`load_moves_ffi`): the longest
/// queue, the sum of each sample's queue, the samples, how many of them found the map
/// running, each sample's time (ms since the probe started) and queue, the mailboxes
/// taken, the map's memory in bytes when its queue was longest and each sample's time and
/// the reductions the maps had spent by then.
pub type Probe {
  Probe(
    longest: Int,
    sum: Int,
    samples: Int,
    running: Int,
    series: List(#(Int, Int)),
    taken: List(Taken),
    peak_memory_bytes: Int,
    reductions_series: List(#(Int, Int)),
  )
}

/// The names of the messages waiting in the map at `at_ms`, when its queue was `queue`.
pub type Taken {
  Taken(at_ms: Int, queue: Int, names: List(String))
}

/// The longest queue found in one second of a run.
pub type Second {
  Second(second: Int, longest: Int)
}

/// The longest queue of each second that holds a sample, the first second first.
pub fn by_second(series series: List(#(Int, Int))) -> List(Second) {
  list.fold(series, dict.new(), fn(seconds, sample) {
    dict.upsert(seconds, sample.0 / 1000, fn(found) {
      int.max(option.unwrap(found, 0), sample.1)
    })
  })
  |> dict.to_list
  |> list.sort(fn(one, other) { int.compare(one.0, other.0) })
  |> list.map(fn(second) { Second(second: second.0, longest: second.1) })
}

/// The second with the longest queue, the earlier of two with the same, or `Error(Nil)`
/// for a run that took no sample.
pub fn peak(series series: List(#(Int, Int))) -> Result(Second, Nil) {
  list.fold(by_second(series:), Error(Nil), fn(peak, second) {
    case peak {
      Ok(Second(longest:, ..)) if longest >= second.longest -> peak
      Ok(_) | Error(Nil) -> Ok(second)
    }
  })
}

/// How many messages of each name, the most first, those with the same count in
/// alphabetical order.
pub fn kinds(names names: List(String)) -> List(#(String, Int)) {
  list.fold(names, dict.new(), fn(counts, name) {
    dict.upsert(counts, name, fn(found) { option.unwrap(found, 0) + 1 })
  })
  |> dict.to_list
  |> list.sort(fn(one, other) {
    case int.compare(other.1, one.1) {
      order.Eq -> string.compare(one.0, other.0)
      by_count -> by_count
    }
  })
}

/// A mean of `total` over `count`, to one decimal, or a dash for none.
pub fn per(total total: Int, count count: Int) -> String {
  case count {
    0 -> "-"
    _ ->
      float.to_string(float.to_precision(
        int.to_float(total) /. int.to_float(count),
        1,
      ))
  }
}

/// `part` of `whole` as a percentage to one decimal, or a dash for no whole.
pub fn percent(part part: Int, whole whole: Int) -> String {
  case whole {
    0 -> "-"
    _ ->
      float.to_string(float.to_precision(
        100.0 *. int.to_float(part) /. int.to_float(whole),
        1,
      ))
      <> "%"
  }
}

/// The map's queue over a step in one line: the longest, the mean over the samples and the
/// share of the samples that found the map running.
pub fn summary(probe probe: Probe) -> String {
  "the map's message queue: longest "
  <> int.to_string(probe.longest)
  <> ", mean "
  <> per(total: probe.sum, count: probe.samples)
  <> " over "
  <> int.to_string(probe.samples)
  <> " samples, one every 10 ms; its process was found running in "
  <> percent(part: probe.running, whole: probe.samples)
  <> " of them"
}

/// The reductions the maps spent from `from_ms` to `to_ms` (ms since the probe started): the
/// last sample at or before `to_ms` less the first at or after `from_ms`, or `Error(Nil)`
/// when the window holds no two samples.
pub fn reductions_between(
  probe probe: Probe,
  from_ms from_ms: Int,
  to_ms to_ms: Int,
) -> Result(Int, Nil) {
  let first =
    list.find(probe.reductions_series, fn(sample) { sample.0 >= from_ms })
  let last =
    list.find(list.reverse(probe.reductions_series), fn(sample) {
      sample.0 <= to_ms
    })
  case first, last {
    Ok(first), Ok(last) if last.0 > first.0 -> Ok(last.1 - first.1)
    _, _ -> Error(Nil)
  }
}

/// What a run prints of the map's queue: the longest queue of each second, the step's
/// `marks` (a name and its millisecond since the probe started), the peak, what the
/// mailboxes taken held, and the map's memory when its queue was longest.
pub fn lines(
  probe probe: Probe,
  marks marks: List(#(String, Int)),
) -> List(String) {
  list.flatten([
    [
      "the map's longest queue in each second (second: queue): "
        <> string.join(
        list.map(by_second(series: probe.series), fn(second) {
          int.to_string(second.second) <> ": " <> int.to_string(second.longest)
        }),
        ", ",
      ),
      "marks of the step, in seconds from the probe's start: "
        <> string.join(
        list.map(marks, fn(mark) {
          mark.0 <> " " <> int.to_string(mark.1 / 1000)
        }),
        ", ",
      ),
      case peak(series: probe.series) {
        Ok(Second(second:, longest:)) ->
          "the map's queue peaked in second "
          <> int.to_string(second)
          <> " at "
          <> int.to_string(longest)
        Error(Nil) -> "the map's queue was never sampled"
      },
    ],
    case probe.taken {
      [] -> [
        "no mailbox was taken: the queue never passed 1,000 (at most 6 are taken in a run, 500 ms apart)",
      ]
      taken ->
        list.prepend(
          list.map(taken, fn(one) {
            "the map's mailbox at "
            <> int.to_string(one.at_ms)
            <> " ms, "
            <> int.to_string(one.queue)
            <> " messages: "
            <> string.join(
              list.map(kinds(names: one.names), fn(kind) {
                kind.0 <> " " <> int.to_string(kind.1)
              }),
              ", ",
            )
          }),
          int.to_string(list.length(taken))
            <> " mailboxes were taken (at most 6 in a run, 500 ms apart, each when the queue passed 1,000):",
        )
    },
    [
      "the map's memory when its queue was longest: "
      <> int.to_string(probe.peak_memory_bytes)
      <> " bytes",
    ],
  ])
}
