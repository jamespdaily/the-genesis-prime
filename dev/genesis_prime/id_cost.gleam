//// What typed ids cost: the work a hot path does with a unit id, run once with
//// a plain `Int` and once with a `UnitId(Int)`, so the cost can be measured
//// again on the real path.
////
//// Run it with `gleam run -m genesis_prime/id_cost` on a machine with nothing
//// else heavy running. It lives in `dev/` because Gleam compiles that directory
//// with the project, so `gleam build` keeps it compiling, while `gleam test`
//// never runs it. It uses only the runtime's own clock and counters.
////
//// Per simulated message a variant reads a unit id from the message bytes,
//// looks the unit up in a dictionary of 10,000 units, updates it and puts the
//// id in front of a list of 49 nearby ids for the reply. A run is 1,000,000
//// messages in a fresh process, timed after the dictionary is built. Each
//// round runs every variant once, the starting variant rotating, after one
//// discarded round. Allocation is measured in separate runs, which trace the
//// process's garbage collections.

import genesis_prime/id_cost/extra_lookup_variant
import genesis_prime/id_cost/measurement.{type TermSizes}
import genesis_prime/id_cost/message_stream
import genesis_prime/id_cost/plain_variant
import genesis_prime/id_cost/typed_variant
import genesis_prime/id_cost/workload.{type Prepared}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

const messages_per_run = 1_000_000

const rounds = 10

const cost_limit_percent = 5.0

const allocation_repeats = 3

type Variant {
  Variant(name: String, prepare: fn() -> Prepared)
}

type Run {
  Run(
    variant: String,
    milliseconds: Float,
    reductions_per_message: Float,
    result: Int,
  )
}

type Allocation {
  Allocation(
    variant: String,
    words_per_message: List(Float),
    units_size: TermSizes,
  )
}

type Summary {
  Summary(
    variant: String,
    milliseconds: List(Float),
    median_milliseconds: Float,
    reductions_per_message: Float,
  )
}

/// Runs the trial and prints the counter check, the raw runs, the tables and
/// what the choosing rule picks.
pub fn main() -> Nil {
  let plain = Variant("A plain Int", plain_variant.prepare)
  let typed = Variant("B UnitId(Int)", typed_variant.prepare)
  let planted = Variant("C plain + extra lookup", extra_lookup_variant.prepare)
  let variants = [plain, typed, planted]
  let stream = message_stream.build(messages_per_run)

  io.println("== Counter check: a list of 100000 elements is 200000 words")
  io.println(
    "words allocated and kept:      "
    <> int.to_string(in_fresh_process(kept_list_words)),
  )
  io.println(
    "words allocated and discarded: "
    <> int.to_string(in_fresh_process(discarded_list_words)),
  )

  io.println("\n== Raw time runs (one discarded round first)")
  list.each(variants, fn(variant) { timed_run(variant, stream) })
  let runs =
    message_stream.indexes(rounds)
    |> list.flat_map(fn(round) {
      list.map(rotate(variants, round), fn(variant) {
        let run = timed_run(variant, stream)
        io.println(
          "round "
          <> int.to_string(round + 1)
          <> "  "
          <> string.pad_end(run.variant, 24, " ")
          <> two_places(run.milliseconds)
          <> " ms  "
          <> two_places(run.reductions_per_message)
          <> " reductions/message  result "
          <> int.to_string(run.result),
        )
        run
      })
    })
  let summaries =
    list.map(variants, fn(variant) {
      summarise(
        variant.name,
        list.filter(runs, fn(run) { run.variant == variant.name }),
      )
    })
  print_time(summaries)

  io.println("\n== Raw allocation runs")
  let allocations =
    list.map(variants, fn(variant) { allocation_runs(variant, stream) })
  print_memory(allocations)
  print_verdict(summaries:, allocations:, runs:)
}

fn rotate(items: List(a), by: Int) -> List(a) {
  let by = by % list.length(items)
  list.append(list.drop(items, by), list.take(items, by))
}

fn timed_run(variant: Variant, stream: BitArray) -> Run {
  let subject = process.new_subject()
  let _pid =
    process.spawn_unlinked(fn() {
      process.send(subject, measure_time(variant, stream))
    })
  let assert Ok(run) = process.receive(subject, 300_000)
    as "a time run did not finish"
  run
}

