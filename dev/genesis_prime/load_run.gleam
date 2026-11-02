//// The load run: finds how many players the server keeps up with on the real
//// protocol path, and what breaks first.
////
//// ```
//// gleam run -m genesis_prime/load_run
//// ```
////
//// The environment is the server's own (`genesis_prime`): PGHOST, PGPORT,
//// PGUSER, PGPASSWORD and PGDATABASE name a migrated database that is empty of
//// accounts (the run seeds `load-0`, `load-1`, ...), GENESIS_TABLE_DIR the
//// client's tables, GENESIS_GAME_ADDRESS (127.0.0.1) and GENESIS_REALM_NAME. The
//// server's ports are the client's defaults, so no server may be running.
////
//// ```
////  this node (the load clients, 4 schedulers)        peer node (the server, all cores)
////   players: login, create, enter, ping  ── TCP ──▶   STS, auth and game listeners
////   one sample a second  ◀── peer call ──────────     genesis_prime/load_sample
//// ```
////
//// A ramp starts the server in a node of its own with every listener's cap
//// raised, so no cap is what the run finds, and then goes through steps of
//// 50, 100, 200 ... up to 12,800 players. A step seeds a fresh account for each
//// player, has the players arrive evenly over 10 s (or at 500 a second, when
//// that is longer: this Mac's accept queue overflowed at 4,000 connects at
//// once), hold for 30 s, pinging, and leave; the run then waits for the
//// connections to close and the closed sockets to leave TIME_WAIT. A step is
//// judged by `genesis_prime/load_step`: kept, failed (on which lines), or
//// limited by the clients. The first step that is not kept is followed by one
//// step halfway back to the last that was, rounded to 50, and the ramp ends.
//// Its maximum is the most players of any step that was kept. The run makes two
//// ramps, each on a server of its own, and reports the lower maximum.
////
//// The clients share the machine with the server: macOS cannot pin cores, so
//// the clients' node is limited to four schedulers and each step reports how
//// much of them the clients used. Each player holds three sockets from this
//// machine's 16,384 local ports (49152 to 65535), so the ports are the clients'
//// limit at about 5,400 players, and a player that finds none (`eaddrnotavail`)
//// makes its step clients-limited.

import genesis_prime
import genesis_prime/application
import genesis_prime/load_player.{type Account, type Report, type Stage}
import genesis_prime/load_sample.{type Sample}
import genesis_prime/load_step.{
  type Observation, type Verdict, Kept, Observation,
}
import genesis_prime/readiness
import genesis_prime/server
import genesis_prime/step/runtime
import genesis_prime/store/worker
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import login_client.{type Ports, Ports}
import pog

/// A player that did not finish its path: the stage it was at, or none when it
/// failed while pinging, and what stopped it.
pub type Failure {
  Failure(player: Int, at: Option(Stage), reason: String)
}

