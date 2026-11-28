//// The comment-size rule: a module doc over 40 lines and a function or type
//// doc over 10, counted at 100 columns, is a breach unless the list holds it
//// at its size, and the list can only shrink. The cases are planted; the
//// real-tree test runs the rule over the real `src/` and the real list.

import code_rule/comment_size.{ItemDoc, Listed, ModuleDoc}
import code_rule/planted
import code_rule/repository
import code_rule/source.{type Breach, type SourceFile}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

/// A comment line of `marker` with `columns` columns in all, the first of them
/// numbered `number`.
fn comment_line(
  marker marker: String,
  number number: Int,
  columns columns: Int,
) -> String {
  let text = marker <> " line " <> int.to_string(number) <> " "
  text <> string.repeat("x", int.max(0, columns - string.length(text)))
}

/// `count` doc lines of `marker` starting with the first line "the first"; of
/// the lines after it the first `long` are 101 columns wide and the rest 60.
fn doc(
  marker marker: String,
  count count: Int,
  long long: Int,
) -> List(String) {
  [
    marker <> " the first",
    ..list.repeat(Nil, count - 1)
    |> list.index_map(fn(_, index) {
      let number = index + 2
      let columns = case number - 1 <= long {
        True -> 101
        False -> 60
      }
      comment_line(marker:, number:, columns:)
    })
  ]
}

/// A planted module `src/planted.gleam` whose module doc is `doc`, then a
/// function carrying `item_doc`.
fn module_with(
  doc doc: List(String),
  item_doc item_doc: List(String),
) -> SourceFile {
  planted.file(
    "src/planted.gleam",
    list.flatten([
      doc,
      ["", "import gleam/list", ""],
      item_doc,
      ["pub fn f() {", "  Nil", "}"],
    ]),
  )
}

/// The path and line of each breach.
fn places(breaches: List(Breach)) -> List(#(String, Int)) {
  list.map(breaches, fn(breach) { #(breach.path, breach.line) })
}

const source_path = "src/planted.gleam"

pub fn a_module_doc_over_40_lines_at_100_columns_is_a_breach_unless_listed_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(doc(marker: "////", count: 40, long: 0), [], "40 lines at 60 columns"),
      #(
        doc(marker: "////", count: 41, long: 0),
        [#(source_path, 1)],
        "41 lines",
      ),
      #(
        doc(marker: "////", count: 40, long: 40),
        [#(source_path, 1)],
        "40 lines, 39 of them past 100 columns, are 79",
      ),
      #(
        doc(marker: "////", count: 30, long: 11),
        [#(source_path, 1)],
        "30 lines of which 11 run past 100 columns are 41",
      ),
      #(
        doc(marker: "////", count: 30, long: 10),
        [],
        "30 lines of which 10 run past 100 are 40",
      ),
      #(
        list.append(doc(marker: "////", count: 20, long: 0), [
          "////",
          ..doc(marker: "////", count: 20, long: 0)
        ]),
        [#(source_path, 1)],
        "a bare `////` line is a line of the block",
      ),
    ],
    fn(row) {
      let #(lines, expected, reason) = row
      assert places(
          comment_size.breaches(
            files: [module_with(doc: lines, item_doc: [])],
            listed: [],
          ),
        )
        == expected
        as reason
    },
  )
}

