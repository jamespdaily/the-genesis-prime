//// The movement load run: how the server keeps up when many players on one map
//// move at once, on the real protocol path.
////
//// ```
//// gleam run -m genesis_prime/load_moves                     50 players
//// gleam run -m genesis_prime/load_moves -- 200              200 players
//// gleam run -m genesis_prime/load_moves -- 100 casting      100 players that also cast
//// gleam run -m genesis_prime/load_moves -- 100 34.7         the paired main run's delay 99th, ms
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
//// With the word `casting`, every walker also presses its level-1 ability (the Relentless
//// Strikes builder, `load_player.pressed_spell4_base_id`) at `cast_first_ms` after the step begins and
//// again `cast_ms` later; the probes read the casts as a 0x7ff, a 0x7f4 and a 0x7fe each. The
//// ability has no cast time (Spell4 32078), so `cast_ms` is the scene's spacing, which the
//// owed casts are counted by (`load_sight.casts_owed`).
////
//// Beside the walkers, `probes` clients of the real protocol join the map and send
//// tagged moves (`genesis_prime/load_move_delay`); the run prints the delay from a
//// probe's send to each other probe's receipt, as its mean and 99th percentile.
////
//// Every walker and probe also keeps what it read of the other players
//// (`genesis_prime/load_sight`): the 0x262 of each other player once, so a run owes
//// (players + probes) x (players + probes - 1) of them, and the 0x638 read for a unit after
//// its 0x355. The probe in the server's node keeps the map's queue each 10 ms with the
//// messages in its mailbox when it is long (`genesis_prime/load_queue`), and the run prints
//// them with the time from a probe's entry to its last 0x262 of another player, which are
//// printed and not judged.
////
//// The run fails, with exit status 1, when the step's verdict is a failure, when the probes
//// read fewer moves than were sent to them, when a client was shown fewer players than
//// there are pairs, when a casting scene's probes read fewer casts than they are owed, when
//// the map's queue grew or the delay's 99th percentile passed the baseline given on the
//// command line by 50 ms, or when a frame was read after its unit's removal: each is
//// judged by `genesis_prime/load_judged`.
////
//// The map falls behind when its queue grows with the hold instead of staying
//// near zero, or when the share of samples that find its process running
//// approaches all of them.

import argv
import genesis_prime
import genesis_prime/load_judged.{Judged}
import genesis_prime/load_move_delay
import genesis_prime/load_player
import genesis_prime/load_queue.{type Probe}
import genesis_prime/load_run
import genesis_prime/load_sample
import genesis_prime/load_sight
import genesis_prime/load_step
import genesis_prime/step/runtime
import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
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

/// The casting scene: when the walkers first press their ability, after the step begins
/// (the probes are in the world by `probes_in_world_ms` after the arrival, so half a
/// second later), and the time between a walker's presses. Both presses finish, `cast_ms`
/// after each, `settle_ms` before the probes stop reading, so both are owed.
const cast_first_ms = 11_500

const cast_ms = 3000

/// How long before the probes stop reading a cast must have finished for them to owe it.
const settle_ms = 3000

@external(erlang, "load_moves_ffi", "start_probe")
pub fn start_probe(supervisor: process_name) -> Nil

/// What the map showed, as the server's node sampled it.
@external(erlang, "load_moves_ffi", "stop_probe")
pub fn stop_probe() -> Probe

/// What the command line asks for: the walkers, whether they cast, and the paired main
/// run's delay 99th percentile in microseconds.
type Run {
  Run(players: Int, casting: Bool, baseline_p99_us: Option(Int))
}

fn run_of(arguments: List(String)) -> Run {
  case arguments {
    [] -> Run(players: default_players, casting: False, baseline_p99_us: None)
    [number, ..words] -> {
      let run =
        Run(
          players: result.lazy_unwrap(int.parse(number), fn() {
            panic as "the number of players is a whole number"
          }),
          casting: list.contains(words, "casting"),
          baseline_p99_us: None,
        )
      case list.filter(words, fn(word) { word != "casting" }) {
        [] -> run
        [baseline] ->
          Run(
            ..run,
            baseline_p99_us: Some(float.round(
              result.lazy_unwrap(float.parse(baseline), fn() {
                panic as "the baseline is the paired run's 99th percentile in milliseconds, with a decimal point"
              })
              *. 1000.0,
            )),
          )
        [_, ..] -> panic as "the run takes a number, `casting` and a baseline"
      }
    }
  }
}