fn measure_time(variant: Variant, stream: BitArray) -> Run {
  let prepared = variant.prepare()
  measurement.collect()
  let reductions_before = measurement.reductions()
  let started = measurement.monotonic_nanoseconds()
  let result = prepared.run(stream)
  let finished = measurement.monotonic_nanoseconds()
  let reductions_after = measurement.reductions()
  Run(
    variant: variant.name,
    milliseconds: int.to_float(finished - started) /. 1_000_000.0,
    reductions_per_message: int.to_float(reductions_after - reductions_before)
      /. int.to_float(messages_per_run),
    result:,
  )
}

fn allocation_runs(variant: Variant, stream: BitArray) -> Allocation {
  let measured =
    list.map(message_stream.indexes(allocation_repeats), fn(_) {
      in_fresh_process(fn() {
        let prepared = variant.prepare()
        measurement.start_counting_allocation()
        let _result = prepared.run(stream)
        #(
          int.to_float(measurement.stop_counting_allocation())
            /. int.to_float(messages_per_run),
          prepared.units_size,
        )
      })
    })
  let assert [#(_, units_size), ..] = measured as "no allocation runs"
  let words_per_message = list.map(measured, fn(run) { run.0 })
  io.println(
    string.pad_end(variant.name, 24, " ")
    <> string.join(list.map(words_per_message, two_places), "  ")
    <> " words/message",
  )
  Allocation(variant: variant.name, words_per_message:, units_size:)
}

fn in_fresh_process(work: fn() -> a) -> a {
  let subject = process.new_subject()
  let _pid = process.spawn_unlinked(fn() { process.send(subject, work()) })
  let assert Ok(result) = process.receive(subject, 300_000)
    as "an allocation run did not finish"
  result
}

fn kept_list_words() -> Int {
  measurement.start_counting_allocation()
  let kept = list.repeat(0, 100_000)
  let words = measurement.stop_counting_allocation()
  let assert [0, ..] = kept as "the kept list was lost"
  words
}

fn discarded_list_words() -> Int {
  measurement.start_counting_allocation()
  let _length = list.length(list.repeat(0, 100_000))
  measurement.stop_counting_allocation()
}

fn summarise(name: String, runs: List(Run)) -> Summary {
  let milliseconds = list.map(runs, fn(run) { run.milliseconds })
  Summary(
    variant: name,
    milliseconds:,
    median_milliseconds: median(milliseconds),
    reductions_per_message: median(
      list.map(runs, fn(run) { run.reductions_per_message }),
    ),
  )
}

fn print_time(summaries: List(Summary)) -> Nil {
  io.println(
    "\n== Measure 1: time for 1000000 messages, "
    <> int.to_string(rounds)
    <> " runs each",
  )
  list.each(summaries, fn(summary) {
    let sorted = list.sort(summary.milliseconds, float.compare)
    let assert Ok(fastest) = list.first(sorted) as "no runs"
    let assert Ok(slowest) = list.last(sorted) as "no runs"
    io.println(
      string.pad_end(summary.variant, 24, " ")
      <> "median "
      <> two_places(summary.median_milliseconds)
      <> " ms  min "
      <> two_places(fastest)
      <> "  max "
      <> two_places(slowest)
      <> "  range "
      <> two_places(slowest -. fastest)
      <> " ("
      <> two_places(
        { slowest -. fastest } /. summary.median_milliseconds *. 100.0,
      )
      <> "% of median)  standard deviation "
      <> two_places(standard_deviation(summary.milliseconds))
      <> "  "
      <> two_places(summary.reductions_per_message)
      <> " reductions/message",
    )
  })
}

fn print_memory(allocations: List(Allocation)) -> Nil {
  io.println("\n== Measure 2: memory")
  list.each(allocations, fn(allocation) {
    io.println(
      string.pad_end(allocation.variant, 24, " ")
      <> two_places(median(allocation.words_per_message))
      <> " words allocated/message  units dictionary: "
      <> int.to_string(allocation.units_size.heap_words)
      <> " words on the heap, "
      <> int.to_string(allocation.units_size.copied_words)
      <> " words copied, "
      <> int.to_string(allocation.units_size.external_bytes)
      <> " external bytes",
    )
  })
}

