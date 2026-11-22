//// How a page's runtime subscribes to what it shows. The expected value is the
//// rule of a page: what the process answers the moment a page joins reaches
//// the page, however fast the answer comes (a process that has an answer
//// hands it over inside the join).

import genesis_prime/dashboard/subscription
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/list
import gleam/string
import lustre
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/server_component
import open_wait
import owned_test

/// A page that lists what it was sent, and joins through `subscription`.
type Message {
  Received(text: String)
  Joining(join: fn() -> Nil)
}

fn app() -> lustre.App(fn(Subject(String)) -> Nil, List(String), Message) {
  lustre.application(init, update, view)
}

fn init(
  join: fn(Subject(String)) -> Nil,
) -> #(List(String), effect.Effect(Message)) {
  #([], subscription.open(join:, received: Received, joining: Joining))
}

fn update(
  model: List(String),
  message: Message,
) -> #(List(String), effect.Effect(Message)) {
  case message {
    Received(text:) -> #([text, ..model], effect.none())
    Joining(join:) -> #(model, subscription.joined(join))
  }
}

fn view(model: List(String)) -> Element(Message) {
  html.ul([], list.map(model, fn(text) { html.li([], [html.text(text)]) }))
}

pub fn a_page_is_handed_what_the_process_answers_inside_its_join_test() -> Nil {
  use <- owned_test.run(10_000)
  let joined = process.new_subject()
  let answer = "an answer sent inside the join"
  let join = fn(subscriber) {
    process.send(subscriber, answer)
    process.send(joined, Nil)
  }
  let assert Ok(runtime) = lustre.start_server_component(app(), join)
  let runtime = server_component.subject(runtime)
  open_wait.received(from: joined, what: "the page's join to be made")

  // The join is made and its answer is sent, so a client that registers now
  // is sent a page that holds it.
  let client = process.new_subject()
  process.send(runtime, server_component.register_subject(client))
  let mounted =
    open_wait.received(from: client, what: "the runtime's first message")
  assert string.contains(
    json.to_string(server_component.client_message_to_json(mounted)),
    answer,
  )
    as "the page does not hold what the process answered inside the join"
  process.send(runtime, lustre.shutdown())
}
