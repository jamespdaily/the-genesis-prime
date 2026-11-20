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
import genesis_prime/dashboard/secret
import gleam/bit_array
import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import open_wait
import owned_test
import shellout
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

/// Writes an executable file.
fn plant_executable(path: String, text: String) -> Nil {
  let assert Ok(Nil) = simplifile.write(path, text)
  let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o755)
  Nil
}

/// What `ps` says of when process `pid` started, with blanks collapsed, as the
/// live lock's owner record keeps it.
fn started_text(pid: Int) -> String {
  let assert Ok(text) =
    shellout.command(
      run: "ps",
      with: ["-o", "lstart=", "-p", int.to_string(pid)],
      in: ".",
      opt: [],
    )
    as "ps could not read the test's own process"
  text
  |> string.split(" ")
  |> list.map(string.trim)
  |> list.filter(fn(word) { word != "" })
  |> string.join(" ")
}

/// A `podman` that answers as a healthy Podman does for what `state.sh` asks,
/// unless the file `fails` stands beside it, when every call exits 2.
const fake_podman =
  "#!/bin/bash
here=$(dirname \"$0\")
if [ -e \"$here/fails\" ]; then
  echo 'cannot reach the machine' >&2
  exit 2
fi
case \"$1\" in
  info | exec) exit 0 ;;
  container)
    case \"$2\" in
      exists) exit 0 ;;
      inspect)
        case \"$*\" in
          *genesis.revision*) echo '9d2015a0 192.168.1.5 true' ;;
          *State.Status*) echo running ;;
        esac
        ;;
    esac
    ;;
esac
"

/// An `lsof` that shows two established connections on the game port.
const fake_lsof =
  "#!/bin/bash
echo 'COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME'
echo 'gvproxy  4242 jim   10u  IPv4 0x1      0t0  TCP 127.0.0.1:24000->127.0.0.1:50001 (ESTABLISHED)'
echo 'gvproxy  4242 jim   11u  IPv4 0x2      0t0  TCP 127.0.0.1:24000->127.0.0.1:50002 (ESTABLISHED)'
"

pub fn the_overview_shows_what_state_sh_reports_and_marks_it_stale_when_it_fails_test() -> Nil {
  use <- owned_test.run(120_000)
  use home <- dashboard_support.with_home

  // The planted world: a live lock of a client start and an update lock whose
  // owner is this test's own process, a hold, and the updater's log.
  let pid = dashboard_support.os_pid()
  let process_words = "(process " <> int.to_string(pid) <> ")"
  let assert Ok(Nil) =
    simplifile.create_directory_all(home <> "/play-service/update.lock")
  let assert Ok(Nil) = simplifile.create_directory_all(home <> "/live.lock")
  let assert Ok(Nil) =
    simplifile.write(
      home <> "/live.lock/owner",
      "token=planted\nkind=client\nfolder=\npid="
        <> int.to_string(pid)
        <> "\nstarted="
        <> started_text(pid)
        <> "\ncommit=planted\n",
    )
  let assert Ok(Nil) =
    simplifile.write(
      home <> "/play-service/update.lock/owner",
      int.to_string(pid) <> "\n",
    )
  let assert Ok(Nil) = simplifile.write(home <> "/play-service/held", "")
  let assert Ok(Nil) =
    simplifile.write(
      home <> "/play-service.log",
      "2026-11-20 02:00:00 play-service: older line\n2026-11-20 02:41:58 play-service: replacing genesis-play\n",
    )

  // Fake `podman` and `lsof` ahead of the system's on the PATH of a wrapper,
  // which runs the repository's own `state.sh` under `/bin/bash`.
  let fakes = home <> "/fakes"
  let assert Ok(Nil) = simplifile.create_directory_all(fakes)
  plant_executable(fakes <> "/podman", fake_podman)
  plant_executable(fakes <> "/lsof", fake_lsof)
  let assert Ok(repository) = simplifile.current_directory()
  let wrapper = home <> "/state-wrapper.sh"
  plant_executable(
    wrapper,
    "#!/bin/bash\nexport PATH="
      <> fakes
      <> ":/usr/bin:/bin\nexport GENESIS_HOME="
      <> home
      <> "\nexec /bin/bash "
      <> repository
      <> "/dev/play_service/state.sh\n",
  )

  let settings =
    dashboard.Settings(
      ..dashboard_support.settings(home),
      state_script: wrapper,
    )
  let running = started(settings)
  let key = dashboard_support.written_key(home:)

  // The page shows what the script reports. The probe is a second subscriber
  // that tells when a reading has been made.
  let probe = process.new_subject()
  host.subscribe(running.poller, probe)
  let _first = open_wait.received(probe, "the first reading")
  let socket = opened_socket(settings.port, key)
  let shown =
    frames_holding(socket, [
      "running",
      "9d2015a0",
      "192.168.1.5",
      "running, ready",
      "held",
      "running " <> process_words,
      "2026-11-20 02:41:58 play-service: replacing genesis-play",
      "held by a client start " <> process_words,
      "\"2\"",
    ])
  assert !string.contains(shown, "stale") as "a healthy read is not stale"

  // Podman fails: the same values are shown stale, with the reason and an age.
  let assert Ok(Nil) = simplifile.write(fakes <> "/fails", "")
  host.poll_now(running.poller)
  let _failing = open_wait.received(probe, "the reading with Podman failing")
  let _stale =
    frames_holding(socket, [
      "stale ",
      " s: the Podman machine could not be read",
      " s: podman exited with status 2: cannot reach the machine",
    ])

  // Podman works again: a page opened now shows no stale word.
  let assert Ok(Nil) = simplifile.delete(fakes <> "/fails")
  host.poll_now(running.poller)
  let _recovered =
    open_wait.received(probe, "the reading after Podman recovered")
  let later = opened_socket(settings.port, key)
  let again = frames_holding(later, ["9d2015a0", "running, ready"])
  assert !string.contains(again, "stale") as "the stale words are gone"
  dashboard_support.close(later)

  // The script is removed: every fact is stale, naming the path.
  let assert Ok(Nil) = simplifile.delete(wrapper)
  host.poll_now(running.poller)
  let _without = open_wait.received(probe, "the reading without the script")
  let _gone =
    frames_holding(socket, ["the state script is not found: " <> wrapper])
  dashboard_support.close(socket)
}
