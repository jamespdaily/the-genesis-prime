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
////                         │     poller of the state script ──► page runtimes' readings
////                         │     factory of the page's runtimes (one per tab)
////                         └── mist on 127.0.0.1:PORT ── web.handle ──► answer
////                                                           │ upgrade
////                                                  websocket ── a runtime of its own
////                         │
////                   entry file published, URL printed
//// ```
////
//// - The settings come from `GENESIS_HOME` (else the user's `.genesis-prime`,
////   as `table_folder.home` says), `GENESIS_DASHBOARD_PORT` (default 7700) and
////   `GENESIS_CLIENT_FILES_DIR` (else `client-files` under the home). The
////   state script is `dev/play_service/state.sh` of the worktree the dashboard
////   runs from; it is run with `GENESIS_HOME` set to the settings' home.
//// - A poller that dies is rebuilt together with the page runtimes, whose
////   sockets then close, so every open page reconnects and subscribes again
////   instead of showing its last reading as if it were fresh.
//// - The start refuses, with its reason, when the port is busy (two dashboards
////   must not run) and when the key cannot be kept, whether the entry file
////   cannot be written or cannot be published (a key that cannot be kept must
////   not be served).
//// - A websocket's runtime is started only after the gate allows the upgrade,
////   so a refused handshake costs nothing; the runtime is stopped when the
////   socket closes.

import envoy
import genesis_prime/dashboard/access.{type Gate, Gate}
import genesis_prime/dashboard/host
import genesis_prime/dashboard/overview
import genesis_prime/dashboard/page.{type Page}
import genesis_prime/dashboard/secret
import genesis_prime/dashboard/socket
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
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import lustre
import mist.{type Connection, type ResponseData}
import simplifile

/// Where the dashboard listens, keeps its entry file and reads what it serves,
/// and which script reports the play service and how often.
pub type Settings {
  Settings(
    port: Int,
    genesis_home: String,
    client_fonts_folder: String,
    stylesheet_folder: String,
    state_script: String,
    poll_interval_ms: Int,
  )
}

/// A dashboard that is serving: its gate, its owner process, the factory of
/// the page runtimes and the poller the pages subscribe to.
pub type Running {
  Running(
    gate: Gate,
    owner: Pid,
    runtimes: socket.Runtimes,
    poller: Subject(host.Message),
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
fn pages() -> List(Page) {
  [overview.page()]
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
      respond(context:, runtimes_name:, poller:, request:)
    })
    |> mist.bind(access.loopback)
    |> mist.port(settings.port)
    |> mist.after_start(fn(_port, _scheme, _address) { Nil })
  let poller_settings =
    host.Settings(
      start_read: host.script_reader(
        path: settings.state_script,
        environment: [#("GENESIS_HOME", settings.genesis_home)],
        deadline_ms: host.deadline_ms,
      ),
      now_ms: runtime.monotonic_ms,
      interval_ms: settings.poll_interval_ms,
      deadline_ms: host.deadline_ms,
    )
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
            poller:,
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

/// How many page runtimes are alive.
pub fn runtime_count(running running: Running) -> Int {
  factory_supervisor.count_children(running.runtimes)
}

fn respond(
  context context: web.Context,
  runtimes_name runtimes_name: process.Name(
    factory_supervisor.Message(
      Subject(host.Message),
      Subject(lustre.RuntimeMessage(overview.Message)),
    ),
  ),
  poller poller: Subject(host.Message),
  request request: Request(Connection),
) -> Response(ResponseData) {
  case web.handle(context, request) {
    web.Answer(answer) ->
      response.map(answer, fn(body) {
        mist.Bytes(bytes_tree.from_bit_array(body))
      })
    web.Upgrade ->
      case process.named(runtimes_name) {
        Ok(_) ->
          socket.upgrade(
            request:,
            runtimes: factory_supervisor.get_by_name(runtimes_name),
            poller:,
          )
        // The page runtimes are being rebuilt; the client asks again.
        Error(Nil) ->
          response.new(503)
          |> response.set_body(mist.Bytes(bytes_tree.new()))
      }
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
