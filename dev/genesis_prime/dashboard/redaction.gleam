//// The mask on the database's password in the text the Logs page shows.
////
//// ```text
//// text ──find "password"──► spacing ──"=>"──► spacing ──► "value" or <<"value">> ──► "[hidden]"
////            └─ no key, or a value of another shape: the text is kept
//// ```
////
//// - The key is the word `password` followed by `=>`, as `pgo` 0.20.0 prints
////   its pool configuration when a connection crashes: the value is a string
////   (`"x"`) or a binary (`<<"x">>`), on the key's line or, when long, on the
////   next line (`test/fixture/otp_log`, `pgo_handler.erl:27` names the option).
//// - A spacing between the parts is spaces, tabs, newlines and `|`, which the
////   updater writes for each newline of a container's last lines (`lib.sh`,
////   `tr '\n' '|'`).
//// - A value ends at its closing quote, where a backslash escapes the next
////   character; a value that is cut and has none is hidden to the end of the
////   text.
//// - The mark says nothing of the value's length.
////
//// Only this form has a rule. A password printed in another form is shown:
//// an environment dump, a connection URL, pgo's own option form
//// (`[{password,"x"}]`, the tuple `pgo_handler.erl:27` documents), and a value
//// that is not a string. A string or binary that Erlang prints as numbers
//// (`password => [112,8364,120]`, `<<112,226,130,172,120>>`, as it does for
//// a control character or a character outside Latin-1) is shown too. The play
//// database's password is `openssl rand -hex 16` (`install.sh`), which prints
//// as a string.

import gleam/string

/// What stands in the quotes for a hidden value.
const hidden = "[hidden]"

/// The word before a value.
const key = "password"

/// The text with the value of each `password =>` key hidden.
pub fn hide_passwords(text: String) -> String {
  hide_from(text, "")
}

fn hide_from(text: String, done: String) -> String {
  case string.split_once(text, key) {
    Error(Nil) -> done <> text
    Ok(#(before, after)) -> {
      let #(shown, remaining) = after_key(after)
      hide_from(remaining, done <> before <> key <> shown)
    }
  }
}

/// What follows a key: the text to show in place of what was read, and the
/// text left. A key that is not followed by `=>` and a value keeps the text.
fn after_key(text: String) -> #(String, String) {
  let #(first_spacing, rest) = take_spacing(text)
  case rest {
    "=>" <> rest -> {
      let #(second_spacing, rest) = take_spacing(rest)
      let #(shown, remaining) = value(rest)
      #(first_spacing <> "=>" <> second_spacing <> shown, remaining)
    }
    _ -> #("", text)
  }
}

/// A value at the start of the text: the mark in its quotes, and the text after
/// the value. Text that holds no value there is kept.
fn value(text: String) -> #(String, String) {
  case text {
    "<<\"" <> body -> #("<<\"" <> hidden <> "\"", after_quote(body))
    "\"" <> body -> #("\"" <> hidden <> "\"", after_quote(body))
    _ -> #("", text)
  }
}

/// The text after the closing quote of a string whose opening quote was read;
/// nothing when the string has no closing quote.
fn after_quote(text: String) -> String {
  case string.pop_grapheme(text) {
    Error(Nil) -> ""
    Ok(#("\"", rest)) -> rest
    Ok(#("\\", rest)) ->
      case string.pop_grapheme(rest) {
        Ok(#(_, rest)) -> after_quote(rest)
        Error(Nil) -> ""
      }
    Ok(#(_, rest)) -> after_quote(rest)
  }
}

/// The leading spaces, tabs, newlines and `|` of the text, and the text after
/// them.
fn take_spacing(text: String) -> #(String, String) {
  take_spacing_from(text, "")
}

fn take_spacing_from(text: String, spacing: String) -> #(String, String) {
  case string.pop_grapheme(text) {
    Ok(#(" ", rest)) -> take_spacing_from(rest, spacing <> " ")
    Ok(#("\t", rest)) -> take_spacing_from(rest, spacing <> "\t")
    Ok(#("\n", rest)) -> take_spacing_from(rest, spacing <> "\n")
    Ok(#("|", rest)) -> take_spacing_from(rest, spacing <> "|")
    Ok(_) | Error(Nil) -> #(spacing, text)
  }
}

/// Whether the text ends at a `password =>` key, so that the value is on the
/// next line.
pub fn ends_at_a_password_key(text: String) -> Bool {
  let trimmed = string.trim_end(text)
  case string.ends_with(trimmed, "=>") {
    False -> False
    True ->
      trimmed
      |> string.drop_end(2)
      |> string.trim_end
      |> string.ends_with(key)
  }
}

/// A line that follows a line ending at a `password =>` key, with the value at
/// its start hidden and the rest of it masked like any text.
pub fn hide_a_value_after_a_key(line: String) -> String {
  let #(spacing, rest) = take_spacing(line)
  let #(shown, remaining) = value(rest)
  spacing <> shown <> hide_passwords(remaining)
}
