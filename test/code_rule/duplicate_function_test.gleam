//// The duplicate-function rule. Expected values are the writing-gleam skill,
//// Modules: never copy a function from another module, move it to the module
//// both callers share. Two functions in different modules are copies when
//// their bodies are the same once string literals are alike; a body shorter
//// than the minimum, a body repeated inside one module and a generated module
//// are not breaches. An allow-list entry names a module, a function and the
//// reason the copy stays, and an entry with no copy is a breach.
//// Every breach is planted in made-up files.

import code_rule/duplicate_function
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import genesis_prime/message_generator
import genesis_prime/table_generator/difference
import gleam/list
import gleam/string
import owned_test
import unitest

/// Gleam lines of a function whose body spans four lines, so it is over the
/// minimum.
fn long_function(
  name name: String,
  name_text name_text: String,
  count count: String,
  variable variable: String,
) -> List(String) {
  [
    "pub fn " <> name <> "(" <> variable <> ": Int) -> Int {",
    "  let label = \"" <> name_text <> "\"",
    "  let total = " <> variable <> " + " <> count,
    "  log(label, total)",
    "  total",
    "}",
  ]
}

fn module(path: String, lines: List(String)) -> SourceFile {
  planted.file(path:, lines: ["//// A planted module.", "", ..lines])
}

fn plain_pair() -> List(SourceFile) {
  [
    module(
      "src/planted/first.gleam",
      long_function(
        name: "first_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      ),
    ),
    module(
      "src/planted/second.gleam",
      long_function(
        name: "second_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      ),
    ),
  ]
}

pub fn the_same_function_in_two_modules_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches = duplicate_function.breaches(plain_pair(), allowed: [])
  assert list.map(breaches, fn(breach) { breach.path })
    == ["src/planted/first.gleam", "src/planted/second.gleam"]
  assert planted.lines(breaches) == [3, 3]
  let assert [first, ..] = breaches as "expected breaches"
  assert string.contains(first.rule, "src/planted/second.gleam second_total")
}

pub fn a_copy_that_differs_only_in_a_string_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module(
      "src/planted/first.gleam",
      long_function(
        name: "first_total",
        name_text: "login rule",
        count: "1",
        variable: "n",
      ),
    ),
    module(
      "src/planted/second.gleam",
      long_function(
        name: "second_total",
        name_text: "game rule",
        count: "1",
        variable: "n",
      ),
    ),
  ]
  assert list.length(duplicate_function.breaches(files, allowed: [])) == 2
}

pub fn a_copy_that_differs_in_a_number_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module(
      "src/planted/first.gleam",
      long_function(
        name: "first_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      ),
    ),
    module(
      "src/planted/second.gleam",
      long_function(
        name: "second_total",
        name_text: "alpha",
        count: "2",
        variable: "n",
      ),
    ),
  ]
  assert duplicate_function.breaches(files, allowed: []) == []
}

pub fn a_copy_that_differs_in_a_variable_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module(
      "src/planted/first.gleam",
      long_function(
        name: "first_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      ),
    ),
    module(
      "src/planted/second.gleam",
      long_function(
        name: "second_total",
        name_text: "alpha",
        count: "1",
        variable: "m",
      ),
    ),
  ]
  assert duplicate_function.breaches(files, allowed: []) == []
}

pub fn a_body_below_the_minimum_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert duplicate_function.minimum_lines == 4
  let short = fn(name) {
    [
      "pub fn " <> name <> "(n: Int) -> Int {",
      "  let total = n + 1",
      "  log(\"total\", total)",
      "  total",
      "}",
    ]
  }
  let files = [
    module("src/planted/first.gleam", short("first_total")),
    module("src/planted/second.gleam", short("second_total")),
  ]
  assert duplicate_function.breaches(files, allowed: []) == []
}

pub fn a_body_at_the_minimum_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let exact = fn(name) {
    [
      "pub fn " <> name <> "(n: Int) -> Int {",
      "  let total = n + 1",
      "  let doubled = total * 2",
      "  log(\"total\", total)",
      "  doubled",
      "}",
    ]
  }
  let files = [
    module("src/planted/first.gleam", exact("first_total")),
    module("src/planted/second.gleam", exact("second_total")),
  ]
  assert list.length(duplicate_function.breaches(files, allowed: [])) == 2
}

pub fn a_copy_the_formatter_laid_over_more_lines_is_still_a_copy_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module("src/planted/first.gleam", [
      "pub fn first_read(n: Int) -> Int {",
      "  let bits = size(n)",
      "  let assert Ok(value) = read(bits) as \"short\"",
      "  value",
      "}",
    ]),
    module("src/planted/second.gleam", [
      "pub fn second_read(n: Int) -> Int {",
      "  let bits = size(n)",
      "  let assert Ok(value) = read(bits)",
      "    as \"a message long enough to need its own line\"",
      "  value",
      "}",
    ]),
  ]
  assert list.length(duplicate_function.breaches(files, allowed: [])) == 2
}

pub fn the_same_body_twice_in_one_module_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module(
      "src/planted/only.gleam",
      list.append(
        long_function(
          name: "first_total",
          name_text: "alpha",
          count: "1",
          variable: "n",
        ),
        long_function(
          name: "second_total",
          name_text: "alpha",
          count: "1",
          variable: "n",
        ),
      ),
    ),
  ]
  assert duplicate_function.breaches(files, allowed: []) == []
}

