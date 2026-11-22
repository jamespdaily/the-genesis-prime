//// The dashboard as a whole: its start and its refusals, and what a browser
//// fetches from it on a free loopback port. Expected values are the gate's
//// rule (no answer without this start's key), the start's rule (two
//// dashboards must not run, and a key that cannot be kept must not be
//// served) and the listener's rule (the loopback address only).

import dashboard_otp_log_support as otp_support
import dashboard_support
import event_wait
import frame_peer
import genesis_prime/dashboard
import genesis_prime/dashboard/access
import genesis_prime/dashboard/follow
import genesis_prime/dashboard/host_reading.{type Reading}
import genesis_prime/dashboard/log_lines
import genesis_prime/dashboard/overview.{Model}
import genesis_prime/dashboard/read_poll
import genesis_prime/dashboard/secret
import genesis_prime/dashboard/socket
import gleam/bit_array
import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import open_wait
import owned_test
import play_service_support.{Answer} as support
import simplifile

fn started(settings: dashboard.Settings) -> dashboard.Running {
  let assert Ok(running) = dashboard.start(settings)
    as "the dashboard did not start"
  running
}

pub fn the_start_report_prints_the_key_once_and_logs_it_never_test() -> Nil {
  use <- owned_test.run(5000)
  let gate = dashboard_support.gate()
  let report = dashboard.start_report(gate)
  assert string.contains(
    report.print_line,
    "http://127.0.0.1:7700/k/" <> dashboard_support.key <> "/",
  )
  assert report.log_lines != [] as "the start logs that it serves"
  list.each(report.log_lines, fn(line) {
    assert !string.contains(line, dashboard_support.key)
      as "a log line holds the key"
  })
}

pub fn a_busy_port_or_an_unwritable_key_folder_stops_the_dashboard_with_its_reason_test() -> Nil {
  use <- owned_test.run(5000)

  // The port is already listened on: no second dashboard, and the first's
  // entry file is left as it was.
  use home <- dashboard_support.with_home
  let #(_listener, busy) = frame_peer.listen()
  let settings =
    dashboard.Settings(..dashboard_support.settings(home), port: busy)
  let assert Ok(Nil) = simplifile.create_directory_all(home <> "/dashboard")
  let assert Ok(Nil) = simplifile.write(secret.entry_path(home), "first start")
  let assert Error(dashboard.ListenerNotStarted(_)) = dashboard.start(settings)
  assert simplifile.read(secret.entry_path(home)) == Ok("first start")

  // The key folder is a file.
  use other <- dashboard_support.with_home
  let assert Ok(Nil) = simplifile.write(other <> "/dashboard", "not a folder")
  let settings = dashboard_support.settings(other)
  let assert Error(dashboard.EntryNotKept(secret.FolderNotPrepared(..))) =
    dashboard.start(settings)
  assert !dashboard_support.accepts(settings.port)
    as "a key that cannot be kept is not served"

  // The folder the key folder lives in cannot be written, so it cannot be made.
  use closed <- dashboard_support.with_home
  let assert Ok(Nil) = simplifile.set_permissions_octal(closed, 0o500)
  let settings = dashboard_support.settings(closed)
  let result = dashboard.start(settings)
  let assert Ok(Nil) = simplifile.set_permissions_octal(closed, 0o700)
  let assert Error(dashboard.EntryNotKept(secret.FolderNotPrepared(..))) =
    result
  assert !dashboard_support.accepts(settings.port)
    as "a key that cannot be kept is not served"

  // The entry file cannot be published (a folder stands where it goes): the
  // dashboard that had started is stopped, and no pending file is left.
  use unpublishable <- dashboard_support.with_home
  let assert Ok(Nil) =
    simplifile.create_directory_all(secret.entry_path(unpublishable))
  let settings = dashboard_support.settings(unpublishable)
  let assert Error(dashboard.EntryNotKept(secret.FileNotPublished(..))) =
    dashboard.start(settings)
  assert !dashboard_support.accepts(settings.port)
    as "a key that cannot be kept is not served"
  assert simplifile.is_file(secret.entry_path(unpublishable) <> ".pending")
    == Ok(False)
    as "the pending entry file is removed"
}

pub fn the_dashboard_binds_the_loopback_address_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert access.loopback == "127.0.0.1"
  use home <- dashboard_support.with_home
  let settings = dashboard_support.settings(home)
  let _running = started(settings)
  assert dashboard_support.accepts(settings.port)
  // A socket bound to every address would show 0.0.0.0, and one bound to the
  // machine's network address that address.
  assert dashboard_support.bound_addresses(settings.port) == ["127.0.0.1"]
}

pub fn a_page_without_the_client_files_folder_falls_back_to_system_fonts_test() -> Nil {
  use <- owned_test.run(5000)
  use home <- dashboard_support.with_home
  let settings = dashboard_support.settings(home)
  let _running = started(settings)
  let prefix = "/k/" <> dashboard_support.written_key(home)
  let headers = dashboard_support.browser(port: settings.port)

  let font =
    dashboard_support.send(
      settings.port,
      prefix <> "/art/cube-cond.ttf",
      headers,
    )
  assert font.status == 404
  let page = dashboard_support.send(settings.port, prefix <> "/", headers)
  assert page.status == 200
  assert string.contains(result_text(page.body), "lustre-server-component")

  // Each font role in the palette ends in a family every system has.
  let assert Ok(palette) = simplifile.read("dev/dashboard/palette.css")
  let font_lines =
    string.split(palette, "\n")
    |> list.filter(fn(line) { string.contains(line, "--font-") })
  assert list.length(font_lines) == 3
  list.each(font_lines, fn(line) {
    let families =
      string.split(string.trim(line), ",")
      |> list.map(fn(family) { string.trim(string.replace(family, ";", "")) })
    let assert Ok(last) = list.last(families)
    assert list.contains(["sans-serif", "monospace", "serif"], last) as line
  })
}

