//// The Erlang environment rule. Expected values are the writing-gleam skill,
//// Packages: take the first step that does the job, and a Gleam package from
//// Hex (envoy for an environment variable, argv for the arguments) comes
//// before an Erlang external. So no tracked `.erl` file calls `os:getenv`
//// (any arity) or `init:get_plain_arguments`. A call is text outside an
//// Erlang comment (from `%` to the end of the line) and outside a string, so
//// a comment or a message that names the function is not a breach. Each
//// breach is planted in a made-up file, reported at its line.

import code_rule/erlang_environment
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test

pub fn a_call_to_os_getenv_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("dev/planted_ffi.erl", [
      "-module(planted_ffi).",
      "-export([get/1]).",
      "get(Name) ->",
      "    os:getenv(unicode:characters_to_list(Name)).",
    ])
  assert planted.lines(erlang_environment.breaches(file)) == [4]
}

pub fn a_call_to_os_getenv_with_no_name_or_a_default_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("dev/planted_ffi.erl", [
      "all() -> os:getenv().",
      "fallback(Name) -> os:getenv(Name, \"none\").",
    ])
  assert planted.lines(erlang_environment.breaches(file)) == [1, 2]
}

pub fn a_call_to_init_get_plain_arguments_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("test/planted_ffi.erl", [
      "arguments() ->",
      "    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].",
    ])
  assert planted.lines(erlang_environment.breaches(file)) == [2]
}

pub fn a_reference_to_the_function_without_a_call_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("dev/planted_ffi.erl", [
      "names(Names) -> lists:map(fun os:getenv/1, Names).",
    ])
  assert planted.lines(erlang_environment.breaches(file)) == [1]
}

pub fn a_breach_after_a_percent_sign_in_a_string_is_still_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("dev/planted_ffi.erl", [
      "f() -> io:format(\"100% done~n\"), os:getenv(\"HOME\").",
    ])
  assert planted.lines(erlang_environment.breaches(file)) == [1]
}

pub fn a_file_that_reads_neither_is_clean_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("dev/planted_ffi.erl", [
      "-module(planted_ffi).",
      "-export([pid/0, side/0, flags/0]).",
      "pid() -> os:getpid().",
      "side() -> os:cmd(\"ps\").",
      "flags() -> init:get_argument(escript).",
      "other() -> myos:getenv_cache().",
    ])
  assert erlang_environment.breaches(file) == []
}

pub fn a_comment_or_a_string_that_names_the_functions_is_clean_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("dev/planted_ffi.erl", [
      "%% Not os:getenv, and not init:get_plain_arguments.",
      "f() -> ok. % os:getenv(Name) is what envoy wraps",
      "g() -> \"os:getenv\".",
    ])
  assert erlang_environment.breaches(file) == []
}

pub fn no_tracked_erlang_file_reads_the_environment_or_the_arguments_test() -> Nil {
  use <- owned_test.run(10_000)
  let files = repository.erlang_sources()
  assert list.length(files) >= 10 as "tracked Erlang files were not found"
  assert list.flat_map(files, erlang_environment.breaches) == []
}
