//// The raw-type rule. Expected values are the rule in the issue that set it: a
//// game table's raw type number is decoded once into a tagged type where the
//// table is read, and game and map code matches on that type. A `case` on a
//// row's `type_` field with integer patterns, and a `==` or `!=` of that field
//// with an integer or a constant, are reported at their line; a tagged type, a
//// check against 0, two type fields compared with each other, and the modules
//// that read the table (`table/`) and the wire (`message/`) are not. Every
//// case is planted in a made-up file; the last tests read the source tree.

import code_rule/planted
import code_rule/raw_type.{Gap}
import code_rule/repository
import gleam/list
import owned_test
import unitest

const game_path = "src/genesis_prime/game/planted.gleam"

fn breach_lines(source_lines: List(String)) -> List(Int) {
  let file = planted.file(game_path, source_lines)
  planted.lines(raw_type.breaches(files: [file], gaps: []))
}

pub fn a_case_on_a_rows_type_field_with_integer_patterns_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn name(row: Row) -> String {",
    "  case row.type_ {",
    "    2 -> \"creature\"",
    "    8 -> \"group\"",
    "    _ -> \"other\"",
    "  }",
    "}",
    "",
    "pub fn named(row: Row, place_type: Int) -> String {",
    "  case row.type_ {",
    "    type_ if type_ == place_type -> \"place\"",
    "    _ -> \"other\"",
    "  }",
    "}",
    "",
    "pub fn in_a_tuple(row: Row, count: Int) -> Int {",
    "  case count, row.type_ {",
    "    0, 2 -> 1",
    "    _, _ -> 0",
    "  }",
    "}",
  ]
  assert breach_lines(lines) == [2, 10, 17]
}

pub fn a_comparison_of_a_rows_type_field_with_an_integer_or_constant_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn is_group(row: Row) -> Bool {",
    "  row.type_ == 8",
    "}",
    "",
    "pub fn not_place(row: Row, place_type: Int) -> Bool {",
    "  row.type_ != place_type",
    "}",
    "",
    "pub fn reversed(row: Row) -> Bool {",
    "  16 == row.type_",
    "}",
    "",
    "pub fn from_another_module(row: Row) -> Bool {",
    "  row.type_ == quest_log.use_a_creature_type",
    "}",
    "",
    "pub fn each_one(row: Row) -> Bool {",
    "  row.type_ == 2 || row.type_ == 8",
    "}",
  ]
  assert breach_lines(lines) == [2, 6, 10, 14, 18, 18]
}

pub fn a_case_on_a_tagged_type_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn name(row: Row) -> String {",
    "  case row.type_ {",
    "    Place -> \"place\"",
    "    Kill(..) -> \"kill\"",
    "    Other(type_) -> \"other\"",
    "  }",
    "}",
    "",
    "pub fn is_place(row: Row) -> Bool {",
    "  row.type_ == Place || row.type_ != objective_kind.Kill",
    "}",
    "",
    "pub fn by_variable(type_: Int) -> String {",
    "  case type_ {",
    "    2 -> \"creature\"",
    "    _ -> \"other\"",
    "  }",
    "}",
  ]
  assert breach_lines(lines) == []
}

pub fn the_module_that_decodes_a_table_may_read_its_type_field_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn kind(row: Row) -> Int {",
    "  case row.type_ {",
    "    2 -> 1",
    "    _ -> 0",
    "  }",
    "}",
    "",
    "pub fn is_group(row: Row) -> Bool {",
    "  row.type_ == 8",
    "}",
  ]
  let decoders = [
    "src/genesis_prime/table/quest_objective.gleam",
    "src/genesis_prime/message/quest_objective.gleam",
  ]
  list.each(decoders, fn(path) {
    let file = planted.file(path, lines)
    assert raw_type.breaches(files: [file], gaps: []) == []
  })
}

// The false-hit measure over `src/` outside `table/` and `message/` found 50
// sites that compare or match the field named `type_`, every one a dispatch,
// and one "this field is 0" check (the pattern `Objective(type_: 0, ..)` in
// quest_log, which the rule does not read). A 0 in a type column means no type,
// so a check against 0 decides nothing about what kind of row it is; and two
// type fields compared with each other name no kind either.
pub fn a_zero_or_none_check_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn untyped(row: Row) -> Bool {",
    "  row.type_ == 0",
    "}",
    "",
    "pub fn typed(row: Row) -> Bool {",
    "  row.type_ != 0",
    "}",
    "",
    "pub fn zero_or_not(row: Row) -> Int {",
    "  case row.type_ {",
    "    0 -> 0",
    "    other -> other",
    "  }",
    "}",
    "",
    "pub fn same_kind(first: Row, second: Row) -> Bool {",
    "  first.type_ == second.type_",
    "}",
  ]
  assert breach_lines(lines) == []
}

pub fn each_known_gap_names_an_open_issue_and_a_new_site_fails_test() -> Nil {
  // Deadline: all seven tests of this file ran in 146 ms together, so 5 s is
  // more than 30 times the body.
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Open on 2026-11-16: the quest objective step, and the parent of the
  // target-group and other-table lines ("Target groups and other tables are
  // later lines on #328").
  let open_issues = [888, 328]
  assert list.all(raw_type.known_gaps, fn(gap) {
    list.contains(open_issues, gap.issue)
  })
  assert raw_type.known_gaps != []
  let files = repository.sources(["src"])
  assert raw_type.breaches(files: files, gaps: raw_type.known_gaps) == []
  // A site in a function with no listed gap, and one beyond a listed count,
  // each fail; the sites a gap lists do not.
  let planted_file =
    planted.file(game_path, [
      "pub fn known(row: Row) -> Bool {",
      "  row.type_ == 2 || row.type_ == 8",
      "}",
      "",
      "pub fn fresh(row: Row) -> Bool {",
      "  row.type_ == 16",
      "}",
    ])
  let gaps = [Gap(path: game_path, function: "known", sites: 1, issue: 888)]
  assert planted.lines(raw_type.breaches(files: [planted_file], gaps: gaps))
    == [2, 6]
  let gaps = [Gap(path: game_path, function: "known", sites: 2, issue: 888)]
  assert planted.lines(raw_type.breaches(files: [planted_file], gaps: gaps))
    == [6]
}

pub fn a_listed_gap_with_fewer_sites_than_listed_fails_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(game_path, [
      "pub fn known(row: Row) -> Bool {",
      "  row.type_ == 2",
      "}",
    ])
  let removed = Gap(path: game_path, function: "removed", sites: 1, issue: 888)
  let fewer = Gap(path: game_path, function: "known", sites: 2, issue: 888)
  assert list.length(raw_type.breaches(files: [file], gaps: [removed])) == 2
    as "the unlisted site, and the listed gap that has none"
  assert list.length(raw_type.breaches(files: [file], gaps: [fewer])) == 1
    as "the listed gap that has one site of its two"
}
