//// The trial procedure the load mains share: contenders run at rising player
//// counts until one falls behind, the counts around the fall rerun at full
//// length, contenders run in paired rounds with the starting order rotating,
//// and the tables and the narrowing a choosing rule is built from. A main
//// decides what a contender is (a prototype, a scheduler count) and what its
//// choosing rule keeps; this module carries out the runs and prints them.

import genesis_prime/topology/latency
import genesis_prime/topology/run.{type Pace, type RunResult, type Timing}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/string

/// One thing a trial compares: a prototype, a scheduler count. Its name is
/// printed in every table and tells it apart from the other contenders of the
/// same trial, so names are unique within one.
pub type Contender {
  Contender(
    name: String,
    /// Runs one load for this contender and returns what it counted: the
    /// player count, the visibility range in metres and the timing.
    run: fn(Int, Float, Timing) -> RunResult,
  )
}

/// One finished run and the name of the contender that ran it.
pub type Measured {
  Measured(contender: String, result: RunResult)
}

/// Where one contender stopped keeping up at one visibility range, from the
/// full-length confirmation runs only. A run whose owners kept up but whose
/// players did not all report counts as kept up.
pub type Ceiling {
  Ceiling(
    contender: String,
    visibility_range: Float,
    /// The highest player count whose confirmation run kept up, or none when
    /// no confirmation run kept up.
    kept_up_at: Option(Int),
    /// The lowest player count whose confirmation run fell behind, or none
    /// when none did.
    fell_behind_at: Option(Int),
  )
}

/// What one contender's climb at one visibility range found: its short runs,
/// its full-length confirmation runs and the ceiling they show.
pub type Climb {
  Climb(
    visibility_range: Float,
    short: List(Measured),
    full: List(Measured),
    ceiling: Ceiling,
  )
}

/// What the paired rounds found for one contender: the medians, over the
/// rounds, of the scheduler busy microseconds per message handled, of the
/// 99th-percentile latency in microseconds and of the memory per unit in
/// words.
pub type Timed {
  Timed(
    contender: String,
    microseconds_per_message: Float,
    p99_microseconds: Int,
    memory_words_per_unit: Float,
  )
}

/// A contender dropped at one step of a choosing rule, and why.
pub type Dropped {
  Dropped(contender: String, reason: String)
}

/// What one step of a choosing rule left and dropped.
pub type Narrowed {
  Narrowed(left: List(Timed), dropped: List(Dropped))
}

/// Runs the contender once, printing the run as it finishes.
pub fn measured_run(
  contender contender: Contender,
  players players: Int,
  visibility_range visibility_range: Float,
  timing timing: Timing,
) -> Measured {
  let result = contender.run(players, visibility_range, timing)
  io.println(
    string.pad_end(contender.name, 32, " ")
    <> pad_start(text: int.to_string(result.players), width: 5)
    <> " players "
    <> pad_start(text: int.to_string(result.creatures), width: 6)
    <> " creatures range "
    <> pad_start(text: two_places(visibility_range), width: 7)
    <> ": p50 "
    <> pad_start(
      text: int.to_string(latency.percentile(result.latency, 50.0)),
      width: 8,
    )
    <> " p99 "
    <> pad_start(
      text: int.to_string(latency.percentile(result.latency, 99.0)),
      width: 8,
    )
    <> " max "
    <> pad_start(text: int.to_string(latency.maximum(result.latency)), width: 8)
    <> " us, moves "
    <> int.to_string(result.moves_sent)
    <> " updates "
    <> int.to_string(result.updates_received)
    <> " queues "
    <> int.to_string(list.fold(result.queue_samples, 0, int.max))
    <> " (largest) "
    <> pace_name(result.pace),
  )
  Measured(contender: contender.name, result:)
}

/// The climb and its confirmation for one contender at one visibility range,
/// printing a heading before each: short runs counting up through
/// `player_counts`, then full-length reruns around where it fell behind.
pub fn climb_and_confirm(
  contender contender: Contender,
  visibility_range visibility_range: Float,
  player_counts player_counts: List(Int),
) -> Climb {
  io.println(
    "\n-- "
    <> contender.name
    <> ", range "
    <> two_places(visibility_range)
    <> " m: short runs, counting players up",
  )
  let short = climb(contender:, visibility_range:, player_counts:)
  io.println("-- full-length confirmation runs")
  let full = confirm(contender:, climbed: short, visibility_range:)
  Climb(
    visibility_range:,
    short:,
    full:,
    ceiling: ceiling_of(contender:, visibility_range:, confirmed: full),
  )
}