fn result_text(body: BitArray) -> String {
  let assert Ok(text) = bit_array.to_string(body)
  text
}

pub fn the_dashboard_serves_the_page_the_stylesheets_and_a_font_with_the_key_test() -> Nil {
  use <- owned_test.run(5000)
  use home <- dashboard_support.with_home
  let font_bytes = <<"planted font bytes":utf8>>
  let assert Ok(Nil) =
    simplifile.create_directory_all(home <> "/client-files/UI/Fonts")
  let assert Ok(Nil) =
    simplifile.write_bits(
      home <> "/client-files/UI/Fonts/CubeOffcCond.ttf",
      font_bytes,
    )
  let settings = dashboard_support.settings(home)
  let _running = started(settings)
  let prefix = "/k/" <> dashboard_support.written_key(home)
  let port = settings.port
  let headers = dashboard_support.browser(port:)

  // The entry URL is the page, and every link on it stays under the prefix.
  let page = dashboard_support.send(port, prefix <> "/", headers)
  assert page.status == 200
  let text = result_text(page.body)
  assert string.contains(text, "lustre-server-component")
  assert string.contains(text, "route=\"ws\"")
  assert string.contains(text, "href=\"palette.css\"")
  assert string.contains(text, "href=\"style.css\"")
  assert dashboard_support.send(port, prefix <> "/palette.css", headers).status
    == 200
  let style = dashboard_support.send(port, prefix <> "/style.css", headers)
  assert style.status == 200
  assert !string.contains(result_text(style.body), "url(\"/")
    as "a font url that starts at the root leaves the key prefix"
  let font =
    dashboard_support.send(port, prefix <> "/art/cube-cond.ttf", headers)
  assert font.status == 200
  assert font.body == font_bytes

  // No answer sets a cookie.
  list.each([page, style, font], fn(reply) {
    assert dashboard_support.header(reply:, name: "set-cookie") == None
  })
}

pub fn every_route_and_the_websocket_refuse_without_the_key_and_a_refused_upgrade_starts_no_runtime_test() -> Nil {
  use <- owned_test.run(5000)
  use home <- dashboard_support.with_home
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let port = settings.port
  let key = dashboard_support.written_key(home)
  let origin = "http://127.0.0.1:" <> int.to_string(port)
  assert dashboard.runtime_count(running) == 0

  let browser = dashboard_support.browser(port:)

  // Every route without the key prefix, or with another key, is the one
  // refusal.
  list.each(
    [
      "/", "/style.css", "/palette.css", "/art/cube-cond.ttf", "/ws", "/logs",
      "/logs-ws",
    ],
    fn(path) {
      list.each([path, "/k/wrong" <> path], fn(spelled) {
        let reply = dashboard_support.send(port, spelled, browser)
        assert reply.status == 403 as spelled
        assert reply.body == <<>> as spelled
      })
    },
  )

  // A handshake outside the key prefix, with another key, or with the key and
  // a foreign origin or none, is refused before a runtime starts.
  let socket = "/k/" <> key <> "/ws"
  let logs_socket = "/k/" <> key <> "/logs-ws"
  let refused = [
    #("no key prefix", "/ws", [#("Origin", origin), ..browser]),
    #("another key", "/k/wrong/ws", [#("Origin", origin), ..browser]),
    #("a foreign origin", socket, [
      #("Origin", "https://evil.example"),
      ..browser
    ]),
    #("no origin", socket, browser),
    #("logs: no key prefix", "/logs-ws", [#("Origin", origin), ..browser]),
    #("logs: another key", "/k/wrong/logs-ws", [#("Origin", origin), ..browser]),
    #("logs: a foreign origin", logs_socket, [
      #("Origin", "https://evil.example"),
      ..browser
    ]),
    #("logs: no origin", logs_socket, browser),
  ]
  list.each(refused, fn(row) {
    let #(connection, reply) =
      dashboard_support.handshake(port:, path: row.1, headers: row.2)
    dashboard_support.close(connection)
    assert reply.status == 403 as row.0
  })
  assert dashboard.runtime_count(running) == 0
    as "a refused handshake started a runtime"

  // The key prefix and the right origin upgrade, and the runtime that serves
  // the page's first message is the one the count then holds.
  let #(connection, reply) =
    dashboard_support.handshake(port:, path: socket, headers: [
      #("Origin", origin),
      ..browser
    ])
  assert reply.status == 101
  let first = dashboard_support.read_frame(connection)
  assert bit_array.byte_size(first) > 0
  assert dashboard.runtime_count(running) == 1
  dashboard_support.close(connection)
}

/// Opens the Overview's websocket as a browser does and returns the connection
/// once the server has upgraded it.
fn opened_socket(port: Int, key: String) -> dashboard_support.Connection {
  opened_socket_at(port:, key:, route: "ws")
}

