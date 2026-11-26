//// The movement load run: how the server keeps up when many players on one map
//// move at once, on the real protocol path.
////
//// ```
//// gleam run -m genesis_prime/load_moves                     50 players
//// gleam run -m genesis_prime/load_moves -- 200              200 players
//// gleam run -m genesis_prime/load_moves -- 100 casting      100 players that also cast
//// gleam run -m genesis_prime/load_moves -- 100 34.7         the paired main run's delay 99th, ms
//// gleam run -m genesis_prime/load_moves -- 200 unread       200 players that open no frame
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
//// process running (`load_moves_ffi`), and the reductions it spent while the probes read per
//// move sent in that window. Nothing is traced, so the probe adds only its own reads to the
//// map's work.
////
//// With the word `casting`, the walkers are Espers that press their level-1 ability with a cast
//// time (Telekinetic Strike, `load_player.pressed_spell4_base_id`, cast time 1,250 ms) at
//// `cast_first_ms` after the step begins and again `cast_every_ms` later, so each probe is
//// shown each cast held for its cast time while moves are relayed: the probes read the
//// casts as a 0x7ff, a 0x7f4 and a 0x7fe each, and the run owes each probe the 0x7ff and the
//// 0x7fe of every cast of a walker that finished a settle time before the probes stopped
//// (`load_sight.casts_owed`, `load_player.frames_per_press`).
////
//// With the word `unread`, the walkers drop each frame the server writes them unopened, as
//// the capacity ramp's players do (`load_player.DropFrames`), so the run's own clients do not
//// pay to decrypt and decode every 0x262 of every other player: only the probes read, and
//// the run judges the pairs they are shown and the removals they read, not the walkers'.
////
//// Beside the walkers, `probes` clients of the real protocol join the map and send
//// tagged moves (`genesis_prime/load_move_delay`); the run prints the delay from a
//// probe's send to each other probe's receipt, as its mean and 99th percentile.
////
//// Every walker and probe also keeps what it read of the other players
//// (`genesis_prime/load_sight`): the 0x262 of each other player once, so a run owes
//// (players + probes) x (players + probes - 1) of them, and the frames read for a unit after
//// its 0x355, which the probes' leaving gives each walker to read (walkers x probes removals).
//// The probe in the server's node keeps the map's queue each 10 ms with the
//// messages in its mailbox when it is long (`genesis_prime/load_queue`), and the run prints
//// them with the time from a probe's entry to its last 0x262 of another player, which are
//// printed and not judged.
////
//// The run fails, with exit status 1, when the step's verdict is a failure, when the probes
//// read fewer moves than were sent to them, when a client was shown fewer players than
//// there are pairs, when a casting scene's probes read fewer 0x7ff or 0x7fe of the walkers'
//// casts than they are owed, when the walkers read fewer removals than the probes' leaving
//// gives them, when the map's queue grew or the delay's 99th percentile passed the baseline
//// given on the command line by 50 ms, or when a frame was read after its unit's removal or
//// no removal was read at all: each is judged by `genesis_prime/load_judged`.
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
import gleam/set
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
/// second later), and the time between a walker's presses. Both presses finish, a cast
/// time after each (`load_player.pressed_cast_ms`), `settle_ms` before the probes stop
/// reading, so both are owed.
const cast_first_ms = 11_500

const cast_every_ms = 3000

/// How long before the probes stop reading a cast must have finished for them to owe it.
const settle_ms = 3000

@external(erlang, "load_moves_ffi", "start_probe")
pub fn start_probe(supervisor: process_name) -> Nil

/// What the map showed, as the server's node sampled it.
@external(erlang, "load_moves_ffi", "stop_probe")
pub fn stop_probe() -> Probe

/// What the command line asks for: the walkers, whether they cast, whether they open the
/// frames they are written, and the paired main run's delay 99th percentile in microseconds.
type Run {
  Run(
    players: Int,
    casting: Bool,
    reading: load_player.Reading,
    baseline_p99_us: Option(Int),
  )
}

fn run_of(arguments: List(String)) -> Run {
  case arguments {
    [] ->
      Run(
        players: default_players,
        casting: False,
        reading: load_player.ReadFrames,
        baseline_p99_us: None,
      )
    [number, ..words] -> {
      let run =
        Run(
          players: result.lazy_unwrap(int.parse(number), fn() {
            panic as "the number of players is a whole number"
          }),
          casting: list.contains(words, "casting"),
          reading: case list.contains(words, "unread") {
            True -> load_player.DropFrames
            False -> load_player.ReadFrames
          },
          baseline_p99_us: None,
        )
      case
        list.filter(words, fn(word) { word != "casting" && word != "unread" })
      {
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
        [_, ..] ->
          panic as "the run takes a number, `casting`, `unread` and a baseline"
      }
    }
  }
}

