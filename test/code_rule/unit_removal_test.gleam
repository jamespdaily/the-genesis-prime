//// The unit-removal rule. Expected value is the rule: the viewer ends a unit
//// at one function, `unit_removed` in genesis_prime/game/connection/viewers, so
//// that the unit's casts are finished before its 0x355 and forgotten with it
//// (`cast.target_node_end`) for every way a unit goes: a removal news, the
//// map's `Gone`, and a static object's `ObjectsUnseen`. A function of the file
//// other than `unit_removed` that names `unit_forgotten`, `cast_loses_unit` or
//// `finishes_of_forgotten_casts` is a breach, reported at its line. The rule is
//// shown on a planted file, then read over the real one.

import code_rule/planted
import code_rule/source.{type SourceFile, SourceFile}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import owned_test
import unitest

const viewers_path = "src/genesis_prime/game/connection/viewers.gleam"

const the_one_function = "unit_removed"

const removal_pieces = [
  "unit_forgotten", "cast_loses_unit", "finishes_of_forgotten_casts",
]

/// The lines where a function of the file other than the one removal function
/// names a piece of a removal.
fn pieces_outside(file file: SourceFile) -> List(Int) {
  let module = syntax.parse(file)
  module.functions
  |> list.flat_map(fn(definition) {
    case definition.definition.name == the_one_function {
      True -> []
      False ->
        glance.Module(..module, functions: [definition])
        |> syntax.references
        |> list.filter(fn(reference) {
          let name = case reference {
            syntax.Unqualified(name:, ..) | syntax.Qualified(name:, ..) -> name
          }
          list.contains(removal_pieces, name)
        })
        |> list.map(fn(reference) {
          syntax.line_of(
            text: file.text,
            byte_offset: syntax.location_of(reference).start,
          )
        })
    }
  })
  |> list.sort(int.compare)
}

pub fn a_unit_is_removed_only_through_the_one_removal_function_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: viewers_path, lines: [
      "pub fn unit_removed() {",
      "  unit_forgotten()",
      "  cast_loses_unit()",
      "  finishes_of_forgotten_casts()",
      "}",
      "",
      "fn an_arm() {",
      "  unit_forgotten()",
      "}",
      "",
      "fn a_value() {",
      "  list.map([], cast_loses_unit)",
      "}",
      "",
      "fn another() {",
      "  finishes_of_forgotten_casts()",
      "}",
    ])
  assert pieces_outside(file: planted_file) == [8, 12, 16]
    as "each piece named outside the one function is found, called or passed on"
  assert pieces_outside(file: SourceFile(
      path: viewers_path,
      text: source.read(viewers_path),
    ))
    == []
    as "the viewer removes a unit only through its one removal function"
}
