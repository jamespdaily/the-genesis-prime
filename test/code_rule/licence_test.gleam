//// The licence rule. Expected values are the approved test list on the
//// licence issue (#306), the change to AGPL-3.0, and these facts:
////
//// - The accepted list for AGPL-3.0 is the permissive licences (Apache-2.0,
////   MIT, BSD-2-Clause, BSD-3-Clause, ISC) and the copyleft licences the FSF
////   lists as compatible with it (MPL-2.0, LGPL-2.1-or-later, LGPL-3.0,
////   GPL-3.0, AGPL-3.0), as SPDX identifiers, under `[tools.licences]` in the
////   Gleam project file. SSPL-1.0 is not an open-source licence and stays off.
//// - A Gleam package states its licence in `licences` of its own project
////   file (glexer writes `licenses`); an Erlang package states it in the
////   `{licenses, [...]}` entry of `src/<otp_app>.app.src` (`otp_app` is the
////   application name in `manifest.toml`). Both are read from
////   `build/packages/<name>/`.
//// - A package that declares no licence there passes only when `declared`
////   under `[tools.licences]` names it, with an accepted licence and where it
////   was checked (accepted on the licence issue (#306), on the shell card: Ranch, built with erlang.mk,
////   states its ISC licence only in its LICENSE file and on Hex).

import code_rule/licence.{NoLicence, Unaccepted}
import code_rule/source
import envoy
import gleam/list
import gleam/result
import gleam/string
import owned_test
import planted_table
import simplifile
import unitest

const accepted_list = [
  "Apache-2.0",
  "MIT",
  "BSD-2-Clause",
  "BSD-3-Clause",
  "ISC",
  "MPL-2.0",
  "LGPL-2.1-or-later",
  "LGPL-3.0-only",
  "LGPL-3.0-or-later",
  "GPL-3.0-only",
  "GPL-3.0-or-later",
  "AGPL-3.0-only",
  "AGPL-3.0-or-later",
]

pub fn the_project_file_names_the_agpl_licence_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert licence.gleam_licences(source.read("gleam.toml")) == ["AGPL-3.0-only"]
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
    #("planted_server", ["SSPL-1.0"]),
    #("planted_codec", ["MIT"]),
  ]
  let refusals = licence.refusals(packages, accepted_list)
  assert refusals == [Unaccepted("planted_server", ["SSPL-1.0"])]
  let assert [refusal] = refusals as "expected exactly one refusal"
  let message = licence.describe(refusal)
  assert string.contains(message, "planted_server")
  assert string.contains(message, "SSPL-1.0")
}

pub fn a_package_with_any_accepted_licence_passes_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let packages = [
    #("planted_dual", ["SSPL-1.0", "MIT"]),
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

pub fn an_erlang_package_is_read_from_the_application_file_its_manifest_entry_names_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // `hpack_erl` is built as the application `hpack` (`otp_app` in the
  // manifest), so its file is `src/hpack.app.src`; `plain` is named as its
  // application is.
  let manifest =
    string.join(
      [
        "packages = [",
        "  { name = \"hpack_erl\", version = \"0.3.0\", build_tools = [\"rebar3\"], requirements = [], otp_app = \"hpack\", source = \"hex\", outer_checksum = \"00\" },",
        "  { name = \"plain\", version = \"1.0.0\", build_tools = [\"rebar3\"], requirements = [], otp_app = \"plain\", source = \"hex\", outer_checksum = \"00\" },",
        "]",
      ],
      "\n",
    )
  use folder <- planted_table.with_folder(result.unwrap(
    envoy.get("TMPDIR"),
    "/tmp",
  ))
  let assert Ok(Nil) =
    simplifile.create_directory_all(folder <> "/hpack_erl/src")
  let assert Ok(Nil) = simplifile.create_directory_all(folder <> "/plain/src")
  let assert Ok(Nil) =
    simplifile.write(
      folder <> "/hpack_erl/src/hpack.app.src",
      "{application, hpack, [{licenses, [\"MIT\"]}]}.\n",
    )
  let assert Ok(Nil) =
    simplifile.write(
      folder <> "/plain/src/plain.app.src",
      "{application, plain, [{licenses, [\"ISC\"]}]}.\n",
    )
  assert licence.installed(manifest, folder)
    == [#("hpack_erl", ["MIT"]), #("plain", ["ISC"])]
}