/// Opens the websocket at `route` inside the key prefix as a browser does and
/// returns the connection once the server has upgraded it. The runtimes'
/// factory is rebuilt for a moment when what it follows was, and the server
/// then answers 503; the next ask is made at once, since each ends with the
/// server's answer.
fn opened_socket_at(
  port port: Int,
  key key: String,
  route route: String,
) -> dashboard_support.Connection {
  let origin = "http://127.0.0.1:" <> int.to_string(port)
  let #(connection, reply) =
    dashboard_support.handshake(
      port:,
      path: "/k/" <> key <> "/" <> route,
      headers: [#("Origin", origin), ..dashboard_support.browser(port:)],
    )
  case reply.status {
    101 -> connection
    503 -> {
      dashboard_support.close(connection)
      opened_socket_at(port:, key:, route:)
    }
    status -> panic as { "the socket answered " <> int.to_string(status) }
  }
}

/// Why a wait for frames ended with no frame holding what it waited for: a
/// frame held one of the words the wait refuses. The follower that sent it reads
/// again only at its next tick, which these tests never let come, so no frame
/// would follow. `text` is what the frames said.
type Refused {
  Refused(word: String, missing: List(String), text: String)
}

/// How a wait for frames refuses: the words whose presence in a frame, once the
/// `tolerating` words are cut from it, ends the wait because the follower that
/// sent them reads again only at its next tick, which these tests never let
/// come.
type Waits {
  Waits(refusing: List(String), tolerating: List(String))
}

/// The words a page shows for a read that failed for a reason no row names.
const failed_read = "cannot read: "

/// What a source shows when its container's `podman` is not there, as it is in
/// every test that plants no container.
const no_podman = "cannot read: cannot find "

/// The words the Overview shows for a fact no read has given.
const never_read = "No reading: "

/// The words the Overview adds to a fact whose last read failed.
const stale_fact = "stale "

/// A Logs page of planted files: a file that cannot be read refuses. The
/// containers read through a `podman` that is not there, so every frame says
/// that for them.
const file_logs = Waits(refusing: [failed_read], tolerating: [no_podman])

/// A Logs page whose containers are planted (`with_containers`): a source that
/// cannot be read refuses.
const container_logs = Waits(refusing: [failed_read], tolerating: [])

/// An Overview page: a fact no read has given refuses.
const overview = Waits(refusing: [never_read], tolerating: [])

/// An Overview page whose facts are all fresh: a fact no read has given, or
/// whose last read failed, refuses.
const fresh_overview = Waits(refusing: [never_read, stale_fact], tolerating: [])

/// The text of the frames the server sends on the connection until every
/// needle has been in one of them, or what refused the wait.
fn frames_until(
  connection connection: dashboard_support.Connection,
  needles needles: List(String),
  waits waits: Waits,
) -> Result(String, Refused) {
  frames_until_after(connection:, needles:, waits:, seen: "")
}

fn frames_until_after(
  connection connection: dashboard_support.Connection,
  needles needles: List(String),
  waits waits: Waits,
  seen seen: String,
) -> Result(String, Refused) {
  let missing =
    list.filter(needles, fn(needle) { !string.contains(seen, needle) })
  use <- bool.guard(when: missing == [], return: Ok(seen))
  let frame =
    open_wait.named(
      "a frame of the page holding " <> string.join(missing, " and "),
      fn() { dashboard_support.read_frame(connection) },
    )
  let assert Ok(text) = bit_array.to_string(frame) as "a frame is not text"
  let judged =
    list.fold(waits.tolerating, text, fn(judged, word) {
      string.replace(judged, word, "")
    })
  case list.find(waits.refusing, string.contains(judged, _)) {
    Ok(word) -> Error(Refused(word:, missing:, text:))
    Error(Nil) ->
      frames_until_after(
        connection:,
        needles:,
        waits:,
        seen: seen <> "\n" <> text,
      )
  }
}

/// The text of the frames of a page until every needle has been in one of
/// them; a frame that refuses the wait fails the test with the page's text.
fn frames_held(
  connection connection: dashboard_support.Connection,
  needles needles: List(String),
  waits waits: Waits,
) -> String {
  case frames_until(connection:, needles:, waits:) {
    Ok(text) -> text
    Error(Refused(word:, missing:, text:)) ->
      panic as {
        "a frame holds \""
        <> word
        <> "\", so no frame holding "
        <> string.join(missing, " and ")
        <> " will follow: "
        <> text
      }
  }
}

pub fn a_dead_poller_takes_the_page_runtimes_with_it_and_a_new_tab_is_served_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)

  // A page is open: one runtime, and the reading the poller made.
  let first = opened_socket(settings.port, key)
  let _first =
    frames_held(connection: first, needles: ["9d2015a0"], waits: overview)
  assert dashboard.runtime_count(running) == 1

  // The poller dies: the supervisor rebuilds it with the factory of the
  // runtimes, so the page's socket closes.
  let assert Ok(poller_pid) = process.subject_owner(running.poller)
  process.kill(poller_pid)
  assert dashboard_support.closes(first) as "the page's socket stayed open"

  // A new tab is served: one runtime, the old one gone with its factory, and
  // a reading from the rebuilt poller.
  let second = opened_socket(settings.port, key)
  let _second =
    frames_held(connection: second, needles: ["9d2015a0"], waits: overview)
  assert dashboard.runtime_count(running) == 1
  dashboard_support.close(second)
}

/// What `lsof` prints with two connections established on the game port.
const two_connections =
  "COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
gvproxy  4242 jim   10u  IPv4 0x1      0t0  TCP 127.0.0.1:24000->127.0.0.1:50001 (ESTABLISHED)
gvproxy  4242 jim   11u  IPv4 0x2      0t0  TCP 127.0.0.1:24000->127.0.0.1:50002 (ESTABLISHED)
"

/// The Overview's markup for a reading, as the page's runtime renders it.
fn overview_html(reading: Reading) -> String {
  element.to_string(overview.view(Model(reading: Some(reading))))
}

/// Fails, naming the stage and the word, when the markup lacks one of `words`.
fn assert_shows(
  html html: String,
  words words: List(String),
  stage stage: String,
) -> Nil {
  list.each(words, fn(word) {
    assert string.contains(html, word)
      as { stage <> ": the Overview does not show " <> word }
  })
}

