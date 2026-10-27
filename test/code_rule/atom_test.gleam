//// The atom and term rule. Expected values are the rule in CLAUDE.md (decode
//// client bytes at the connection into typed values) and its configuration
//// under `[tools.code_rules]`: outside the modules listed in `atom_or_term`,
//// the source makes no atom from a string (`atom.create`, an external to
//// `erlang:binary_to_atom` or `erlang:list_to_atom`) and reads no term from
//// bytes (`erlang:binary_to_term`), so client input can neither fill the atom
//// table nor build terms. A module is named by its path under `src/`. Each
//// call is planted once in a made-up file.

import code_rule/atom
import code_rule/planted
import code_rule/repository
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

fn external_to(function: String) -> List(String) {
  [
    "//// A planted module.",
    "",
    "@external(erlang, \"erlang\", \""
      <> function
      <> "\") pub fn convert(input: a) -> b",
  ]
}

pub fn the_allowed_modules_are_read_from_the_project_file_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let project_file =
    string.join(
      [
        "name = \"planted\"",
        "",
        "[tools.code_rules]",
        "effectful_modules = []",
        "pure_erlang = []",
        "atom_or_term = [",
        "  { module = \"planted/codec\", reason = \"decodes the planted protocol\" },",
        "  { module = \"planted/table\", reason = \"names the planted columns\" },",
        "]",
      ],
      "\n",
    )
  assert atom.allowed(project_file) == ["planted/codec", "planted/table"]
}

pub fn a_call_that_makes_an_atom_from_a_string_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", [
      "import gleam/erlang/atom",
      "",
      "pub fn make(name: String) -> atom.Atom {",
      "  atom.create(name)",
      "}",
    ])
  assert planted.lines(atom.breaches(file, [])) == [4]
}

pub fn an_external_that_makes_an_atom_from_a_string_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(["binary_to_atom", "list_to_atom"], fn(function) {
    let file = planted.file("src/planted/rule.gleam", external_to(function))
    assert planted.lines(atom.breaches(file, [])) == [3]
      as { "no breach for erlang:" <> function }
  })
}

pub fn an_external_that_reads_a_term_from_bytes_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", external_to("binary_to_term"))
  assert planted.lines(atom.breaches(file, [])) == [3]
}

pub fn a_listed_module_may_make_atoms_and_read_terms_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/codec.gleam", [
      "import gleam/erlang/atom",
      "",
      "pub fn make(name: String) -> atom.Atom {",
      "  atom.create(name)",
      "}",
      "@external(erlang, \"erlang\", \"binary_to_atom\") pub fn a(input: a) -> b",
      "@external(erlang, \"erlang\", \"list_to_atom\") pub fn b(input: a) -> b",
      "@external(erlang, \"erlang\", \"binary_to_term\") pub fn c(input: a) -> b",
    ])
  assert atom.breaches(file, ["planted/codec"]) == []
}

pub fn a_module_beside_the_listed_one_still_breaks_the_rule_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/other.gleam", external_to("binary_to_term"))
  assert planted.lines(atom.breaches(file, ["planted/codec"])) == [3]
}

pub fn a_call_that_only_reads_an_atom_that_exists_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted/rule.gleam", [
      "import gleam/erlang/atom",
      "",
      "pub fn look(name: String) -> Result(atom.Atom, Nil) {",
      "  atom.get(name)",
      "}",
      "",
      "pub fn spell(value: atom.Atom) -> String {",
      "  atom.to_string(value)",
      "}",
      "@external(erlang, \"erlang\", \"binary_to_existing_atom\") pub fn c(input: a) -> b",
      "@external(erlang, \"erlang\", \"abs\") pub fn d(input: Int) -> Int",
    ])
  assert atom.breaches(file, []) == []
}

pub fn no_module_in_src_outside_the_listed_ones_makes_an_atom_or_reads_a_term_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let assert Ok(project_file) = simplifile.read("gleam.toml")
    as "gleam.toml could not be read"
  let allowed = atom.allowed(project_file)
  let files = repository.sources(["src"])
  assert list.flat_map(files, atom.breaches(_, allowed)) == []
}
