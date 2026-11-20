//// The dashboard's gate: whether a request may be answered. A program on this
//// Mac, and every container on the podman machine, reaches the dashboard's
//// loopback port and can set any header, so the port's address is no gate.
////
//// ```text
//// request ──► host is 127.0.0.1:PORT? ──► path is /k/KEY/...? ──► (upgrade) origin is http://127.0.0.1:PORT?
////                  │ no                        │ no                       │ no
////                  └───────────────────────────┴──────────────────────────┴──► Refused
////                                              │ yes
////                                              └──► Allowed(the path inside /k/KEY)
//// ```
////
//// - The key is the first path segment after `/k/`, and every route and the
////   websocket live under that prefix; nothing outside it is answered. It is
////   never a cookie: a browser sends a cookie for `127.0.0.1` to every port,
////   so a page that any container serves on another port would receive it.
//// - A request is allowed with this start's key in the path and `Host`
////   exactly the dashboard's own, which a page that rebinds a host name to
////   this address cannot send.
//// - A websocket upgrade also needs `Origin` exactly the dashboard's own: a
////   browser sets it on a handshake and a page's script cannot change it, so
////   a page of another site in Jim's browser cannot open the socket.
//// - The key is compared in constant time.

import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/http/request.{type Request}
import gleam/int
import gleam/string

/// The address the dashboard listens on and the host it answers to: the
/// literal loopback address, never `localhost` (which a name server or a hosts
/// file could point elsewhere) and never `0.0.0.0`.
pub const loopback = "127.0.0.1"

/// The path segment before the key.
const prefix = "/k/"

/// This start's key and the port the dashboard listens on.
pub type Gate {
  Gate(key: String, port: Int)
}

/// What a request asks for, which decides what it must present.
pub type Kind {
  Document
  Upgrade
}

/// The gate's answer. An allowed request carries its path inside the key
/// prefix, which is what the routes are matched against: `/` for the entry
/// URL, and the empty path when the key is not followed by a slash.
pub type Decision {
  Allowed(path: String)
  Refused
}

/// Decides whether the request may be answered.
pub fn decide(
  gate gate: Gate,
  request request: Request(body),
  kind kind: Kind,
) -> Decision {
  case has_own_host(gate, request), path_inside_prefix(gate, request), kind {
    True, Ok(path), Document -> Allowed(path)
    True, Ok(path), Upgrade ->
      case has_own_origin(gate, request) {
        True -> Allowed(path)
        False -> Refused
      }
    False, _, _ | _, Error(Nil), _ -> Refused
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

/// The URL the operator opens: the key prefix and a slash, which is the first
/// page.
pub fn entry_url(gate gate: Gate) -> String {
  origin(gate.port) <> prefix <> gate.key <> "/"
}

fn has_own_host(gate: Gate, request: Request(body)) -> Bool {
  request.get_header(request, "host") == Ok(host(gate.port))
}

fn has_own_origin(gate: Gate, request: Request(body)) -> Bool {
  request.get_header(request, "origin") == Ok(origin(gate.port))
}

/// The request's path after `/k/KEY`, when `KEY` is this start's key.
fn path_inside_prefix(
  gate: Gate,
  request: Request(body),
) -> Result(String, Nil) {
  use <- bool.guard(!string.starts_with(request.path, prefix), Error(Nil))
  let after_prefix = string.drop_start(request.path, string.length(prefix))
  let #(presented, inside) = case string.split_once(after_prefix, "/") {
    Ok(#(presented, rest)) -> #(presented, "/" <> rest)
    Error(Nil) -> #(after_prefix, "")
  }
  case
    crypto.secure_compare(
      bit_array.from_string(presented),
      bit_array.from_string(gate.key),
    )
  {
    True -> Ok(inside)
    False -> Error(Nil)
  }
}