/// Short runs of one contender at each of `player_counts`, lowest first,
/// stopping after the first run that fell behind; the runs, in the order they
/// ran. A contender that keeps up with every count gives every count's run.
fn climb(
  contender contender: Contender,
  visibility_range visibility_range: Float,
  player_counts player_counts: List(Int),
) -> List(Measured) {
  climb_counts(counts: player_counts, contender:, visibility_range:, ran: [])
}

fn climb_counts(
  counts counts: List(Int),
  contender contender: Contender,
  visibility_range visibility_range: Float,
  ran ran: List(Measured),
) -> List(Measured) {
  case counts {
    [] -> list.reverse(ran)
    [players, ..higher] -> {
      let measured =
        measured_run(
          contender:,
          players:,
          visibility_range:,
          timing: run.short_timing,
        )
      case measured.result.pace {
        run.FellBehind -> list.reverse([measured, ..ran])
        run.KeptUp | run.PlayersFellBehind ->
          climb_counts(counts: higher, contender:, visibility_range:, ran: [
            measured,
            ..ran
          ])
      }
    }
  }
}

/// Full-length reruns of the highest player count of `climbed` that kept up
/// and the first that fell behind, each when there is one.
fn confirm(
  contender contender: Contender,
  climbed climbed: List(Measured),
  visibility_range visibility_range: Float,
) -> List(Measured) {
  let highest_kept_up =
    climbed
    |> list.filter(fn(found) { found.result.pace != run.FellBehind })
    |> list.sort(fn(a, b) { int.compare(a.result.players, b.result.players) })
    |> list.last
  let first_fell_behind =
    climbed
    |> list.filter(fn(found) { found.result.pace == run.FellBehind })
    |> list.sort(fn(a, b) { int.compare(a.result.players, b.result.players) })
    |> list.first
  result.values([highest_kept_up, first_fell_behind])
  |> list.map(fn(found) {
    measured_run(
      contender:,
      players: found.result.players,
      visibility_range:,
      timing: run.full_timing,
    )
  })
}

/// The ceiling `confirmed`, the confirmation runs of one contender at one
/// range, show.
fn ceiling_of(
  contender contender: Contender,
  visibility_range visibility_range: Float,
  confirmed confirmed: List(Measured),
) -> Ceiling {
  let players_where = fn(kept_up) {
    confirmed
    |> list.filter(fn(found) {
      { found.result.pace != run.FellBehind } == kept_up
    })
    |> list.map(fn(found) { found.result.players })
  }
  Ceiling(
    contender: contender.name,
    visibility_range:,
    kept_up_at: players_where(True)
      |> list.reduce(int.max)
      |> option.from_result,
    fell_behind_at: players_where(False)
      |> list.reduce(int.min)
      |> option.from_result,
  )
}

/// Whether the contender kept up at `players` players at the ceiling's range:
/// its highest confirmed player count that kept up reaches `players`.
pub fn keeps_up_at(ceiling ceiling: Ceiling, players players: Int) -> Bool {
  case ceiling.kept_up_at {
    option.Some(kept_up_at) -> kept_up_at >= players
    option.None -> False
  }
}

/// Rounds in which every contender runs once at short timing, the first to run
/// rotating by one contender from round to round so each starts about as often
/// as the others. Prints each run's time per message.
fn paired_rounds(
  contenders contenders: List(Contender),
  rounds rounds: Int,
  players players: Int,
  visibility_range visibility_range: Float,
) -> List(List(Measured)) {
  int.range(0, rounds, [], fn(taken, round) {
    let shift = round % list.length(contenders)
    let order =
      list.append(list.drop(contenders, shift), list.take(contenders, shift))
    let results =
      list.map(order, fn(contender) {
        let measured =
          measured_run(
            contender:,
            players:,
            visibility_range:,
            timing: run.short_timing,
          )
        io.println(
          "  round "
          <> int.to_string(round + 1)
          <> " "
          <> contender.name
          <> ": "
          <> two_places(microseconds_per_message(measured.result))
          <> " us/message, p99 "
          <> int.to_string(p99_of(measured.result))
          <> " us, "
          <> int.to_string(measured.result.messages_handled)
          <> " messages",
        )
        measured
      })
    [results, ..taken]
  })
  |> list.reverse
}

