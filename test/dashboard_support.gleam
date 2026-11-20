//// What the dashboard's tests share: a free loopback port, raw HTTP and
//// websocket exchanges over `gen_tcp` (the dashboard is read as a browser or
//// another program reads it, not through its own functions), a planted
//// folder for `GENESIS_HOME`, and requests and a web context for the pure
//// tests. A request's host and path are written out in each test so the row
//// shows what it presents; the key rides in the path, as `/k/<key>/...`.

import envoy
import genesis_prime/dashboard
import genesis_prime/dashboard/access.{type Gate, Gate}
import genesis_prime/dashboard/page.{type Page}
import genesis_prime/dashboard/web
import gleam/bit_array
import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import planted_table
import simplifile

/// A connection a test opened and keeps open, for a websocket.
pub type Connection

/// What the server answered: its status, its headers with lower-case names and
/// its body.
pub type Reply {
  Reply(status: Int, headers: List(#(String, String)), body: BitArray)
}

/// The key a pure test's gate holds. It is not any real start's key.
pub const key = "Zk3x9QfW1m7TnV0cH4dYbR8uLs2PaE6jXgIoKqM5wNA"

/// A key an earlier start might have made.
pub const previous_key = "p4Rb7YwQ2sTxNf1kJmV9LcHd0uEzA6oGiXaK3qMnW8Y"

/// The port a pure test's gate stands on.
pub const port = 7700

/// The path of a route written without its prefix, under a pure test's key
/// prefix.
pub fn inside(path path: String) -> String {
  "/k/" <> key <> path
}

@external(erlang, "dashboard_support_ffi", "free_port")
pub fn free_port() -> Int

/// The local addresses of this VM's TCP sockets on `port`: what the dashboard's
/// listener and its connections are bound to.
@external(erlang, "dashboard_support_ffi", "bound_addresses")
pub fn bound_addresses(port: Int) -> List(String)

/// Whether a connection to the loopback address on `port` is accepted.
@external(erlang, "dashboard_support_ffi", "accepts")
pub fn accepts(port: Int) -> Bool

@external(erlang, "dashboard_support_ffi", "open")
fn open(
  port: Int,
  request: BitArray,
) -> #(Connection, Int, List(#(String, String)), BitArray)

/// The payload of the next websocket frame the server sends on the connection.
@external(erlang, "dashboard_support_ffi", "read_frame")
pub fn read_frame(connection: Connection) -> BitArray

@external(erlang, "dashboard_support_ffi", "close")
pub fn close(connection: Connection) -> Nil

/// Reads from the connection until the server closes it; true when it did.
@external(erlang, "dashboard_support_ffi", "closes")
pub fn closes(connection: Connection) -> Bool

/// The operating-system process id of the test's own VM, a process that stays
/// alive for as long as the test runs.
@external(erlang, "dashboard_support_ffi", "os_pid")
pub fn os_pid() -> Int

/// Whether the operating-system process with this id is alive.
@external(erlang, "dashboard_support_ffi", "process_alive")
pub fn process_alive(os_pid: Int) -> Bool

pub fn gate() -> Gate {
  Gate(key:, port:)
}

/// A request for the pure tests: the path, the `Host` header, and each other
/// header as written.
pub fn request(
  method method: Method,
  path path: String,
  host host: Option(String),
  headers headers: List(#(String, String)),
) -> Request(String) {
  let #(route, query) = case string.split_once(path, "?") {
    Ok(#(route, query)) -> #(route, query)
    Error(Nil) -> #(path, "")
  }
  let assert Ok(pairs) = uri.parse_query(query)
    as "the test's query is malformed"
  let base =
    request.new()
    |> request.set_method(method)
    |> request.set_path(route)
    |> request.set_query(pairs)
  let with_host = case host {
    Some(host) -> request.set_header(base, "host", host)
    None -> base
  }
  list.fold(headers, with_host, fn(request, header) {
    request.set_header(request, header.0, header.1)
  })
}

/// A GET of `path` as written, with the dashboard's own host.
pub fn get(path path: String) -> Request(String) {
  request(
    method: http.Get,
    path:,
    host: Some("127.0.0.1:" <> int.to_string(port)),
    headers: [],
  )
}

/// The dashboard's own page list.
pub fn pages() -> List(Page) {
  dashboard.pages()
}

/// A web context whose files are `files`, by the path the route reads.
pub fn context(files files: List(#(String, BitArray))) -> web.Context {
  web.Context(
    gate: gate(),
    pages: pages(),
    read_file: fn(path) { list.key_find(files, path) },
    client_fonts_folder: "fonts",
    stylesheet_folder: "styles",
  )
}

/// The six files the dashboard serves, planted where `context` reads them,
/// each holding "planted " and its path.
pub fn planted_files() -> List(#(String, BitArray)) {
  list.map(
    [
      "fonts/CubeOffcCond.ttf",
      "fonts/CubeOffcCondLight.ttf",
      "fonts/segoeui.ttf",
      "fonts/seguisb.ttf",
      "styles/style.css",
      "styles/palette.css",
    ],
    fn(path) { #(path, bit_array.from_string("planted " <> path)) },
  )
}

/// The reply the dashboard's web layer gives a request.
pub fn answer(
  context context: web.Context,
  request request: Request(body),
) -> Response(BitArray) {
  case web.handle(context, request) {
    web.Answer(response) -> response
    web.Upgrade(_) -> panic as "the request was upgraded, not answered"
  }
}

/// The value of the first header of that name in the reply.
pub fn header(reply reply: Reply, name name: String) -> Option(String) {
  list.key_find(reply.headers, name) |> option.from_result
}

/// Sends a GET to the dashboard on the loopback port and reads the reply.
pub fn send(
  port port: Int,
  path path: String,
  headers headers: List(#(String, String)),
) -> Reply {
  let #(connection, status, reply_headers, body) =
    open(port, request_bytes(path:, headers:))
  close(connection)
  Reply(status:, headers: reply_headers, body:)
}

/// The headers a browser sends to the dashboard on `port`.
pub fn browser(port port: Int) -> List(#(String, String)) {
  [#("Host", "127.0.0.1:" <> int.to_string(port))]
}

/// Sends a websocket handshake to `path` and reads the reply to it. The
/// connection stays open for the caller to read frames from and close.
pub fn handshake(
  port port: Int,
  path path: String,
  headers headers: List(#(String, String)),
) -> #(Connection, Reply) {
  let upgrade = [
    #("Upgrade", "websocket"),
    #("Connection", "Upgrade"),
    #("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ=="),
    #("Sec-WebSocket-Version", "13"),
  ]
  let #(connection, status, reply_headers, body) =
    open(port, request_bytes(path:, headers: list.append(headers, upgrade)))
  #(connection, Reply(status:, headers: reply_headers, body:))
}

fn request_bytes(
  path path: String,
  headers headers: List(#(String, String)),
) -> BitArray {
  let lines =
    list.map(headers, fn(header) { header.0 <> ": " <> header.1 <> "\r\n" })
  bit_array.from_string(
    "GET " <> path <> " HTTP/1.1\r\n" <> string.concat(lines) <> "\r\n",
  )
}

/// Runs the body with a folder of its own as `GENESIS_HOME`, removed
/// afterwards.
pub fn with_home(body body: fn(String) -> a) -> a {
  planted_table.with_folder(result.unwrap(envoy.get("TMPDIR"), "/tmp"), body)
}

/// Settings for a dashboard on a free port that keeps its entry file under
/// `home`, serves the client's fonts from `home`'s `client-files/UI/Fonts` and
/// the stylesheets from the repository. Its state script prints a fixed report
/// (`test/dashboard_state_report.sh`), so no test that opens a page runs the
/// developer's real `podman`. Its poller's timer never comes within a test (the
/// interval is a day) and no read is ended by its deadline (a day): a read is
/// made when a page subscribes or a test asks for one, and ends with the script.
/// The log followers' timers never come either (a day): a log is read when a page
/// subscribes or a test calls `follow.read_now`, and no one is told of the
/// followers' reads unless the test sets `log_watcher`.
pub fn settings(home home: String) -> dashboard.Settings {
  dashboard.Settings(
    port: free_port(),
    genesis_home: home,
    client_fonts_folder: home <> "/client-files/UI/Fonts",
    stylesheet_folder: "dev/dashboard",
    state_script: "test/dashboard_state_report.sh",
    poll_interval_ms: 86_400_000,
    read_deadline_ms: 86_400_000,
    log_interval_ms: 86_400_000,
    log_watcher: None,
  )
}

/// The entry URL a started dashboard wrote to its entry file.
pub fn written_url(home home: String) -> String {
  let assert Ok(text) = simplifile.read(home <> "/dashboard/entry-url")
    as "the entry file was not written"
  string.trim(text)
}

/// The key a started dashboard wrote to its entry file: the path segment
/// after `/k/` in the entry URL.
pub fn written_key(home home: String) -> String {
  let assert [_, after] = string.split(written_url(home:), "/k/")
    as "the entry URL holds no key prefix"
  let assert [key, ""] = string.split(after, "/")
    as "the entry URL is not the key prefix and a slash"
  key
}
