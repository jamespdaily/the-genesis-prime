//// The dashboard as a whole: its start and its refusals, and what a browser
//// fetches from it on a free loopback port. Expected values are the gate's
//// rule (no answer without this start's key), the start's rule (two
//// dashboards must not run, and a key that cannot be kept must not be
//// served) and the listener's rule (the loopback address only).

import dashboard_support
import frame_peer
import genesis_prime/dashboard
import genesis_prime/dashboard/access
import genesis_prime/dashboard/secret
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
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
