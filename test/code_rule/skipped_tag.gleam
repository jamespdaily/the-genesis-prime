//// The skipped-tag rule. The test run skips a tag with an environment setting
//// (`skipped_when_set` in `test/genesis_prime_test.gleam`), so a test with that
//// tag runs only where a part of `./check` runs the tag by itself
//// (`run_built genesis_prime_test ... --tag x`). A skipped tag no part runs is a
//// breach, because its tests sit outside every check.
////
//// ```text
//// test/genesis_prime_test.gleam ─▶ each element of `ignored_tags` ─▶ the tags the run skips
//// check ─▶ each `run_built genesis_prime_test --tag y` line ─▶ the tags a part runs
//// breach: a skipped tag no part runs
//// ```
////
//// - An element of `ignored_tags` that is not `skipped_when_set(variable, tag: "x")`
////   with a string literal is a breach, since the rule cannot read its tag and an
////   unread tag must not pass as run.
//// - A part runs a tag only where `check` runs it as a command: the words
////   `run_built genesis_prime_test` and `--tag` with the tag, outside quotes, a
////   trailing comment and the text of a heredoc, on a line that is not a comment,
////   an `echo` or a `printf`; the header or a message that names the tag runs
////   nothing.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

/// Each breach of the rule: an `ignored_tags` the file lacks (at line 1), an
/// element of it the rule cannot read (at its line), and a skipped tag no part
/// runs (at its `skipped_when_set` call).
pub fn breaches(
  test_run test_run: SourceFile,
  check check: SourceFile,
) -> List(Breach) {
  let found = case ignored_tag_entries(test_run) {
    Error(Nil) -> [
      Breach(
        path: test_run.path,
        line: 1,
        rule: "the test run names no `ignored_tags` to read the skipped tags from",
      ),
    ]
    Ok(entries) -> {
      let runs = run_tags(check)
      list.flat_map(entries, entry_breaches(entry: _, test_run:, runs:))
    }
  }
  list.sort(found, fn(first, second) {
    string.compare(first.path, second.path)
    |> order.break_tie(int.compare(first.line, second.line))
  })
}

fn entry_breaches(
  entry entry: Entry,
  test_run test_run: SourceFile,
  runs runs: List(String),
) -> List(Breach) {
  case entry {
    Unreadable(location:) -> [
      Breach(
        path: test_run.path,
        line: syntax.line_of(test_run.text, location.start),
        rule: "an `ignored_tags` element that is not `skipped_when_set(variable, tag: \"x\")` with a string literal",
      ),
    ]
    Skipped(tag:, location:) ->
      case list.contains(runs, tag) {
        True -> []
        False -> [
          Breach(
            path: test_run.path,
            line: syntax.line_of(test_run.text, location.start),
            rule: "the test run skips `"
              <> tag
              <> "` and no part of the check runs it",
          ),
        ]
      }
  }
}

/// An element of `ignored_tags`: a tag the run skips and where its call is
/// written, or an element the rule cannot read and where it is written.
type Entry {
  Skipped(tag: String, location: glance.Span)
  Unreadable(location: glance.Span)
}

/// The elements of the file's `ignored_tags` argument, which a call or a record
/// update names by label, or `Error(Nil)` when the file names none.
fn ignored_tag_entries(file: SourceFile) -> Result(List(Entry), Nil) {
  syntax.parse(file)
  |> syntax.expressions
  |> list.find_map(fn(expression) {
    case expression {
      glance.Call(arguments:, ..) -> ignored_tags_of_call(arguments)
      glance.RecordUpdate(fields:, ..) -> ignored_tags_of_update(fields)
      _ -> Error(Nil)
    }
  })
  |> result.map(entries_of)
}

fn ignored_tags_of_call(
  arguments: List(glance.Field(glance.Expression)),
) -> Result(glance.Expression, Nil) {
  list.find_map(arguments, fn(argument) {
    case argument {
      glance.LabelledField(label: "ignored_tags", item:, ..) -> Ok(item)
      glance.LabelledField(..)
      | glance.ShorthandField(..)
      | glance.UnlabelledField(..) -> Error(Nil)
    }
  })
}

fn ignored_tags_of_update(
  fields: List(glance.RecordUpdateField(glance.Expression)),
) -> Result(glance.Expression, Nil) {
  list.find_map(fields, fn(field) {
    case field {
      glance.RecordUpdateField(label: "ignored_tags", item: Some(item)) ->
        Ok(item)
      glance.RecordUpdateField(..) -> Error(Nil)
    }
  })
}

/// The skipped tags an expression gives: the elements of a list, the arguments
/// of `list.append`, `list.flatten` and `list.concat`, and each
/// `skipped_when_set` call whose tag is a string literal. Anything else is
/// unreadable.
fn entries_of(expression: glance.Expression) -> List(Entry) {
  case expression {
    glance.List(elements:, rest:, ..) ->
      list.flat_map(list.append(elements, option.values([rest])), entries_of)
    glance.Call(
      function: glance.FieldAccess(
        container: glance.Variable(name: "list", ..),
        label:,
        ..,
      ),
      arguments:,
      ..,
    )
      if label == "append" || label == "flatten" || label == "concat"
    -> list.flat_map(argument_items(arguments), entries_of)
    glance.Call(
      function: glance.Variable(name: "skipped_when_set", ..),
      arguments:,
      location:,
    ) ->
      case tag_argument(arguments) {
        Some(glance.String(value:, ..)) -> [Skipped(tag: value, location:)]
        Some(_) | None -> [Unreadable(location:)]
      }
    _ -> [Unreadable(location: syntax.span_of(expression))]
  }
}