pub fn a_copy_of_a_function_repeated_in_another_module_is_a_breach_per_copy_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module(
      "src/planted/first.gleam",
      list.append(
        long_function(
          name: "first_total",
          name_text: "alpha",
          count: "1",
          variable: "n",
        ),
        long_function(
          name: "again_total",
          name_text: "alpha",
          count: "1",
          variable: "n",
        ),
      ),
    ),
    module(
      "test/planted/second.gleam",
      long_function(
        name: "second_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      ),
    ),
  ]
  assert list.map(duplicate_function.breaches(files, allowed: []), fn(breach) {
      breach.path
    })
    == [
      "src/planted/first.gleam",
      "src/planted/first.gleam",
      "test/planted/second.gleam",
    ]
}

pub fn a_generated_module_is_skipped_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let generated = fn(path, header) {
    planted.file(path:, lines: [
      header,
      "",
      ..long_function(
        name: "generated_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      )
    ])
  }
  let by_generator =
    generated(
      "src/planted/message/one.gleam",
      message_generator.generated_marker <> " by `planted/generate`.",
    )
  let by_table_generator =
    generated(
      "src/planted/table/one.gleam",
      difference.generated_marker <> " from the client's DB/One.tbl.",
    )
  let by_squirrel =
    generated(
      "src/planted/store/sql.gleam",
      "//// > 🐿️ This module was generated automatically using v4.7.0 of",
    )
  let by_hand = generated("src/planted/by_hand.gleam", "//// Written by hand.")
  assert duplicate_function.breaches([by_generator, by_squirrel], allowed: [])
    == []
  assert duplicate_function.breaches([by_table_generator, by_hand], allowed: [])
    == []
  assert duplicate_function.breaches([by_generator, by_hand], allowed: []) == []
    as "a generated module is not compared with a hand-written one"
  assert duplicate_function.breaches([by_squirrel, by_hand], allowed: []) == []
}

pub fn a_hand_written_doc_that_mentions_generated_code_is_compared_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // The rule skips only a generator's exact header; prose that starts with
  // "Generated" or says something "was generated automatically" is a person's.
  let module = fn(path, header) {
    planted.file(path:, lines: [
      header,
      "",
      ..long_function(
        name: "adapted_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      )
    ])
  }
  let first =
    module(
      "src/planted/adapter.gleam",
      "//// Generated packets are handled by this hand-written adapter.",
    )
  let second =
    module(
      "src/planted/other.gleam",
      "//// This text was generated automatically by a person's editor.",
    )
  assert list.length(duplicate_function.breaches([first, second], allowed: []))
    == 2
    as "both hand-written copies are breaches"
}

pub fn an_allowed_function_is_left_out_with_its_twin_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert duplicate_function.breaches(plain_pair(), allowed: [
      #("src/planted/second.gleam", "second_total", "a planted reason"),
    ])
    == []
}

pub fn an_allow_list_entry_with_no_copy_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    module(
      "src/planted/first.gleam",
      long_function(
        name: "first_total",
        name_text: "alpha",
        count: "1",
        variable: "n",
      ),
    ),
    module(
      "src/planted/second.gleam",
      long_function(
        name: "second_total",
        name_text: "alpha",
        count: "2",
        variable: "n",
      ),
    ),
  ]
  let breaches =
    duplicate_function.breaches(files, allowed: [
      #("src/planted/second.gleam", "second_total", "a planted reason"),
      #("src/planted/gone.gleam", "gone_total", "a planted reason"),
    ])
  let assert [first, second] = breaches as "expected two stale entries"
  assert string.ends_with(first.rule, "src/planted/second.gleam second_total")
  assert string.ends_with(second.rule, "src/planted/gone.gleam gone_total")
}

/// Functions with the same body in two modules that stay as they are, each with
/// the reason.
const adapter =
  "a rule's adapter: fills its own Session and handlers into client_connection's shared flow; the bodies match because the flow is shared"

const oracle =
  "the scripted client is an independent second reading of the login's SRP, the test's oracle; sharing the code would let the server check itself"

const allowed = [
  #("src/genesis_prime/game/connection.gleam", "flow", adapter),
  #("src/genesis_prime/login/auth_connection.gleam", "flow", adapter),
  #("src/genesis_prime/login/auth_connection.gleam", "ask", adapter),
  #("src/genesis_prime/login/sts_connection.gleam", "ask", adapter),
  #("src/genesis_prime/login/srp.gleam", "bytes_number", oracle),
  #("src/genesis_prime/login/srp.gleam", "digest_words", oracle),
  #("src/genesis_prime/login/srp.gleam", "xor", oracle),
  #("test/scripted_client.gleam", "number_from", oracle),
  #("test/scripted_client.gleam", "digest_words", oracle),
  #("test/scripted_client.gleam", "xor", oracle),
  #("test/sts_connection_test.gleam", "little", oracle),
]

pub fn no_two_modules_hold_the_same_function_test() -> Nil {
  use <- owned_test.run(20_000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(under: ["src", "test", "dev"])
  assert list.length(files) >= 100 as "the repository's modules were not found"
  assert duplicate_function.breaches(files, allowed:) == []
}
