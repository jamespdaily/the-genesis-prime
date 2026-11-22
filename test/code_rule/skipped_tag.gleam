//// The skipped-tag rule. The test run skips a tag with an environment setting
//// (`skipped_when_set` in `test/genesis_prime_test.gleam`), so a test with that
//// tag runs only where a part of `./check` runs the tag by itself
//// (`run_built genesis_prime_test ... --tag x`). A skipped tag no part runs is a
//// breach, because its tests sit outside every check.
////
//// ```text
//// test/genesis_prime_test.gleam ─▶ each element of `ignored_tags` ─▶ the tags the run skips
//// check ─▶ each `run_built genesis_prime_test --tag y` line ─▶ the tags a part runs
//// breach: a skipped tag no part runs, unless every test with it is in `skipped_until_converted`
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
//// - One skipped tag with no part is allowed while it is in
////   `skipped_until_converted` with every test that carries it, each by file and
////   whole name. A test with the tag that is not listed, and a listed test that
////   is missing or has lost the tag, are breaches, so the list only shrinks.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

/// A test the run skips: the test file's path from the repository root, and the
/// test function's name without its `_test` ending.
pub type ListedTest {
  ListedTest(path: String, name: String)
}

/// A skipped tag no part runs and the tests that carry it, which the rule
/// allows until each is changed to run without the tag.
pub type Conversion {
  Conversion(tag: String, tests: List(ListedTest))
}

/// The one skipped tag no part runs. Each of its tests pins a count or a list of
/// what the server handles, which a test's literal does not hold.
pub const skipped_until_converted =
  Conversion(
    tag: "dev_tool",
    tests: [
      ListedTest(
        "test/coverage_innate_test.gleam",
        "the_starting_set_holds_the_20_spells_of_the_innates_beside_the_59_of_the_abilities",
      ),
      ListedTest(
        "test/coverage_innate_test.gleam",
        "the_innate_slots_behind_a_level_gate_are_listed_as_left_out_and_none_is_open_at_level_1",
      ),
      ListedTest(
        "test/coverage_item_use_test.gleam",
        "every_item_row_with_a_spell_is_counted_once_and_more_are_played_than_before",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "coverage_counts_the_crowd_control_rows",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_measure_counts_the_gains_the_plan_refuses_as_not_read",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_measure_counts_the_damage_rows_the_area_load_refuses_as_not_read",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_measure_counts_a_proxy_that_names_no_spell_or_aims_elsewhere_as_not_read",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_measure_reads_a_row_behind_a_target_prerequisite_only_when_its_gate_is_read_for_every_kind",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "coverage_counts_the_periodic_rows",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_measure_counts_a_force_remove_whose_selector_names_no_row_as_not_read",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_measure_totals_match_the_plan",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "the_coverage_measure_counts_the_type_3_rows_the_plan_refuses",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "coverage_counts_the_union_rows_as_read",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "type_97_rows_are_each_read_left_out_or_refused_by_name",
      ),
      ListedTest(
        "test/coverage_plan_test.gleam",
        "type_15_rows_are_each_read_left_out_or_refused_by_name",
      ),
      ListedTest(
        "test/coverage_test.gleam",
        "every_engine_declares_its_area_and_the_type_columns_its_table_has",
      ),
      ListedTest(
        "test/named_unreached_test.gleam",
        "the_real_tables_count_42736_with_no_reason",
      ),
      ListedTest(
        "test/named_unreached_test.gleam",
        "the_real_tables_give_52370_its_reason",
      ),
      ListedTest(
        "test/named_unreached_test.gleam",
        "the_real_tables_list_72652_and_48584_as_links",
      ),
      ListedTest(
        "test/named_unreached_test.gleam",
        "the_real_tables_count_72652_by_the_effect_of_its_tooltip_and_list_it_as_a_link",
      ),
      ListedTest(
        "test/named_unreached_test.gleam",
        "the_real_tables_hold_exactly_three_counted_and_no_missing_row_with_volatility_planted",
      ),
      ListedTest(
        "test/objective_kind_test.gleam",
        "coverage_quest_objective_handled_ids_agree_with_objective_kind",
      ),
    ],
  )

/// Each breach of the rule: an `ignored_tags` the file lacks (at line 1), an
/// element of it the rule cannot read (at its line), a skipped tag no part runs
/// (at its `skipped_when_set` call) unless the conversion names it, and, for the
/// converted tag, each test that carries it without a listing or is listed
/// without carrying it.
pub fn breaches(
  test_run test_run: SourceFile,
  check check: SourceFile,
  files files: List(SourceFile),
  until_converted until_converted: Conversion,
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
      list.flat_map(entries, entry_breaches(
        entry: _,
        test_run:,
        runs:,
        files:,
        conversion: until_converted,
      ))
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
  files files: List(SourceFile),
  conversion conversion: Conversion,
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
      case list.contains(runs, tag), tag == conversion.tag {
        True, _ -> []
        False, True -> unconverted_breaches(files, conversion)
        False, False -> [
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

/// A test function with its tag: where it is written, and its whole name.
type Carrier {
  Carrier(path: String, name: String, line: Int)
}

fn carriers(files: List(SourceFile), tag: String) -> List(Carrier) {
  list.flat_map(files, fn(file) {
    list.filter_map(syntax.parse(file).functions, fn(definition) {
      let function = definition.definition
      case
        function.publicity == glance.Public
        && string.ends_with(function.name, "_test")
        && list.any(function.body, fn(statement) {
          list.contains(syntax.tags_of(statement), tag)
        })
      {
        True ->
          Ok(Carrier(
            path: file.path,
            name: function.name,
            line: syntax.line_of(
              file.text,
              definition.definition.location.start,
            ),
          ))
        False -> Error(Nil)
      }
    })
  })
}

/// Each test function (public, its name ending `_test`) that carries the tag,
/// as its file's path and its name without `_test`, sorted.
pub fn carrying(
  files files: List(SourceFile),
  tag tag: String,
) -> List(ListedTest) {
  carriers(files, tag)
  |> list.map(fn(carrier) {
    ListedTest(carrier.path, string.drop_end(carrier.name, 5))
  })
  |> list.sort(fn(first, second) {
    string.compare(
      first.path <> " " <> first.name,
      second.path <> " " <> second.name,
    )
  })
}

fn unconverted_breaches(
  files: List(SourceFile),
  conversion: Conversion,
) -> List(Breach) {
  let carried = carriers(files, conversion.tag)
  let unlisted =
    list.filter_map(carried, fn(carrier) {
      case list.any(conversion.tests, fn(listed) { names(listed, carrier) }) {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: carrier.path,
            line: carrier.line,
            rule: "the test `"
              <> carrier.name
              <> "` carries the skipped tag `"
              <> conversion.tag
              <> "` and is not in the list of tests skipped until converted",
          ))
      }
    })
  let dead =
    list.filter_map(conversion.tests, fn(listed) {
      case list.any(carried, fn(carrier) { names(listed, carrier) }) {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: listed.path,
            line: 1,
            rule: "the listed test `"
              <> listed.name
              <> "` is missing or no longer carries the skipped tag `"
              <> conversion.tag
              <> "`",
          ))
      }
    })
  list.append(unlisted, dead)
}

fn names(listed: ListedTest, carrier: Carrier) -> Bool {
  listed.path == carrier.path && carrier.name == listed.name <> "_test"
}