/// The whole run: the real `state.sh` under fake `podman` and `lsof` (the
/// scene's `PATH` holds no other), the poller, the page runtime and the
/// socket. Every wait ends with a reading the poller sent or a frame of the
/// page; the script's bounds count looks the fake look answers at once, and the
/// poller's deadline is a day, so no machine's load can end a read early.
pub fn the_overview_shows_what_state_sh_reports_and_marks_it_stale_when_it_fails_test() -> Nil {
  use <- owned_test.run(120_000)
  use scene <- support.with_scene

  // The planted world: a live lock of a client start and an update lock whose
  // owner is this test's own process, a hold, and the updater's log; Podman
  // and the machine healthy, two connections on the game port.
  let pid = support.os_pid()
  let process_words = "(process " <> int.to_string(pid) <> ")"
  let owner =
    support.owner_record(
      kind: "client",
      folder: "",
      pid:,
      started: support.started_text(pid:),
    )
  support.plant_live_lock(scene:, record: Some(owner))
  support.plant_update_lock(scene:, owner: Some(pid))
  support.plant_hold(scene)
  support.plant_home_file(
    scene:,
    name: "play-service.log",
    text: "2026-11-20 02:00:00 play-service: older line\n2026-11-20 02:41:58 play-service: replacing genesis-play\n",
  )
  support.plant(scene:, key: support.info, answer: support.quiet)
  support.plant_container(
    scene:,
    name: support.server_container,
    status: "running",
    labels: "9d2015a0 192.168.1.5 true",
  )
  support.plant_status(
    scene:,
    name: support.database_container,
    status: "running",
  )
  support.plant(scene:, key: support.ready, answer: support.quiet)
  support.plant(
    scene:,
    key: support.connections,
    answer: Answer(..support.quiet, output: two_connections),
  )

  // The dashboard runs a wrapper that runs the repository's `state.sh`.
  let assert Ok(repository) = simplifile.current_directory()
  let wrapper = scene.home <> "/state-wrapper.sh"
  let assert Ok(Nil) =
    simplifile.write(
      wrapper,
      support.wrapper(
        scene:,
        script: repository <> "/dev/play_service/state.sh",
      ),
    )
  let assert Ok(Nil) = simplifile.set_permissions_octal(wrapper, 0o755)
  let settings =
    dashboard.Settings(
      ..dashboard_support.settings(scene.home),
      state_script: wrapper,
    )
  let running = started(settings)
  let key = dashboard_support.written_key(home: scene.home)

  // The first reading shows what the script reports. The probe is a second
  // subscriber that tells when a reading has been made.
  let probe = process.new_subject()
  read_poll.subscribe(running.poller, probe)
  let healthy = [
    "running",
    "9d2015a0",
    "192.168.1.5",
    "running, ready",
    "held",
    "running " <> process_words,
    "2026-11-20 02:41:58 play-service: replacing genesis-play",
    "held by a client start " <> process_words,
  ]
  let first = overview_html(open_wait.received(probe, "the first reading"))
  assert_shows(
    html: first,
    words: [healthy, ["<span class=\"state\">2</span>"]] |> list.flatten,
    stage: "the first reading",
  )
  assert !string.contains(first, "stale") as "a healthy read is not stale"
  let socket = opened_socket(settings.port, key)
  let shown =
    frames_held(
      connection: socket,
      needles: [healthy, ["\"2\""]] |> list.flatten,
      waits: fresh_overview,
    )
  assert !string.contains(shown, "stale") as "a healthy read is not stale"

  // Podman fails: the same values are shown stale, with the reason and an age.
  let stale_words = [
    "stale ",
    " s: the Podman machine could not be read",
    " s: podman exited with status 2: cannot reach the machine",
  ]
  support.plant(
    scene:,
    key: support.info,
    answer: Answer(
      ..support.quiet,
      exits: [2],
      error: "cannot reach the machine\n",
    ),
  )
  read_poll.read_now(running.poller)
  let failing =
    overview_html(open_wait.received(probe, "the reading with Podman failing"))
  assert_shows(html: failing, words: stale_words, stage: "Podman failing")
  let _stale =
    frames_held(connection: socket, needles: stale_words, waits: overview)

  // Podman works again: a page opened now shows no stale word.
  support.plant(scene:, key: support.info, answer: support.quiet)
  read_poll.read_now(running.poller)
  let recovered =
    overview_html(open_wait.received(
      probe,
      "the reading after Podman recovered",
    ))
  assert_shows(html: recovered, words: healthy, stage: "Podman recovered")
  assert !string.contains(recovered, "stale") as "the stale words are gone"
  let later = opened_socket(settings.port, key)
  let again =
    frames_held(
      connection: later,
      needles: ["9d2015a0", "running, ready"],
      waits: fresh_overview,
    )
  assert !string.contains(again, "stale") as "the stale words are gone"
  dashboard_support.close(later)

  // The script is removed: every fact is stale, naming the path.
  let assert Ok(Nil) = simplifile.delete(wrapper)
  read_poll.read_now(running.poller)
  let without =
    overview_html(open_wait.received(probe, "the reading without the script"))
  let not_found = "the state script is not found: " <> wrapper
  assert_shows(html: without, words: [not_found], stage: "the script removed")
  let _gone =
    frames_held(connection: socket, needles: [not_found], waits: overview)
  dashboard_support.close(socket)
}

const stamp = "2026-11-20 02:00:0"

fn plant_logs(
  home home: String,
  updater updater: String,
  launchd launchd: String,
) -> Nil {
  let assert Ok(Nil) = simplifile.write(home <> "/play-service.log", updater)
  let assert Ok(Nil) =
    simplifile.write(home <> "/play-service.launchd.log", launchd)
  Nil
}

