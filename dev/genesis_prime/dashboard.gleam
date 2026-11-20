//// The dashboard: a web page on this Mac that shows how the play server is
//// doing. `gleam run -m genesis_prime/dashboard` in a worktree of main starts
//// it, prints one URL, and serves until it is stopped. The page opens only
//// with the key made at this start (`dashboard/access`, `dashboard/secret`):
//// the URL printed is the one way in.
////
//// ```text
//// start ──► key ──► entry file written (private, not yet published)
////                         │
////          supervisor ────┼── (rebuilt together, poller first)
////                         │     poller of the state script ──► Overview runtimes' readings
////                         │     factory of the Overview's runtimes (one per tab)
////                         ├── (rebuilt together, followers first)
////                         │     follower of each log file ──► Logs runtimes' lines
////                         │     follower of each container's log (reads through podman)
////                         │     factory of the Logs page's runtimes (one per tab)
////                         └── mist on 127.0.0.1:PORT ── web.handle ──► answer
////                                                           │ upgrade of a page
////                                                  websocket ── a runtime of that page, its own
////                         │
////                   entry file published, URL printed
//// ```
////
//// - The settings come from `GENESIS_HOME` (else the user's `.genesis-prime`,
////   as `table_folder.home` says), `GENESIS_DASHBOARD_PORT` (default 7700) and
////   `GENESIS_CLIENT_FILES_DIR` (else `client-files` under the home). The
////   state script is `dev/play_service/state.sh` of the worktree the dashboard
////   runs from; it is run with `GENESIS_HOME` set to the settings' home.
//// - A poller that dies is rebuilt together with the Overview's runtimes, and a
////   log follower that dies with the Logs page's runtimes, whose sockets then
////   close, so every open page reconnects and subscribes again instead of
////   showing its last reading or lines as if they were fresh.
//// - The Logs page follows `play-service.log` and `play-service.launchd.log`
////   inside the settings' home, which the updater's scripts write, and the
////   containers `genesis-play` and `genesis-play-postgres` through `podman`
////   (found on the search path at the start; a start without one shows each
////   container's log as unreadable, with that reason).
//// - The start refuses, with its reason, when the port is busy (two dashboards
////   must not run) and when the key cannot be kept, whether the entry file
////   cannot be written or cannot be published (a key that cannot be kept must
////   not be served).
//// - A websocket's runtime is started only after the gate allows the upgrade,
////   so a refused handshake costs nothing; the runtime is stopped when the
////   socket closes.

