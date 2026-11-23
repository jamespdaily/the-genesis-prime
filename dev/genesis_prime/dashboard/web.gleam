//// The dashboard's routes and what each answers, over plain requests and
//// responses so every decision is a function of the request.
////
//// ```text
//// request ──► access.decide ──► route by method and path inside /k/KEY ──► serve the route
////                  │ Refused                      │ none
////                  ▼                              ▼
////     the one refusal (403, empty, sealed)      404, sealed
//// ```
////
//// - The route table lists `GET` routes and one websocket upgrade for each
////   page: nothing but the authenticated websocket changes anything. A route is found by its
////   method and its path inside the key prefix, so a method the table does not
////   list for a path is not served.
//// - A refused request gets one answer whatever its path, so the port tells a
////   stranger only that it is open; a path that is not in the table is a 404
////   only behind the key.
//// - Every answer carries `Cache-Control: no-store` and `Referrer-Policy:
////   no-referrer` (the key sits in the URL, and a cache or a referrer would
////   copy it) and forbids framing with `Content-Security-Policy:
////   frame-ancestors 'none'` and `X-Frame-Options: DENY` (a page of another
////   port on `127.0.0.1` must not frame the dashboard).
//// - No answer sets a cookie: the key rides in the path (`dashboard/access`).

import genesis_prime/dashboard/access.{
  type Gate, Allowed, Document, Refused, Upgrade as UpgradeRequest,
}
import genesis_prime/dashboard/art
import genesis_prime/dashboard/page.{type Page}
import gleam/bit_array
import gleam/http.{type Method, Get}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list

/// What a route answers.
pub type Serves {
  PageDocument(page: Page)
  Asset(asset: art.Asset)
  Websocket(page: Page)
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
/// upgraded to the websocket of a page's runtime.
pub type Outcome {
  Answer(response: Response(BitArray))
  Upgrade(page: Page)
}

/// Every route: each page and its websocket, and each file of the allow-list.
pub fn routes(pages: List(Page)) -> List(Route) {
  list.flatten([
    list.map(pages, fn(page) { Route(Get, page.path, PageDocument(page)) }),
    list.map(art.assets(), fn(asset) { Route(Get, asset.path, Asset(asset)) }),
    list.map(pages, fn(page) {
      Route(Get, page.runtime_path(page), Websocket(page))
    }),
  ])
}

/// The route listed for this method and this path inside the key prefix. The
/// match is on the whole path, so no other spelling of a path finds a route.
fn find_route(
  routes routes: List(Route),
  method method: Method,
  path path: String,
) -> Result(Route, Nil) {
  list.find(routes, fn(route) { route.method == method && route.path == path })
}

/// Decides what a request gets.
pub fn handle(
  context context: Context,
  request request: Request(body),
) -> Outcome {
  case access.decide(context.gate, request, Document) {
    Refused -> Answer(refusal())
    Allowed(path) ->
      case
        find_route(routes: routes(context.pages), method: request.method, path:)
      {
        Error(Nil) -> Answer(seal(not_found()))
        Ok(route) -> serve(context:, request:, serves: route.serves)
      }
  }
}

/// The answer of a route the gate allowed. A websocket upgrade also needs the
/// dashboard's own origin.
fn serve(
  context context: Context,
  request request: Request(body),
  serves serves: Serves,
) -> Outcome {
  case serves {
    Websocket(page) ->
      case access.decide(context.gate, request, UpgradeRequest) {
        Allowed(_) -> Upgrade(page)
        Refused -> Answer(refusal())
      }
    PageDocument(page) ->
      Answer(
        seal(content(
          "text/html; charset=utf-8",
          bit_array.from_string(page.document(context.pages, page)),
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

/// The headers every answer carries.
fn seal(response: Response(BitArray)) -> Response(BitArray) {
  response
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("referrer-policy", "no-referrer")
  |> response.set_header("content-security-policy", "frame-ancestors 'none'")
  |> response.set_header("x-frame-options", "DENY")
}

/// The one answer to a request that may not be answered.
pub fn refusal() -> Response(BitArray) {
  seal(response.new(403) |> response.set_body(<<>>))
}