pub fn the_logs_page_follows_the_updater_log_and_launchds_log_through_a_browsers_socket_test() -> Nil {
  use <- owned_test.run(120_000)
  use home <- dashboard_support.with_home
  let updater_path = home <> "/play-service.log"
  let escape = "\u{1B}"
  plant_logs(
    home:,
    updater: stamp
      <> "0 play-service: first line\n"
      <> stamp
      <> "1 play-service: second line\n"
      <> stamp
      <> "2 play-service: third line\n"
      <> stamp
      <> "3 play-service: genesis-play did not come up: state running, exit code 0, restarted 1 times; its last lines: |  genesis_prime.load_content"
      <> escape
      <> "[90m src/genesis_prime.gleam:137"
      <> escape
      <> "[0m\n",
    launchd: "Error: building at STEP \"RUN gleam deps download\": exit status 1\n",
  )
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)
  let socket = opened_socket_at(port: settings.port, key:, route: "logs-ws")

  // The first frames hold the lines of both sources, the ANSI line as text and
  // the failures in the role of a failure.
  let first =
    frames_held(
      connection: socket,
      needles: [
        "first line",
        "third line",
        "load_content src/genesis_prime.gleam:137",
        "Error: building at STEP",
        "role-bad",
      ],
      waits: file_logs,
    )
  assert !string.contains(first, "[90m") as "the colour code is not shown"
  assert !string.contains(first, "u001b") as "no escape reaches the page"

  // A line appended to the updater's log is the next frame's.
  let assert Ok(Nil) =
    simplifile.append(updater_path, stamp <> "4 play-service: fourth line\n")
  follow.read_now(running.updater_log)
  let _appended =
    frames_held(connection: socket, needles: ["fourth line"], waits: file_logs)

  // The file cut shorter: a frame with the mark.
  let assert Ok(Nil) = simplifile.write(updater_path, "short\n")
  follow.read_now(running.updater_log)
  let _cut =
    frames_held(
      connection: socket,
      needles: ["the log was cut shorter", "short"],
      waits: file_logs,
    )

  // The file removed: a frame that says there is no log yet.
  let assert Ok(Nil) = simplifile.delete(updater_path)
  follow.read_now(running.updater_log)
  let _removed =
    frames_held(connection: socket, needles: ["no log yet"], waits: file_logs)
  dashboard_support.close(socket)

  // A dashboard started with neither file serves the page and says so for
  // both.
  use bare <- dashboard_support.with_home
  let bare_settings = dashboard_support.settings(bare)
  let _bare = started(bare_settings)
  let bare_key = dashboard_support.written_key(home: bare)
  let page =
    dashboard_support.send(
      bare_settings.port,
      "/k/" <> bare_key <> "/logs",
      dashboard_support.browser(port: bare_settings.port),
    )
  assert page.status == 200
  assert string.contains(result_text(page.body), "route=\"logs-ws\"")
  let bare_socket =
    opened_socket_at(port: bare_settings.port, key: bare_key, route: "logs-ws")
  let empty =
    frames_held(
      connection: bare_socket,
      needles: [
        bare <> "/play-service.log",
        bare <> "/play-service.launchd.log",
        "no log yet",
      ],
      waits: file_logs,
    )
  assert list.length(string.split(empty, "no log yet")) >= 3
    as "both sources say there is no log yet"
  dashboard_support.close(bare_socket)
}

pub fn closing_the_logs_socket_ends_its_runtime_and_the_followers_reads_test() -> Nil {
  use <- owned_test.run(120_000)
  use home <- dashboard_support.with_home
  plant_logs(home:, updater: "one\n", launchd: "alpha\n")
  let watcher = process.new_subject()
  let settings =
    dashboard.Settings(
      ..dashboard_support.settings(home),
      log_watcher: Some(watcher),
    )
  let running = started(settings)
  let key = dashboard_support.written_key(home:)

  // Open: one runtime, both sources' lines.
  let socket = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _first =
    frames_held(connection: socket, needles: ["one", "alpha"], waits: file_logs)
  assert dashboard.runtime_count(running) == 1

  // Closed: the runtime ends and every follower, the containers' included, drops
  // its subscriber.
  dashboard_support.close(socket)
  all_dropped(watcher:, seen: [])
  event_wait.until("the logs runtime to end", fn() {
    dashboard.runtime_count(running) == 0
  })

  // A line appended afterwards is read by no one.
  let assert Ok(Nil) = simplifile.append(home <> "/play-service.log", "two\n")
  follow.read_now(running.updater_log)
  follow.read_now(running.launchd_log)
  assert follow.subscriber_count(running.updater_log) == 0
  assert follow.subscriber_count(running.launchd_log) == 0
  assert process.receive(watcher, 0) == Error(Nil)
    as "a follower read with no page open"

  // A second socket gets the newest lines again.
  let second = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _again =
    frames_held(
      connection: second,
      needles: ["one", "two", "alpha"],
      waits: file_logs,
    )
  dashboard_support.close(second)
}

pub fn a_logs_socket_is_upgraded_only_once_its_runtime_has_started_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  plant_logs(home:, updater: "one\n", launchd: "alpha\n")
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)
  let headers = [
    #("Origin", "http://127.0.0.1:" <> int.to_string(settings.port)),
    ..dashboard_support.browser(port: settings.port)
  ]

  // The factory holds the start the handshake asks of it: the server has not
  // answered. Mist ends a socket whose init takes over 500 ms with an HTTP
  // answer written after the 101, which a loaded machine reaches.
  let connection =
    dashboard_support.with_factory_held(
      runtimes: running.log_runtimes,
      during: fn(start_asked) {
        let connection =
          dashboard_support.handshake_sent(
            port: settings.port,
            path: "/k/" <> key <> "/logs-ws",
            headers:,
          )
        start_asked()
        assert !dashboard_support.has_bytes(connection)
          as "the server upgraded the socket before its runtime had started"
        connection
      },
    )

  // The factory let go: the runtime starts, the socket is upgraded and the
  // page's lines come.
  assert dashboard_support.handshake_reply(connection).status == 101
  let _first =
    frames_held(connection:, needles: ["one", "alpha"], waits: file_logs)
  assert dashboard.runtime_count(running) == 1
  dashboard_support.close(connection)
}

pub fn a_handshake_whose_factory_dies_before_it_answers_is_answered_503_and_the_next_is_served_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  plant_logs(home:, updater: "one\n", launchd: "alpha\n")
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)

  // The factory holds the start the handshake asks of it and then dies: the
  // ask ends with an exit, not an error, and the answer is the one of a start
  // that did not happen, never an HTTP 500 of the server's own.
  answered_503_when_the_factory_dies(
    running:,
    port: settings.port,
    key:,
    route: "ws",
    runtimes: running.runtimes,
  )
  answered_503_when_the_factory_dies(
    running:,
    port: settings.port,
    key:,
    route: "logs-ws",
    runtimes: running.log_runtimes,
  )
}

