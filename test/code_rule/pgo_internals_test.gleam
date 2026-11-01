//// The pgo-internals rule: no test reads the internals of `pgo`, the Erlang
//// library under `pog`. Expected values are the card's rule that tests wait on
//// the readiness ask and no test names a pgo module or process; `pog`, the
//// Gleam package every database test uses, is allowed. Each breach is planted
//// once in a made-up file, and the helper the rule replaces, the pool waiter
//// as it stood, is planted whole.

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

pub fn a_pgo_process_name_in_a_gleam_string_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "import gleam/erlang/atom",
      "",
      "pub fn name() -> atom.Atom {",
      "  atom.create(\"pgo_pool_sup\")",
      "}",
    ])
  assert planted.lines(pgo_internals.breaches(file)) == [4]
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
      "",
      "pub fn text() -> String {",
      "  \"pgo's internals\" <> \"pgoxyz\"",
      "}",
    ])
  assert pgo_internals.breaches(file) == []
}

pub fn an_erlang_helper_that_writes_a_pgo_atom_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/pool_ffi.erl", [
      "-module(pool_ffi).",
      "%% pgo_pool_sup:start_link() would be a breach if it were called here.",
      "children(Sup) -> pgo_connection_sup:which_children(Sup).",
      "query(Sql) -> pgo:query(Sql).",
      "kind(Pid) -> proc_lib:translate_initial_call(Pid) =:= {supervisor, pgo_pool_sup, 1}.",
      "label() -> <<\"pgo_pool:checkout\">>.",
      "other(Pool) -> pool:checkout(Pool).",
      "close(Pool) -> pgoxyz:close(Pool).",
    ])
  assert planted.lines(pgo_internals.erlang_breaches(file)) == [3, 4, 5]
    as "a call, a module and a process name are breaches; a comment, a string and a name that only starts with the letters are not"
}

pub fn the_pool_waiter_the_rule_replaces_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // test/pool_started_ffi.erl as it stood: it reached pgo's processes through
  // supervisor:which_children, sys:get_state and the name of pgo's pool
  // supervisor, with no call into a pgo module.
  let file =
    planted.file("test/pool_started_ffi.erl", [
      "-module(pool_started_ffi).",
      "-export([await/2]).",
      "",
      "%% Whether the pool registered as Name has started within WithinMs",
      "%% milliseconds. The pool's own processes are pgo's (pgo_pool.erl,",
      "%% pgo_pool_sup.erl): the pool, whose supervisor holds the connection",
      "%% supervisor, the connection starter and the type server. A gen_statem or",
      "%% gen_server answers a system request only between events, so `sys:get_state`",
      "%% on a process returns once the event it is in has ended: the starter's first",
      "%% event starts every connection and then calls the type server, which loads",
      "%% the types through a connection, and a connection's first event opens it.",
      "%% Every one of them has answered when the pool has started, and a pool whose",
      "%% database is away never does.",
      "-spec await(atom(), non_neg_integer()) -> boolean().",
      "await(Name, WithinMs) ->",
      "    Deadline = erlang:monotonic_time(millisecond) + WithinMs,",
      "    case whereis(Name) of",
      "        undefined -> false;",
      "        Pool ->",
      "            try started(Pool, Deadline)",
      "            catch exit:_ -> false",
      "            end",
      "    end.",
      "",
      "started(Pool, Deadline) ->",
      "    idle(Pool, Deadline),",
      "    Sup = pool_supervisor(Pool),",
      "    Children = supervisor:which_children(Sup),",
      "    idle(child(connection_starter, Children), Deadline),",
      "    ConnectionSup = child(connection_sup, Children),",
      "    Connections = [Pid || {_, Pid, _, _} <- supervisor:which_children(ConnectionSup),",
      "                          is_pid(Pid)],",
      "    lists:foreach(fun(Pid) -> idle(Pid, Deadline) end, Connections),",
      "    true.",
      "",
      "%% Returns when the process is between events, and exits when that takes past",
      "%% the deadline or the process is gone.",
      "idle(Pid, Deadline) ->",
      "    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),",
      "    _ = sys:get_state(Pid, Remaining),",
      "    ok.",
      "",
      "%% The supervisor the pool process started and is linked to.",
      "pool_supervisor(Pool) ->",
      "    {links, Links} = process_info(Pool, links),",
      "    [Sup] = [Pid || Pid <- Links, is_pid(Pid),",
      "                    proc_lib:translate_initial_call(Pid) =:= {supervisor, pgo_pool_sup, 1}],",
      "    Sup.",
      "",
      "child(Id, Children) ->",
      "    {Id, Pid, _, _} = lists:keyfind(Id, 1, Children),",
      "    Pid.",
    ])
  assert planted.lines(pgo_internals.erlang_breaches(file)) == [47]
    as "the name of pgo's pool supervisor, the one place the file reaches pgo"
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
