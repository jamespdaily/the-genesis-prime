//// The message module rule (`code_rule/message_module`): the planted cases show what a
//// breach is, and the real map message module is read against it. The types it must
//// hold are the map's inbox (`Message`), what the map answers and sends (`Outgoing`,
//// `Notice`, `NotJoined`, `NotSummoned`) and the payloads a creature and a player tell
//// through the map (`Payload`, `Delivered`, `Inbound`, `Landing`).

import code_rule/message_module
import code_rule/planted
import code_rule/source
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

const map_message_types = [
  "Message", "Outgoing", "Notice", "NotJoined", "NotSummoned", "Payload",
  "Delivered", "Inbound", "Landing",
]

pub fn the_map_message_module_holds_types_only_and_no_function_that_reads_a_state_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(
        ["type Inbox {", "  Ping", "}"],
        ["Inbox"],
        [],
        "a module of types passes",
      ),
      #(
        [
          "type Inbox {",
          "  Ping",
          "}",
          "",
          "fn count(state: Int) -> Int {",
          "  state",
          "}",
        ],
        ["Inbox"],
        [#(5, "a message module holds no function, and count is one")],
        "a private function that reads a state fails at its line",
      ),
      #(
        [
          "pub type Inbox {",
          "  Ping",
          "}",
          "",
          "pub fn peek(state: Inbox) -> Inbox {",
          "  state",
          "}",
        ],
        ["Inbox"],
        [#(5, "a message module holds no function, and peek is one")],
        "a public function fails at its line",
      ),
      #(
        ["type Inbox {", "  Ping", "}"],
        ["Inbox", "Outbox"],
        [#(1, "the message module defines no type Outbox")],
        "a type the module is meant to hold and lacks fails at line 1",
      ),
    ],
    fn(row) {
      let #(lines, types, expected, reason) = row
      let file = planted.file("src/planted/message.gleam", lines)
      assert message_module.breaches(file:, types:)
        |> list.map(fn(breach) { #(breach.line, breach.rule) })
        == expected
        as reason
    },
  )
  let file =
    source.SourceFile(
      path: "src/genesis_prime/map/message.gleam",
      text: source.read("src/genesis_prime/map/message.gleam"),
    )
  let breaches = message_module.breaches(file:, types: map_message_types)
  assert breaches == []
    as {
      int.to_string(list.length(breaches))
      <> " breaches, the first: "
      <> string.inspect(list.first(breaches))
    }
}
