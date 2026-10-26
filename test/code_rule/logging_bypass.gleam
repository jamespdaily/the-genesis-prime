//// The logging rules: every log line goes through `genesis_prime/telemetry/log`,
//// so no line bypasses its record of who and where, and that record has no
//// field a secret could be put in.

import code_rule/source.{type Breach, type SourceFile}

/// Each `@external(erlang, ...)` in a Gleam file that names a function of
/// `logger`, or `io:format` or `io:fwrite`, unless the file is the logging
/// module.
pub fn gleam_breaches(file: SourceFile) -> List(Breach) {
  todo as "read the Gleam file's externals"
}

/// Each line of an Erlang file that calls a function of `logger`, uses one of
/// its `?LOG_` macros, or calls `io:format` or `io:fwrite`, unless the file is
/// the logging module's Erlang file. Text in a comment, a string or a quoted
/// atom is not read.
pub fn erlang_breaches(file: SourceFile) -> List(Breach) {
  todo as "read the Erlang file's calls"
}

/// Each field of a custom type named `Who`, `Actor`, `Place` or `Message`
/// whose label names a secret: a password, a session, a secret, a token or a
/// key.
pub fn secret_fields(file: SourceFile) -> List(Breach) {
  todo as "read the logging types' field labels"
}