/// `rounds` paired rounds of every contender at short timing, then each
/// contender's median, minimum, maximum and standard deviation of the time per
/// message and its median latency and memory, printed one line each. The
/// caller prints the heading.
pub fn time_per_message(
  contenders contenders: List(Contender),
  rounds rounds: Int,
  players players: Int,
  visibility_range visibility_range: Float,
) -> List(Timed) {
  let taken = paired_rounds(contenders:, rounds:, players:, visibility_range:)
  list.map(contenders, fn(contender) {
    let results =
      list.map(taken, fn(round) { result_of(round, contender.name) })
    let values = list.map(results, microseconds_per_message)
    let timed =
      Timed(
        contender: contender.name,
        microseconds_per_message: median(values),
        p99_microseconds: float.round(
          median(list.map(results, fn(result) { int.to_float(p99_of(result)) })),
        ),
        memory_words_per_unit: median(
          list.map(results, fn(result) { result.memory_words_per_unit }),
        ),
      )
    io.println(
      string.pad_end(contender.name, 32, " ")
      <> "median "
      <> two_places(timed.microseconds_per_message)
      <> " us/message  min "
      <> two_places(minimum(values))
      <> "  max "
      <> two_places(maximum(values))
      <> "  standard deviation "
      <> two_places(standard_deviation(values))
      <> "  median p99 "
      <> int.to_string(timed.p99_microseconds)
      <> " us  median memory "
      <> two_places(timed.memory_words_per_unit)
      <> " words per unit",
    )
    timed
  })
}

fn result_of(round: List(Measured), contender: String) -> RunResult {
  let assert Ok(found) =
    list.find(round, fn(found) { found.contender == contender })
    as "every round holds every contender"
  found.result
}

/// Microseconds of scheduler busy time per message the owners handled.
fn microseconds_per_message(result: RunResult) -> Float {
  int.to_float(result.busy_microseconds)
  /. int.to_float(int.max(1, result.messages_handled))
}

/// The 99th-percentile latency of a run, in microseconds.
pub fn p99_of(result: RunResult) -> Int {
  latency.percentile(result.latency, 99.0)
}

/// Prints microseconds from a move's send to its arrival at a player in range,
/// for each of `runs`, with the pace of each run. `kind` heads the column of
/// contender names and `suffix` ends the heading.
pub fn print_latency(
  kind kind: String,
  suffix suffix: String,
  runs runs: List(Measured),
) -> Nil {
  io.println(
    "latency: microseconds from a move's send to its arrival at a player in range"
    <> suffix,
  )
  io.println(
    string.pad_end(kind, 32, " ")
    <> pad_start(text: "players", width: 9)
    <> pad_start(text: "p50", width: 10)
    <> pad_start(text: "p99", width: 10)
    <> pad_start(text: "max", width: 10)
    <> pad_start(text: "arrivals", width: 12)
    <> "  pace",
  )
  list.each(sorted_by_creatures_and_players(runs), fn(found) {
    io.println(
      string.pad_end(found.contender, 32, " ")
      <> pad_start(text: int.to_string(found.result.players), width: 9)
      <> pad_start(
        text: int.to_string(latency.percentile(found.result.latency, 50.0)),
        width: 10,
      )
      <> pad_start(text: int.to_string(p99_of(found.result)), width: 10)
      <> pad_start(
        text: int.to_string(latency.maximum(found.result.latency)),
        width: 10,
      )
      <> pad_start(
        text: int.to_string(latency.count(found.result.latency)),
        width: 12,
      )
      <> "  "
      <> pace_name(found.result.pace),
    )
  })
}

/// Prints each ceiling: the highest player count that kept up and the lowest
/// that fell behind, in the full-length confirmation runs. `suffix` ends the
/// heading.
pub fn print_ceiling(
  suffix suffix: String,
  ceilings ceilings: List(Ceiling),
) -> Nil {
  io.println(
    "\n== ceiling: highest player count that kept up and lowest that fell behind, full-length runs only"
    <> suffix,
  )
  list.each(ceilings, fn(ceiling) {
    io.println(
      string.pad_end(ceiling.contender, 32, " ")
      <> " range "
      <> pad_start(text: two_places(ceiling.visibility_range), width: 7)
      <> " m: kept up at "
      <> players_text(players: ceiling.kept_up_at, none: "no count")
      <> ", fell behind at "
      <> players_text(players: ceiling.fell_behind_at, none: "no count"),
    )
  })
}

/// Prints the words of memory per unit of each of `runs`. `suffix` ends the
/// heading.
pub fn print_memory(suffix suffix: String, runs runs: List(Measured)) -> Nil {
  io.println("memory: words per unit" <> suffix)
  list.each(sorted_by_creatures_and_players(runs), fn(found) {
    io.println(
      string.pad_end(found.contender, 32, " ")
      <> pad_start(text: int.to_string(found.result.players), width: 5)
      <> " players: "
      <> two_places(found.result.memory_words_per_unit)
      <> " words per unit",
    )
  })
}

/// The pace of a run as it is printed in a table.
pub fn pace_name(pace: Pace) -> String {
  case pace {
    run.KeptUp -> "KeptUp"
    run.FellBehind -> "FellBehind"
    run.PlayersFellBehind -> "PlayersFellBehind"
  }
}

