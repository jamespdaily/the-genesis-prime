//// The dashboard's allow-list of files. Expected values are the client's
//// fonts folder (`UI/Fonts` holds `CubeOffcCond.ttf`, `CubeOffcCondLight.ttf`,
//// `segoeui.ttf` and `seguisb.ttf`) and the two stylesheets in `dev/dashboard`:
//// the dashboard serves those six names and nothing else a request can spell.

import genesis_prime/dashboard/art.{Asset, ClientFonts, DashboardFolder}
import gleam/list
import owned_test

pub fn art_serves_only_the_named_files_test() -> Nil {
  use <- owned_test.run(5000)
  let named = [
    #(
      "/art/cube-cond.ttf",
      Asset("/art/cube-cond.ttf", ClientFonts, "CubeOffcCond.ttf", "font/ttf"),
    ),
    #(
      "/art/cube-cond-light.ttf",
      Asset(
        "/art/cube-cond-light.ttf",
        ClientFonts,
        "CubeOffcCondLight.ttf",
        "font/ttf",
      ),
    ),
    #(
      "/art/segoe-ui.ttf",
      Asset("/art/segoe-ui.ttf", ClientFonts, "segoeui.ttf", "font/ttf"),
    ),
    #(
      "/art/segoe-ui-semibold.ttf",
      Asset(
        "/art/segoe-ui-semibold.ttf",
        ClientFonts,
        "seguisb.ttf",
        "font/ttf",
      ),
    ),
    #(
      "/style.css",
      Asset(
        "/style.css",
        DashboardFolder,
        "style.css",
        "text/css; charset=utf-8",
      ),
    ),
    #(
      "/palette.css",
      Asset(
        "/palette.css",
        DashboardFolder,
        "palette.css",
        "text/css; charset=utf-8",
      ),
    ),
  ]
  list.each(named, fn(row) {
    assert art.find(row.0) == Ok(row.1) as row.0
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
    #("the folder", "/art"),
    #("a directory name", "/art/UI"),
    #("a font under the root", "/cube-cond.ttf"),
    #("a stylesheet in the fonts folder", "/art/style.css"),
    #("another case", "/ART/cube-cond.ttf"),
  ]
  list.each(refused, fn(row) {
    assert art.find(row.1) == Error(Nil) as row.0
  })
}
