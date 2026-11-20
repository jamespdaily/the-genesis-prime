//// The dashboard's web layer over plain requests and responses. Expected
//// values are the security rule: the key leaves the URL after the entry, a
//// stranger learns only that the port is open, no answer is cached or
//// leaves a referrer, and nothing but the authenticated websocket changes
//// anything.

import dashboard_support
import genesis_prime/dashboard/web
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

fn entry(path: String) -> Request(String) {
  dashboard_support.request(
    method: http.Get,
    path:,
    host: Some("127.0.0.1:7700"),
    headers: [],
  )
}

pub fn the_entry_exchanges_the_key_for_a_cookie_and_leaves_no_key_in_the_url_test() -> Nil {
  use <- owned_test.run(5000)
  let context = dashboard_support.context(files: [])
  let right =
    dashboard_support.answer(
      context,
      entry("/enter?key=" <> dashboard_support.key),
    )
  assert right.status == 303
  assert response.get_header(right, "location") == Ok("/")
  let assert Ok(cookie) = response.get_header(right, "set-cookie")
    as "the entry set no cookie"
  let attributes = string.split(cookie, "; ")
  assert list.contains(attributes, "dashboard_key=" <> dashboard_support.key)
  assert list.contains(attributes, "HttpOnly")
  assert list.contains(attributes, "SameSite=Strict")
  assert list.contains(attributes, "Path=/")
  assert !list.contains(attributes, "Secure")
    as "a Secure cookie is not sent back by every browser on plain http"

  let refused = [
    #("a wrong key", entry("/enter?key=wrong")),
    #("an empty key", entry("/enter?key=")),
    #("no key", entry("/enter")),
    #(
      "a POST with the right key",
      dashboard_support.request(
        method: http.Post,
        path: "/enter?key=" <> dashboard_support.key,
        host: Some("127.0.0.1:7700"),
        headers: [],
      ),
    ),
    #(
      "the right key on a foreign host",
      dashboard_support.request(
        method: http.Get,
        path: "/enter?key=" <> dashboard_support.key,
        host: Some("rebind.example:7700"),
        headers: [],
      ),
    ),
  ]
  list.each(refused, fn(row) {
    let reply = dashboard_support.answer(context, row.1)
    assert reply.status == 403 as row.0
    assert response.get_header(reply, "set-cookie") == Error(Nil) as row.0
  })
}

pub fn every_answer_forbids_caching_and_referrers_test() -> Nil {
  use <- owned_test.run(5000)
  let with_style =
    dashboard_support.context(files: [
      #("styles/style.css", <<"body {}">>),
    ])
  let cookie = Some("dashboard_key=" <> dashboard_support.key)
  let rows = [
    #("a 403", dashboard_support.get("/", None), 403),
    #("the page", dashboard_support.get("/", cookie), 200),
    #("a 303", entry("/enter?key=" <> dashboard_support.key), 303),
    #("a 404 font", dashboard_support.get("/art/cube-cond.ttf", cookie), 404),
    #("a stylesheet", dashboard_support.get("/style.css", cookie), 200),
    #(
      "an unknown path behind the key",
      dashboard_support.get("/nothing", cookie),
      404,
    ),
  ]
  list.each(rows, fn(row) {
    let reply = dashboard_support.answer(with_style, row.1)
    assert reply.status == row.2 as row.0
    assert response.get_header(reply, "cache-control") == Ok("no-store")
      as row.0
    assert response.get_header(reply, "referrer-policy") == Ok("no-referrer")
      as row.0
  })
}

pub fn a_refused_request_gets_one_empty_answer_whatever_the_path_test() -> Nil {
  use <- owned_test.run(5000)
  let context = dashboard_support.context(files: [])
  let paths = [
    "/",
    "/style.css",
    "/art/cube-cond.ttf",
    "/ws",
    "/enter",
    "/nothing",
  ]
  let answers =
    list.map(paths, fn(path) {
      dashboard_support.answer(context, dashboard_support.get(path, None))
    })
  let assert [first, ..rest] = answers
  assert first.status == 403
  assert first.body == <<>>
  list.each(rest, fn(answer) {
    assert answer.status == first.status
    assert answer.body == first.body
    assert sorted(answer.headers) == sorted(first.headers)
  })
}

pub fn no_route_but_the_websocket_changes_anything_test() -> Nil {
  use <- owned_test.run(5000)
  let routes = web.routes(dashboard_support.pages())
  assert reads_only(routes)
  assert !reads_only([web.Route(http.Post, "/stop", web.EntryExchange)])
    as "a table that lists a POST fails the check"

  // A method other than GET is refused on every route, with every credential.
  let context = dashboard_support.context(files: [])
  list.each(routes, fn(route) {
    list.each([http.Post, http.Put, http.Delete, http.Patch], fn(method) {
      let request =
        dashboard_support.request(
          method:,
          path: route.path <> "?key=" <> dashboard_support.key,
          host: Some("127.0.0.1:7700"),
          headers: [
            #("cookie", "dashboard_key=" <> dashboard_support.key),
            #("origin", "http://127.0.0.1:7700"),
          ],
        )
      assert dashboard_support.answer(context, request) == web.refusal()
        as { http.method_to_string(method) <> " " <> route.path }
    })
  })
}

/// Every route is a GET, and exactly one of them is the websocket upgrade.
fn reads_only(routes: List(web.Route)) -> Bool {
  list.all(routes, fn(route) { route.method == http.Get })
  && list.count(routes, fn(route) { route.serves == web.Websocket }) == 1
}

fn sorted(headers: List(#(String, String))) -> List(#(String, String)) {
  list.sort(headers, fn(first, second) {
    string.compare(first.0 <> first.1, second.0 <> second.1)
  })
}
