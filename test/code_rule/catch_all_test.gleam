//// The catch-all rule. Expected values are the rule in the writing-gleam skill,
//// section Types and data: no catch-all `_` over a type that can gain
//// variants. A clause that is `_` or a bare variable is refused when a sibling
//// clause matches a constructor other than `True`, `False`, `Ok`, `Error`,
//// `Some`, `None` or `Nil`; a catch-all over integers or strings, or beside
//// only those constructors, passes. The breach is reported at the catch-all
//// pattern's line. Every case is planted in a made-up file.

import code_rule/catch_all
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test
import unitest

fn shape_case(clauses: List(String)) -> List(String) {
  list.flatten([
    [
      "pub type Shape {",
      "  Circle",
      "  Rectangle(width: Int, height: Int)",
      "}",
      "",
      "pub fn area(shape: Shape) -> Int {",
      "  case shape {",
    ],
    clauses,
    ["  }", "}"],
  ])
}

fn breach_lines(source_lines: List(String)) -> List(Int) {
  planted.file("src/planted.gleam", source_lines)
  |> catch_all.breaches
  |> planted.lines
}

pub fn a_discard_beside_a_custom_types_constructor_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = shape_case(["    Circle -> 1", "    _ -> 2"])
  assert breach_lines(lines) == [9]
}

pub fn a_bare_variable_beside_a_custom_types_constructor_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = shape_case(["    Circle -> 1", "    other -> 2"])
  assert breach_lines(lines) == [9]
}

pub fn a_catch_all_beside_a_constructor_with_fields_or_a_module_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let with_fields =
    shape_case(["    Rectangle(width, height) -> width", "    _ -> 0"])
  let qualified = shape_case(["    shapes.Circle -> 1", "    _ -> 0"])
  assert breach_lines(with_fields) == [9]
    as "no breach beside a constructor with fields"
  assert breach_lines(qualified) == [9]
    as "no breach beside a qualified constructor"
}

pub fn a_catch_all_before_a_constructor_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = shape_case(["    _ -> 2", "    Circle -> 1"])
  assert breach_lines(lines) == [8]
}

pub fn each_catch_all_is_reported_at_its_own_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines =
    list.append(shape_case(["    Circle -> 1", "    _ -> 2"]), [
      "",
      "pub fn corners(shape: Shape) -> Int {",
      "  case shape {",
      "    Rectangle(_, _) -> 4",
      "    rest -> 0",
      "  }",
      "}",
    ])
  assert breach_lines(lines) == [9, 16]
}

pub fn a_catch_all_over_integers_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn name(count: Int) -> String {",
    "  case count {",
    "    0 -> \"none\"",
    "    1 -> \"one\"",
    "    _ -> \"many\"",
    "  }",
    "}",
  ]
  assert breach_lines(lines) == []
}

pub fn a_catch_all_over_strings_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn size(word: String) -> Int {",
    "  case word {",
    "    \"one\" -> 1",
    "    \"two\" -> 2",
    "    other -> 0",
    "  }",
    "}",
  ]
  assert breach_lines(lines) == []
}

pub fn a_catch_all_beside_only_the_fixed_constructors_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn read(result: Result(Int, Nil), flag: Bool, maybe: Option(Int)) -> Int {",
    "  let a = case result {",
    "    Ok(value) -> value",
    "    _ -> 0",
    "  }",
    "  let b = case flag {",
    "    True -> 1",
    "    other -> 0",
    "  }",
    "  let c = case maybe {",
    "    Some(value) -> value",
    "    _ -> 0",
    "  }",
    "  let d = case result {",
    "    Error(Nil) -> 1",
    "    _ -> 0",
    "  }",
    "  let e = case maybe {",
    "    None -> 1",
    "    _ -> 0",
    "  }",
    "  a + b + c + d + e",
    "}",
  ]
  assert breach_lines(lines) == []
}

pub fn a_catch_all_with_no_constructor_beside_it_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "pub fn always(value: Int) -> Int {",
    "  case value {",
    "    _ -> 1",
    "  }",
    "}",
  ]
  assert breach_lines(lines) == []
}

pub fn a_case_that_names_every_constructor_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = shape_case(["    Circle -> 1", "    Rectangle(_, _) -> 2"])
  assert breach_lines(lines) == []
}

pub fn no_case_in_src_or_test_has_a_catch_all_beside_a_growing_type_test() -> Nil {
  // Deadline: the body took 374 to 392 ms in three runs alone, so 5 s is more
  // than 3 times that.
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(["src", "test"])
  assert list.flat_map(files, catch_all.breaches) == []
}