pub fn a_function_or_type_doc_over_10_lines_is_a_breach_unless_listed_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(doc(marker: "///", count: 10, long: 0), [], "10 lines"),
      #(doc(marker: "///", count: 11, long: 0), [#(source_path, 5)], "11 lines"),
      #(
        doc(marker: "///", count: 6, long: 5),
        [#(source_path, 5)],
        "6 lines, 5 of them past 100",
      ),
      #(
        doc(marker: "///", count: 6, long: 4),
        [],
        "6 lines, 4 of them past 100 columns, are 10",
      ),
    ],
    fn(row) {
      let #(lines, expected, reason) = row
      assert places(
          comment_size.breaches(
            files: [module_with(doc: ["//// A module."], item_doc: lines)],
            listed: [],
          ),
        )
        == expected
        as reason
    },
  )
  let type_file =
    planted.file(
      source_path,
      list.flatten([
        doc(marker: "///", count: 11, long: 0),
        ["pub type Shape {", "  Round", "}"],
      ]),
    )
  assert places(comment_size.breaches(files: [type_file], listed: []))
    == [#(source_path, 1)]
    as "a type's doc is a function's doc"
  let variant_file =
    planted.file(
      source_path,
      list.flatten([
        ["pub type Shape {"],
        doc(marker: "  ///", count: 11, long: 0),
        ["  Round", "}"],
      ]),
    )
  assert places(comment_size.breaches(files: [variant_file], listed: []))
    == [#(source_path, 2)]
    as "an indented variant's doc is counted too"
}

pub fn a_listed_block_that_grew_is_a_breach_and_one_that_shrank_or_went_must_leave_or_lower_its_row_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let list_place = #(comment_size.list_path, 1)
  let big =
    module_with(doc: doc(marker: "////", count: 45, long: 0), item_doc: [])
  let at_cap =
    module_with(doc: doc(marker: "////", count: 40, long: 0), item_doc: [])
  let none = module_with(doc: ["//// A module."], item_doc: [])
  let row = fn(size) { Listed("planted", ModuleDoc, "the first", size, 1) }
  list.each(
    [
      #(big, [row(45)], [], "listed at its size"),
      #(big, [row(44)], [#(source_path, 1)], "grew past its row"),
      #(big, [row(50)], [list_place], "shrank below its row"),
      #(big, [], [#(source_path, 1)], "over its cap with no row"),
      #(at_cap, [row(45)], [list_place], "within its cap, the row leaves"),
      #(at_cap, [row(40)], [list_place], "at its cap and its row, it leaves"),
      #(none, [row(45)], [list_place], "gone, the row leaves"),
      #(
        big,
        [Listed("planted", ItemDoc, "the first", 45, 1)],
        [#(source_path, 1), list_place],
        "a row of the other kind holds nothing",
      ),
      #(
        big,
        [Listed("planted", ModuleDoc, "another first line", 45, 1)],
        [#(source_path, 1), list_place],
        "a row of another first line holds nothing",
      ),
      #(
        big,
        [row(45), Listed("planted", ModuleDoc, "the first", 45, 2)],
        [#(comment_size.list_path, 2)],
        "a repeated row",
      ),
      #(
        big,
        [
          Listed("planted", ModuleDoc, "the first", 45, 1),
          Listed("another", ModuleDoc, "x", 45, 2),
        ],
        [#(comment_size.list_path, 2), #(comment_size.list_path, 2)],
        "an out of order row, which is also for a module that is gone",
      ),
    ],
    fn(entry) {
      let #(file, listed, expected, reason) = entry
      assert places(comment_size.breaches(files: [file], listed:)) == expected
        as reason
    },
  )
}

pub fn the_list_is_read_as_module_kind_first_line_and_size_per_line_from_line_1_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert comment_size.parse_list(
      "a/b module The first line of it 45\n\na/b item  12\n",
    )
    == [
      Listed("a/b", ModuleDoc, "The first line of it", 45, 1),
      Listed("a/b", ItemDoc, "", 12, 3),
    ]
    as "the first line is the words between the kind and the size"
}

pub fn a_failure_table_or_supervision_diagram_the_rules_read_is_exempt_by_its_stated_reason_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let table = [
    "//// | Point | What happens |",
    "//// |---|---|",
    ..list.repeat("//// | a point | a test `a_test` |", 45)
  ]
  let diagram = [
    "//// ```",
    ..list.append(list.repeat("////  ├─ a child", 45), ["//// ```"])
  ]
  let prose = list.map(table, string.replace(_, "|", "-"))
  let file_of = fn(path, lines) {
    planted.file(path, ["//// The first.", ..lines])
  }
  list.each(
    [
      #(
        file_of("src/planted.gleam", table),
        [],
        "the rows of a failure table, which order coverage reads",
      ),
      #(
        file_of("src/planted.gleam", [
          "//// | Name | What |",
          "//// |---|---|",
          ..list.repeat("//// | a | b |", 45)
        ]),
        [#("src/planted.gleam", 1)],
        "a table that is no failure table is counted",
      ),
      #(
        file_of("src/planted.gleam", prose),
        [#("src/planted.gleam", 1)],
        "the same lines as prose are counted",
      ),
      #(
        file_of("src/genesis_prime/server.gleam", diagram),
        [],
        "the supervision diagram of the server module",
      ),
      #(
        file_of("src/planted.gleam", diagram),
        [#("src/planted.gleam", 1)],
        "a diagram of any other module is counted",
      ),
      #(
        file_of(
          "src/genesis_prime/server.gleam",
          list.append(diagram, list.repeat("//// prose", 40)),
        ),
        [#("src/genesis_prime/server.gleam", 1)],
        "the prose beside the diagram is counted",
      ),
    ],
    fn(entry) {
      let #(file, expected, reason) = entry
      assert places(comment_size.breaches(files: [file], listed: []))
        == expected
        as reason
    },
  )
}

pub fn every_block_of_the_real_tree_is_within_its_cap_or_its_listed_size_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(under: ["src"])
  let listed = comment_size.parse_list(source.read(comment_size.list_path))
  assert listed != [] as "the list holds the blocks of today's tree"
  let breaches = comment_size.breaches(files:, listed:)
  assert breaches == []
    as {
      int.to_string(list.length(breaches))
      <> " breaches, the first: "
      <> string.inspect(list.first(breaches))
    }
}
