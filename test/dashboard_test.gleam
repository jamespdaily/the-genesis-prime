//// The dashboard as a whole: its start and its refusals, and what a browser
//// fetches from it on a free loopback port. Expected values are the gate's
//// rule (no answer without this start's key), the start's rule (two
//// dashboards must not run, and a key that cannot be kept must not be
//// served) and the listener's rule (the loopback address only).

import dashboard_support
import frame_peer
import genesis_prime/dashboard
import genesis_prime/dashboard/access
import genesis_prime/dashboard/host
import genesis_prime/dashboard/host_reading.{type Reading}
import genesis_prime/dashboard/overview.{Model}
import genesis_prime/dashboard/secret
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
    ["/", "/style.css", "/palette.css", "/art/cube-cond.ttf", "/ws"],
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
  let refused = [
    #("no key prefix", "/ws", [#("Origin", origin), ..browser]),
    #("another key", "/k/wrong/ws", [#("Origin", origin), ..browser]),
    #("a foreign origin", socket, [
      #("Origin", "https://evil.example"),
      ..browser
    ]),
    #("no origin", socket, browser),
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

/// Opens the page's websocket as a browser does and returns the connection
/// once the server has upgraded it. The runtimes' factory is rebuilt for a
/// moment when the poller was, and the server then answers 503; the next ask
/// is made at once, since each ends with the server's answer.
fn opened_socket(port: Int, key: String) -> dashboard_support.Connection {
  let origin = "http://127.0.0.1:" <> int.to_string(port)
  let #(connection, reply) =
    dashboard_support.handshake(port:, path: "/k/" <> key <> "/ws", headers: [
      #("Origin", origin),
      ..dashboard_support.browser(port:)
    ])
  case reply.status {
    101 -> connection
    503 -> {
      dashboard_support.close(connection)
      opened_socket(port, key)
    }
    status -> panic as { "the socket answered " <> int.to_string(status) }
  }
}

/// The text of the frames the server sends on the connection until every
/// needle has been in one of them.
fn frames_holding(
  connection: dashboard_support.Connection,
  needles: List(String),
) -> String {
  frames_holding_after(connection:, needles:, seen: "")
}

fn frames_holding_after(
  connection connection: dashboard_support.Connection,
  needles needles: List(String),
  seen seen: String,
) -> String {
  use <- bool.guard(
    when: list.all(needles, string.contains(seen, _)),
    return: seen,
  )
  let frame = dashboard_support.read_frame(connection)
  let assert Ok(text) = bit_array.to_string(frame) as "a frame is not text"
  frames_holding_after(connection:, needles:, seen: seen <> "\n" <> text)
}

pub fn a_dead_poller_takes_the_page_runtimes_with_it_and_a_new_tab_is_served_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home
  let settings = dashboard_support.settings(home)
  let running = started(settings)
  let key = dashboard_support.written_key(home:)

  // A page is open: one runtime, and the reading the poller made.
  let first = opened_socket(settings.port, key)
  let _first = frames_holding(first, ["9d2015a0"])
  assert dashboard.runtime_count(running) == 1

  // The poller dies: the supervisor rebuilds it with the factory of the
  // runtimes, so the page's socket closes.
  let assert Ok(poller_pid) = process.subject_owner(running.poller)
  process.kill(poller_pid)
  assert dashboard_support.closes(first) as "the page's socket stayed open"

  // A new tab is served: one runtime, the old one gone with its factory, and
  // a reading from the rebuilt poller.
  let second = opened_socket(settings.port, key)
  let _second = frames_holding(second, ["9d2015a0"])
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
  host.subscribe(running.poller, probe)
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
  let shown = frames_holding(socket, [healthy, ["\"2\""]] |> list.flatten)
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
  host.poll_now(running.poller)
  let failing =
    overview_html(open_wait.received(probe, "the reading with Podman failing"))
  assert_shows(html: failing, words: stale_words, stage: "Podman failing")
  let _stale = frames_holding(socket, stale_words)

  // Podman works again: a page opened now shows no stale word.
  support.plant(scene:, key: support.info, answer: support.quiet)
  host.poll_now(running.poller)
  let recovered =
    overview_html(open_wait.received(
      probe,
      "the reading after Podman recovered",
    ))
  assert_shows(html: recovered, words: healthy, stage: "Podman recovered")
  assert !string.contains(recovered, "stale") as "the stale words are gone"
  let later = opened_socket(settings.port, key)
  let again = frames_holding(later, ["9d2015a0", "running, ready"])
  assert !string.contains(again, "stale") as "the stale words are gone"
  dashboard_support.close(later)

  // The script is removed: every fact is stale, naming the path.
  let assert Ok(Nil) = simplifile.delete(wrapper)
  host.poll_now(running.poller)
  let without =
    overview_html(open_wait.received(probe, "the reading without the script"))
  let not_found = "the state script is not found: " <> wrapper
  assert_shows(html: without, words: [not_found], stage: "the script removed")
  let _gone = frames_holding(socket, [not_found])
  dashboard_support.close(socket)
}
