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
      web.Websocket(page:) -> {
        assert web.handle(context, inside) == web.Upgrade(page) as route.path
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
