//// The movement load run: how the server keeps up when many players on one map
//// move at once, on the real protocol path.
////
//// ```
//// gleam run -m genesis_prime/load_moves            50 players
//// gleam run -m genesis_prime/load_moves -- 200     200 players
//// ```
////
//// The environment, the two nodes and the step are the load run's
//// (`genesis_prime/load_run`): a migrated database empty of accounts (the run
//// seeds `load-0`, `load-1`, ...), the client's tables, the server's ports (so
//// no server may be running), the server in a node of its own and the players
//// in this one, limited to the clients' schedulers (`load_run.start_clients`).
//// All the players log in, create a character and enter the same map, where
//// every character starts at the same place, so each is in sight of every other;
//// each then sends a 0x0637 every 125 ms (`genesis_prime/load_player`, walking)
//// for `hold_ms`, so each player's connection sends each move to every other
//// player's connection.
////
//// The step is printed as the load run prints one (`load_run.describe`, with
//// its verdict, its ping round trips, its longest mailbox of any process and the
//// lines the server logged), followed by what the map showed: the longest and
//// the mean of its message queue, and the share of the samples that found its
//// process running (`load_moves_ffi`). Nothing is traced: tracing the map's
//// functions slowed it enough to fall behind at 200 players, where the same run
//// untraced keeps up.
////
//// The map falls behind when its queue grows with the hold instead of staying
//// near zero, or when the share of samples that find its process running
//// approaches all of them.

import argv
import genesis_prime
import genesis_prime/load_player
import genesis_prime/load_run
import genesis_prime/load_sample
import genesis_prime/load_step
import gleam/float
import gleam/int
import gleam/io
import gleam/result
import pog

/// How many players walk on the one map when the run is given no number.
const default_players = 50

/// How long the players take to arrive, and how long they walk after the last
/// has, in milliseconds.
const arrival_ms = 5000

const hold_ms = 20_000

/// What the map showed, as the server's node sampled it: the longest message
/// queue, the sum of the queue of each sample, how many samples there were and
/// how many of them found the map's process running.
type Probe =
  #(Int, Int, Int, Int)

@external(erlang, "load_moves_ffi", "start_probe")
fn start_probe(supervisor: process_name) -> Nil

@external(erlang, "load_moves_ffi", "stop_probe")
fn stop_probe() -> Probe

pub fn main() -> Nil {
  let players = case argv.load().arguments {
    [number, ..] ->
      int.parse(number)
      |> result.lazy_unwrap(fn() {
        panic as "the number of players is a whole number"
      })
    [] -> default_players
  }
  load_run.start_clients()
  let peer = load_run.start_peer()
  let settings = load_run.in_peer(peer, load_run.start_server)
  let assert Ok(started) = pog.start(genesis_prime.pool())
    as "the pool for the accounts started"
  let accounts = load_player.accounts(first: 0, count: players)
  load_player.seed(pool: started.data, accounts:)
  load_run.in_peer(peer, fn() { start_probe(settings.world.map_supervisor) })
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
  let #(longest, queued, samples, running) = load_run.in_peer(peer, stop_probe)
  load_run.stop_peer(peer)
  io.println(load_run.describe(
    players:,
    arrival_ms:,
    outcome:,
    verdict: load_step.judge(outcome.observation),
  ))
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
    "the map's process was found running in "
    <> percent(running, samples)
    <> " of the samples",
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

/// `part` of `whole` as a percentage to one decimal, or a dash for no whole.
fn percent(part: Int, whole: Int) -> String {
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