fn answered_503_when_the_factory_dies(
  running running: dashboard.Running,
  port port: Int,
  key key: String,
  route route: String,
  runtimes runtimes: socket.Runtimes(argument, message),
) -> Nil {
  let connection =
    dashboard_support.with_factory_held(runtimes:, during: fn(start_asked) {
      let connection =
        dashboard_support.handshake_sent(
          port:,
          path: "/k/" <> key <> "/" <> route,
          headers: [
            #("Origin", "http://127.0.0.1:" <> int.to_string(port)),
            ..dashboard_support.browser(port:)
          ],
        )
      start_asked()
      dashboard_support.kill_factory(runtimes)
      connection
    })
  assert dashboard_support.handshake_reply(connection).status == 503 as route
  dashboard_support.close(connection)

  // The tree starts the factory again, and the next tab is served by it.
  let socket = opened_socket_at(port:, key:, route:)
  assert dashboard.runtime_count(running) == 1 as route
  dashboard_support.close(socket)
  event_wait.until("the runtime of " <> route <> " to end", fn() {
    dashboard.runtime_count(running) == 0
  })
}

pub fn a_handshake_the_websocket_upgrade_refuses_stops_the_runtime_it_started_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  plant_logs(home:, updater: "one\n", launchd: "alpha\n")
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)
  let headers = [
    #("Origin", "http://127.0.0.1:" <> int.to_string(settings.port)),
    ..dashboard_support.browser(port: settings.port)
  ]

  // The gate allows the request: its key prefix and origin are right. The
  // upgrade is refused for the missing `Sec-WebSocket-Key` after the runtime
  // started, and the runtime does not stay with no socket to serve.
  list.each(["ws", "logs-ws"], fn(route) {
    let #(connection, reply) =
      dashboard_support.handshake_without_key(
        port: settings.port,
        path: "/k/" <> key <> "/" <> route,
        headers:,
      )
    dashboard_support.close(connection)
    assert reply.status == 400 as route
    event_wait.until("the runtime of " <> route <> " to end", fn() {
      dashboard.runtime_count(running) == 0
    })
  })
}

pub fn a_dead_follower_takes_the_log_runtimes_with_it_and_a_new_tab_is_served_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  plant_logs(home:, updater: "one\n", launchd: "alpha\n")
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)

  let first = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _first =
    frames_held(connection: first, needles: ["one", "alpha"], waits: file_logs)
  assert dashboard.runtime_count(running) == 1

  // A follower dies: the supervisor rebuilds the followers with the factory of
  // the log runtimes, so the page's socket closes.
  let assert Ok(follower_pid) = process.subject_owner(running.updater_log)
  process.kill(follower_pid)
  assert dashboard_support.closes(first) as "the page's socket stayed open"

  // A new tab is served: one runtime, and the lines.
  let second = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _second =
    frames_held(connection: second, needles: ["one", "alpha"], waits: file_logs)
  assert dashboard.runtime_count(running) == 1

  // A container's follower dies: the same, and the tab after it is served.
  let assert Ok(container_pid) = process.subject_owner(running.server_log)
  process.kill(container_pid)
  assert dashboard_support.closes(second) as "the page's socket stayed open"
  let third = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _third =
    frames_held(connection: third, needles: ["one", "alpha"], waits: file_logs)
  assert dashboard.runtime_count(running) == 1
  dashboard_support.close(third)
}

// ---------------------------------------------------------------------------
// The containers' logs, read through a fake `podman`.

/// The second the fake `podman` prints before every line it logs first.
const log_second = "2026-11-20T09:10:12-05:00"

/// The id of the server's container, and of the container that replaced it.
const first_id =
  "1111111111111111111111111111111111111111111111111111111111111111"

const second_id =
  "2222222222222222222222222222222222222222222222222222222222222222"

/// The lines as `podman logs --timestamps` prints them, each after `second`.
fn logged(lines lines: List(String), second second: String) -> String {
  list.map(lines, fn(line) { second <> " " <> line <> "\n" })
  |> string.concat
}

/// A scene whose `podman` knows both containers: the server's log is the
/// captures of an OTP crash and of a pgo crash that prints the password, the
/// database's the captured sample of Postgres' log. Gives the dashboard's
/// settings, reading through that `podman`.
fn with_containers(body body: fn(support.Scene, dashboard.Settings) -> a) -> a {
  use scene <- support.with_scene
  let podman = support.plant_podman(scene)
  support.plant_identity(scene:, name: support.server_container, id: first_id)
  support.plant_container_log(
    scene:,
    name: support.server_container,
    text: logged(
      lines: list.append(
        otp_support.capture("c2_progress_crash_supervisor_plain.txt"),
        otp_support.capture("c5b_pgo_crash_long_password_wraps.txt"),
      ),
      second: log_second,
    ),
  )
  support.plant_identity(scene:, name: support.database_container, id: first_id)
  support.plant_container_log(
    scene:,
    name: support.database_container,
    text: logged(
      lines: otp_support.capture("c4_postgres_container_sample.txt"),
      second: log_second,
    ),
  )
  body(
    scene,
    dashboard.Settings(
      ..dashboard_support.settings(scene.home),
      podman_path: podman,
    ),
  )
}

/// The planted password of the capture of a pgo crash.
const planted_password =
  "ZZ0123456789abcdefghijklmnopqrstuvwxyzQQ0123456789abcdefghijklmnopqrstuvwxyzQQ0123456789abcdefgZZ"

/// A list item of the page as the frames hold it: the rest of its text after
/// the words that were looked for, and its role.
type Item {
  Item(rest_of_text: String, role: String)
}

