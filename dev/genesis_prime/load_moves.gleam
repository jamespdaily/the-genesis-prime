//// The movement load run: how the map keeps up when many players on one map
//// move at once, on the real protocol path.
////
//// ```
//// gleam run -m genesis_prime/load_moves
//// ```
////
//// The environment is the load run's (`genesis_prime/load_run`): a migrated
//// database empty of accounts (the run seeds `load-0`, `load-1`, ...), the
//// client's tables, and the server's ports, so no server may be running.
////
//// The server runs in a node of its own and the players in this one. All the
//// players log in, create a character and enter the same map, where every
//// character starts at the same place, so each is in sight of every other; each
//// then sends a 0x0637 every 125 ms (`genesis_prime/load_player`, walking) for
//// `hold_ms`, so the map relays each move to every other player. The VM counts
//// the calls of the map's `moved` and the time they take, and a process of its
//// own samples the map's message queue every 10 ms
//// (`load_moves_ffi`). The run prints the moves counted, the time per move, the
//// longest and the mean queue, the ping round trips the players saw and how
//// many players failed.
////
//// The map falls behind when its queue grows with the hold instead of staying
//// near zero, or when the time per move times the moves a second approaches a
//// second.

import genesis_prime
import genesis_prime/load_player
import genesis_prime/load_run
import genesis_prime/load_sample
import genesis_prime/load_step
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import pog

/// How many players walk on the one map: the issue's load target.
const players = 50

/// How long the players take to arrive, and how long they walk after the last
/// has, in milliseconds.
const arrival_ms = 5000

const hold_ms = 20_000

/// What the map's moves cost, as the server's node counted them: the calls of
/// the map's move function, the microseconds they took in all, the longest
/// message queue the map showed, the sum of the queues sampled and how many
/// samples there were.
type Probe =
  #(Int, Int, Int, Int, Int)

@external(erlang, "load_moves_ffi", "start_probe")
fn start_probe() -> Nil

@external(erlang, "load_moves_ffi", "stop_probe")
fn stop_probe() -> Probe

pub fn main() -> Nil {
  load_run.silence_crash_reports()
  load_sample.start()
  let peer = load_run.start_peer()
  let settings = load_run.in_peer(peer, load_run.start_server)
  let assert Ok(started) = pog.start(genesis_prime.pool())
    as "the pool for the accounts started"
  let accounts = load_player.accounts(first: 0, count: players)
  load_player.seed(pool: started.data, accounts:)
  load_run.in_peer(peer, start_probe)
  let outcome =
    load_run.run_step_walking(
      ports: load_run.ports_of(settings),
      accounts:,
      arrival_ms:,
      hold_ms:,
      walking: True,
      sample_server: fn() {
        load_run.in_peer(peer, fn() { load_sample.take(settings) })
      },
    )
  let #(moves, micros, longest, queued, samples) =
    load_run.in_peer(peer, stop_probe)
  load_run.stop_peer(peer)
  io.println(
    int.to_string(players)
    <> " walking players, "
    <> int.to_string(arrival_ms / 1000)
    <> " s arriving and "
    <> int.to_string(hold_ms / 1000)
    <> " s walking",
  )
  io.println("moves the map handled: " <> int.to_string(moves))
  io.println(
    "time per move: "
    <> per(micros, moves)
    <> " microseconds (the map's own time in its move function)",
  )
  io.println(
    "the map's message queue: longest "
    <> int.to_string(longest)
    <> ", mean "
    <> per(queued, samples)
    <> " over "
    <> int.to_string(samples)
    <> " samples, one every 10 ms",
  )
  io.println(
    "players that failed: "
    <> int.to_string(list.length(outcome.failures))
    <> "; ping round trip p99: "
    <> int.to_string(load_step.percentile(
      values: outcome.observation.ping_round_trip_us,
      percent: 99,
    ))
    <> " microseconds; verdict: "
    <> load_step.describe(load_step.judge(outcome.observation)),
  )
}

/// A mean of `total` over `count`, to one decimal, or a dash for none.
fn per(total: Int, count: Int) -> String {
  case count {
    0 -> "-"
    _ ->
      float.to_string(float.to_precision(
        int.to_float(total) /. int.to_float(count),
        1,
      ))
  }
}
