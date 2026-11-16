//// Game and map code does not branch on a game table's raw type number: a
//// `case` on a row's type field with integer patterns (or a guard on a bound
//// name), or a `==` or `!=` of that field with an integer or a constant,
//// outside the modules that read the table (`table/`) or the wire (`message/`).
//// A type field is `type_` (the client column named `type`) or a field ending
//// in `_type`, `_type_id` or `_type_enum`.
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
////   decide no kind, so they are not reported.
//// - A name read from an imported module (`quest_log.use_a_creature_type`) is a
////   constant, not a field, unless the function takes a parameter of that name
////   or the name is `type_`. `option_type` (the client option message) and
////   `unit_type` (a spawned object) are fields no table holds and are not read.
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

/// Every site in `src/` today. Issue 888 removes the sites that read a quest
/// objective table row, 890 those that read the type of a quest log's
/// objective, and 891 those on the other tables' type columns.
pub const known_gaps = [
  Gap(
    path: "src/genesis_prime/game/departures.gleam",
    function: "counts_its_terminal",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/equip_requirement.gleam",
    function: "offered",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/item_price.gleam",
    function: "paid",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/item_property.gleam",
    function: "give_picked",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "advance_quest",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "arrivals",
    sites: 3,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "buttons",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "counts",
    sites: 10,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "credits_a_used_unit",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "finishes",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "group_member",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "held_item",
    sites: 2,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "hidden_script",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "required_sibling_arrived",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "visible_script_broken",
    sites: 1,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/objective.gleam",
    function: "visits",
    sites: 1,
    issue: 890,
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
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_log.gleam",
    function: "counted_by_unit",
    sites: 3,
    issue: 890,
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
    issue: 890,
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
    path: "src/genesis_prime/game/quest_turn_in.gleam",
    function: "is_credits",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_turn_in.gleam",
    function: "left_out",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_turn_in.gleam",
    function: "place_items",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/quest_turn_in.gleam",
    function: "rewarded",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/random_stat.gleam",
    function: "accepted",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/shortcut_spell.gleam",
    function: "build",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/game/spell_plan.gleam",
    function: "heal_of",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "creatures_of",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "listed",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "row_has",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/game/vendor_sale.gleam",
    function: "junk_stack",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/world_map/checklist_index.gleam",
    function: "is_target",
    sites: 1,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/world_map/creature_guard_spells.gleam",
    function: "guard_of",
    sites: 1,
    issue: 891,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "is_click_kind",
    sites: 2,
    issue: 890,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "is_placed_kind",
    sites: 3,
    issue: 888,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "paired_unit_type",
    sites: 1,
    issue: 891,
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
    let modules = module_names(module, definition.definition)
    glance.Module(..module, functions: [definition])
    |> syntax.expressions
    |> list.flat_map(site_offsets(_, modules))
    |> list.map(fn(offset) {
      Site(
        path: file.path,
        function: definition.definition.name,
        line: syntax.line_of(file.text, offset),
      )
    })
  })
}

/// The names the file's imports go by in qualified names (an alias, or the last
/// segment of the module path), except a name the function takes as a
/// parameter: `objective.type_` is the row when `objective` is a parameter.
fn module_names(
  module: glance.Module,
  function: glance.Function,
) -> List(String) {
  let parameters =
    list.filter_map(function.parameters, fn(parameter) {
      case parameter.name {
        glance.Named(name) -> Ok(name)
        glance.Discarded(_) -> Error(Nil)
      }
    })
  list.filter_map(module.imports, fn(definition) {
    let name = case definition.definition.alias {
      Some(glance.Named(alias)) -> alias
      Some(glance.Discarded(_)) | None ->
        definition.definition.module
        |> string.split("/")
        |> list.last
        |> result.unwrap(definition.definition.module)
    }
    case list.contains(parameters, name) {
      True -> Error(Nil)
      False -> Ok(name)
    }
  })
}

/// The start of the expression when it is a raw-type site.
fn site_offsets(
  expression: glance.Expression,
  modules: List(String),
) -> List(Int) {
  case expression {
    glance.Case(location:, subjects:, clauses:) ->
      case
        list.index_map(subjects, fn(subject, index) {
          option.is_some(type_column(subject, modules))
          && list.any(clauses, clause_names_a_number(_, index))
        })
        |> list.any(fn(dispatches) { dispatches })
      {
        True -> [location.start]
        False -> []
      }
    glance.BinaryOperator(name: glance.Eq, location:, left:, right:)
    | glance.BinaryOperator(name: glance.NotEq, location:, left:, right:) ->
      case compares_with_a_number(left:, right:, modules:) {
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

/// The column name when the expression is a row field that holds a table's
/// type: the client column named `type`, or one ending in `_type`, `_type_id`
/// or `_type_enum`. A name from an imported module is a constant, not a field,
/// except `type_`, which is never a constant's name; and `option_type` and
/// `unit_type` are fields of the client option message and of a spawned object,
/// which no table holds.
fn type_column(
  expression: glance.Expression,
  modules: List(String),
) -> Option(String) {
  case expression {
    glance.FieldAccess(container:, label:, ..) ->
      case
        is_type_column(label)
        && !is_a_modules_constant(container:, label:, modules:)
      {
        True -> Some(label)
        False -> None
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
    | glance.List(..)
    | glance.Fn(..)
    | glance.RecordUpdate(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Case(..)
    | glance.BinaryOperator(..)
    | glance.Echo(..) -> None
  }
}

fn is_type_column(label: String) -> Bool {
  case label {
    "option_type" | "unit_type" -> False
    "type_" -> True
    _ ->
      string.ends_with(label, "_type")
      || string.ends_with(label, "_type_id")
      || string.ends_with(label, "_type_enum")
  }
}

fn is_a_modules_constant(
  container container: glance.Expression,
  label label: String,
  modules modules: List(String),
) -> Bool {
  case container {
    glance.Variable(name:, ..) ->
      label != "type_" && list.contains(modules, name)
    glance.FieldAccess(..)
    | glance.Int(..)
    | glance.Float(..)
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

/// A type field against an integer other than 0, or against a name that is not
/// a constructor: the raw number is the one branched on. A constructor is not,
/// and two type fields compare two rows and decide no kind.
fn compares_with_a_number(
  left left: glance.Expression,
  right right: glance.Expression,
  modules modules: List(String),
) -> Bool {
  case type_column(left, modules), type_column(right, modules) {
    Some(_), None -> is_a_number(right)
    None, Some(_) -> is_a_number(left)
    Some(_), Some(_) | None, None -> False
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
