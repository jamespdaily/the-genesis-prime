//// The dashboard's navigation, read as the HTML text a browser receives. A
//// later page adds a module and one line in the page list, so the navigation
//// holds one link per page of the list.

import genesis_prime/dashboard/page.{Page}
import gleam/list
import gleam/string
import lustre/element
import owned_test

pub fn the_navigation_lists_every_page_of_the_page_list_test() -> Nil {
  use <- owned_test.run(5000)
  let pages = [Page("Alpha", "/alpha"), Page("Beta", "/beta")]
  let html =
    element.to_string(page.navigation(pages, current: Page("Alpha", "/alpha")))

  // Each link opens with `<a `; the text between two of them is one link.
  let assert [_before, ..links] = string.split(html, "<a ")
  assert list.length(links) == 2
  let assert [alpha, beta] = links
  assert string.contains(alpha, "href=\"/alpha\"")
  assert string.contains(alpha, "Alpha")
  assert string.contains(beta, "href=\"/beta\"")
  assert string.contains(beta, "Beta")
  assert string.contains(alpha, "aria-current=\"page\"")
    as "the current page is marked"
  assert !string.contains(beta, "aria-current") as "no other page is marked"

  let on_beta =
    element.to_string(page.navigation(pages, current: Page("Beta", "/beta")))
  let assert [_, first, second] = string.split(on_beta, "<a ")
  assert !string.contains(first, "aria-current")
  assert string.contains(second, "aria-current=\"page\"")
}
