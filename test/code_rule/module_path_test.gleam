//// The module-path rules. Expected values are the writing-gleam skill,
//// Modules: "Name and split modules by game domain. Never group by kind (no
//// `types`, `rules` or `utils`), and no module in a folder named for another
//// package", with the kind names the folder-tree issue's test list gives
//// (test 2): `type`, `types`, `util`, `utils`, `helper`, `helpers`, `rule`,
//// `rules`, `common`, `shared`, `misc`, `lib`, `core`, `model`, `models`. A
//// package's name is read from `manifest.toml`, which lists every package
//// the project uses (test 3). A segment is a whole folder or module name of
//// the path under `src/`; a name that only contains a kind name is fine.
//// Every breach is planted in a made-up file.

import code_rule/module_path
import code_rule/planted
import code_rule/repository
import code_rule/source
import gleam/list
import gleam/string
import owned_test

import unitest

pub fn a_folder_named_by_kind_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(module_path.kind_names, fn(name) {
    let file =
      planted.file("src/genesis_prime/map/" <> name <> "/tile.gleam", [
        "pub const a = 1",
      ])
    let assert [breach] = module_path.named_by_kind([file])
      as { "expected exactly one breach for the folder " <> name }
    assert breach.path == file.path
    assert breach.line == 1
    assert string.contains(breach.rule, name)
  })
}

pub fn a_module_named_by_kind_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(module_path.kind_names, fn(name) {
    let file =
      planted.file("src/genesis_prime/map/" <> name <> ".gleam", [
        "pub const a = 1",
      ])
    let assert [breach] = module_path.named_by_kind([file])
      as { "expected exactly one breach for the module " <> name }
    assert breach.path == file.path
    assert string.contains(breach.rule, name)
  })
}

pub fn the_kind_names_are_the_fifteen_in_the_test_list_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert list.sort(module_path.kind_names, string.compare)
    == [
      "common",
      "core",
      "helper",
      "helpers",
      "lib",
      "misc",
      "model",
      "models",
      "rule",
      "rules",
      "shared",
      "type",
      "types",
      "util",
      "utils",
    ]
}

pub fn a_name_that_only_contains_a_kind_name_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    planted.file("src/genesis_prime/rule_check.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/typeset/library.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/map/modeller.gleam", ["pub const a = 1"]),
  ]
  assert module_path.named_by_kind(files) == []
}

pub fn a_module_path_named_by_kind_is_reported_once_per_file_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    planted.file("src/genesis_prime/map/tile.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/util/strings.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/login/types.gleam", ["pub const a = 1"]),
  ]
  assert list.map(module_path.named_by_kind(files), fn(breach) { breach.path })
    == [
      "src/genesis_prime/util/strings.gleam",
      "src/genesis_prime/login/types.gleam",
    ]
}

pub fn no_folder_or_module_under_src_is_named_by_kind_test() -> Nil {
  // Deadline: the body took 82 to 106 ms in three runs alone, so 5 s is more
  // than 3 times that.
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert module_path.named_by_kind(repository.sources(["src"])) == []
}

pub fn the_package_names_are_read_from_the_manifest_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let manifest =
    string.join(
      [
        "packages = [",
        "  { name = \"gleam_stdlib\", version = \"1.0.5\", build_tools = [\"gleam\"], requirements = [], otp_app = \"gleam_stdlib\", source = \"hex\", outer_checksum = \"AA\" },",
        "  { name = \"pog\", version = \"4.1.0\", build_tools = [\"gleam\"], requirements = [\"gleam_stdlib\"], otp_app = \"pog\", source = \"hex\", outer_checksum = \"BB\" },",
        "]",
        "",
        "[requirements]",
        "pog = { version = \">= 4.1.0 and < 5.0.0\" }",
      ],
      "\n",
    )
  assert module_path.packages(manifest) == ["gleam_stdlib", "pog"]
}

pub fn a_folder_named_for_a_package_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/pog/pool.gleam", ["pub const a = 1"])
  let assert [breach] =
    module_path.named_for_a_package([file], ["gleam_stdlib", "pog"])
    as "expected exactly one breach"
  assert breach.path == file.path
  assert breach.line == 1
  assert string.contains(breach.rule, "pog")
}

pub fn a_module_named_for_a_package_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/database/simplifile.gleam", [
      "pub const a = 1",
    ])
  let assert [breach] =
    module_path.named_for_a_package([file], ["gleam_stdlib", "simplifile"])
    as "expected exactly one breach"
  assert breach.path == file.path
  assert string.contains(breach.rule, "simplifile")
}

pub fn a_path_with_no_package_name_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = [
    planted.file("src/genesis_prime/database/pool.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime/pogo/pool.gleam", ["pub const a = 1"]),
    planted.file("src/genesis_prime.gleam", ["pub const a = 1"]),
  ]
  assert module_path.named_for_a_package(files, ["gleam_stdlib", "pog"]) == []
}

pub fn no_folder_or_module_under_src_is_named_for_a_package_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let packages = module_path.packages(source.read("manifest.toml"))
  assert list.length(packages) >= 40 as "the manifest packages were not found"
  assert module_path.named_for_a_package(repository.sources(["src"]), packages)
    == []
}
