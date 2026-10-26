//// The licence rule. Expected values are the approved test list on the
//// licence issue (Apache-2.0 chosen by Jim) and these facts:
////
//// - `LICENSE` is the Apache License 2.0 text as its publisher gives it, at
////   https://www.apache.org/licenses/LICENSE-2.0.txt: 11358 bytes, 201 lines
////   once the blank line before and after it is dropped, 11356 characters
////   once the same newlines are dropped, SHA-256
////   cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30. The
////   checks below are its opening and closing lines, its section headings,
////   its line count and its length.
//// - The accepted list for Apache-2.0 is Apache-2.0, MIT, BSD-2-Clause,
////   BSD-3-Clause and ISC (SPDX identifiers), under `[tools.licences]` in
////   the Gleam project file.
//// - A Gleam package states its licence in `licences` of its own project
////   file (glexer writes `licenses`); an Erlang package states it in the
////   `{licenses, [...]}` entry of `src/<name>.app.src`. Both are read from
////   `build/packages/<name>/`.

import code_rule/licence.{NoLicence, Unaccepted}
import gleam/list
import gleam/string
import owned_test
import simplifile

const accepted_list = [
  "Apache-2.0",
  "MIT",
  "BSD-2-Clause",
  "BSD-3-Clause",
  "ISC",
]

fn read(path: String) -> String {
  let assert Ok(text) = simplifile.read(path) as { "could not read " <> path }
  text
}

pub fn the_licence_file_is_the_apache_licence_2_0_text_test() -> Nil {
  use <- owned_test.run(5000)
  let lines =
    string.split(read("LICENSE"), "\n")
    |> list.drop_while(fn(line) { line == "" })
    |> list.reverse
    |> list.drop_while(fn(line) { line == "" })
    |> list.reverse
  let text = string.join(lines, "\n")
  assert list.first(lines)
    == Ok("                                 Apache License")
  assert list.take(list.drop(lines, 1), 3)
    == [
      "                           Version 2.0, January 2004",
      "                        http://www.apache.org/licenses/",
      "",
    ]
  assert list.drop(lines, 4) |> list.first
    == Ok("   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION")
  assert list.contains(
    lines,
    "   APPENDIX: How to apply the Apache License to your work.",
  )
  assert list.last(lines) == Ok("   limitations under the License.")
  assert list.length(lines) == 201
  assert string.length(text) == 11_356
}

pub fn the_project_file_names_the_apache_licence_test() -> Nil {
  use <- owned_test.run(5000)
  assert licence.gleam_licences(read("gleam.toml")) == ["Apache-2.0"]
}

pub fn the_licences_of_a_gleam_package_are_read_under_either_spelling_test() -> Nil {
  use <- owned_test.run(5000)
  let spelled_licences =
    "name = \"planted\"\nlicences = [\"Apache-2.0\", \"MIT\"]\n"
  let spelled_licenses = "name = \"planted\"\nlicenses = [\"MIT\"]\n"
  let undeclared = "name = \"planted\"\nversion = \"1.0.0\"\n"
  assert licence.gleam_licences(spelled_licences) == ["Apache-2.0", "MIT"]
  assert licence.gleam_licences(spelled_licenses) == ["MIT"]
  assert licence.gleam_licences(undeclared) == []
}

pub fn the_licences_of_an_erlang_package_are_read_whatever_the_spacing_test() -> Nil {
  use <- owned_test.run(5000)
  let compact =
    "{application,planted,\n [{description,\"A planted package\"},\n  {licenses,[\"Apache-2.0\"]},\n  {links,[]}]}.\n"
  let spaced =
    string.join(
      [
        "{application, planted,",
        " [",
        "  {description, \"A planted package\"},",
        "  {licenses,",
        "    [\"MIT\",",
        "     \"BSD-3-Clause\"",
        "    ]},",
        "  {links, [{\"GitHub\", \"https://example.invalid/planted\"}]}",
        " ]}.",
      ],
      "\n",
    )
  let undeclared =
    "{application, planted, [{description, \"A planted package\"}]}.\n"
  assert licence.erlang_licences(compact) == ["Apache-2.0"]
  assert licence.erlang_licences(spaced) == ["MIT", "BSD-3-Clause"]
  assert licence.erlang_licences(undeclared) == []
}

pub fn the_accepted_list_is_read_from_the_project_file_test() -> Nil {
  use <- owned_test.run(5000)
  let planted =
    string.join(
      [
        "name = \"planted\"",
        "",
        "[tools.licences]",
        "accepted = [\"Apache-2.0\", \"MIT\"]",
      ],
      "\n",
    )
  assert licence.accepted(planted) == ["Apache-2.0", "MIT"]
  assert licence.accepted(read("gleam.toml")) == accepted_list
}

pub fn a_package_whose_licences_are_all_off_the_list_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  let packages = [
    #("planted_server", ["AGPL-3.0"]),
    #("planted_codec", ["MIT"]),
  ]
  let refusals = licence.refusals(packages, accepted_list)
  assert refusals == [Unaccepted("planted_server", ["AGPL-3.0"])]
  let assert [refusal] = refusals as "expected exactly one refusal"
  let message = licence.describe(refusal)
  assert string.contains(message, "planted_server")
  assert string.contains(message, "AGPL-3.0")
}

pub fn a_package_with_any_accepted_licence_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let packages = [
    #("planted_dual", ["AGPL-3.0", "MIT"]),
    #("planted_apache", ["Apache-2.0"]),
    #("planted_isc", ["ISC"]),
  ]
  assert licence.refusals(packages, accepted_list) == []
}

pub fn a_package_with_no_licence_found_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let packages = [#("planted_bare", []), #("planted_codec", ["MIT"])]
  let refusals = licence.refusals(packages, accepted_list)
  assert refusals == [NoLicence("planted_bare")]
  let assert [refusal] = refusals as "expected exactly one refusal"
  assert string.contains(licence.describe(refusal), "planted_bare")
}

pub fn every_package_in_the_manifest_has_an_accepted_licence_test() -> Nil {
  use <- owned_test.run(10_000)
  let manifest = read("manifest.toml")
  let packages = licence.installed(manifest, "build/packages")
  assert list.length(packages) >= 40 as "the manifest packages were not found"
  let accepted = licence.accepted(read("gleam.toml"))
  assert list.map(licence.refusals(packages, accepted), licence.describe) == []
}
