//// Game and map code does not branch on a game table's raw type number: a
//// `case` on a row's `type_` field with integer patterns (or a guard on a
//// bound name), or a `==` or `!=` of that field with an integer or a constant,
//// outside the modules that read the table (`table/`) or the wire (`message/`).
////
//// ```text
//// src files -> sites per function -> minus each function's listed gap -> breaches
//// ```
////
//// - A table's `type` column decodes once, where the table is read, into a
////   tagged type; code matches on that type, so a new type adds a variant and
////   the compiler names each place that handles it. A comparison with a
////   constructor, and a `case` with constructor patterns, is that tagged type.
//// - A check against 0 (no type) and two type fields compared with each other
////   decide no kind, so they are not reported. The field is the one named
////   `type_`, the client column literally named `type`; other tables' columns
////   that end in `_type` are not read by this rule.
//// - Each site that exists today is a known gap, counted per function and
////   naming the open issue whose work removes it. A function with more sites
////   than listed fails, and so does a gap whose function has fewer.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

/// The raw-type sites one function holds today, and the open issue whose work
/// removes them.
pub type Gap {
  Gap(path: String, function: String, sites: Int, issue: Int)
}

/// Every site in `src/` today. Quest objective sites wait on the quest
/// objective type step; the target group sites on the later lines of the
/// table redesign.
pub const known_gaps = [
  Gap(
    path: "src/genesis_prime/game/departures.gleam",
    function: "counts_its_terminal",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "advance_quest",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "arrivals",
    sites: 3,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "buttons",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "counts",
    sites: 10,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "credits_a_used_unit",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "finishes",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "group_member",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "held_item",
    sites: 2,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "hidden_script",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "required_sibling_arrived",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "visible_script_broken",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "visits",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/place_objective.gleam",
    function: "at_marker",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/place_objective.gleam",
    function: "is_place_counted",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/place_objective.gleam",
    function: "repeated",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/place_objective.gleam",
    function: "unmarked",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/projector.gleam",
    function: "objective_broken",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "as_logged",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "counted_by_unit",
    sites: 3,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "is_checklist",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "is_percent_kind",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "is_placeholder",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "reused_unit_objectives",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/shortcut_spell.gleam",
    function: "build",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "creatures_of",
    sites: 1,
    issue: 328,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "listed",
    sites: 1,
    issue: 328,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "row_has",
    sites: 1,
    issue: 328,
  ),
  Gap(
    path: "src/genesis_prime/world_map/checklist_index.gleam",
    function: "is_target",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "is_click_kind",
    sites: 2,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "is_placed_kind",
    sites: 3,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "plan",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/world_map/spawn.gleam",
    function: "captives",
    sites: 1,
    issue: 888,
  ),
]

/// One raw-type site: the function that holds it and its line.
type Site {
  Site(path: String, function: String, line: Int)
}

