//// The dashboard's gate. Expected values are the gate's rule: a container on
//// this Mac reaches the dashboard's loopback port and can set any header, so
//// a request is allowed only with this start's key in the path
//// (`/k/<key>/...`) and the dashboard's own host; a websocket handshake also
//// needs the dashboard's own origin, which a page's script cannot change. The
//// key is never a cookie: a browser sends a cookie for `127.0.0.1` to every
//// port, so a page any container serves on another port would receive it.

import dashboard_support
import genesis_prime/dashboard/access.{Allowed, Document, Refused}
import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test

type Row {
  Row(
    reason: String,
    path: String,
    host: Option(String),
    headers: List(#(String, String)),
    expected: access.Decision,
  )
}

const own_host = "127.0.0.1:7700"

pub fn a_request_is_allowed_only_with_this_starts_key_and_the_dashboards_own_host_test() -> Nil {
  use <- owned_test.run(5000)
  let key = dashboard_support.key
  let rows = [
    Row("no key prefix", "/", Some(own_host), [], Refused),
    Row(
      "a path outside the key prefix",
      "/style.css",
      Some(own_host),
      [],
      Refused,
    ),
    Row("a wrong key in the path", "/k/wrong/", Some(own_host), [], Refused),
    Row(
      "the previous start's key",
      "/k/" <> dashboard_support.previous_key <> "/",
      Some(own_host),
      [],
      Refused,
    ),
    Row("an empty key", "/k//", Some(own_host), [], Refused),
    Row("the prefix without a key", "/k/", Some(own_host), [], Refused),
    Row(
      "the key's first characters",
      "/k/Zk3x9QfW/",
      Some(own_host),
      [],
      Refused,
    ),
    Row(
      "the key and more characters",
      "/k/" <> key <> "x/",
      Some(own_host),
      [],
      Refused,
    ),
    Row(
      "the key under another prefix",
      "/x/k/" <> key <> "/",
      Some(own_host),
      [],
      Refused,
    ),
    Row(
      "the prefix in another case",
      "/K/" <> key <> "/",
      Some(own_host),
      [],
      Refused,
    ),
    Row("the key in the query", "/?key=" <> key, Some(own_host), [], Refused),
    Row(
      "the key in a cookie",
      "/",
      Some(own_host),
      [#("cookie", "dashboard_key=" <> key)],
      Refused,
    ),
    Row(
      "the right key and the right host",
      "/k/" <> key <> "/",
      Some(own_host),
      [],
      Allowed("/"),
    ),
    Row(
      "the right key and a file under it",
      "/k/" <> key <> "/art/cube-cond.ttf",
      Some(own_host),
      [],
      Allowed("/art/cube-cond.ttf"),
    ),
    Row(
      "the right key without the slash after it",
      "/k/" <> key,
      Some(own_host),
      [],
      Allowed(""),
    ),
    Row(
      "the right key and a foreign host",
      "/k/" <> key <> "/",
      Some("rebind.example:7700"),
      [],
      Refused,
    ),
    Row("the right key and no Host", "/k/" <> key <> "/", None, [], Refused),
    Row(
      "the right key and 127.0.0.1 with another port",
      "/k/" <> key <> "/",
      Some("127.0.0.1:7701"),
      [],
      Refused,
    ),
    Row(
      "the right key and the host without a port",
      "/k/" <> key <> "/",
      Some("127.0.0.1"),
      [],
      Refused,
    ),
  ]
  list.each(rows, fn(row) {
    let request =
      dashboard_support.request(
        method: http.Get,
        path: row.path,
        host: row.host,
        headers: row.headers,
      )
    assert access.decide(dashboard_support.gate(), request, Document)
      == row.expected
      as row.reason
  })
}