fn argument_items(
  arguments: List(glance.Field(glance.Expression)),
) -> List(glance.Expression) {
  list.filter_map(arguments, fn(argument) {
    case argument {
      glance.LabelledField(item:, ..) | glance.UnlabelledField(item) -> Ok(item)
      glance.ShorthandField(..) -> Error(Nil)
    }
  })
}

/// The argument that gives the tag of a `skipped_when_set` call: the one labelled
/// `tag`, or the second given by position.
fn tag_argument(
  arguments: List(glance.Field(glance.Expression)),
) -> Option(glance.Expression) {
  let labelled =
    list.find_map(arguments, fn(argument) {
      case argument {
        glance.LabelledField(label: "tag", item:, ..) -> Ok(item)
        glance.LabelledField(..)
        | glance.ShorthandField(..)
        | glance.UnlabelledField(..) -> Error(Nil)
      }
    })
  case labelled, arguments {
    Ok(item), _ -> Some(item)
    Error(Nil), [_, glance.UnlabelledField(item), ..] -> Some(item)
    Error(Nil), _ -> None
  }
}

/// The tags the test run skips, as the string literals of its
/// `skipped_when_set(.., tag: "x")` elements, in the order written.
pub fn skipped_tags(test_run: SourceFile) -> List(String) {
  ignored_tag_entries(test_run)
  |> result.unwrap([])
  |> list.filter_map(fn(entry) {
    case entry {
      Skipped(tag:, ..) -> Ok(tag)
      Unreadable(..) -> Error(Nil)
    }
  })
}

/// The tags the parts of `check` run by themselves, in the order written: the
/// word after `--tag` on a line that holds `run_built genesis_prime_test` as two
/// words of the shell's command, and is not a comment, an `echo`, a `printf` or
/// the text of a heredoc.
pub fn run_tags(check: SourceFile) -> List(String) {
  lines_outside_heredocs(
    lines: string.split(check.text, "\n"),
    ends_at: None,
    kept: [],
  )
  |> list.flat_map(fn(line) {
    case shell_words(line) {
      [] -> []
      [first, ..] as words ->
        case first == "echo" || first == "printf" {
          True -> []
          False -> tags_after_run(words)
        }
    }
  })
}

/// The lines that are not the text of a heredoc: a line holding `<<WORD` (also
/// `<<-WORD`, `<<'WORD'` and `<<"WORD"`, but not the here-string `<<<`) starts
/// the text, which ends at the first line that is `WORD` alone. The starting
/// line is kept, the text and its end are dropped.
fn lines_outside_heredocs(
  lines lines: List(String),
  ends_at ends_at: Option(String),
  kept kept: List(String),
) -> List(String) {
  case lines, ends_at {
    [], _ -> list.reverse(kept)
    [line, ..rest], Some(word) ->
      case string.trim(line) == word {
        True -> lines_outside_heredocs(lines: rest, ends_at: None, kept: kept)
        False ->
          lines_outside_heredocs(lines: rest, ends_at: ends_at, kept: kept)
      }
    [line, ..rest], None ->
      lines_outside_heredocs(lines: rest, ends_at: heredoc_word(line), kept: [
        line,
        ..kept
      ])
  }
}

fn heredoc_word(line: String) -> Option(String) {
  case string.split_once(line, "<<") {
    Ok(#(_, "<" <> _)) | Error(Nil) -> None
    Ok(#(_, after)) ->
      string.drop_start(after, case string.starts_with(after, "-") {
        True -> 1
        False -> 0
      })
      |> string.trim
      |> string.replace("'", "")
      |> string.replace("\"", "")
      |> string.split(" ")
      |> list.first
      |> option.from_result
  }
}

/// The words of a shell line: split at spaces and tabs outside quotes, the text
/// inside single and double quotes left out of its word, and a `#` that starts a
/// word ending the line.
fn shell_words(line: String) -> List(String) {
  words_from(
    characters: string.to_graphemes(line),
    quote: None,
    word: "",
    words: [],
  )
}

fn words_from(
  characters characters: List(String),
  quote quote: Option(String),
  word word: String,
  words words: List(String),
) -> List(String) {
  case characters, quote {
    [], _ -> list.reverse(with_word(word, words))
    ["\\", _, ..rest], Some("\"") ->
      words_from(characters: rest, quote: quote, word: word, words: words)
    [character, ..rest], Some(closing) ->
      case character == closing {
        True ->
          words_from(characters: rest, quote: None, word: word, words: words)
        False ->
          words_from(characters: rest, quote: quote, word: word, words: words)
      }
    ["\\", escaped, ..rest], None ->
      words_from(
        characters: rest,
        quote: None,
        word: word <> escaped,
        words: words,
      )
    ["\"" as opening, ..rest], None | ["'" as opening, ..rest], None ->
      words_from(
        characters: rest,
        quote: Some(opening),
        word: word,
        words: words,
      )
    [" ", ..rest], None | ["\t", ..rest], None ->
      words_from(
        characters: rest,
        quote: None,
        word: "",
        words: with_word(word, words),
      )
    ["#", ..], None if word == "" -> list.reverse(words)
    [character, ..rest], None ->
      words_from(
        characters: rest,
        quote: None,
        word: word <> character,
        words: words,
      )
  }
}

fn with_word(word: String, words: List(String)) -> List(String) {
  case word {
    "" -> words
    _ -> [word, ..words]
  }
}

fn tags_after_run(words: List(String)) -> List(String) {
  case words {
    ["run_built", "genesis_prime_test", ..rest] -> tags_after_flag(rest)
    [_, ..rest] -> tags_after_run(rest)
    [] -> []
  }
}

fn tags_after_flag(words: List(String)) -> List(String) {
  case words {
    ["--tag", tag, ..rest] -> [tag, ..tags_after_flag(rest)]
    [_, ..rest] -> tags_after_flag(rest)
    [] -> []
  }
}
