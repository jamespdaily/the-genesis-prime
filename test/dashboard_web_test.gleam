//// The dashboard's web layer over plain requests and responses. Expected
//// values are the security rule: the key rides in the path and is never a
//// cookie, a stranger learns only that the port is open, no answer is cached,
//// leaves a referrer or can be framed, and nothing but the authenticated
//// websocket changes anything.

import dashboard_support
import genesis_prime/dashboard/access
import genesis_prime/dashboard/web
import gleam/bit_array
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test

const own_host = "127.0.0.1:7700"

fn with_origin(path: String) -> Request(String) {
  dashboard_support.request(
    method: http.Get,
    path:,
    host: Some(own_host),
    headers: [#("origin", "http://127.0.0.1:7700")],
  )
}

pub fn the_key_rides_in_the_path_and_no_cookie_is_ever_set_test() -> Nil {
  use <- owned_test.run(5000)
  let context =
    dashboard_support.context(files: dashboard_support.planted_files())

  // The entry URL is the key prefix and a slash, and it opens the page.
  let gate = dashboard_support.gate()
  assert access.entry_url(gate)
    == "http://127.0.0.1:7700/k/Zk3x9QfW1m7TnV0cH4dYbR8uLs2PaE6jXgIoKqM5wNA/"
  let page =
    dashboard_support.answer(
      context,
      dashboard_support.get("/k/Zk3x9QfW1m7TnV0cH4dYbR8uLs2PaE6jXgIoKqM5wNA/"),
    )
  assert page.status == 200
  assert string.contains(result_text(page.body), "lustre-server-component")

  // Every route lives under the prefix: with it the route answers (the
  // websocket upgrades), without it the one refusal. No answer sets a cookie.
  list.each(web.routes(dashboard_support.pages()), fn(route) {
    let inside = with_origin(dashboard_support.inside(route.path))
    let outside = with_origin(route.path)
    case route.serves {
      web.Websocket -> {
        assert web.handle(context, inside) == web.Upgrade as route.path
        assert web.handle(context, outside) == web.Answer(web.refusal())
          as route.path
      }
      web.PageDocument(_) | web.Asset(_) -> {
        let answered = dashboard_support.answer(context, inside)
        assert answered.status == 200 as route.path
        assert response.get_header(answered, "set-cookie") == Error(Nil)
          as route.path
        assert dashboard_support.answer(context, outside) == web.refusal()
          as route.path
      }
    }
  })

  // A wrong, empty or missing key is the one refusal, with no cookie.
  let refused = [
    #("a wrong key", "/k/wrong/"),
    #("an empty key", "/k//"),
    #("no key", "/k/"),
    #("no prefix", "/"),
    #("the old entry path with the key in the query", "/enter?key=right"),
  ]
  list.each(refused, fn(row) {
    let reply = dashboard_support.answer(context, dashboard_support.get(row.1))
    assert reply == web.refusal() as row.0
    assert response.get_header(reply, "set-cookie") == Error(Nil) as row.0
  })
}

fn result_text(body: BitArray) -> String {
  let assert Ok(text) = bit_array.to_string(body)
  text
}

pub fn every_answer_forbids_caching_and_referrers_test() -> Nil {
  use <- owned_test.run(5000)
  let with_style =
    dashboard_support.context(files: [
      #("styles/style.css", <<"body {}">>),
    ])
  let rows = [
    #("a 403", dashboard_support.get("/"), 403),
    #("the page", dashboard_support.get(dashboard_support.inside("/")), 200),
    #(
      "a 404 font",
      dashboard_support.get(dashboard_support.inside("/art/cube-cond.ttf")),
      404,
    ),
    #(
      "a stylesheet",
      dashboard_support.get(dashboard_support.inside("/style.css")),
      200,
    ),
    #(
      "an unknown path behind the key",
      dashboard_support.get(dashboard_support.inside("/nothing")),
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
    assert response.get_header(reply, "content-security-policy")
      == Ok("frame-ancestors 'none'")
      as row.0
    assert response.get_header(reply, "x-frame-options") == Ok("DENY") as row.0
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
    "/k/",
    "/k/wrong/",
    "/k/wrong/style.css",
    "/k/wrong/ws",
  ]
  let answers =
    list.map(paths, fn(path) {
      dashboard_support.answer(context, dashboard_support.get(path))
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
  assert !reads_only([web.Route(http.Post, "/stop", web.Websocket)])
    as "a table that lists a POST fails the check"

  // The lookup reads the route's method: a route listed for POST is found by
  // a POST and not by a GET.
  let with_post = [web.Route(http.Post, "/stop", web.Websocket)]
  assert web.find_route(with_post, http.Post, "/stop")
    == Ok(web.Route(http.Post, "/stop", web.Websocket))
  assert web.find_route(with_post, http.Get, "/stop") == Error(Nil)

  // A method other than GET is never served: without the key it is the one
  // refusal, and with every credential no route is found.
  let context =
    dashboard_support.context(files: dashboard_support.planted_files())
  list.each(routes, fn(route) {
    list.each([http.Post, http.Put, http.Delete, http.Patch], fn(method) {
      let label = http.method_to_string(method) <> " " <> route.path
      let keyed =
        dashboard_support.request(
          method:,
          path: dashboard_support.inside(route.path),
          host: Some(own_host),
          headers: [#("origin", "http://127.0.0.1:7700")],
        )
      let answered = dashboard_support.answer(context, keyed)
      assert answered.status == 404 as label
      assert answered.body == <<>> as label
      let unkeyed =
        dashboard_support.request(
          method:,
          path: route.path,
          host: Some(own_host),
          headers: [#("origin", "http://127.0.0.1:7700")],
        )
      assert dashboard_support.answer(context, unkeyed) == web.refusal()
        as label
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
