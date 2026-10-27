//// The logging rules. Expected values are the designing-processes skill,
//// Logging: a line is logged through Erlang's logger and carries who and
//// where as metadata, and never a password, session key or other secret. The
//// logging module (`src/genesis_prime/telemetry/log.gleam` and its Erlang file
//// `src/log_ffi.erl`) is the one place that calls `logger`, so a call to
//// `logger`, to a `?LOG_` macro of `logger.hrl`, or to `io:format` or
//// `io:fwrite` from anywhere else in `src/` is a line that bypasses the
//// record. A call is code outside an Erlang comment, string or quoted atom;
//// a function of another module whose name starts the same (`io_lib:format`,
//// `my_logger:info`) is not a call. The record has no secret field: no field
//// of `Who`, `Actor`, `Place` or `Message` is labelled for a password, a
//// session, a secret, a token or a key. Each breach is planted in a made-up
//// file, each clean case beside it, and each rule is then run over the real
//// tree.

import code_rule/logging_bypass
import code_rule/planted
import code_rule/repository
import gleam/list
import gleam/string
import owned_test
import unitest

/// The path of the logging module's Gleam file, which may call `logger`.
const logging_module = "src/genesis_prime/telemetry/log.gleam"

/// The path of the logging module's Erlang file, which may call `logger`.
const logging_erlang_file = "src/log_ffi.erl"

fn external_to(module: String, function: String) -> String {
  "@external(erlang, \""
  <> module
  <> "\", \""
  <> function
  <> "\") pub fn call(text: String) -> Nil"
}

// Gleam externals.

pub fn an_external_to_logger_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/login.gleam", [
      "//// A planted module.",
      "",
      external_to("logger", "info"),
      external_to("logger", "set_primary_config"),
    ])
  assert planted.lines(logging_bypass.gleam_breaches(file)) == [3, 4]
}

pub fn an_external_to_io_format_or_io_fwrite_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/login.gleam", [
      "//// A planted module.",
      "",
      external_to("io", "format"),
      external_to("io", "fwrite"),
    ])
  assert planted.lines(logging_bypass.gleam_breaches(file)) == [3, 4]
}

pub fn an_external_to_another_function_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/genesis_prime/login.gleam", [
      "//// A planted module.",
      "",
      external_to("io", "columns"),
      external_to("io_lib", "format"),
      external_to("logger_ffi", "info"),
      external_to("erlang", "memory"),
    ])
  assert logging_bypass.gleam_breaches(file) == []
}

pub fn the_logging_module_may_call_logger_but_a_module_beside_it_may_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = [
    "//// A planted module.",
    "",
    external_to("logger", "log"),
    external_to("io", "format"),
  ]
  assert logging_bypass.gleam_breaches(planted.file(logging_module, lines))
    == []
  let beside = "src/genesis_prime/telemetry/snapshot.gleam"
  assert planted.lines(
      logging_bypass.gleam_breaches(planted.file(beside, lines)),
    )
    == [3, 4]
}

// Erlang files.

pub fn a_call_to_logger_or_a_log_macro_in_an_erlang_file_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted_ffi.erl", [
      "-module(planted_ffi).",
      "-include_lib(\"kernel/include/logger.hrl\").",
      "report(Text) -> logger:info(Text).",
      "level() -> logger:set_primary_config(level, debug).",
      "macro(Text) -> ?LOG_ERROR(Text).",
      "reference() -> fun logger:log/3.",
    ])
  assert planted.lines(logging_bypass.erlang_breaches(file)) == [3, 4, 5, 6]
}

pub fn a_call_to_io_format_or_io_fwrite_in_an_erlang_file_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted_ffi.erl", [
      "show(Text) -> io:format(\"~s~n\", [Text]).",
      "show(Device, Text) -> io:format(Device, \"~s~n\", [Text]).",
      "write(Text) -> io:fwrite(\"~s~n\", [Text]).",
      "reference() -> fun io:format/2.",
    ])
  assert planted.lines(logging_bypass.erlang_breaches(file)) == [1, 2, 3, 4]
}

pub fn an_erlang_file_that_calls_neither_is_clean_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("src/planted_ffi.erl", [
      "-module(planted_ffi).",
      "text(Format, Arguments) -> io_lib:format(Format, Arguments).",
      "columns() -> io:columns().",
      "other(Text) -> my_logger:info(Text).",
      "helper(Text) -> logger_ffi:info(Text).",
      "level() -> myio:format(\"~s\", []).",
      "%% Not logger:info, and not io:format.",
      "ok() -> ok. % io:fwrite(Text) is what a log line is for",
      "text() -> \"logger:info and io:format and ?LOG_ERROR\".",
    ])
  assert logging_bypass.erlang_breaches(file) == []
}

pub fn the_logging_modules_erlang_file_may_call_logger_but_a_file_beside_it_may_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let lines = ["write(Text) -> logger:log(info, {string, Text}, #{})."]
  assert logging_bypass.erlang_breaches(planted.file(logging_erlang_file, lines))
    == []
  assert planted.lines(
      logging_bypass.erlang_breaches(planted.file("src/snapshot_ffi.erl", lines)),
    )
    == [1]
}

// The record has no field for a secret.

pub fn a_logging_type_with_a_field_for_a_secret_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(logging_module, [
      "//// A planted module.",
      "",
      "pub type Who {",
      "  Who(account: Int, session_key: String)",
      "}",
      "",
      "pub type Actor {",
      "  Character(id: Int, password: String)",
      "  Unit(id: Int, auth_token: String)",
      "}",
      "",
      "pub type Place {",
      "  Process(name: String, client_secret: String)",
      "}",
      "",
      "pub type Message {",
      "  Numbered(number: Int, key: String)",
      "}",
    ])
  assert planted.lines(logging_bypass.secret_fields(file)) == [4, 8, 9, 13, 17]
}

pub fn a_logging_type_with_fields_for_who_and_where_only_is_clean_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(logging_module, [
      "//// A planted module.",
      "",
      "pub type Who {",
      "  Who(account: Int, actor: Actor, place: Place, message: Message)",
      "}",
      "",
      "pub type Actor {",
      "  Character(id: Int)",
      "  Unit(id: Int)",
      "}",
      "",
      "pub type Place {",
      "  Process(name: String)",
      "  Map(id: Int)",
      "}",
      "",
      "pub type Message {",
      "  Named(name: String, number: Int)",
      "}",
      "",
      "pub type Other {",
      "  Other(session_key: String)",
      "}",
    ])
  assert logging_bypass.secret_fields(file) == []
}

// The real tree.

pub fn no_gleam_file_under_src_calls_logger_or_prints_outside_the_logging_module_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let breaches =
    repository.sources(["src"])
    |> list.flat_map(logging_bypass.gleam_breaches)
  assert breaches == []
}

pub fn no_erlang_file_under_src_calls_logger_or_prints_outside_the_logging_module_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let files =
    repository.erlang_sources()
    |> list.filter(fn(file) { string.starts_with(file.path, "src/") })
  assert list.length(files) >= 2 as "the Erlang files under src/ were not found"
  assert list.any(files, fn(file) { file.path == logging_erlang_file })
    as "the logging module's Erlang file was not found"
  assert list.flat_map(files, logging_bypass.erlang_breaches) == []
}

pub fn the_logging_types_of_the_real_logging_module_have_no_field_for_a_secret_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let files =
    repository.sources(["src"])
    |> list.filter(fn(file) { file.path == logging_module })
  assert list.length(files) == 1 as "the logging module was not found"
  assert list.flat_map(files, logging_bypass.secret_fields) == []
}
