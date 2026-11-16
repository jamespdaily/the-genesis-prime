//// The raw-type rule. Expected values are the rule: a game table's raw type
//// number is decoded once into a tagged type where the table is read, and game
//// and map code matches on that type. A `case` on a row's type field (`type_`,
//// or a name ending `_type`, `_type_id` or `_type_enum`) with integer
//// patterns, a `==`, `!=`, `<`, `<=`, `>` or `>=` of that field with an
//// integer or a constant, and a `list.contains` of that field in a list of
//// numbers are reported at their line; a tagged type, two type fields compared
//// with each other, and the modules that read the table (`table/`) and the
//// wire (`message/`) are not. Every case is planted in a made-up file; the
//// last tests read the source tree.

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
    "import genesis_prime/game/quest_log",
    "",
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
  assert breach_lines(lines) == [4, 8, 12, 16, 20, 20]
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

pub fn a_case_or_comparison_on_a_column_ending_in_type_id_or_type_enum_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn is_money(reward: Reward) -> Bool {",
    "  reward.quest2_reward_type_id == 2",
    "}",
    "",
    "pub fn property(picked: Stat) -> Int {",
    "  case picked.item_stat_type_enum {",
    "    1 -> 1",
    "    _ -> 0",
    "  }",
    "}",
    "",
    "pub fn heals(effect: Effect) -> Bool {",
    "  effect.effect_type == 118",
    "}",
    "",
    "pub fn none(price: Price) -> Bool {",
    "  price.currency_type_id == 0",
    "}",
  ]
  assert breach_lines(lines) == [2, 6, 13, 17]
}

pub fn a_name_from_an_imported_module_is_a_constant_not_a_field_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "import genesis_prime/game/currency",
    "import genesis_prime/game/objective",
    "",
    "pub fn paid(price: Price) -> Bool {",
    "  price.currency_type_id != currency.credits_type",
    "}",
    "",
    "pub fn not_a_type_field(reward: Reward) -> Bool {",
    "  reward.object_id == currency.credits_type",
    "}",
    "",
    "pub fn a_parameter_named_like_a_module(objective: Row) -> Bool {",
    "  objective.type_ == 2",
    "}",
    "",
    "pub fn a_closure_named_like_a_module(rows: List(Row)) -> List(Row) {",
    "  list.filter(rows, fn(objective) { objective.type_ == 2 })",
    "}",
    "",
    "pub fn a_parameter_shadowing_an_import(currency: Price) -> Bool {",
    "  currency.currency_type_id == 2",
    "}",
    "",
    "pub fn a_let_shadowing_an_import() -> Bool {",
    "  let currency = price()",
    "  currency.currency_type_id == 2",
    "}",
    "",
    "pub fn a_closure_parameter_shadowing_an_import(rows: List(Price)) -> Bool {",
    "  list.any(rows, fn(currency) { currency.currency_type_id == 2 })",
    "}",
    "",
    "pub fn a_pattern_shadowing_an_import(found: Result(Price, Nil)) -> Bool {",
    "  case found {",
    "    Ok(currency) -> currency.currency_type_id == 2",
    "    Error(Nil) -> False",
    "  }",
    "}",
    "",
    "pub fn another_module_constant_is_not_a_field() -> Bool {",
    "  objective.scripted_type == currency.credits_type",
    "}",
  ]
  assert breach_lines(lines) == [5, 13, 17, 21, 26, 30, 35]
}

pub fn the_client_option_and_a_spawned_object_have_type_fields_no_table_holds_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn option_sent(option: ClientOption) -> Bool {",
    "  case option.option_type {",
    "    1 -> True",
    "    _ -> False",
    "  }",
    "}",
    "",
    "pub fn of_the_type(object: Object, unit_type: Int) -> Bool {",
    "  object.unit_type == unit_type",
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

// A 0 in a type column is a type in some tables (`entity_type`), so a check
// against 0 branches on a raw type number like any other; two type fields
// compared with each other name no kind.
pub fn a_check_against_zero_is_a_breach_and_two_type_fields_compared_are_not_test() -> Nil {
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
  assert breach_lines(lines) == [2, 6, 10]
}

pub fn an_ordering_of_a_type_field_against_a_number_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn below(row: Row) -> Bool {",
    "  row.creation_type_enum < 26",
    "}",
    "",
    "pub fn at_most(row: Row, limit: Int) -> Bool {",
    "  row.type_ <= limit",
    "}",
    "",
    "pub fn above(row: Row) -> Bool {",
    "  row.type_ > 8",
    "}",
    "",
    "pub fn at_least(row: Row) -> Bool {",
    "  2 >= row.type_",
    "}",
    "",
    "pub fn older(first: Row, second: Row) -> Bool {",
    "  first.type_ < second.type_",
    "}",
    "",
    "pub fn another_field(row: Row) -> Bool {",
    "  row.amount < 26",
    "}",
  ]
  assert breach_lines(lines) == [2, 6, 10, 14]
}

pub fn a_type_field_looked_up_in_a_list_of_numbers_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "import gleam/list",
    "import genesis_prime/game/currency",
    "",
    "pub fn listed(row: Row) -> Bool {",
    "  list.contains([14, 18, 28], row.type_)",
    "}",
    "",
    "pub fn named_list(row: Row, kill_types: List(Int)) -> Bool {",
    "  list.contains(kill_types, row.type_)",
    "}",
    "",
    "pub fn labelled(row: Row, kill_types: List(Int)) -> Bool {",
    "  list.contains(this: row.type_, in: kill_types)",
    "}",
    "",
    "pub fn piped(row: Row) -> Bool {",
    "  row.type_ |> list.contains([2, 8], _)",
    "}",
    "",
    "pub fn tagged(row: Row) -> Bool {",
    "  list.contains([Place, Kill], row.type_)",
    "}",
    "",
    "pub fn another_field(row: Row) -> Bool {",
    "  list.contains([1, 2], row.amount)",
    "}",
    "",
    "pub fn another_module(row: Row) -> Bool {",
    "  currency.contains([1, 2], row.type_)",
    "}",
  ]
  assert breach_lines(lines) == [5, 9, 13, 17]
}

pub fn each_known_gap_names_an_open_issue_and_a_new_site_fails_test() -> Nil {
  // Deadline: the tests of this file ran in 205 ms together, so 5 s is more than
  // 20 times the body.
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let open_issues = [886, 898]
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

pub fn a_function_listed_twice_in_the_known_gaps_fails_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(game_path, [
      "pub fn known(row: Row) -> Bool {",
      "  row.type_ == 2",
      "}",
    ])
  let once = Gap(path: game_path, function: "known", sites: 1, issue: 888)
  assert raw_type.breaches(files: [file], gaps: [once]) == []
  assert planted.lines(raw_type.breaches(files: [file], gaps: [once, once]))
    == [1]
    as "listing the function twice is one breach at line 1"
}
