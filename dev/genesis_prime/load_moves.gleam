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
//// seeds `load-0`, `load-1`, ...), the client's tables and ground, the server in a
//// node of its own and the players in this one, limited to the clients' schedulers
//// (`load_run.start_clients`). The server listens on ports the operating system picks
//// (`load_run.on_free_ports`), so another server may be running.
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
//// Beside the walkers, `probes` clients of the real protocol join the map and send
//// tagged moves (`genesis_prime/load_move_delay`); the run prints the delay from a
//// probe's send to each other probe's receipt, as its mean and 99th percentile.
////
//// The run fails, with exit status 1, when the step's verdict is a failure or when the probes
//// read fewer moves than were sent to them (the moves read are judged by
//// `genesis_prime/load_judged`, with the moves sent to a probe as the minimum, at least 1).
////
//// The map falls behind when its queue grows with the hold instead of staying
//// near zero, or when the share of samples that find its process running
//// approaches all of them.

import argv
import genesis_prime
import genesis_prime/load_judged.{Judged}
import genesis_prime/load_move_delay
import genesis_prime/load_player
import genesis_prime/load_run
import genesis_prime/load_sample
import genesis_prime/load_step
import genesis_prime/step/runtime
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import pog

/// How many players walk on the one map when the run is given no number.
const default_players = 50

/// How long the players take to arrive, and how long they walk after the last
/// has, in milliseconds.
const arrival_ms = 5000

const hold_ms = 20_000

/// The clients that measure the delay, when the walkers have all arrived, how long
/// after that all are in the world, and how long they send moves.
const probes = 4

const probes_in_world_ms = 6000

const probe_window_ms = 10_000

/// What the map showed, as the server's node sampled it: the longest message
/// queue, the sum of the queue of each sample, how many samples there were and
/// how many of them found the map's process running.
pub type Probe =
  #(Int, Int, Int, Int)

@external(erlang, "load_moves_ffi", "start_probe")
pub fn start_probe(supervisor: process_name) -> Nil

@external(erlang, "load_moves_ffi", "stop_probe")
pub fn stop_probe() -> Probe

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
  let settings =
    load_run.in_peer(peer, fn() {
      load_run.start_server_with(change: load_run.on_free_ports)
    })
  let assert Ok(started) = pog.start(genesis_prime.pool())
    as "the pool for the accounts started"
  let accounts = load_player.accounts(first: 0, count: players)
  let probe_accounts = load_player.accounts(first: players, count: probes)
  load_player.seed(pool: started.data, accounts:)
  load_player.seed(pool: started.data, accounts: probe_accounts)
  load_run.in_peer(peer, fn() { start_probe(settings.world.map_supervisor) })
  let ports = load_run.in_peer(peer, fn() { load_run.ports_of(settings) })
  let begin_ms = runtime.now().monotonic_ms
  let probed = process.new_subject()
  list.each(probe_accounts, fn(account) {
    load_move_delay.start(
      plan: load_move_delay.Plan(
        account:,
        begin_ms: begin_ms + arrival_ms,
        sync_ms: begin_ms + arrival_ms + probes_in_world_ms,
        window_ms: probe_window_ms,
      ),
      ports:,
      report: probed,
    )
  })
  let outcome =
    load_run.run_step_walking(
      ports:,
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
  let step_verdict = load_step.judge(outcome.observation)
  io.println(load_run.describe(
    players:,
    arrival_ms:,
    outcome:,
    verdict: step_verdict,
  ))
  io.println(
    "the map's message queue: longest "
    <> int.to_string(longest)
    <> ", mean "
    <> per(total: queued, count: samples)
    <> " over "
    <> int.to_string(samples)
    <> " samples, one every 10 ms",
  )
  io.println(
    "the map's process was found running in "
    <> percent(part: running, whole: samples)
    <> " of the samples",
  )
  let delays =
    load_move_delay.delays(
      probed: list.map(probe_accounts, fn(_) {
        load_move_delay.reported(report: probed, within_ms: 1000)
      }),
    )
  let summary = load_move_delay.summary(delays:)
  io.println(
    "mover-to-viewer delay, from a probe's send to another probe's receipt among "
    <> int.to_string(players)
    <> " walkers: mean "
    <> per(total: summary.mean_us, count: 1000)
    <> " ms, 99th percentile "
    <> per(total: summary.p99_us, count: 1000)
    <> " ms, longest "
    <> per(total: summary.longest_us, count: 1000)
    <> " ms, over "
    <> int.to_string(summary.moves)
    <> " moves read of "
    <> int.to_string(delays.expected)
    <> " sent to a probe ("
    <> int.to_string(probes)
    <> " probes, one move every 125 ms for "
    <> int.to_string(probe_window_ms / 1000)
    <> " s)",
  )
  let judged =
    load_judged.judge(
      judged: [
        Judged(
          event: load_judged.MovesRead,
          count: summary.moves,
          minimum: int.max(1, delays.expected),
        ),
      ],
      conditions: [
        load_judged.Condition(
          held: case step_verdict {
            load_step.Failed(..) -> False
            load_step.Kept | load_step.ClientsLimited -> True
          },
          said: "the step's verdict is " <> load_step.describe(step_verdict),
        ),
      ],
    )
  list.each(judged.lines, io.println)
  load_judged.require(verdict: judged)
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