pub fn main() -> Nil {
  let Run(players:, casting:, reading:, baseline_p99_us:) =
    run_of(argv.load().arguments)
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
        True -> [
          begin_ms + cast_first_ms,
          begin_ms + cast_first_ms + cast_every_ms,
        ]
        False -> []
      },
      reading:,
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
  io.println(load_queue.summary(probe:))
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
    <> load_queue.per(total: summary.mean_us, count: 1000)
    <> " ms, 99th percentile "
    <> load_queue.per(total: summary.p99_us, count: 1000)
    <> " ms, longest "
    <> load_queue.per(total: summary.longest_us, count: 1000)
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
  let window_begins_ms = begin_ms + arrival_ms + probes_in_world_ms
  let window_ends_ms = window_begins_ms + probe_window_ms
  let walkers_moves_in_window =
    list.count(
      list.flat_map(outcome.walked, fn(walked) { walked.moved_ms }),
      fn(moved_ms) {
        moved_ms >= window_begins_ms && moved_ms <= window_ends_ms
      },
    )
  let probes_moves =
    int.sum(list.map(reports, fn(report) { dict.size(report.probed.sent_us) }))
  io.println(
    case
      load_queue.reductions_between(
        probe:,
        from_ms: window_begins_ms - probe_started_ms,
        to_ms: window_ends_ms - probe_started_ms,
      )
    {
      Ok(reductions) ->
        "the map's reductions while the probes read: "
        <> int.to_string(reductions)
        <> ", "
        <> load_queue.per(
          total: reductions,
          count: walkers_moves_in_window + probes_moves,
        )
        <> " per move sent ("
        <> int.to_string(walkers_moves_in_window)
        <> " moves of the walkers and "
        <> int.to_string(probes_moves)
        <> " of the probes in the window)"
      Error(Nil) ->
        "the map's reductions while the probes read are not known: the window holds no two samples"
    },
  )
  let shown_after_us =
    list.filter_map(reports, fn(report) {
      option.to_result(report.sight.last_create_us, Nil)
      |> result.map(fn(last_us) { last_us - report.entered_us })
    })
  io.println(
    "a probe's entry to its last player shown: mean "
    <> load_queue.per(
      total: int.sum(shown_after_us),
      count: int.max(1, list.length(shown_after_us)) * 1000,
    )
    <> " ms, 99th percentile "
    <> load_queue.per(
      total: load_step.percentile(values: shown_after_us, percent: 99),
      count: 1000,
    )
    <> " ms, over "
    <> int.to_string(list.length(shown_after_us))
    <> " probes",
  )
  let players_all = players + probes
  let probe_sights = list.map(reports, fn(report) { report.sight })
  let walker_sights =
    list.filter_map(outcome.walked, fn(walked) {
      option.to_result(walked.sight, Nil)
    })
  let sights = list.append(walker_sights, probe_sights)
  let walkers_units =
    set.from_list(list.map(outcome.walked, fn(walked) { walked.unit_id }))
  let probes_units =
    set.from_list(list.map(reports, fn(report) { report.probed.unit_id }))
  let held_us = load_sight.held_us(sights: probe_sights, casters: walkers_units)
  case casting {
    True ->
      io.println(
        "casts of the walkers held at a probe, from its 0x7ff to its 0x7fe: "
        <> int.to_string(list.length(held_us))
        <> " read start to end, shortest "
        <> load_queue.per(
          total: result.unwrap(list.reduce(held_us, int.min), 0),
          count: 1000,
        )
        <> " ms, mean "
        <> load_queue.per(
          total: int.sum(held_us),
          count: int.max(1, list.length(held_us)) * 1000,
        )
        <> " ms (cast time "
        <> int.to_string(load_player.pressed_cast_ms)
        <> " ms)",
      )
    False -> Nil
  }
  let pressed_ms =
    list.flat_map(outcome.walked, fn(walked) {
      list.map(walked.pressed_ms, fn(at_ms) { at_ms - begin_ms })
    })
  let owed =
    load_sight.casts_owed(
      pressed_ms:,
      duration_ms: load_player.pressed_cast_ms,
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
            minimum: case reading {
              load_player.ReadFrames -> players_all * { players_all - 1 }
              load_player.DropFrames -> probes * { players_all - 1 }
            },
          ),
        ],
        case reading {
          load_player.ReadFrames -> [
            Judged(
              event: load_judged.RemovalsRead,
              count: load_sight.removals_read(
                sights: walker_sights,
                of: probes_units,
              ),
              minimum: players * probes,
            ),
          ]
          load_player.DropFrames -> []
        },
        case casting {
          True -> {
            let frames_read = fn(message_id) {
              load_sight.cast_frames_read(
                sights: probe_sights,
                message_id:,
                casters: walkers_units,
              )
            }
            let owed_frames = probes * owed * load_player.frames_per_press
            [
              Judged(
                event: load_judged.CastStartsRead,
                count: frames_read(0x07FF),
                minimum: owed_frames,
              ),
              Judged(
                event: load_judged.CastEndsRead,
                count: frames_read(0x07FE),
                minimum: owed_frames,
              ),
              Judged(
                event: load_judged.CastsHeld,
                count: list.count(held_us, fn(held_us) {
                  held_us >= load_player.pressed_cast_ms * 1000 / 2
                }),
                minimum: owed_frames,
              ),
            ]
          }
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
          removals: load_sight.removals_read(
            sights:,
            of: set.union(walkers_units, probes_units),
          ),
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