pub fn main() -> Nil {
  let Run(players:, casting:, baseline_p99_us:) = run_of(argv.load().arguments)
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
  let probe_started_ms = runtime.now().monotonic_ms
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
      presses_at_ms: case casting {
        True -> [begin_ms + cast_first_ms, begin_ms + cast_first_ms + cast_ms]
        False -> []
      },
      sample_server: fn() {
        load_run.in_peer(peer, fn() { load_sample.take(settings) })
      },
    )
  let probe = load_run.in_peer(peer, stop_probe)
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
    <> int.to_string(probe.longest)
    <> ", mean "
    <> per(total: probe.sum, count: probe.samples)
    <> " over "
    <> int.to_string(probe.samples)
    <> " samples, one every 10 ms",
  )
  io.println(
    "the map's process was found running in "
    <> percent(part: probe.running, whole: probe.samples)
    <> " of the samples",
  )
  let offset_ms = begin_ms - probe_started_ms
  list.each(
    load_queue.lines(probe:, marks: [
      #("arrival begins", offset_ms),
      #("arrival ends", offset_ms + arrival_ms),
      #("probes in the world", offset_ms + arrival_ms + probes_in_world_ms),
      #(
        "probes stop reading",
        offset_ms + arrival_ms + probes_in_world_ms + probe_window_ms,
      ),
      #("hold ends", offset_ms + arrival_ms + hold_ms),
    ]),
    io.println,
  )
  let reports =
    list.map(probe_accounts, fn(_) {
      load_move_delay.reported(report: probed, within_ms: 1000)
    })
  let delays =
    load_move_delay.delays(
      probed: list.map(reports, fn(report) { report.probed }),
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
  let sights =
    list.append(
      list.map(outcome.walked, fn(walked) { walked.sight }),
      list.map(reports, fn(report) { report.sight }),
    )
  let moves_sent =
    int.sum(list.map(outcome.walked, fn(walked) { walked.moves }))
    + int.sum(
      list.map(reports, fn(report) { dict.size(report.probed.sent_us) }),
    )
  io.println(
    "the map's reductions: "
    <> int.to_string(probe.reductions)
    <> ", "
    <> per(total: probe.reductions, count: moves_sent)
    <> " per move sent ("
    <> int.to_string(moves_sent)
    <> " moves sent by the walkers and the probes, the joins included)",
  )
  let shown_after_us =
    list.filter_map(reports, fn(report) {
      option.to_result(report.sight.last_create_us, Nil)
      |> result.map(fn(last_us) { last_us - report.entered_us })
    })
  io.println(
    "a probe's entry to its last player shown: mean "
    <> per(
      total: int.sum(shown_after_us),
      count: int.max(1, list.length(shown_after_us)) * 1000,
    )
    <> " ms, 99th percentile "
    <> per(
      total: load_step.percentile(values: shown_after_us, percent: 99),
      count: 1000,
    )
    <> " ms, over "
    <> int.to_string(list.length(shown_after_us))
    <> " probes",
  )
  let players_all = players + probes
  let probe_sights = list.map(reports, fn(report) { report.sight })
  let pressed_ms =
    list.flat_map(outcome.walked, fn(walked) {
      list.map(walked.pressed_ms, fn(at_ms) { at_ms - begin_ms })
    })
  let owed =
    load_sight.casts_owed(
      pressed_ms:,
      duration_ms: cast_ms,
      ended_ms: arrival_ms + probes_in_world_ms + probe_window_ms,
      settle_ms:,
    )
  let judged =
    load_judged.judge(
      judged: list.flatten([
        [
          Judged(
            event: load_judged.MovesRead,
            count: summary.moves,
            minimum: int.max(1, delays.expected),
          ),
          Judged(
            event: load_judged.PlayersShown,
            count: load_sight.players_shown(sights:),
            minimum: players_all * { players_all - 1 },
          ),
        ],
        case casting {
          True -> [
            Judged(
              event: load_judged.CastFramesRead,
              count: load_sight.cast_frames_read(
                sights: probe_sights,
                message_id: 0x07FF,
              )
                + load_sight.cast_frames_read(
                sights: probe_sights,
                message_id: 0x07FE,
              ),
              minimum: probes * owed * 2,
            ),
          ]
          False -> []
        },
      ]),
      conditions: [
        load_judged.map_keeps_up(
          queued: probe.sum,
          samples: probe.samples,
          running: probe.running,
          players: players_all,
        ),
        load_judged.delay_within_guard(p99_us: summary.p99_us, baseline_p99_us:),
        load_judged.no_frame_after_removal(
          violations: load_sight.frames_after_removal(sights:),
        ),
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