import envoy
import genesis_prime/dashboard/access.{type Gate, Gate}
import genesis_prime/dashboard/container_follow
import genesis_prime/dashboard/container_log
import genesis_prime/dashboard/follow
import genesis_prime/dashboard/host
import genesis_prime/dashboard/log_lines
import genesis_prime/dashboard/logs
import genesis_prime/dashboard/overview
import genesis_prime/dashboard/page.{type Page}
import genesis_prime/dashboard/script
import genesis_prime/dashboard/secret
import genesis_prime/dashboard/socket
import genesis_prime/dashboard/subscribers
import genesis_prime/dashboard/web
import genesis_prime/dev_exit
import genesis_prime/step/runtime
import genesis_prime/table_folder
import gleam/bytes_tree
import gleam/crypto
import gleam/erlang/process.{type Pid, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import lustre
import mist.{type Connection, type ResponseData}
import simplifile

/// Where the dashboard listens, keeps its entry file and reads what it serves,
/// which script reports the play service, how often it is read and how long a
/// read may run before it is ended, how often the log files are read, the
/// `podman` program the container logs are read through, how often they are
/// read and how long one call of it may run, and who is told of the log
/// followers' reads and drops (the containers' included).
pub type Settings {
  Settings(
    port: Int,
    genesis_home: String,
    client_fonts_folder: String,
    stylesheet_folder: String,
    state_script: String,
    poll_interval_ms: Int,
    read_deadline_ms: Int,
    log_interval_ms: Int,
    podman_path: String,
    container_interval_ms: Int,
    container_call_deadline_ms: Int,
    log_watcher: Option(Subject(follow.Event)),
  )
}

/// A dashboard that is serving: its gate, its owner process, the factory of
/// each page's runtimes, the poller the Overview subscribes to and the
/// followers of the log files and the containers the Logs page subscribes to.
pub type Running {
  Running(
    gate: Gate,
    owner: Pid,
    runtimes: socket.Runtimes(Subject(host.Message), overview.Message),
    log_runtimes: socket.Runtimes(logs.Followers, logs.Message),
    poller: Subject(host.Message),
    updater_log: Subject(follow.Message),
    launchd_log: Subject(follow.Message),
    server_log: Subject(container_follow.Message),
    database_log: Subject(container_follow.Message),
  )
}

/// Why the dashboard did not start.
pub type StartError {
  ListenerNotStarted(reason: actor.StartError)
  EntryNotKept(reason: secret.EntryError)
}

/// Why the settings could not be read from the environment.
type SettingsError {
  PortNotANumber(text: String)
}

/// What the start says: lines for the log, which never hold the key, and the
/// one line to print, which holds the entry URL.
pub type Report {
  Report(log_lines: List(String), print_line: String)
}

/// The port the dashboard listens on when nothing sets it.
const default_port = 7700

/// The pages of the dashboard, in the order of the navigation.
pub fn pages() -> List(Page) {
  [overview.page(), logs.page()]
}

/// Reads the settings from the environment.
fn settings_from_environment() -> Result(Settings, SettingsError) {
  use port <- result.try(case envoy.get("GENESIS_DASHBOARD_PORT") {
    Error(Nil) -> Ok(default_port)
    Ok(text) -> int.parse(text) |> result.replace_error(PortNotANumber(text:))
  })
  Ok(Settings(
    port:,
    genesis_home: table_folder.home(),
    client_fonts_folder: table_folder.client_files_path() <> "/UI/Fonts",
    stylesheet_folder: "dev/dashboard",
    state_script: "dev/play_service/state.sh",
    poll_interval_ms: host.interval_ms,
    read_deadline_ms: host.deadline_ms,
    log_interval_ms: follow.interval_ms,
    // A name no search finds is run as it is, and its read says it was not found.
    podman_path: result.unwrap(script.find_on_path("podman"), "podman"),
    container_interval_ms: container_follow.interval_ms,
    container_call_deadline_ms: container_follow.call_deadline_ms,
    log_watcher: None,
  ))
}

/// Starts the dashboard, linked to the caller: a new key, the entry file, the
/// page's runtime factory and the web server. A start that returns an error
/// leaves nothing serving and the entry file of an earlier start as it was.
pub fn start(settings settings: Settings) -> Result(Running, StartError) {
  let gate =
    Gate(key: secret.make(crypto.strong_random_bytes), port: settings.port)
  use pending <- result.try(
    secret.prepare_entry(
      home: settings.genesis_home,
      url: access.entry_url(gate),
    )
    |> result.map_error(EntryNotKept),
  )
  let runtimes_name = process.new_name("dashboard_runtimes")
  let poller_name = process.new_name("dashboard_poller")
  let poller = process.named_subject(poller_name)
  let log_runtimes_name = process.new_name("dashboard_log_runtimes")
  let updater_name = process.new_name("dashboard_updater_log")
  let launchd_name = process.new_name("dashboard_launchd_log")
  let server_name = process.new_name("dashboard_server_log")
  let database_name = process.new_name("dashboard_database_log")
  let followers =
    logs.Followers(
      updater: process.named_subject(updater_name),
      launchd: process.named_subject(launchd_name),
      server: process.named_subject(server_name),
      database: process.named_subject(database_name),
    )
  let context =
    web.Context(
      gate:,
      pages: pages(),
      read_file: fn(path) {
        simplifile.read_bits(path) |> result.replace_error(Nil)
      },
      client_fonts_folder: settings.client_fonts_folder,
      stylesheet_folder: settings.stylesheet_folder,
    )
  let server =
    mist.new(fn(request) {
      respond(
        context:,
        served: Served(runtimes_name:, poller:, log_runtimes_name:, followers:),
        request:,
      )
    })
    |> mist.bind(access.loopback)
    |> mist.port(settings.port)
    |> mist.after_start(fn(_port, _scheme, _address) { Nil })
  let poller_settings =
    host.Settings(
      start_read: host.script_reader(
        path: settings.state_script,
        environment: [#("GENESIS_HOME", settings.genesis_home)],
        deadline_ms: settings.read_deadline_ms,
      ),
      now_ms: runtime.monotonic_ms,
      interval_ms: settings.poll_interval_ms,
      deadline_ms: settings.read_deadline_ms,
      arm: subscribers.send_after,
    )
  let log_follower = fn(source) {
    let assert Ok(file_name) = log_lines.file_name(source)
      as "the updater's log and launchd's log are files"
    follow.Settings(
      source:,
      path: settings.genesis_home <> "/" <> file_name,
      reader: follow.file_reader(),
      interval_ms: settings.log_interval_ms,
      arm: subscribers.send_after,
      watcher: settings.log_watcher,
    )
  }
  let container_follower = fn(source) {
    let assert Ok(container) = container_log.container_name(source)
      as "the server's log and the database's are containers'"
    container_follow.Settings(
      source:,
      start_read: container_follow.podman_reader(
        podman: settings.podman_path,
        container:,
        call_deadline_ms: settings.container_call_deadline_ms,
      ),
      interval_ms: settings.container_interval_ms,
      deadline_ms: container_follow.read_deadline_ms(
        call_deadline_ms: settings.container_call_deadline_ms,
      ),
      arm: subscribers.send_after,
      watcher: settings.log_watcher,
    )
  }
  let start_tree = fn() {
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(
      static_supervisor.new(static_supervisor.RestForOne)
      |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
      |> static_supervisor.add(host.supervised(
        settings: poller_settings,
        name: poller_name,
      ))
      |> static_supervisor.add(
        lustre.factory(overview.app())
        |> factory_supervisor.restart_strategy(supervision.Temporary)
        |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)
        |> factory_supervisor.named(runtimes_name)
        |> factory_supervisor.supervised,
      )
      |> static_supervisor.supervised,
    )
    |> static_supervisor.add(
      static_supervisor.new(static_supervisor.RestForOne)
      |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
      |> static_supervisor.add(follow.supervised(
        settings: log_follower(log_lines.UpdaterLog),
        name: updater_name,
      ))
      |> static_supervisor.add(follow.supervised(
        settings: log_follower(log_lines.LaunchdLog),
        name: launchd_name,
      ))
      |> static_supervisor.add(container_follow.supervised(
        settings: container_follower(log_lines.ServerLog),
        name: server_name,
      ))
      |> static_supervisor.add(container_follow.supervised(
        settings: container_follower(log_lines.DatabaseLog),
        name: database_name,
      ))
      |> static_supervisor.add(
        lustre.factory(logs.app())
        |> factory_supervisor.restart_strategy(supervision.Temporary)
        |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)
        |> factory_supervisor.named(log_runtimes_name)
        |> factory_supervisor.supervised,
      )
      |> static_supervisor.supervised,
    )
    |> static_supervisor.add(mist.supervised(server))
    |> static_supervisor.start
  }
  case start_owner(start_tree) {
    Error(reason) -> {
      secret.discard(pending)
      Error(ListenerNotStarted(reason))
    }
    Ok(#(owner, tree)) ->
      case secret.publish(pending) {
        Ok(Nil) ->
          Ok(Running(
            gate:,
            owner:,
            runtimes: factory_supervisor.get_by_name(runtimes_name),
            log_runtimes: factory_supervisor.get_by_name(log_runtimes_name),
            poller:,
            updater_log: followers.updater,
            launchd_log: followers.launchd,
            server_log: followers.server,
            database_log: followers.database,
          ))
        Error(reason) -> {
          stop_tree(owner:, tree:)
          secret.discard(pending)
          Error(EntryNotKept(reason))
        }
      }
  }
}

/// Starts the tree in a process of its own, which traps exits so that a tree
/// that fails to start comes back as an error and not as an exit signal to the
/// caller. The tree stands while the caller lives: the owner ends when the
/// caller or the tree does, and the tree then stops with it. Gives the owner
/// and the tree's supervisor.
fn start_owner(
  start_tree: fn() ->
    Result(actor.Started(static_supervisor.Supervisor), actor.StartError),
) -> Result(#(Pid, Pid), actor.StartError) {
  let caller = process.self()
  let reply = process.new_subject()
  process.spawn_unlinked(fn() {
    process.trap_exits(True)
    case start_tree() {
      Error(reason) -> process.send(reply, Error(reason))
      Ok(started) -> {
        let caller_down = process.monitor(caller)
        process.send(reply, Ok(#(process.self(), started.pid)))
        process.new_selector()
        |> process.select_specific_monitor(caller_down, fn(_down) { Nil })
        |> process.select_trapped_exits(fn(_exit) { Nil })
        |> process.selector_receive_forever
      }
    }
  })
  process.receive_forever(reply)
}

/// Stops a tree that started: ends its owner, the supervisor's parent, and
/// waits until the supervisor has stopped its children, so the port is free
/// when this returns.
fn stop_tree(owner owner: Pid, tree tree: Pid) -> Nil {
  let tree_down = process.monitor(tree)
  process.kill(owner)
  process.new_selector()
  |> process.select_specific_monitor(tree_down, fn(_down) { Nil })
  |> process.selector_receive_forever
}

/// What the start says about a dashboard with this gate.
pub fn start_report(gate gate: Gate) -> Report {
  Report(
    log_lines: [
      "dashboard: serving on "
        <> access.origin(gate.port)
        <> ", for this Mac only",
      "dashboard: the entry URL is in the entry file under the dashboard folder of GENESIS_HOME",
    ],
    print_line: "Open the dashboard: " <> access.entry_url(gate),
  )
}

/// How many page runtimes are alive, of every page.
pub fn runtime_count(running running: Running) -> Int {
  factory_supervisor.count_children(running.runtimes)
  + factory_supervisor.count_children(running.log_runtimes)
}

/// What the pages' runtimes are started with and where their factories are
/// named: the Overview's by the poller, the Logs page's by the log followers.
type Served {
  Served(
    runtimes_name: process.Name(
      factory_supervisor.Message(
        Subject(host.Message),
        Subject(lustre.RuntimeMessage(overview.Message)),
      ),
    ),
    poller: Subject(host.Message),
    log_runtimes_name: process.Name(
      factory_supervisor.Message(
        logs.Followers,
        Subject(lustre.RuntimeMessage(logs.Message)),
      ),
    ),
    followers: logs.Followers,
  )
}

fn respond(
  context context: web.Context,
  served served: Served,
  request request: Request(Connection),
) -> Response(ResponseData) {
  case web.handle(context, request) {
    web.Answer(answer) ->
      response.map(answer, fn(body) {
        mist.Bytes(bytes_tree.from_bit_array(body))
      })
    web.Upgrade(upgraded_page) ->
      case upgraded_page.key {
        page.OverviewKey ->
          upgraded(
            runtimes_name: served.runtimes_name,
            argument: served.poller,
            request:,
          )
        page.LogsKey ->
          upgraded(
            runtimes_name: served.log_runtimes_name,
            argument: served.followers,
            request:,
          )
      }
  }
}

/// The websocket of a page whose runtimes are in the factory named
/// `runtimes_name`.
fn upgraded(
  runtimes_name runtimes_name: process.Name(
    factory_supervisor.Message(
      argument,
      Subject(lustre.RuntimeMessage(message)),
    ),
  ),
  argument argument: argument,
  request request: Request(Connection),
) -> Response(ResponseData) {
  let rebuilding = fn() {
    response.new(503) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
  case process.named(runtimes_name) {
    Ok(_) ->
      case
        socket.upgrade(
          request:,
          runtimes: factory_supervisor.get_by_name(runtimes_name),
          argument:,
        )
      {
        Ok(upgraded) -> upgraded
        // A runtime that did not start, as a factory that ended does not start
        // one: the client asks again.
        Error(Nil) -> rebuilding()
      }
    // The page runtimes are being rebuilt; the client asks again.
    Error(Nil) -> rebuilding()
  }
}

/// Starts the dashboard, prints its URL and serves until the VM stops.
pub fn main() -> Nil {
  case settings_from_environment() {
    Error(PortNotANumber(text)) ->
      fail("GENESIS_DASHBOARD_PORT is not a number: " <> text)
    Ok(settings) ->
      case start(settings:) {
        Error(error) -> fail(describe(error, settings))
        Ok(running) -> {
          let report = start_report(gate: running.gate)
          list.each(report.log_lines, io.println_error)
          io.println(report.print_line)
          // The dashboard serves until its owner ends.
          let owner_down = process.monitor(running.owner)
          process.new_selector()
          |> process.select_specific_monitor(owner_down, fn(_down) { Nil })
          |> process.selector_receive_forever
          fail("the dashboard stopped")
        }
      }
  }
}

fn fail(message: String) -> Nil {
  io.println_error("dashboard: " <> message)
  dev_exit.halt(1)
}

fn describe(error: StartError, settings: Settings) -> String {
  case error {
    ListenerNotStarted(_) ->
      "could not listen on "
      <> access.loopback
      <> ":"
      <> int.to_string(settings.port)
      <> "; another dashboard may be running, or GENESIS_DASHBOARD_PORT names a port in use"
    EntryNotKept(secret.FolderNotPrepared(folder:, reason:)) ->
      "could not make "
      <> folder
      <> " private: "
      <> simplifile.describe_error(reason)
    EntryNotKept(secret.FileNotWritten(path:, reason:))
    | EntryNotKept(secret.FileNotPublished(path:, reason:)) ->
      "could not write " <> path <> ": " <> simplifile.describe_error(reason)
  }
}
