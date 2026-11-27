//// The person-as-source rule. A line of a tracked text file under `src/`,
//// `test/` or `dev/` that holds the word Jim is a breach at its line unless a row of the keep list
//// holds it. A row with no such line is a breach at the row's line of the
//// list, and the list must be sorted with one row per line. Every case is
//// planted; the last test runs the rule over the real tree and the real list.

import code_rule/jim_source.{Kept}
import code_rule/planted
import code_rule/repository
import code_rule/source
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

pub fn a_line_naming_jim_is_a_breach_unless_the_keep_list_holds_it_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(
        planted.file("src/planted.gleam", [
          "//// A module.", "/// The cap is Jim's decision.",
        ]),
        [],
        [2],
        "a src comment",
      ),
      #(
        planted.file("test/planted_test.gleam", [
          "pub fn f() {", "  assert x as \"Jim's answer\"", "}",
        ]),
        [],
        [2],
        "a test's `as` message",
      ),
      #(
        planted.file("dev/planted.py", ["x = 1", "# Jim said so", "y = 2"]),
        [],
        [2],
        "a dev Python comment",
      ),
      #(
        planted.file("src/planted.gleam", ["/// The cap is Jim's decision."]),
        [Kept("src/planted.gleam", "/// The cap is Jim's decision.", 1)],
        [],
        "the same line on the keep list",
      ),
      #(
        planted.file("src/planted.gleam", [
          "    /// The cap is Jim's decision.",
        ]),
        [Kept("src/planted.gleam", "/// The cap is Jim's decision.", 1)],
        [],
        "a kept line is matched by its trimmed text",
      ),
      #(
        planted.file("src/planted.gleam", [
          "/// Jimmy chose it.", "/// A jim in it.", "/// The prejim and Jimbo.",
        ]),
        [],
        [],
        "Jimmy and jim inside another word are no breach",
      ),
    ],
    fn(row) {
      let #(file, kept, expected, reason) = row
      assert planted.lines(jim_source.breaches(files: [file], kept:))
        == expected
        as reason
    },
  )
}

pub fn a_keep_list_row_with_no_such_line_is_a_breach_at_its_row_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file = planted.file("src/planted.gleam", ["/// Jim's cap.", "/// A cap."])
  list.each(
    [
      #(
        [
          Kept("src/planted.gleam", "/// Jim's cap.", 1),
          Kept("src/planted.gleam", "/// Jim's fixed line.", 2),
        ],
        [2],
        "the file no longer holds the row's line",
      ),
      #(
        [
          Kept("src/gone.gleam", "/// Jim's cap.", 1),
          Kept("src/planted.gleam", "/// Jim's cap.", 2),
        ],
        [1],
        "the row's file is gone",
      ),
    ],
    fn(row) {
      let #(kept, expected, reason) = row
      let breaches = jim_source.breaches(files: [file], kept:)
      assert planted.lines(breaches) == expected as reason
      assert list.all(breaches, fn(breach) {
        breach.path == jim_source.list_path
      })
        as { reason <> ": the breach is at the list" }
    },
  )
}

pub fn the_keep_list_is_sorted_with_one_row_per_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let first = "/// Jim's a."
  let second = "/// Jim's b."
  let file = planted.file("src/planted.gleam", [first, second])
  list.each(
    [
      #(
        [
          Kept("src/planted.gleam", first, 1),
          Kept("src/planted.gleam", second, 2),
        ],
        [],
        "in order",
      ),
      #(
        [
          Kept("src/planted.gleam", second, 1),
          Kept("src/planted.gleam", first, 2),
        ],
        [2],
        "a row out of order",
      ),
      #(
        [
          Kept("src/planted.gleam", first, 1),
          Kept("src/planted.gleam", first, 2),
          Kept("src/planted.gleam", second, 3),
        ],
        [2],
        "a repeated row",
      ),
    ],
    fn(row) {
      let #(kept, expected, reason) = row
      assert planted.lines(jim_source.breaches(files: [file], kept:))
        == expected
        as reason
    },
  )
}

pub fn the_real_tree_names_jim_only_on_its_keep_list_lines_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let files = repository.texts(under: ["src", "test", "dev"])
  assert files != [] as "the scan read no file"
  let breaches =
    jim_source.breaches(
      files:,
      kept: jim_source.parse_list(source.read(jim_source.list_path)),
    )
  assert breaches == []
    as {
      int.to_string(list.length(breaches))
      <> " breaches, the first: "
      <> string.inspect(list.first(breaches))
    }
}
