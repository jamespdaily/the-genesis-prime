//// The dashboard's routes and what each answers, over plain requests and
//// responses so every decision is a function of the request.
////
//// ```text
//// request ──► GET? ──► route by path ──► access.decide ──► serve the route
////               │ no                          │ Refused
////               └──────────────► the one refusal (403, empty, sealed)
//// ```
////
//// - The route table lists `GET` routes and the one websocket upgrade: nothing
////   but the authenticated websocket changes anything, and a request of any
////   other method is refused like any request without the key.
//// - A refused request gets one answer whatever its path, so the port tells a
////   stranger only that it is open; a path that is not in the table is a 404
////   only behind the key.
//// - Every answer carries `Cache-Control: no-store` and `Referrer-Policy:
////   no-referrer`: the key sits in the entry URL, and a cache or a referrer
////   would copy it.
//// - `/enter?key=` trades the key for the `dashboard_key` cookie and redirects
////   to `/`, so the key leaves the address bar.

import genesis_prime/dashboard/access.{
  type Gate, Allowed, Document, Entry, Refused, Upgrade as UpgradeRequest,
}
import genesis_prime/dashboard/art
import genesis_prime/dashboard/page.{type Page}
import gleam/bit_array
import gleam/http.{type Method, Get}
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None, Some}

/// What a route answers.
pub type Serves {
  PageDocument(page: Page)
  Asset(asset: art.Asset)
  EntryExchange
  Websocket
}

/// One route: a method, a path and what it serves.
pub type Route {
  Route(method: Method, path: String, serves: Serves)
}

/// What the web layer needs: the gate, the page list, how a file is read (the
/// path is the folder and the file name) and where the two folders of served
/// files are.
pub type Context {
  Context(
    gate: Gate,
    pages: List(Page),
    read_file: fn(String) -> Result(BitArray, Nil),
    client_fonts_folder: String,
    stylesheet_folder: String,
  )
}

/// What the web layer does with a request: answer it, or hand it on to be
/// upgraded to the page's websocket.
pub type Outcome {
  Answer(response: Response(BitArray))
  Upgrade
}

/// The path the page's runtime connects to.
const runtime_route = "/ws"

/// Every route: each page, each file of the allow-list, the entry and the
/// websocket.
pub fn routes(pages: List(Page)) -> List(Route) {
  list.flatten([
    list.map(pages, fn(page) { Route(Get, page.path, PageDocument(page)) }),
    list.map(art.assets(), fn(asset) { Route(Get, asset.path, Asset(asset)) }),
    [
      Route(Get, "/enter", EntryExchange),
      Route(Get, runtime_route, Websocket),
    ],
  ])
}

/// Decides what a request gets.
pub fn handle(
  context context: Context,
  request request: Request(body),
) -> Outcome {
  case request.method {
    Get -> {
      let route =
        list.find(routes(context.pages), fn(route) {
          route.path == request.path
        })
      let kind = case route {
        Ok(Route(serves: Websocket, ..)) -> UpgradeRequest
        Ok(Route(serves: EntryExchange, ..)) -> Entry
        _ -> Document
      }
      case access.decide(context.gate, request, kind), route {
        Refused, _ -> Answer(refusal())
        Allowed, Error(Nil) -> Answer(seal(not_found()))
        Allowed, Ok(route) -> serve(context, route.serves)
      }
    }
    _ -> Answer(refusal())
  }
}

fn serve(context: Context, serves: Serves) -> Outcome {
  case serves {
    Websocket -> Upgrade
    EntryExchange -> Answer(seal(entry_exchange(context.gate)))
    PageDocument(page) ->
      Answer(
        seal(content(
          "text/html; charset=utf-8",
          bit_array.from_string(page.document(
            context.pages,
            page,
            runtime_route,
          )),
        )),
      )
    Asset(asset) -> {
      let folder = case asset.location {
        art.ClientFonts -> context.client_fonts_folder
        art.DashboardFolder -> context.stylesheet_folder
      }
      case context.read_file(folder <> "/" <> asset.file_name) {
        Ok(bytes) -> Answer(seal(content(asset.media_type, bytes)))
        Error(Nil) -> Answer(seal(not_found()))
      }
    }
  }
}

fn content(media_type: String, body: BitArray) -> Response(BitArray) {
  response.new(200)
  |> response.set_header("content-type", media_type)
  |> response.set_body(body)
}

fn not_found() -> Response(BitArray) {
  response.new(404) |> response.set_body(<<>>)
}

/// The cookie that carries the key, set on the redirect to the first page.
fn entry_exchange(gate: Gate) -> Response(BitArray) {
  let attributes =
    cookie.Attributes(
      max_age: None,
      domain: None,
      path: Some("/"),
      secure: False,
      http_only: True,
      same_site: Some(cookie.Strict),
    )
  response.redirect("/")
  |> response.set_cookie(access.cookie_name, gate.key, attributes)
  |> response.map(fn(_) { <<>> })
}

/// The headers every answer carries.
fn seal(response: Response(BitArray)) -> Response(BitArray) {
  response
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("referrer-policy", "no-referrer")
}

/// The one answer to a request that may not be answered.
pub fn refusal() -> Response(BitArray) {
  seal(response.new(403) |> response.set_body(<<>>))
}
