//// How many schedulers the server should run on: prototype C, a map process
//// with a sender pool, under the same load at 1, 4, 8 and all the cores'
//// worth of schedulers, in one map and in several maps at once.
////
//// Run it with `gleam run -m genesis_prime/scheduler_count` on a machine with
//// nothing else heavy running. It shares its runs and tables with
//// `genesis_prime/topology` through `genesis_prime/topology/trial`, and
//// `gleam test` never runs it. The harness process runs at high priority, and
//// the schedulers online are set back to every core at the end.
////
//// The parts, selected by naming them after `--` (none named runs all of
//// them):
////
//// - `one-map`: for each count and each visibility range in
////   `visibility_ranges`, player counts counted up with short runs until the
////   map falls behind, then the count below that and the count that fell
////   behind rerun at full length; the ceilings table.
//// - `maps`: for each count and range, one short run of `map_count` maps of
////   `players_per_map` players and `creatures_per_map` creatures each: p99,
////   max, pace, and how many maps fell behind.
//// - `time`: `time_rounds` paired short rounds across the counts at
////   `comparison_players` players, `creature_count` creatures and the default
////   range: median scheduler busy time per message, p99 and memory per unit.
//// - the choosing rule, which runs after `one-map`, `maps` and `time` when all
////   three ran.

import genesis_prime/topology/run.{type RunResult}
import genesis_prime/topology/trial.{
  type Ceiling, type Contender, type Narrowed, type Timed,
}

/// The scheduler counts compared: 1; 4, a small service host; 8, this
/// machine's performance cores, leaving out its 4 efficiency cores; and 12,
/// every core of this machine, the BEAM's default. `counts_for` drops a count
/// above the machine's cores and adds the machine's core count when it is not
/// listed, so the last count is always every core.
const scheduler_counts = [1, 4, 8, 12]

/// The creatures on the map in the one-map and time parts.
const creature_count = 10_000

/// The player counts the one-map climb goes through, lowest first.
const player_counts = [100, 200, 400, 800]

/// The visibility ranges of the one-map and maps parts, in metres. 100 is the
/// stand-in every other run uses; 640 is the client's default draw distance
/// (`lod.viewDistance`, setting object 0x140c46410), which bounds what a
/// player can see.
const visibility_ranges = [100.0, 640.0]

/// How many maps run side by side in the maps part.
const map_count = 4

/// The players on each map of the maps part: with `map_count` maps, the same
/// 400 players as the one-map part's `ceiling_floor_players`.
const players_per_map = 100

/// The creatures on each map of the maps part: with `map_count` maps, the same
/// 10,000 creatures as `creature_count`.
const creatures_per_map = 2500

/// How many paired rounds the time per message is taken over; the median
/// counts.
const time_rounds = 5

/// The player count at which latency, time per message and memory are
/// compared by the choosing rule, at `creature_count` creatures and the
/// default visibility range.
const comparison_players = 100

/// Choosing rule, first step: a count whose map did not keep up at this many
/// players, in one map and in `map_count` maps, at every visibility range in
/// `visibility_ranges`, is out.
const ceiling_floor_players = 400

/// Choosing rule, second step: a count whose median 99th-percentile latency is
/// at least this many microseconds above the lowest left is dropped. It is a
/// tenth of the client's movement send interval, 125 ms (0x140c3a004).
const latency_tie_microseconds = 12_500

/// Choosing rule, third step: a count whose median scheduler busy time per
/// message is more than this percent above the lowest left is dropped; a
/// smaller difference is below what the harness can resolve between two runs.
const resolution_percent = 5.0

/// The parts of the run, in the order they run.
const parts = ["one-map", "maps", "time"]

/// What the maps part found for one count at one range: the short run of
/// `map_count` maps.
type ManyMaps {
  ManyMaps(schedulers: Int, visibility_range: Float, result: RunResult)
}

/// What the choosing rule ends with.
type Choice {
  /// One count, and what the second and third steps dropped on the way.
  Picked(schedulers: Int, by_latency: Narrowed, by_cpu: Narrowed)
  /// Every count is out: no count keeps up at `ceiling_floor_players` players.
  NoCountKeepsUp
}

