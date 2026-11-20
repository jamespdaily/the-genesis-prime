//// The dashboard's HTML document: the title bar with a link to every page of the
//// page list, the stylesheets, and the server component element whose runtime
//// the websocket starts. A page is a title and a path inside the key prefix
//// (`dashboard/access`).
////
//// - Every link, stylesheet and the runtime's route is written relative to the
////   document (`style.css`, not `/style.css`), so it stays under the key
////   prefix the document was opened at.
//// - A view names colours and fonts only by the roles `palette.css` defines.

import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/server_component

/// One page of the dashboard: the title its link shows and the path it is
/// served at.
pub type Page {
  Page(title: String, path: String)
}

/// A path inside the key prefix as a link relative to the document: the
/// prefix's own page is `./`, any other path is its name.
fn relative_link(path: String) -> String {
  case string.drop_start(path, 1) {
    "" -> "./"
    name -> name
  }
}

/// The document served for `current`: its runtime connects to `runtime_route`,
/// a path inside the key prefix.
pub fn document(
  pages pages: List(Page),
  current current: Page,
  runtime_route runtime_route: String,
) -> String {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "Genesis Prime - " <> current.title),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(relative_link("/palette.css")),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(relative_link("/style.css")),
      ]),
      server_component.script(),
    ]),
    html.body([], [
      html.div([attribute.class("console")], [
        html.header([attribute.class("bar")], [
          html.span([attribute.class("brand")], [html.text("Genesis Prime")]),
          navigation(pages:, current:),
        ]),
        html.main([attribute.class("page")], [
          server_component.element(
            [server_component.route(relative_link(runtime_route))],
            [],
          ),
        ]),
      ]),
    ]),
  ])
  |> element.to_document_string
}

/// A link to each page, in the page list's order, with `current` marked.
pub fn navigation(
  pages pages: List(Page),
  current current: Page,
) -> Element(message) {
  html.nav(
    [attribute.class("tabs")],
    list.map(pages, fn(page) { link(page, current) }),
  )
}

fn link(page: Page, current: Page) -> Element(message) {
  let marked = case page.path == current.path {
    True -> [attribute.aria_current("page")]
    False -> []
  }
  html.a([attribute.href(relative_link(page.path)), ..marked], [
    html.text(page.title),
  ])
}
