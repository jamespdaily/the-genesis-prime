//// The logging rules: every log line goes through `genesis_prime/telemetry/log`,
//// so no line bypasses its record of who and where, and that record has no
//// field a secret could be put in.

import code_rule/erlang_text
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/string

/// The logging module's Gleam file, the one Gleam file that may call `logger`.
const logging_gleam_file = "src/genesis_prime/telemetry/log.gleam"

/// The logging module's Erlang file, the one Erlang file that may call
/// `logger`.
const logging_erlang_file = "src/log_ffi.erl"

/// The types of the logging module that name who and where a line is about.
const logging_types = ["Who", "Actor", "Place", "Message"]

/// Words that, in a field's label, mark a field made for a secret.
const secret_words = ["password", "session", "secret", "token", "key"]

/// Each `@external(erlang, ...)` in a Gleam file that names a function of
/// `logger`, or `io:format` or `io:fwrite`, unless the file is the logging
/// module.
pub fn gleam_breaches(file: SourceFile) -> List(Breach) {
  case file.path == logging_gleam_file {
    True -> []
    False ->
      syntax.parse(file).functions
      |> list.filter(fn(definition) {
        list.any(syntax.erlang_externals(definition.attributes), writes_a_line)
      })
      |> list.map(fn(definition) {
        Breach(
          path: file.path,
          line: syntax.line_of(file.text, definition.definition.location.start),
          rule: "an external that writes a log line outside the logging module; use genesis_prime/telemetry/log",
        )
      })
      |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
  }
}

fn writes_a_line(external: #(String, String)) -> Bool {
  case external {
    #("logger", _) -> True
    #("io", "format") | #("io", "fwrite") -> True
    #(_, _) -> False
  }
}

/// Each line of an Erlang file that calls a function of `logger`, uses one of
/// its `?LOG_` macros, or calls `io:format` or `io:fwrite`, unless the file is
/// the logging module's Erlang file. Text in a comment, a string or a quoted
/// atom is not read.
pub fn erlang_breaches(file: SourceFile) -> List(Breach) {
  case file.path == logging_erlang_file {
    True -> []
    False ->
      string.split(file.text, "\n")
      |> list.index_map(fn(line, index) {
        #(index + 1, erlang_text.code_of(line))
      })
      |> list.filter(fn(numbered) { writes_a_line_in(numbered.1) })
      |> list.map(fn(numbered) {
        Breach(
          path: file.path,
          line: numbered.0,
          rule: "an Erlang call that writes a log line outside the logging module; use genesis_prime/telemetry/log",
        )
      })
  }
}

fn writes_a_line_in(code: String) -> Bool {
  erlang_text.starts_name(code, "logger:")
  || erlang_text.starts_name(code, "?LOG_")
  || erlang_text.names(code, "io:format")
  || erlang_text.names(code, "io:fwrite")
}

/// Each field of a custom type named `Who`, `Actor`, `Place` or `Message`
/// whose label names a secret: a password, a session, a secret, a token or a
/// key.
pub fn secret_fields(file: SourceFile) -> List(Breach) {
  syntax.parse(file).custom_types
  |> list.filter(fn(definition) {
    list.contains(logging_types, definition.definition.name)
  })
  |> list.flat_map(fn(definition) { definition.definition.variants })
  |> list.flat_map(fn(variant) { variant.fields })
  |> list.filter_map(secret_field(file, _))
  |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
}

/// The breach a field is, when its label names a secret.
fn secret_field(
  file: SourceFile,
  field: glance.VariantField,
) -> Result(Breach, Nil) {
  case field {
    glance.LabelledVariantField(item:, label:) ->
      case names_a_secret(label) {
        True ->
          Ok(Breach(
            path: file.path,
            line: syntax.line_of(file.text, type_start(item)),
            rule: "a logging type with a field for a secret: " <> label,
          ))
        False -> Error(Nil)
      }
    glance.UnlabelledVariantField(..) -> Error(Nil)
  }
}

fn names_a_secret(label: String) -> Bool {
  list.any(secret_words, string.contains(label, _))
}

/// The byte offset where a type is written.
fn type_start(type_: glance.Type) -> Int {
  case type_ {
    glance.NamedType(location:, ..)
    | glance.TupleType(location:, ..)
    | glance.FunctionType(location:, ..)
    | glance.VariableType(location:, ..)
    | glance.HoleType(location:, ..) -> location.start
  }
}
