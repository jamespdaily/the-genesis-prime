//// The licence rule. Expected values are the approved test list on the
//// licence issue (Apache-2.0 chosen by Jim) and these facts:
////
//// - The accepted list for Apache-2.0 is Apache-2.0, MIT, BSD-2-Clause,
////   BSD-3-Clause and ISC (SPDX identifiers), under `[tools.licences]` in
////   the Gleam project file.
//// - A Gleam package states its licence in `licences` of its own project
////   file (glexer writes `licenses`); an Erlang package states it in the
////   `{licenses, [...]}` entry of `src/<name>.app.src`. Both are read from
////   `build/packages/<name>/`.
//// - A package that declares no licence there passes only when `declared`
////   under `[tools.licences]` names it, with an accepted licence and where it
////   was checked (Jim's yes, on the shell card: Ranch, built with erlang.mk,
////   states its ISC licence only in its LICENSE file and on Hex).

import code_rule/licence.{NoLicence, Unaccepted}
import code_rule/source
import gleam/list
import gleam/string
import owned_test
import unitest

const accepted_list = [
  "Apache-2.0",
  "MIT",
  "BSD-2-Clause",
  "BSD-3-Clause",
  "ISC",
]

pub fn the_project_file_names_the_apache_licence_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert licence.gleam_licences(source.read("gleam.toml")) == ["Apache-2.0"]
}

pub fn the_licences_of_a_gleam_package_are_read_under_either_spelling_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
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
  use <- unitest.tag("code_rule")
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
  use <- unitest.tag("code_rule")
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
  assert licence.accepted(source.read("gleam.toml")) == accepted_list
}

pub fn a_package_whose_licences_are_all_off_the_list_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
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
  use <- unitest.tag("code_rule")
  let packages = [
    #("planted_dual", ["AGPL-3.0", "MIT"]),
    #("planted_apache", ["Apache-2.0"]),
    #("planted_isc", ["ISC"]),
  ]
  assert licence.refusals(packages, accepted_list) == []
}

pub fn a_package_with_no_licence_found_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let packages = [#("planted_bare", []), #("planted_codec", ["MIT"])]
  let refusals = licence.refusals(packages, accepted_list)
  assert refusals == [NoLicence("planted_bare")]
  let assert [refusal] = refusals as "expected exactly one refusal"
  assert string.contains(licence.describe(refusal), "planted_bare")
}

pub fn every_package_in_the_manifest_has_an_accepted_licence_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let manifest = source.read("manifest.toml")
  let packages = licence.installed(manifest, "build/packages")
  assert list.length(packages) >= 40 as "the manifest packages were not found"
  let project_file = source.read("gleam.toml")
  let accepted = licence.accepted(project_file)
  let packages = licence.with_declared(packages, licence.declared(project_file))
  assert list.map(licence.refusals(packages, accepted), licence.describe) == []
}

pub fn a_package_with_no_licence_passes_only_when_declared_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted =
    string.join(
      [
        "name = \"planted\"",
        "",
        "[tools.licences]",
        "accepted = [\"ISC\"]",
        "declared = [",
        "  { package = \"planted_listed\", licence = \"ISC\", evidence = \"its LICENSE file\" },",
        "]",
      ],
      "\n",
    )
  let declared = licence.declared(planted)
  assert declared == [#("planted_listed", "ISC")]
  let packages = [
    #("planted_listed", []),
    #("planted_unlisted", []),
    #("planted_own", ["MIT"]),
  ]
  let filled = licence.with_declared(packages, declared)
  assert filled
    == [
      #("planted_listed", ["ISC"]),
      #("planted_unlisted", []),
      #("planted_own", ["MIT"]),
    ]
    as "only a package with no licence of its own takes its declared one"
  assert licence.refusals(filled, ["ISC"])
    == [
      NoLicence("planted_unlisted"),
      licence.Unaccepted("planted_own", ["MIT"]),
    ]
    as "the listed package passes; the unlisted one is still refused"
}
