//// The generation rule. Expected value is the rule: a generation is the number of one
//// sight of a pair in one map (genesis_prime/world_map/generation), so only the map
//// that numbers its sights makes one. A reference to `generation.first` or
//// `generation.after` in a file of `src` or `dev` other than the map's own
//// (`genesis_prime/world_map/map`) and the generation module is a breach, reported at
//// its line. The rule is shown on a planted file, then read over the real ones.

import code_rule/planted
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/int
import gleam/list
import owned_test
import unitest

const generation_module = "genesis_prime/world_map/generation"

const maker_names = ["first", "after"]

const makers = [
  "src/genesis_prime/world_map/map.gleam",
  "src/genesis_prime/world_map/generation.gleam",
]

/// The lines of the file that make a generation.
fn makes(file file: SourceFile) -> List(Int) {
  syntax.references_to(
    module: syntax.parse(file),
    from: [generation_module],
    named: maker_names,
  )
  |> list.map(fn(reference) {
    syntax.line_of(
      text: file.text,
      byte_offset: syntax.location_of(reference).start,
    )
  })
  |> list.sort(int.compare)
}

pub fn a_generation_is_made_only_in_the_map_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: "src/genesis_prime/world_map/creature.gleam", lines: [
      "import genesis_prime/world_map/generation",
      "import genesis_prime/world_map/generation as sight_number",
      "import genesis_prime/world_map/generation.{first as begin}",
      "",
      "fn qualified() {",
      "  generation.first()",
      "}",
      "",
      "fn aliased(g) {",
      "  sight_number.after(g)",
      "}",
      "",
      "fn unqualified() {",
      "  begin()",
      "}",
      "",
      "fn compared(a, b) {",
      "  generation.compare(a, b)",
      "}",
    ])
  assert makes(file: planted_file) == [6, 10, 14]
    as "a call through the module, through its alias and through an unqualified import is found, and a comparison is not"
  assert list.flat_map(
      list.append(source.files(under: "src"), source.files(under: "dev")),
      fn(file) {
        case list.contains(makers, file.path) {
          True -> []
          False ->
            list.map(makes(file:), fn(line) {
              file.path <> ":" <> int.to_string(line)
            })
        }
      },
    )
    == []
    as "no file of src or dev but the map makes a generation"
}
