//// The dashboard's gate. Expected values are the gate's rule: a container on
//// this Mac reaches the dashboard's loopback port and can set any header, so
//// a request is allowed only with this start's key in the `dashboard_key`
//// cookie and the dashboard's own host; a websocket handshake also needs the
//// dashboard's own origin, which a page's script cannot change.

import dashboard_support
import genesis_prime/dashboard/access.{Allowed, Document, Refused, Upgrade}
import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test

type Row {
  Row(
    reason: String,
    cookie: Option(String),
    host: Option(String),
    expected: access.Decision,
  )
}

const own_host = "127.0.0.1:7700"

pub fn a_request_is_allowed_only_with_this_starts_key_and_the_dashboards_own_host_test() -> Nil {
  use <- owned_test.run(5000)
  let right = "dashboard_key=" <> dashboard_support.key
  let rows = [
    Row("no cookie", None, Some(own_host), Refused),
    Row(
      "a cookie of another name",
      Some("session=" <> dashboard_support.key),
      Some(own_host),
      Refused,
    ),
    Row("a wrong key", Some("dashboard_key=wrong"), Some(own_host), Refused),
    Row(
      "the previous start's key",
      Some("dashboard_key=" <> dashboard_support.previous_key),
      Some(own_host),
      Refused,
    ),
    Row(
      "the right key and the right host",
      Some(right),
      Some(own_host),
      Allowed,
    ),
    Row(
      "the right key and a foreign host",
      Some(right),
      Some("rebind.example:7700"),
      Refused,
    ),
    Row("the right key and no Host", Some(right), None, Refused),
    Row(
      "the right key and 127.0.0.1 with another port",
      Some(right),
      Some("127.0.0.1:7701"),
      Refused,
    ),
    Row(
      "the right key and the host without a port",
      Some(right),
      Some("127.0.0.1"),
      Refused,
    ),
    Row(
      "the key twice, the wrong one last",
      Some(right <> "; dashboard_key=wrong"),
      Some(own_host),
      Refused,
    ),
    Row(
      "the key twice, the wrong one first",
      Some("dashboard_key=wrong; " <> right),
      Some(own_host),
      Refused,
    ),
    Row(
      "the right key among other cookies",
      Some("theme=dark; " <> right <> "; lang=en"),
      Some(own_host),
      Allowed,
    ),
  ]
  list.each(rows, fn(row) {
    let headers = case row.cookie {
      Some(cookie) -> [#("cookie", cookie)]
      None -> []
    }
    let request =
      dashboard_support.request(
        method: http.Get,
        path: "/",
        host: row.host,
        headers:,
      )
    assert access.decide(dashboard_support.gate(), request, Document)
      == row.expected
      as row.reason
  })
}

type Handshake {
  Handshake(
    reason: String,
    cookie: String,
    origin: Option(String),
    expected: access.Decision,
  )
}

pub fn a_websocket_upgrade_also_needs_the_dashboards_own_origin_test() -> Nil {
  use <- owned_test.run(5000)
  let right = "dashboard_key=" <> dashboard_support.key
  let rows = [
    Handshake("no Origin", right, None, Refused),
    Handshake("an Origin of null", right, Some("null"), Refused),
    Handshake(
      "127.0.0.1 on another port",
      right,
      Some("http://127.0.0.1:7701"),
      Refused,
    ),
    Handshake(
      "localhost on the port",
      right,
      Some("http://localhost:7700"),
      Refused,
    ),
    Handshake(
      "https on the port",
      right,
      Some("https://127.0.0.1:7700"),
      Refused,
    ),
    Handshake("a foreign site", right, Some("https://evil.example"), Refused),
    Handshake("the right origin", right, Some("http://127.0.0.1:7700"), Allowed),
    Handshake(
      "a good origin with a wrong key",
      "dashboard_key=wrong",
      Some("http://127.0.0.1:7700"),
      Refused,
    ),
  ]
  list.each(rows, fn(row) {
    let headers = case row.origin {
      Some(origin) -> [#("cookie", row.cookie), #("origin", origin)]
      None -> [#("cookie", row.cookie)]
    }
    let request =
      dashboard_support.request(
        method: http.Get,
        path: "/ws",
        host: Some(own_host),
        headers:,
      )
    assert access.decide(dashboard_support.gate(), request, Upgrade)
      == row.expected
      as row.reason
  })
}