fn print_verdict(
  summaries summaries: List(Summary),
  allocations allocations: List(Allocation),
  runs runs: List(Run),
) -> Nil {
  let assert [plain, typed, planted] = summaries as "three variants expected"
  let assert [plain_memory, typed_memory, _] = allocations
    as "three variants expected"
  let time = percent_over(typed.median_milliseconds, plain.median_milliseconds)
  let allocated =
    percent_over(
      median(typed_memory.words_per_message),
      median(plain_memory.words_per_message),
    )
  let held =
    percent_over(
      int.to_float(typed_memory.units_size.heap_words),
      int.to_float(plain_memory.units_size.heap_words),
    )
  let paired = paired_ratios(runs:, top: plain.variant, bottom: typed.variant)
  io.println("\n== Typed against plain")
  io.println("time, medians:                 " <> signed(time) <> "%")
  io.println(
    "time, median of per-round B/A: "
    <> signed({ median(paired) -. 1.0 } *. 100.0)
    <> "%",
  )
  io.println("words allocated per message:   " <> signed(allocated) <> "%")
  io.println("units dictionary heap words:   " <> signed(held) <> "%")
  let within = fn(cost) { cost <=. cost_limit_percent }
  let picked = case within(time) && within(allocated) && within(held) {
    True -> "typed everywhere"
    False -> "typed everywhere except named hot paths"
  }
  io.println(
    "choosing rule (limit "
    <> two_places(cost_limit_percent)
    <> "% in time and memory): "
    <> picked,
  )

  io.println("\n== Measure 4: the planted extra lookup")
  let spread = range(plain.milliseconds)
  let difference = planted.median_milliseconds -. plain.median_milliseconds
  io.println(
    "median C - median A: "
    <> two_places(difference)
    <> " ms; range of A's runs: "
    <> two_places(spread)
    <> " ms; standard deviation of A's runs: "
    <> two_places(standard_deviation(plain.milliseconds))
    <> " ms; the harness "
    <> case difference >. spread {
      True -> "sees the difference"
      False -> "does not see the difference"
    },
  )
  let planted_ratios =
    paired_ratios(runs:, top: plain.variant, bottom: planted.variant)
  io.println(
    "per-round C/A: median "
    <> signed({ median(planted_ratios) -. 1.0 } *. 100.0)
    <> "%, C slower than A in "
    <> int.to_string(list.count(planted_ratios, fn(ratio) { ratio >. 1.0 }))
    <> " of "
    <> int.to_string(rounds)
    <> " rounds",
  )
}

fn paired_ratios(
  runs runs: List(Run),
  top top: String,
  bottom bottom: String,
) -> List(Float) {
  let tops = list.filter(runs, fn(run) { run.variant == top })
  let bottoms = list.filter(runs, fn(run) { run.variant == bottom })
  list.map2(tops, bottoms, fn(a, b) { b.milliseconds /. a.milliseconds })
}

fn percent_over(value: Float, base: Float) -> Float {
  { value /. base -. 1.0 } *. 100.0
}

fn range(values: List(Float)) -> Float {
  let sorted = list.sort(values, float.compare)
  let assert Ok(smallest) = list.first(sorted) as "no values"
  let assert Ok(largest) = list.last(sorted) as "no values"
  largest -. smallest
}

fn median(values: List(Float)) -> Float {
  let sorted = list.sort(values, float.compare)
  let count = list.length(sorted)
  let assert [_, ..] = sorted as "no values"
  case count % 2 {
    1 -> {
      let assert Ok(middle) = list.first(list.drop(sorted, count / 2))
        as "no middle"
      middle
    }
    _ -> {
      let assert [low, high, ..] = list.drop(sorted, count / 2 - 1)
        as "no middle"
      { low +. high } /. 2.0
    }
  }
}

fn standard_deviation(values: List(Float)) -> Float {
  let count = int.to_float(list.length(values))
  let mean = float.sum(values) /. count
  let squares =
    list.map(values, fn(value) { { value -. mean } *. { value -. mean } })
  let assert Ok(deviation) =
    float.square_root(float.sum(squares) /. { count -. 1.0 })
    as "a variance is not negative"
  deviation
}

fn two_places(value: Float) -> String {
  float.to_string(float.to_precision(value, 2))
}

fn signed(value: Float) -> String {
  case value >=. 0.0 {
    True -> "+" <> two_places(value)
    False -> two_places(value)
  }
}