/// What one step of players showed.
pub type Outcome {
  Outcome(
    observation: Observation,
    failures: List(Failure),
    /// For each player that finished its path, its stages in order, each with
    /// the milliseconds it took.
    stage_times: List(List(#(Stage, Int))),
  )
}

/// What a step's collector hears.
type Heard {
  Told(Report)
  Ended(process.Down)
}

/// A step's collector: what the players have told it and what it has sampled.
type Collecting {
  Collecting(
    selector: process.Selector(Heard),
    players: Dict(Pid, Int),
    reached: Dict(Int, List(#(Stage, Int))),
    trips: List(List(Int)),
    lag_ms: Int,
    failures: List(Failure),
    unconnected: Int,
    pending: Int,
    server: List(Sample),
    clients: List(Sample),
    next_sample_ms: Int,
    until_ms: Int,
    sampling: Bool,
    sample_server: fn() -> Sample,
  )
}

/// The ports the server listens on, the client's defaults.
const ports = Ports(sts_port: 6600, auth_port: 23_115, game_port: 24_000)

/// How many connections each listener may hold during the run: more than the
/// run reaches.
const cap_for_the_run = 1_000_000

const first_players = 50

const most_players = 12_800

/// The most players that begin in a second: this Mac's accept queue overflowed
/// when 4,000 connects came at once and held at 500 a second.
const arrivals_per_second = 500

const hold_ms = 30_000

/// How often the nodes are sampled, in milliseconds.
const sample_every_ms = 1000

/// Plays one step on the server at `ports`: a player for each account, arriving
/// evenly over `arrival_ms`, pinging until `hold_ms` after the last arrives.
/// `sample_server` reads the server once a second; the clients' own node is
/// read here. Gives what the players and the samples showed.
pub fn run_step(
  ports ports: Ports,
  accounts accounts: List(Account),
  arrival_ms arrival_ms: Int,
  hold_ms hold_ms: Int,
  sample_server sample_server: fn() -> Sample,
) -> Outcome {
  let report = process.new_subject()
  let count = list.length(accounts)
  let started_ms = load_sample.milliseconds()
  let until_ms = started_ms + arrival_ms + hold_ms
  let players =
    list.index_map(accounts, fn(account, player) {
      let pid =
        process.spawn_unlinked(fn() {
          load_player.play(
            player:,
            account:,
            ports:,
            begin_at_ms: started_ms + player * arrival_ms / int.max(count, 1),
            until_ms:,
            report:,
          )
        })
      let _monitor = process.monitor(pid)
      #(pid, player)
    })
  let collecting =
    Collecting(
      selector: process.new_selector()
        |> process.select_map(report, Told)
        |> process.select_monitors(Ended),
      players: dict.from_list(players),
      reached: dict.new(),
      trips: [],
      lag_ms: 0,
      failures: [],
      unconnected: 0,
      pending: count,
      server: [],
      clients: [],
      next_sample_ms: started_ms,
      until_ms:,
      sampling: True,
      sample_server:,
    )
  collect(collecting) |> outcome
}

/// Hears the players and samples the nodes until every player has ended and the
/// last sample, at the end of the hold, is taken.
fn collect(collecting: Collecting) -> Collecting {
  let collecting = case
    collecting.sampling
    && {
      collecting.pending == 0
      || load_sample.milliseconds() >= collecting.next_sample_ms
    }
  {
    True -> sample(collecting)
    False -> collecting
  }
  case collecting.pending == 0 && !collecting.sampling {
    True -> collecting
    False -> {
      let wait = case collecting.sampling {
        True ->
          int.max(1, collecting.next_sample_ms - load_sample.milliseconds())
        False -> 1000
      }
      case process.selector_receive(from: collecting.selector, within: wait) {
        Ok(heard) -> collect(hear(collecting, heard))
        Error(Nil) -> collect(collecting)
      }
    }
  }
}

/// Reads both nodes. The sample at or after the end of the hold, or after the
/// last player ended, is the last.
fn sample(collecting: Collecting) -> Collecting {
  let now = load_sample.milliseconds()
  let last = now >= collecting.until_ms || collecting.pending == 0
  Collecting(
    ..collecting,
    server: [collecting.sample_server(), ..collecting.server],
    clients: [load_sample.take_node(), ..collecting.clients],
    next_sample_ms: int.min(
      collecting.next_sample_ms + sample_every_ms,
      collecting.until_ms,
    ),
    sampling: !last,
  )
}

fn hear(collecting: Collecting, heard: Heard) -> Collecting {
  case heard {
    Told(load_player.Begun(lag_ms:, ..)) ->
      Collecting(..collecting, lag_ms: int.max(collecting.lag_ms, lag_ms))
    Told(load_player.Reached(player:, stage:, took_ms:)) ->
      Collecting(
        ..collecting,
        reached: dict.upsert(collecting.reached, player, fn(stages) {
          [#(stage, took_ms), ..option.unwrap(stages, [])]
        }),
      )
    Told(load_player.Finished(round_trips_us:, ..)) ->
      Collecting(..collecting, trips: [round_trips_us, ..collecting.trips])
    Ended(process.ProcessDown(pid:, reason: process.Normal, ..)) ->
      Collecting(
        ..collecting,
        players: dict.delete(collecting.players, pid),
        pending: collecting.pending - 1,
      )
    Ended(process.ProcessDown(pid:, reason:, ..)) -> {
      let assert Ok(player) = dict.get(collecting.players, pid)
        as "a player that ended was one the step started"
      let done = list.length(reached_of(collecting, player))
      let reason = describe_exit(reason)
      let collecting =
        Collecting(
          ..collecting,
          players: dict.delete(collecting.players, pid),
          pending: collecting.pending - 1,
        )
      case string.contains(reason, "eaddrnotavail") {
        True ->
          Collecting(..collecting, unconnected: collecting.unconnected + 1)
        False ->
          Collecting(..collecting, failures: [
            Failure(
              player:,
              at: list.drop(load_player.stages(), done)
                |> list.first
                |> option.from_result,
              reason:,
            ),
            ..collecting.failures
          ])
      }
    }
    Ended(process.PortDown(..)) -> collecting
  }
}

fn reached_of(collecting: Collecting, player: Int) -> List(#(Stage, Int)) {
  case dict.get(collecting.reached, player) {
    Ok(stages) -> list.reverse(stages)
    Error(Nil) -> []
  }
}

fn outcome(collecting: Collecting) -> Outcome {
  let finished =
    list.filter_map(dict.keys(collecting.reached), fn(player) {
      let stages = reached_of(collecting, player)
      case list.length(stages) == list.length(load_player.stages()) {
        True -> Ok(stages)
        False -> Error(Nil)
      }
    })
  Outcome(
    observation: Observation(
      failures: list.length(collecting.failures),
      login_to_world_ms: list.map(finished, fn(stages) {
        list.take(stages, 6) |> list.map(fn(stage) { stage.1 }) |> int.sum
      }),
      ping_round_trip_us: list.flatten(collecting.trips),
      server: list.reverse(collecting.server),
      clients: list.reverse(collecting.clients),
      unconnected: collecting.unconnected,
      start_lag_ms: collecting.lag_ms,
    ),
    failures: list.sort(collecting.failures, fn(first, second) {
      int.compare(first.player, second.player)
    }),
    stage_times: finished,
  )
}

/// The ramp's next step, from the steps so far in order: the first doubles from
/// 50 players to 12,800; the first that is not kept is followed by one halfway
/// back to the last that was, rounded to 50, and then none.
fn next_players(history: List(#(Int, Verdict))) -> Option(Int) {
  case list.reverse(history) {
    [] -> Some(first_players)
    [#(players, verdict), ..earlier] ->
      case verdict == Kept, list.any(earlier, fn(step) { step.1 != Kept }) {
        True, False if players * 2 <= most_players -> Some(players * 2)
        False, False -> {
          let middle = { maximum(history) + players } / 2 / 50 * 50
          case middle > maximum(history) && middle < players {
            True -> Some(middle)
            False -> None
          }
        }
        _, _ -> None
      }
  }
}

/// The most players of any step that was kept, 0 when none was.
fn maximum(history: List(#(Int, Verdict))) -> Int {
  history
  |> list.filter(fn(step) { step.1 == Kept })
  |> list.fold(0, fn(most, step) { int.max(most, step.0) })
}

/// Runs in the server's node: starts the server's tree as `gleam run` does, on
/// the database the environment names, with every listener's cap raised for the
/// run, waits until the database answers and its migrations are the files', and
/// gives what the sampler watches.
fn start_server() -> load_sample.Watch {
  log_to_null()
  runtime.show_info_lines()
  runtime.keep_mailboxes_out_of_crash_reports()
  load_sample.start()
  let #(tables, _count) = genesis_prime.load_tables()
  let settings = genesis_prime.settings(tables:)
  let login = settings.login
  let settings =
    server.Settings(
      ..settings,
      login: server.Login(
        sts: server.Served(..login.sts, max_connections: cap_for_the_run),
        auth: server.Served(..login.auth, max_connections: cap_for_the_run),
      ),
      game: server.Served(..settings.game, max_connections: cap_for_the_run),
    )
  let assert Ok(tree) = application.start_server(settings:)
    as "the supervision tree started"
  let assert readiness.Ready =
    readiness.await(
      probe: fn(reply) { worker.probe(store: settings.store, reply:) },
      tree: tree.monitor,
      settings: readiness.Settings(
        within_ms: 30_000,
        attempt_ms: 2000,
        pause_ms: 250,
      ),
      files: genesis_prime.load_migrations(),
    )
    as "the database answered and holds the migrations the build has"
  load_sample.Watch(
    listeners: [
      settings.login.sts.listener,
      settings.login.auth.listener,
      settings.game.listener,
    ],
    store: settings.store,
    pool_size: genesis_prime.pool_settings.pool_size,
  )
}

/// The server's node, started by `start_peer`.
type Peer

@external(erlang, "load_run_ffi", "start_peer")
fn start_peer() -> Peer

@external(erlang, "load_run_ffi", "stop_peer")
fn stop_peer(peer: Peer) -> Nil

@external(erlang, "load_run_ffi", "start_server")
fn start_server_in(
  peer: Peer,
  start: fn() -> load_sample.Watch,
) -> load_sample.Watch

@external(erlang, "load_run_ffi", "sample")
fn sample_of(peer: Peer, watch: load_sample.Watch) -> Sample

@external(erlang, "load_run_ffi", "log_to_null")
fn log_to_null() -> Nil

@external(erlang, "load_run_ffi", "limit_schedulers")
fn limit_schedulers(count: Int) -> Nil

@external(erlang, "load_run_ffi", "silence_crash_reports")
fn silence_crash_reports() -> Nil

@external(erlang, "load_run_ffi", "describe_exit")
fn describe_exit(reason: process.ExitReason) -> String

/// How many schedulers the clients' node has.
const client_schedulers = 4

/// How long the run waits after a step for the closed sockets to leave
/// TIME_WAIT, which holds each one's local port for twice this machine's maximum
/// segment lifetime (`sysctl net.inet.tcp.msl`, 15 s), in milliseconds. Left
/// held, they take the ports the next step's players connect from.
const settle_ms = 35_000

/// How long the run waits for a step's connections to close before it goes on,
/// in milliseconds.
const drain_ms = 60_000

pub fn main() -> Nil {
  limit_schedulers(client_schedulers)
  silence_crash_reports()
  load_sample.start()
  io.println(
    "clients: "
    <> int.to_string(client_schedulers)
    <> " schedulers; the server: all cores of this machine",
  )
  let maxima = list.map([1, 2], ramp)
  io.println(
    "maximum of each ramp: "
    <> string.join(list.map(maxima, int.to_string), ", ")
    <> "; the run's maximum is the lower",
  )
}

/// One ramp on a server of its own, printing each step; its maximum.
fn ramp(run: Int) -> Int {
  io.println("ramp " <> int.to_string(run))
  let peer = start_peer()
  let watch = start_server_in(peer, start_server)
  let assert Ok(started) = pog.start(genesis_prime.pool())
    as "the pool for the accounts started"
  let history =
    climb(
      peer:,
      watch:,
      pool: started.data,
      first_account: { run - 1 } * most_players * 4,
      history: [],
    )
  stop_peer(peer)
  let most = maximum(history)
  io.println(
    "ramp " <> int.to_string(run) <> " maximum: " <> int.to_string(most),
  )
  most
}

fn climb(
  peer peer: Peer,
  watch watch: load_sample.Watch,
  pool pool: pog.Connection,
  first_account first_account: Int,
  history history: List(#(Int, Verdict)),
) -> List(#(Int, Verdict)) {
  case next_players(history) {
    None -> history
    Some(players) -> {
      let accounts = load_player.accounts(first: first_account, count: players)
      load_player.seed(pool:, accounts:)
      let arrival_ms = int.max(10_000, players * 1000 / arrivals_per_second)
      let outcome =
        run_step(ports:, accounts:, arrival_ms:, hold_ms:, sample_server: fn() {
          sample_of(peer, watch)
        })
      let verdict = load_step.judge(outcome.observation)
      io.println(describe(players:, arrival_ms:, outcome:, verdict:))
      await_drain(peer, watch)
      process.sleep(settle_ms)
      climb(
        peer:,
        watch:,
        pool:,
        first_account: first_account + players,
        history: list.append(history, [#(players, verdict)]),
      )
    }
  }
}

/// Waits until the server holds no connection, as the players' ending closes
/// them, up to a minute.
fn await_drain(peer: Peer, watch: load_sample.Watch) -> Nil {
  drain(peer:, watch:, until_ms: load_sample.milliseconds() + drain_ms)
}

fn drain(
  peer peer: Peer,
  watch watch: load_sample.Watch,
  until_ms until_ms: Int,
) -> Nil {
  let held = list.fold(sample_of(peer, watch).connections, 0, int.add)
  case held > 0 && load_sample.milliseconds() < until_ms {
    True -> {
      process.sleep(500)
      drain(peer:, watch:, until_ms:)
    }
    False -> Nil
  }
}

/// One step as the lines the run prints: its players, its verdict, its numbers,
/// the processes whose mailbox never emptied, and how many players ended with
/// each reason and at which stage.
fn describe(
  players players: Int,
  arrival_ms arrival_ms: Int,
  outcome outcome: Outcome,
  verdict verdict: Verdict,
) -> String {
  let observation = outcome.observation
  let server = observation.server
  let clients = observation.clients
  let peak = fn(samples: List(Sample), value: fn(Sample) -> Int) {
    list.fold(samples, 0, fn(most, sample) { int.max(most, value(sample)) })
  }
  let connections = fn(index) {
    peak(server, fn(sample) {
      list.drop(sample.connections, index) |> list.first |> result.unwrap(0)
    })
  }
  let cores = fn(samples: List(Sample)) {
    case samples, list.last(samples) {
      [first, ..], Ok(last) ->
        float.round(100.0 *. load_sample.use_between(first:, last:))
      _, _ -> 0
    }
  }
  let logins = observation.login_to_world_ms
  let pings = observation.ping_round_trip_us
  let numbers = [
    #("failed", observation.failures),
    #(
      "login-to-world p50 ms",
      load_step.percentile(values: logins, percent: 50),
    ),
    #("p99 ms", load_step.percentile(values: logins, percent: 99)),
    #("ping p50 us", load_step.percentile(values: pings, percent: 50)),
    #("p99 us", load_step.percentile(values: pings, percent: 99)),
    #("sts connections", connections(0)),
    #("auth", connections(1)),
    #("game", connections(2)),
    #("longest mailbox", peak(server, longest_mailbox)),
    #("processes waiting", peak(server, fn(s) { list.length(s.waiting) })),
    #("largest heap words", peak(server, fn(s) { s.largest_heap_words })),
    #("server cores %", cores(server)),
    #("run queue", peak(server, fn(s) { s.run_queue })),
    #("store workers waiting", peak(server, fn(s) { s.store_waiting })),
    #("worker start us", peak(server, fn(s) { s.worker_start_us })),
    #("memory MB", peak(server, fn(s) { s.memory_bytes }) / 1_000_000),
    #("log lines", log_lines(server)),
    #("clients cores %", cores(clients)),
    #("clients run queue", peak(clients, fn(s) { s.run_queue })),
    #("start lag ms", observation.start_lag_ms),
    #("players with no local port", observation.unconnected),
  ]
  let stuck =
    list.map(load_step.never_empty(server), fn(waiting) {
      "\n  never empty: " <> waiting.described
    })
  let ended =
    list.group(outcome.failures, fn(failure) { failure.reason })
    |> dict.to_list
    |> list.map(fn(group) {
      let assert [first, ..] = group.1 as "a group has a member"
      "\n  "
      <> int.to_string(list.length(group.1))
      <> " players at "
      <> option.map(first.at, load_player.describe)
      |> option.unwrap("the pings")
      <> ": "
      <> group.0
    })
  "players "
  <> int.to_string(players)
  <> " (arriving over "
  <> int.to_string(arrival_ms / 1000)
  <> " s): "
  <> load_step.describe(verdict)
  <> "\n  "
  <> string.join(
    list.map(numbers, fn(number) { number.0 <> " " <> int.to_string(number.1) }),
    "; ",
  )
  <> string.join(list.append(stuck, ended), "")
}

fn longest_mailbox(sample: Sample) -> Int {
  list.fold(sample.waiting, 0, fn(longest, waiting) {
    int.max(longest, waiting.mailbox)
  })
}

/// The warning and error lines the server logged during the step.
fn log_lines(samples: List(Sample)) -> Int {
  case samples, list.last(samples) {
    [first, ..], Ok(last) -> last.log_lines - first.log_lines
    _, _ -> 0
  }
}