/// Each site in a function beyond the sites its gap lists, at its line, and
/// each gap whose function holds fewer sites than listed, at line 1.
pub fn breaches(
  files files: List(SourceFile),
  gaps gaps: List(Gap),
) -> List(Breach) {
  let found =
    files
    |> list.filter(is_game_or_map_code)
    |> list.flat_map(sites)
    |> list.group(fn(site) { #(site.path, site.function) })
  let unlisted =
    dict.to_list(found)
    |> list.flat_map(fn(entry) {
      let #(#(path, function), in_function) = entry
      in_function
      |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
      |> list.drop(listed_sites(gaps:, path:, function:))
      |> list.map(fn(site) {
        Breach(
          path:,
          line: site.line,
          rule: "raw type number branched on in `"
            <> function
            <> "`: match on the table's tagged type instead",
        )
      })
    })
  let stale =
    list.filter_map(gaps, fn(gap) {
      let held =
        dict.get(found, #(gap.path, gap.function))
        |> result.map(list.length)
        |> result.unwrap(0)
      case held < gap.sites {
        True ->
          Ok(Breach(
            path: gap.path,
            line: 1,
            rule: "the known gap for `"
              <> gap.function
              <> "` lists "
              <> int.to_string(gap.sites)
              <> " raw-type sites and the function holds "
              <> int.to_string(held)
              <> ": lower or remove it",
          ))
        False -> Error(Nil)
      }
    })
  list.append(unlisted, stale)
  |> list.sort(fn(first, second) {
    string.compare(first.path, second.path)
    |> order.break_tie(int.compare(first.line, second.line))
  })
}

fn listed_sites(
  gaps gaps: List(Gap),
  path path: String,
  function function: String,
) -> Int {
  gaps
  |> list.filter(fn(gap) { gap.path == path && gap.function == function })
  |> list.fold(0, fn(total, gap) { total + gap.sites })
}

/// A file under `src/` other than the modules that read the table or the wire,
/// which hold the raw numbers on purpose.
fn is_game_or_map_code(file: SourceFile) -> Bool {
  string.starts_with(file.path, "src/")
  && !string.starts_with(file.path, "src/genesis_prime/table/")
  && !string.starts_with(file.path, "src/genesis_prime/message/")
}

fn sites(file: SourceFile) -> List(Site) {
  let module = syntax.parse(file)
  list.flat_map(module.functions, fn(definition) {
    glance.Module(..module, functions: [definition])
    |> syntax.expressions
    |> list.flat_map(site_offsets)
    |> list.map(fn(offset) {
      Site(
        path: file.path,
        function: definition.definition.name,
        line: syntax.line_of(file.text, offset),
      )
    })
  })
}

/// The start of the expression when it is a raw-type site.
fn site_offsets(expression: glance.Expression) -> List(Int) {
  case expression {
    glance.Case(location:, subjects:, clauses:) ->
      case
        list.index_map(subjects, fn(subject, index) {
          is_type_field(subject)
          && list.any(clauses, clause_names_a_number(_, index))
        })
        |> list.any(fn(dispatches) { dispatches })
      {
        True -> [location.start]
        False -> []
      }
    glance.BinaryOperator(name: glance.Eq, location:, left:, right:)
    | glance.BinaryOperator(name: glance.NotEq, location:, left:, right:) ->
      case compares_with_a_number(left, right) {
        True -> [location.start]
        False -> []
      }
    glance.BinaryOperator(..)
    | glance.Int(..)
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
    | glance.RecordUpdate(..)
    | glance.FieldAccess(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Echo(..) -> []
  }
}

fn is_type_field(expression: glance.Expression) -> Bool {
  case expression {
    glance.FieldAccess(label: "type_", ..) -> True
    glance.FieldAccess(..)
    | glance.Int(..)
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
    | glance.RecordUpdate(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Case(..)
    | glance.BinaryOperator(..)
    | glance.Echo(..) -> False
  }
}

/// A type field against an integer other than 0, or against a name that is not
/// a constructor: the raw number is the one branched on. Two type fields, or a
/// constructor, are not.
fn compares_with_a_number(
  left: glance.Expression,
  right: glance.Expression,
) -> Bool {
  case is_type_field(left), is_type_field(right) {
    True, False -> is_a_number(right)
    False, True -> is_a_number(left)
    True, True | False, False -> False
  }
}

fn is_a_number(expression: glance.Expression) -> Bool {
  case expression {
    glance.Int(value: "0", ..) -> False
    glance.Int(..) -> True
    glance.Variable(name:, ..) -> !is_constructor(name)
    glance.FieldAccess(label:, ..) -> !is_constructor(label)
    glance.Float(..)
    | glance.String(..)
    | glance.NegateInt(..)
    | glance.NegateBool(..)
    | glance.Block(..)
    | glance.Panic(..)
    | glance.Todo(..)
    | glance.Tuple(..)
    | glance.List(..)
    | glance.Fn(..)
    | glance.RecordUpdate(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Case(..)
    | glance.BinaryOperator(..)
    | glance.Echo(..) -> False
  }
}

fn is_constructor(name: String) -> Bool {
  case string.first(name) {
    Ok(first) -> string.lowercase(first) != first
    Error(Nil) -> False
  }
}

/// A clause whose pattern for the subject is an integer other than 0, or a
/// bound name with a guard.
fn clause_names_a_number(clause: glance.Clause, index: Int) -> Bool {
  list.any(clause.patterns, fn(alternative) {
    case list.drop(alternative, index) {
      [pattern, ..] -> pattern_names_a_number(pattern, clause.guard)
      [] -> False
    }
  })
}

fn pattern_names_a_number(
  pattern: glance.Pattern,
  guard: Option(glance.Expression),
) -> Bool {
  case pattern {
    glance.PatternInt(value: "0", ..) -> False
    glance.PatternInt(..) -> True
    glance.PatternVariable(..) | glance.PatternDiscard(..) ->
      case guard {
        Some(_) -> True
        None -> False
      }
    glance.PatternAssignment(pattern: inner, ..) ->
      pattern_names_a_number(inner, guard)
    glance.PatternFloat(..)
    | glance.PatternString(..)
    | glance.PatternTuple(..)
    | glance.PatternList(..)
    | glance.PatternConcatenate(..)
    | glance.PatternBitString(..)
    | glance.PatternVariant(..) -> False
  }
}
