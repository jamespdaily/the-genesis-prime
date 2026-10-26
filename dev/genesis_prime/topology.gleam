//// Which process owns a unit's state: one process per unit with its position
//// in a shared table, or one process that owns the whole map. The two
//// prototypes run the same game rules under the same load, and only the
//// ownership differs.
////
//// Run it with `gleam run -m genesis_prime/topology` on a machine with
//// nothing else heavy running. It lives in `dev/` because Gleam compiles that
//// directory with the project, so `gleam build` keeps it compiling, while
//// `gleam test` never runs it. It uses only the runtime's own counters, so it
//// can be run again on the real map.
////
//// It runs the measures in order and prints a table for each, then the
//// prototype the choosing rule picks.

/// The player counts a run uses.
pub const player_counts = [100, 200, 400, 800]

/// The creature counts a run uses.
pub const creature_counts = [1000, 10_000]

/// The scheduler counts of the scheduler measure, besides all the cores.
pub const scheduler_counts = [1]

/// How many runs the time per message is taken over; the median counts.
pub const time_runs = 5

/// How many rounds the planted-cost measure pairs.
pub const planted_rounds = 5

/// The player count at which the choosing rule compares latency.
pub const comparison_players = 100

/// The creature count at which time per message and the planted cost are
/// measured.
pub const comparison_creatures = 10_000

/// Choosing rule, first step: a prototype whose ceiling, on all cores, is
/// below this many players in one map is out.
pub const ceiling_floor_players = 400

/// Choosing rule, second step: prototypes whose 99th-percentile latency at
/// `comparison_players` is within this percent of each other are tied, and the
/// one with less memory per unit wins.
pub const latency_tie_percent = 10.0

/// Runs measures 2 to 8 in order and prints their tables and the choosing
/// rule's pick.
pub fn main() -> Nil {
  todo as "body in the build commit"
}
