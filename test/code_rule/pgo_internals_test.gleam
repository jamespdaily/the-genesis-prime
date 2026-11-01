//// The pgo-internals rule: no test reads the internals of `pgo`, the Erlang
//// library under `pog`. Expected values are the card's rule that tests wait on
//// the readiness ask and no test imports a pgo module; `pog`, the Gleam
//// package every database test uses, is allowed. Each breach is planted once
//// in a made-up file.

import code_rule/pgo_internals
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test
import unitest

pub fn an_external_to_a_pgo_module_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "//// A planted test.",
      "",
      "@external(erlang, \"pgo_pool\", \"checkout\")",
      "fn checkout(pool: a) -> b",
      "",
      "@external(erlang, \"pgo\", \"query\")",
      "fn query(sql: String) -> b",
    ])
  assert planted.lines(pgo_internals.breaches(file)) == [4, 7]
    as "the breach is on the line of the external's function"
}

pub fn an_external_to_another_module_and_pog_are_no_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "//// A planted test.",
      "",
      "import pog",
      "",
      "@external(erlang, \"pogs\", \"checkout\")",
      "fn checkout(pool: a) -> b",
    ])
  assert pgo_internals.breaches(file) == []
}

pub fn an_erlang_helper_that_qualifies_a_call_by_a_pgo_module_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/pool_ffi.erl", [
      "-module(pool_ffi).",
      "%% pgo_pool_sup:start_link() would be a breach if it were called here.",
      "children(Sup) -> pgo_connection_sup:which_children(Sup).",
      "query(Sql) -> pgo:query(Sql).",
      "label() -> <<\"pgo_pool:checkout\">>.",
      "other(Pool) -> pool:checkout(Pool).",
    ])
  assert planted.lines(pgo_internals.erlang_breaches(file)) == [3, 4]
}

pub fn no_test_reads_pgo_internals_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  assert list.flat_map(repository.sources(under: ["test"]), fn(file) {
      pgo_internals.breaches(file)
    })
    == []
  assert list.flat_map(repository.erlang_sources(under: ["test"]), fn(file) {
      pgo_internals.erlang_breaches(file)
    })
    == []
}