/// Each list item whose text holds `words`. The frames hold the page's elements
/// as JSON, an element's text before its class.
fn items_holding(frames: String, words: String) -> List(Item) {
  string.split(frames, words)
  |> list.drop(1)
  |> list.map(fn(after) {
    let assert Ok(#(rest_of_text, after_text)) =
      string.split_once(after, "\",\"kind\":2}")
      as "an item's text ends with its node"
    let assert Ok(#(_, after_class)) =
      string.split_once(after_text, "\"value\":\"line role-")
      as "an item's class follows its text"
    let assert Ok(#(role, _)) = string.split_once(after_class, " ")
    Item(rest_of_text:, role:)
  })
}

pub fn the_logs_page_shows_the_two_containers_through_a_browsers_socket_test() -> Nil {
  use <- owned_test.run(120_000)
  use scene, settings <- with_containers
  let running = started(settings)
  let key = dashboard_support.written_key(home: settings.genesis_home)
  let socket = opened_socket_at(port: settings.port, key:, route: "logs-ws")

  // The frames hold the four sources, the containers by the call that shows
  // them, and the lines of both containers.
  let first =
    frames_held(
      connection: socket,
      needles: [
        "Updater log",
        "launchd log",
        "Server log",
        "Database log",
        "podman logs genesis-play",
        "podman logs genesis-play-postgres",
        "=CRASH REPORT====",
        "creature2_id",
        "[hidden]",
      ],
      waits: container_logs,
    )

  // The server's crash reports are each one entry, in the role of a failure.
  let crashes = items_holding(first, "=CRASH REPORT====")
  assert list.length(crashes) == 3 as "the three crash reports are three items"
  list.each(crashes, fn(crash) {
    assert crash.role == "bad" as "a crash report is in the role of a failure"
    assert string.contains(crash.rest_of_text, "crasher:")
      as "a crash report is one item with its body"
  })

  // The database's ERROR line is a failure, and its LOG lines are not.
  assert list.map(items_holding(first, "] ERROR:  column"), fn(item) {
      item.role
    })
    == ["bad"]
  assert list.map(items_holding(first, "] LOG:  checkpoint starting"), fn(item) {
      item.role
    })
    == ["text"]

  // The planted password is in no frame the page was sent.
  assert !string.contains(first, planted_password)
    as "the password reached a frame"

  // A line the container logs later arrives once.
  support.plant_container_log(
    scene:,
    name: support.server_container,
    text: logged(
      lines: list.append(
        otp_support.capture("c2_progress_crash_supervisor_plain.txt"),
        otp_support.capture("c5b_pgo_crash_long_password_wraps.txt"),
      ),
      second: log_second,
    )
      <> "2026-11-20T09:10:30-05:00 a line logged later\n",
  )
  read_poll.read_now(running.server_log)
  let later =
    frames_held(
      connection: socket,
      needles: ["a line logged later"],
      waits: container_logs,
    )
  assert string.split(later, "a line logged later") |> list.length == 2
    as "the line came once"
  assert !string.contains(later, planted_password)
  dashboard_support.close(socket)
}

pub fn a_podman_that_goes_away_and_returns_is_shown_stale_with_its_reason_and_then_fresh_test() -> Nil {
  use <- owned_test.run(120_000)
  use scene, settings <- with_containers
  let running = started(settings)
  let key = dashboard_support.written_key(home: settings.genesis_home)
  let first = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _lines =
    frames_held(
      connection: first,
      needles: ["creature2_id", "=CRASH REPORT===="],
      waits: container_logs,
    )

  // Podman is not reachable: a frame with the reason, and a page opened now
  // shows the lines the follower kept, dimmed.
  support.plant_unreachable(scene:, name: support.server_container)
  read_poll.read_now(running.server_log)
  let _reason =
    frames_held(
      connection: first,
      needles: [
        "Podman is not reachable",
        "unable to connect to Podman socket",
      ],
      waits: container_logs,
    )
  let second = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let kept =
    frames_held(
      connection: second,
      needles: [
        "Podman is not reachable",
        "=CRASH REPORT====",
        "stale",
      ],
      waits: container_logs,
    )
  assert string.contains(kept, "role-warn")
  dashboard_support.close(second)

  // Podman answers again, and a line was logged meanwhile: it comes once, and
  // a page opened now shows no reason and no dimming.
  support.plant_identity(scene:, name: support.server_container, id: first_id)
  support.plant_container_log(
    scene:,
    name: support.server_container,
    text: logged(
      lines: list.append(
        otp_support.capture("c2_progress_crash_supervisor_plain.txt"),
        otp_support.capture("c5b_pgo_crash_long_password_wraps.txt"),
      ),
      second: log_second,
    )
      <> "2026-11-20T09:10:31-05:00 logged meanwhile\n",
  )
  read_poll.read_now(running.server_log)
  let back =
    frames_held(
      connection: first,
      needles: ["logged meanwhile"],
      waits: container_logs,
    )
  assert string.split(back, "logged meanwhile") |> list.length == 2
    as "the line logged meanwhile came once"
  let third = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let fresh =
    frames_held(
      connection: third,
      needles: ["logged meanwhile", "=CRASH REPORT===="],
      waits: container_logs,
    )
  assert !string.contains(fresh, "Podman is not reachable")
  assert !string.contains(fresh, "stale")
  dashboard_support.close(third)

  // The container was replaced: a frame with the mark, then its lines.
  support.plant_identity(scene:, name: support.server_container, id: second_id)
  support.plant_container_log(
    scene:,
    name: support.server_container,
    text: logged(lines: ["the new container's line"], second: log_second),
  )
  read_poll.read_now(running.server_log)
  let replaced =
    frames_held(
      connection: first,
      needles: [
        "the container was replaced",
        "the new container's line",
      ],
      waits: container_logs,
    )
  assert !string.contains(replaced, planted_password)
  dashboard_support.close(first)
}

/// A page whose follower cannot read what it follows, and what the wait for
/// frames of that page ends with: `plant` makes the failure, `route` is the
/// page's socket, `word` the one the wait refused on, and `reason(home)` the
/// text the page gives for the failure.
type Unreadable {
  Unreadable(
    why: String,
    plant: fn(support.Scene, dashboard.Settings) -> dashboard.Settings,
    route: String,
    waits: Waits,
    needles: List(String),
    word: String,
    reason: fn(String) -> String,
  )
}

pub fn a_failed_read_ends_a_wait_for_frames_with_its_reason_on_each_page_test() -> Nil {
  use <- owned_test.run(30_000)
  // In each row the follower reads again only at a tick, which the test never
  // lets come, so the needles never arrive and only the refusal ends the wait.
  let rows = [
    Unreadable(
      why: "a container that podman cannot inspect",
      plant: fn(scene, settings) {
        support.plant(
          scene:,
          key: support.identity(support.server_container),
          answer: Answer(
            exits: [1],
            output: "",
            error: "the planted podman failed\n",
          ),
        )
        settings
      },
      route: "logs-ws",
      waits: container_logs,
      needles: ["=CRASH REPORT===="],
      word: failed_read,
      reason: fn(_home) { failed_read <> "the planted podman failed" },
    ),
    Unreadable(
      why: "a folder where the updater's log should be",
      plant: fn(scene, settings) {
        let assert Ok(Nil) =
          simplifile.create_directory(scene.home <> "/play-service.log")
        settings
      },
      route: "logs-ws",
      waits: file_logs,
      needles: ["a line that never comes"],
      word: failed_read,
      reason: fn(_home) { failed_read <> "eisdir" },
    ),
    Unreadable(
      why: "a state script that is not there",
      plant: fn(scene, settings) {
        dashboard.Settings(
          ..settings,
          state_script: scene.home <> "/no-state-script.sh",
        )
      },
      route: "ws",
      waits: overview,
      needles: ["9d2015a0"],
      word: never_read,
      reason: fn(home) {
        never_read
        <> "the state script is not found: "
        <> home
        <> "/no-state-script.sh"
      },
    ),
  ]
  list.each(rows, fn(row) {
    use scene, settings <- with_containers
    let settings = row.plant(scene, settings)
    let _running = started(settings)
    let key = dashboard_support.written_key(home: settings.genesis_home)
    let socket = opened_socket_at(port: settings.port, key:, route: row.route)
    let assert Error(Refused(word:, missing:, text:)) =
      frames_until(connection: socket, needles: row.needles, waits: row.waits)
      as { row.why <> ": the wait was not refused" }
    assert word == row.word
      as { row.why <> ": the wait is refused by another word" }
    assert missing == row.needles
      as { row.why <> ": the error names other words than were waited for" }
    assert string.contains(text, row.reason(scene.home))
      as { row.why <> ": the error does not hold the page's reason" }
    dashboard_support.close(socket)
  })
}

/// Waits until every follower of the four sources has told the watcher it
/// dropped a subscriber.
fn all_dropped(
  watcher watcher: process.Subject(follow.Event),
  seen seen: List(log_lines.Source),
) -> Nil {
  use <- bool.guard(when: list.length(seen) == 4, return: Nil)
  case open_wait.received(from: watcher, what: "a follower's report") {
    follow.SubscriberDropped(source) ->
      all_dropped(watcher:, seen: list.unique([source, ..seen]))
    follow.ReadMade(_) -> all_dropped(watcher:, seen:)
  }
}

pub fn closing_the_logs_socket_stops_the_podman_calls_and_leaves_no_process_test() -> Nil {
  use <- owned_test.run(120_000)
  use scene, settings <- with_containers
  let watcher = process.new_subject()
  let settings = dashboard.Settings(..settings, log_watcher: Some(watcher))
  let running = started(settings)
  let key = dashboard_support.written_key(home: settings.genesis_home)
  let socket = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  let _first =
    frames_held(
      connection: socket,
      needles: [
        "creature2_id",
        "=CRASH REPORT====",
      ],
      waits: container_logs,
    )

  // Closed: every follower drops its subscriber, and a read asked for after
  // that starts no read. A follower tells the watcher before it starts a read,
  // and its answer to the count comes after, so the watcher's mailbox shows
  // every read the two asks started.
  dashboard_support.close(socket)
  all_dropped(watcher:, seen: [])
  assert support.calls(scene) != [] as "the page's reads called podman"
  read_poll.read_now(running.server_log)
  read_poll.read_now(running.database_log)
  assert read_poll.subscriber_count(running.server_log) == 0
  assert read_poll.subscriber_count(running.database_log) == 0
  assert process.receive(watcher, 0) == Error(Nil)
    as "a follower started a read with no page open"

  // A `logs` call that blocks when the socket closes is ended by the read's
  // deadline, and is gone when its process id is dead. The dashboard of this part
  // ends a call after the test's own 5 s, long enough for the fake's other calls
  // (0.15 s) under load.
  let settings =
    dashboard.Settings(
      ..settings,
      port: dashboard_support.free_port(),
      container_call_deadline_ms: 5000,
    )
  let second = started(settings)
  let key = dashboard_support.written_key(home: settings.genesis_home)
  support.plant_block(
    scene:,
    key: support.container_log(support.server_container),
  )
  let blocked = opened_socket_at(port: settings.port, key:, route: "logs-ws")
  event_wait.until("the blocked call to record its process id", fn() {
    // A read whose `inspect` timed out never reached `logs`; ask for another.
    read_poll.read_now(second.server_log)
    support.blocked_pids(
      scene:,
      key: support.container_log(support.server_container),
    )
    != []
  })
  dashboard_support.close(blocked)
  all_dropped(watcher:, seen: [])
  let assert [pid, ..] =
    support.blocked_pids(
      scene:,
      key: support.container_log(support.server_container),
    )
  event_wait.until("the blocked call to be ended by its deadline", fn() {
    !support.alive(pid)
  })
}