fn sorted_by_creatures_and_players(runs: List(Measured)) -> List(Measured) {
  list.sort(runs, fn(a, b) {
    case int.compare(a.result.creatures, b.result.creatures) {
      order.Eq -> int.compare(a.result.players, b.result.players)
      other -> other
    }
  })
}

/// A player count as text, or `none` when there is no count.
pub fn players_text(players players: Option(Int), none none: String) -> String {
  case players {
    option.Some(players) -> int.to_string(players) <> " players"
    option.None -> none
  }
}

/// The contenders whose 99th-percentile latency is under `tie_microseconds`
/// above the lowest of `standings`, and the others with why they were dropped.
/// `standings` holds at least one.
pub fn narrow_by_latency(
  standings standings: List(Timed),
  tie_microseconds tie_microseconds: Int,
) -> Narrowed {
  narrow(
    standings:,
    measure: fn(standing) { int.to_float(standing.p99_microseconds) },
    too_far: fn(value, lowest) {
      value -. lowest >=. int.to_float(tie_microseconds)
    },
    reason: fn(standing, lowest) {
      "p99 "
      <> int.to_string(standing.p99_microseconds)
      <> " us is "
      <> two_places(int.to_float(standing.p99_microseconds) -. lowest)
      <> " us above the lowest, "
      <> two_places(lowest)
      <> " us"
    },
  )
}

/// The contenders whose scheduler busy time per message is at most
/// `resolution_percent` percent above the lowest of `standings`, and the
/// others with why they were dropped. `standings` holds at least one.
pub fn narrow_by_cpu(
  standings standings: List(Timed),
  resolution_percent resolution_percent: Float,
) -> Narrowed {
  narrow(
    standings:,
    measure: fn(standing) { standing.microseconds_per_message },
    too_far: fn(value, lowest) {
      percent_above(value:, lowest:) >. resolution_percent
    },
    reason: fn(standing, lowest) {
      two_places(standing.microseconds_per_message)
      <> " us/message is "
      <> signed(percent_above(value: standing.microseconds_per_message, lowest:))
      <> "% above the lowest, "
      <> two_places(lowest)
      <> " us/message"
    },
  )
}

/// The standings whose `measure` is not too far above the lowest `measure`
/// among them, in their order, and the others with why they were dropped.
fn narrow(
  standings standings: List(Timed),
  measure measure: fn(Timed) -> Float,
  too_far too_far: fn(Float, Float) -> Bool,
  reason reason: fn(Timed, Float) -> String,
) -> Narrowed {
  let assert Ok(lowest) = list.reduce(list.map(standings, measure), float.min)
    as "a step is given at least one standing"
  let #(left, far) =
    list.partition(standings, fn(standing) {
      !too_far(measure(standing), lowest)
    })
  Narrowed(
    left:,
    dropped: list.map(far, fn(standing) {
      Dropped(contender: standing.contender, reason: reason(standing, lowest))
    }),
  )
}

/// Prints a step's title and who it dropped and why.
pub fn print_narrowed(title title: String, narrowed narrowed: Narrowed) -> Nil {
  io.println(title)
  case narrowed.dropped {
    [] -> io.println("   none dropped")
    dropped ->
      list.each(dropped, fn(found) {
        io.println("   " <> found.contender <> ": " <> found.reason)
      })
  }
}

/// How many percent of `lowest` the `value` is above it.
fn percent_above(value value: Float, lowest lowest: Float) -> Float {
  { value -. lowest } /. lowest *. 100.0
}

/// The median of `values`, which are not empty; the mean of the two middle
/// values when there is an even number.
pub fn median(values: List(Float)) -> Float {
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

/// The smallest of `values`, which are not empty.
fn minimum(values: List(Float)) -> Float {
  let assert Ok(smallest) = list.first(list.sort(values, float.compare))
    as "no values"
  smallest
}

/// The largest of `values`, which are not empty.
fn maximum(values: List(Float)) -> Float {
  let assert Ok(largest) = list.last(list.sort(values, float.compare))
    as "no values"
  largest
}

/// The sample standard deviation of `values`, which hold at least two.
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

/// A float rounded to two decimal places, as text.
pub fn two_places(value: Float) -> String {
  float.to_string(float.to_precision(value, 2))
}

/// A float to two places with a leading `+` when it is not negative.
fn signed(value: Float) -> String {
  case value >=. 0.0 {
    True -> "+" <> two_places(value)
    False -> two_places(value)
  }
}

/// Text padded on the left with spaces to `width`.
pub fn pad_start(text text: String, width width: Int) -> String {
  string.pad_start(text, width, " ")
}
