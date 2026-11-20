//// The dashboard's gate: whether a request may be answered. A program on this
//// Mac, and every container on the podman machine, reaches the dashboard's
//// loopback port and can set any header, so the port's address is no gate.
////
//// ```text
//// request ──► host is 127.0.0.1:PORT? ──► key presented? ──► (upgrade) origin is http://127.0.0.1:PORT?
////                  │ no                        │ no                     │ no
////                  └───────────────────────────┴────────────────────────┴──► Refused
//// ```
////
//// - A page, a stylesheet or a font is allowed with this start's key in the
////   `dashboard_key` cookie and `Host` exactly the dashboard's own, which a
////   page that rebinds a host name to this address cannot send.
//// - The entry (`/enter?key=`) is allowed with the key in its query and the
////   same `Host`; it is where the cookie comes from.
//// - A websocket upgrade also needs `Origin` exactly the dashboard's own: a
////   browser sets it on a handshake and a page's script cannot change it, so
////   a page of another site in Jim's browser cannot open the socket.
//// - A key is compared in constant time, and a request that presents the key
////   twice is allowed only when every copy is right.

import gleam/bit_array
import gleam/crypto
import gleam/http/request.{type Request}
import gleam/int
import gleam/list
import gleam/result

/// The address the dashboard listens on and the host it answers to: the
/// literal loopback address, never `localhost` (which a name server or a hosts
/// file could point elsewhere) and never `0.0.0.0`.
pub const loopback = "127.0.0.1"

/// The name of the cookie that carries the key.
pub const cookie_name = "dashboard_key"

/// This start's key and the port the dashboard listens on.
pub type Gate {
  Gate(key: String, port: Int)
}

/// What a request asks for, which decides what it must present.
pub type Kind {
  Document
  Upgrade
  Entry
}

/// The gate's answer.
pub type Decision {
  Allowed
  Refused
}

/// Decides whether the request may be answered.
pub fn decide(
  gate gate: Gate,
  request request: Request(body),
  kind kind: Kind,
) -> Decision {
  let allowed =
    has_own_host(gate, request)
    && case kind {
      Document -> cookie_holds_key(gate, request)
      Upgrade ->
        cookie_holds_key(gate, request) && has_own_origin(gate, request)
      Entry -> query_holds_key(gate, request)
    }
  case allowed {
    True -> Allowed
    False -> Refused
  }
}

/// The `Host` a request to the dashboard carries.
fn host(port: Int) -> String {
  loopback <> ":" <> int.to_string(port)
}

/// The `Origin` of a page the dashboard served.
pub fn origin(port: Int) -> String {
  "http://" <> host(port)
}

/// The URL that exchanges the key for the cookie, which the operator opens.
pub fn entry_url(gate gate: Gate) -> String {
  origin(gate.port) <> "/enter?key=" <> gate.key
}

fn has_own_host(gate: Gate, request: Request(body)) -> Bool {
  request.get_header(request, "host") == Ok(host(gate.port))
}

fn has_own_origin(gate: Gate, request: Request(body)) -> Bool {
  request.get_header(request, "origin") == Ok(origin(gate.port))
}

fn cookie_holds_key(gate: Gate, request: Request(body)) -> Bool {
  request.get_cookies(request)
  |> list.filter(fn(cookie) { cookie.0 == cookie_name })
  |> list.map(fn(cookie) { cookie.1 })
  |> every_copy_is_the_key(gate)
}

fn query_holds_key(gate: Gate, request: Request(body)) -> Bool {
  request.get_query(request)
  |> result.unwrap([])
  |> list.filter(fn(pair) { pair.0 == "key" })
  |> list.map(fn(pair) { pair.1 })
  |> every_copy_is_the_key(gate)
}

fn every_copy_is_the_key(presented: List(String), gate: Gate) -> Bool {
  presented != []
  && list.all(presented, fn(copy) {
    crypto.secure_compare(
      bit_array.from_string(copy),
      bit_array.from_string(gate.key),
    )
  })
}
