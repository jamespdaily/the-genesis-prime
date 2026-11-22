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
//// - A part runs a tag only on a line of `check` that is not a comment, an `echo`
////   or a `printf` and holds the words `run_built genesis_prime_test` and
////   `--tag` with the tag; the header or a message that names the tag runs nothing.
//// - One skipped tag with no part is allowed while it is in
////   `skipped_until_converted` with every test that carries it, each by file and
////   the start of its name. A test with the tag that is not listed, and a listed
////   test that is missing or has lost the tag, are breaches, so the list only
////   shrinks.

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
/// start of the test function's name (the whole name for a test whose name does
/// not change).
pub type ListedTest {
  ListedTest(path: String, name_start: String)
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
        "test/coverage_type_test.gleam",
        "the_effect_types_the_measure_handles_are_1_3_4_7_8_10_11_14_15_17_18_26_29_35_42_52_64_73_76_80_81_83_84_95_97_112_118_and_145",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_prerequisite_types_the_measure_handles_are_the_thirty_five_read_and_those_with_no_case",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_starting_abilities_column_holds_the_issues_effect_counts",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_starting_abilities_column_holds_the_issues_prerequisite_counts",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_starting_abilities_and_innates_reach_79_spells_with_the_gates_a_level_1_character_can_open",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "each_decoded_type_not_handled_is_listed_with_its_reason_and_a_fact_key_the_file_holds",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_effect_types_3_10_11_14_15_17_18_29_35_42_52_64_73_76_80_81_83_84_95_97_112_118_and_145_are_partial_with_a_reason_and_a_fact_key_the_file_holds",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_clients_522_type_73_rows_count_488_handled_and_34_not",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_clients_74_type_83_rows_count_49_not_read_and_its_9_type_84_rows_4",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_clients_starting_abilities_leave_out_the_runner_prerequisites_and_the_proxies_behind_amp_gates",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_starting_abilities_totals_hold_208_of_217_effect_rows_and_79_of_79_conditions_handled",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_innate_cost_emm_ids_the_measure_handles_are_4_and_7",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_other_emm_ids_are_decoded_and_missing_with_the_reason_and_the_fact_key",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_spend_engine_counts_the_ids_of_both_columns_and_the_starting_abilities_hold_4_once",
      ),
      ListedTest("test/coverage_type_test.gleam", "coverage_proc_rows_read"),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_clients_rows_of_types_18_81_and_145_count_6_316_and_0_not_read_and_17_and_80_221_and_375",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_clients_358_disguise_rows_count_159_read_and_the_two_exosuit_rows_among_the_starting_abilities",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_despawn_type_is_counted_read_by_the_rows_the_plan_applies",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "the_unit_state_type_is_counted_read_by_the_rows_the_plan_applies",
      ),
      ListedTest(
        "test/coverage_type_test.gleam",
        "type_35_rows_aimed_at_the_caster_are_counted_read",
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
  let breaches = case ignored_tag_entries(test_run) {
    Error(Nil) -> [
      Breach(
        path: test_run.path,
        line: 1,
        rule: "the test run names no `ignored_tags` to read the skipped tags from",
      ),
    ]
    Ok(entries) -> {
      let runs = run_tags(check)
      list.flat_map(entries, fn(entry) {
        case entry {
          Unreadable(location:) -> [
            Breach(
              path: test_run.path,
              line: syntax.line_of(test_run.text, location.start),
              rule: "an `ignored_tags` element that is not `skipped_when_set(variable, tag: \"x\")` with a string literal",
            ),
          ]
          Skipped(tag:, ..) if tag == until_converted.tag ->
            case list.contains(runs, tag) {
              True -> []
              False -> unconverted_breaches(files, until_converted)
            }
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
      })
    }
  }
  list.sort(breaches, fn(first, second) {
    string.compare(first.path, second.path)
    |> order.break_tie(int.compare(first.line, second.line))
  })
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
      glance.Call(arguments:, ..) ->
        list.find_map(arguments, fn(argument) {
          case argument {
            glance.LabelledField(label: "ignored_tags", item:, ..) -> Ok(item)
            glance.LabelledField(..)
            | glance.ShorthandField(..)
            | glance.UnlabelledField(..) -> Error(Nil)
          }
        })
      glance.RecordUpdate(fields:, ..) ->
        list.find_map(fields, fn(field) {
          case field {
            glance.RecordUpdateField(label: "ignored_tags", item: Some(item)) ->
              Ok(item)
            glance.RecordUpdateField(..) -> Error(Nil)
          }
        })
      glance.Int(..)
      | glance.Float(..)
      | glance.String(..)
      | glance.Variable(..)
      | glance.NegateInt(..)
      | glance.NegateBool(..)
      | glance.Block(..)
      | glance.Panic(..)
      | glance.Todo(..)
      | glance.Tuple(..)
      | glance.List(..)
      | glance.Fn(..)
      | glance.FieldAccess(..)
      | glance.TupleIndex(..)
      | glance.FnCapture(..)
      | glance.BitString(..)
      | glance.Case(..)
      | glance.BinaryOperator(..)
      | glance.Echo(..) -> Error(Nil)
    }
  })
  |> result.map(entries_of)
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
    glance.Int(..)
    | glance.Float(..)
    | glance.String(..)
    | glance.Variable(..)
    | glance.NegateInt(..)
    | glance.NegateBool(..)
    | glance.Block(..)
    | glance.Panic(..)
    | glance.Todo(..)
    | glance.Tuple(..)
    | glance.Fn(..)
    | glance.RecordUpdate(..)
    | glance.FieldAccess(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Case(..)
    | glance.BinaryOperator(..)
    | glance.Echo(..) -> [Unreadable(location: syntax.span_of(expression))]
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
/// words, and is not a comment, an `echo` or a `printf`.
pub fn run_tags(check: SourceFile) -> List(String) {
  string.split(check.text, "\n")
  |> list.flat_map(fn(line) {
    let words =
      string.replace(line, "\t", " ")
      |> string.split(" ")
      |> list.filter(fn(word) { word != "" })
    case words {
      [] -> []
      [first, ..] ->
        case
          string.starts_with(first, "#") || first == "echo" || first == "printf"
        {
          True -> []
          False -> tags_after_run(words)
        }
    }
  })
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
/// as its file's path and its whole name, sorted.
pub fn carrying(
  files files: List(SourceFile),
  tag tag: String,
) -> List(ListedTest) {
  carriers(files, tag)
  |> list.map(fn(carrier) { ListedTest(carrier.path, carrier.name) })
  |> list.sort(fn(first, second) {
    string.compare(
      first.path <> " " <> first.name_start,
      second.path <> " " <> second.name_start,
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
              <> listed.name_start
              <> "` is missing or no longer carries the skipped tag `"
              <> conversion.tag
              <> "`",
          ))
      }
    })
  list.append(unlisted, dead)
}

fn names(listed: ListedTest, carrier: Carrier) -> Bool {
  listed.path == carrier.path
  && string.starts_with(carrier.name, listed.name_start)
}
