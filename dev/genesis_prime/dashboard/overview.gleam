//// The Overview page: a card for each thing it will show, each saying that
//// there is no reading yet. It is a server component with no state; a later
//// page of readings gives it a model and messages.

import genesis_prime/dashboard/page.{type Page, Page}
import gleam/list
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// The cards, by the title each shows.
const cards = ["Play service", "Play database", "Updater", "Live lock"]

/// The Overview as an entry of the page list.
pub fn page() -> Page {
  Page(title: "Overview", path: "/")
}

/// The Overview's content.
fn view() -> Element(message) {
  html.section([], [
    html.h2([], [html.text("Overview")]),
    html.div(
      [attribute.class("grid")],
      list.map(cards, fn(title) {
        html.div([attribute.class("card")], [
          html.div([attribute.class("label")], [html.text(title)]),
          html.p([attribute.class("empty")], [html.text("No reading yet")]),
        ])
      }),
    ),
  ])
}

/// The Overview as a server component, which sends no message to itself.
pub fn app() -> lustre.App(Nil, Nil, Nil) {
  lustre.element(view())
}
