//// The dashboard's allow-list of files, asked of the route the server serves
//// (a request for each path through `web.handle`). Expected values are the
//// client's fonts folder (`UI/Fonts` holds `CubeOffcCond.ttf`,
//// `CubeOffcCondLight.ttf`, `segoeui.ttf` and `seguisb.ttf`) and the two
//// stylesheets in `dev/dashboard`: the dashboard serves those six names and
//// nothing else a request can spell.

import dashboard_support
import genesis_prime/dashboard/art
import gleam/bit_array
import gleam/http/response
import gleam/list
import owned_test

pub fn art_serves_only_the_named_files_test() -> Nil {
  use <- owned_test.run(5000)
  // Every file is planted, holding "planted " and where it is read from, so a
  // reply holds the file its path names or no file.
  let context =
    dashboard_support.context(files: dashboard_support.planted_files())
  let named = [
    #("/art/cube-cond.ttf", "fonts/CubeOffcCond.ttf", "font/ttf"),
    #("/art/cube-cond-light.ttf", "fonts/CubeOffcCondLight.ttf", "font/ttf"),
    #("/art/segoe-ui.ttf", "fonts/segoeui.ttf", "font/ttf"),
    #("/art/segoe-ui-semibold.ttf", "fonts/seguisb.ttf", "font/ttf"),
    #("/style.css", "styles/style.css", "text/css; charset=utf-8"),
    #("/palette.css", "styles/palette.css", "text/css; charset=utf-8"),
  ]
  list.each(named, fn(row) {
    let reply =
      dashboard_support.answer(
        context,
        dashboard_support.get(dashboard_support.inside(row.0)),
      )
    assert reply.status == 200 as row.0
    assert reply.body == bit_array.from_string("planted " <> row.1) as row.0
    assert response.get_header(reply, "content-type") == Ok(row.2) as row.0
  })
  assert list.length(art.assets()) == 6

  let refused = [
    #("a name that is not listed", "/art/x.ttf"),
    #("a parent folder", "/art/../state.json"),
    #("an encoded parent", "/art/%2e%2e"),
    #("a twice encoded parent", "/art/%252e%252e"),
    #("a parent and an encoded slash", "/art/..%2f"),
    #("a backslash form", "/art/..\\state.json"),
    #("an empty name", "/art/"),
    #("a trailing slash", "/art/cube-cond.ttf/"),
    #("a name and more characters", "/art/cube-cond.ttf.bak"),
    #("a name's first characters", "/art/cube-cond"),
    #("an encoded name", "/art/cube%2dcond.ttf"),
    #("the folder", "/art"),
    #("a directory name", "/art/UI"),
    #("a font under the root", "/cube-cond.ttf"),
    #("a stylesheet in the fonts folder", "/art/style.css"),
    #("a stylesheet and a trailing slash", "/style.css/"),
    #("another case", "/ART/cube-cond.ttf"),
  ]
  list.each(refused, fn(row) {
    let reply =
      dashboard_support.answer(
        context,
        dashboard_support.get(dashboard_support.inside(row.1)),
      )
    assert reply.status == 404 as row.0
    assert reply.body == <<>> as row.0
  })
}