/// Runs the parts named after `--`, or all of them, in order, and prints their
/// tables and the choosing rule's pick. The harness process runs at high
/// priority, and every core is online again at the end.
pub fn main() -> Nil {
  todo as "body in the build commit"
}

/// The counts of `scheduler_counts` that are at most `cores`, lowest first,
/// then `cores` itself when it is not among them. This machine's performance
/// cores are 8 of its 12.
fn counts_for(cores cores: Int) -> List(Int) {
  todo as "body in the build commit"
}

/// The name a count is printed under and found by in every table, such as
/// "C, 4 schedulers".
fn contender_name(schedulers schedulers: Int) -> String {
  todo as "body in the build commit"
}

/// Prototype C on `schedulers` schedulers as a contender: one map at
/// `creature_count` creatures, with the sender pool of prototype C
/// (`map_process.SenderPool`).
fn contender_of(schedulers schedulers: Int) -> Contender {
  todo as "body in the build commit"
}

/// The one-map part: for each count and each range, the climb and its
/// confirmation, then the ceilings table. The ceilings, one per count and
/// range.
fn one_map(counts counts: List(Int)) -> List(Ceiling) {
  todo as "body in the build commit"
}

/// The maps part: for each count and each range, one short run of `map_count`
/// maps of `players_per_map` players and `creatures_per_map` creatures each,
/// then the table of `print_maps`. The runs, one per count and range.
fn many_maps(counts counts: List(Int)) -> List(ManyMaps) {
  todo as "body in the build commit"
}

/// Prints p99 latency, maximum latency, pace and how many maps fell behind for
/// each of `runs`.
fn print_maps(runs runs: List(ManyMaps)) -> Nil {
  todo as "body in the build commit"
}

/// The time part: `time_rounds` paired rounds, rotating the starting count, of
/// every count at `comparison_players` players, `creature_count` creatures,
/// the default visibility range and short timing. Prints each run, then each
/// count's median, minimum, maximum and standard deviation of the time per
/// message and its median p99 and memory.
fn time_per_message(counts counts: List(Int)) -> List(Timed) {
  todo as "body in the build commit"
}

/// The choosing rule, from the one-map, maps and time parts. It does not depend
/// on the order the counts are listed in:
///
/// 1. Out: a count whose map did not keep up at `ceiling_floor_players`
///    players in one map or in `map_count` maps, at any visibility range in
///    `visibility_ranges`. A run counts as kept up when its pace is not
///    `FellBehind`, as in the ceilings. When every count is out, it says so.
/// 2. Of those left, the lowest median 99th-percentile latency is found, and
///    every count whose latency is at least `latency_tie_microseconds` above
///    it is dropped.
/// 3. Of those left, the lowest median scheduler busy time per message is
///    found, and every count more than `resolution_percent` percent above it
///    is dropped. Of the counts within that percent, the fewest schedulers
///    wins, since it leaves cores to the database and the host.
///
/// It prints each step: who is out or dropped and why, then the pick.
fn choose(
  counts counts: List(Int),
  one_map one_map: List(Ceiling),
  many_maps many_maps: List(ManyMaps),
  timed timed: List(Timed),
) -> Nil {
  todo as "body in the build commit"
}

/// The counts that did not fall out at the first step of the rule, lowest
/// first.
fn counts_left(
  counts counts: List(Int),
  one_map one_map: List(Ceiling),
  many_maps many_maps: List(ManyMaps),
) -> List(Int) {
  todo as "body in the build commit"
}

/// The choice among the standings of the counts that are left, lowest count
/// first: the rule's second and third steps, and the fewest schedulers among
/// the counts the third leaves. `NoCountKeepsUp` when `left` is empty.
fn pick(left left: List(Int), timed timed: List(Timed)) -> Choice {
  todo as "body in the build commit"
}

/// Whether the map or maps of `found` kept up: its pace is not `FellBehind`.
fn kept_up(found: ManyMaps) -> Bool {
  todo as "body in the build commit"
}
