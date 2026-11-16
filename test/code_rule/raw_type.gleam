//// Game and map code does not branch on a game table's raw type number,
//// outside the modules that read the table (`table/`) or the wire
//// (`message/`). A site is a `case` on a row's type field with integer
//// patterns (or a guard on a bound name), a `==`, `!=`, `<`, `<=`, `>` or `>=`
//// of that field with an integer or a name that is not a constructor, or a
//// `list.contains` (called as `list.contains(numbers, row.type_)` or piped
//// into it) of that field and a list of numbers. A type field is `type_` (the
//// client column named `type`) or a field ending in `_type`, `_type_id` or
//// `_type_enum`.
////
//// ```text
//// src files -> sites per function -> minus each function's listed gap -> breaches
//// ```
////
//// - A table's `type` column decodes once, where the table is read, into a
////   tagged type; code matches on that type, so a new type adds a variant and
////   the compiler names each place that handles it. A comparison with a
////   constructor, and a `case` with constructor patterns, is that tagged type.
//// - A check against 0 is a site like any other: 0 is a type in some tables
////   (`entity_type`). Two type fields compared with each other name no kind,
////   so they are not reported.
//// - A name read from an imported module (`quest_log.use_a_creature_type`) is a
////   constant, not a field, unless the function binds a name like the module
////   (a parameter, a `let`, a closure's parameter, a pattern) or the name is
////   `type_`. `option_type` (the client option message) and `unit_type` (a
////   spawned object) are fields no table holds and are not read.
//// - Each site that exists today is a known gap, counted per function and
////   naming the open issue whose work removes it. A function with more sites
////   than listed fails, and so does a gap whose function has fewer, and a
////   function listed twice.

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

/// Every site in `src/`, and the open issue whose work removes it.
pub const known_gaps = [
  Gap(
    path: "src/genesis_prime/game/item_property.gleam",
    function: "give_picked",
    sites: 1,
    issue: 897,
  ),
  Gap(
    path: "src/genesis_prime/game/random_stat.gleam",
    function: "accepted",
    sites: 1,
    issue: 897,
  ),
  Gap(
    path: "src/genesis_prime/game/shortcut_spell.gleam",
    function: "planned",
    sites: 1,
    issue: 898,
  ),
  Gap(
    path: "src/genesis_prime/game/spell_plan.gleam",
    function: "cast_bar_of",
    sites: 1,
    issue: 886,
  ),
  Gap(
    path: "src/genesis_prime/game/spell_plan.gleam",
    function: "heal_of",
    sites: 1,
    issue: 886,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "creatures_of",
    sites: 1,
    issue: 897,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "listed",
    sites: 1,
    issue: 897,
  ),
  Gap(
    path: "src/genesis_prime/game/target_group.gleam",
    function: "row_has",
    sites: 1,
    issue: 897,
  ),
  Gap(
    path: "src/genesis_prime/world_map/creature_guard_spells.gleam",
    function: "guard_of",
    sites: 1,
    issue: 898,
  ),
  Gap(
    path: "src/genesis_prime/world_map/objective_spawn.gleam",
    function: "paired_unit_type",
    sites: 1,
    issue: 898,
  ),
  Gap(
    path: "src/genesis_prime/world_map/spawn.gleam",
    function: "valid_creature",
    sites: 1,
    issue: 898,
  ),
]

/// One raw-type site: the function that holds it and its line.
type Site {
  Site(path: String, function: String, line: Int)
}

/// Each site in a function beyond the sites its gap lists, at its line, and
/// each gap whose function holds fewer sites than listed or is listed twice,
/// at line 1.
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
  let repeated =
    gaps
    |> list.group(fn(gap) { #(gap.path, gap.function) })
    |> dict.to_list
    |> list.filter_map(fn(entry) {
      let #(#(path, function), same) = entry
      case same {
        [_, _, ..] ->
          Ok(Breach(
            path:,
            line: 1,
            rule: "the known gap for `"
              <> function
              <> "` is listed more than once: list it once",
          ))
        [_] | [] -> Error(Nil)
      }
    })
  list.flatten([unlisted, stale, repeated])
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
    let names = names_of(module, definition.definition)
    glance.Module(..module, functions: [definition])
    |> syntax.expressions
    |> list.flat_map(site_offsets(_, names))
    |> list.map(fn(offset) {
      Site(
        path: file.path,
        function: definition.definition.name,
        line: syntax.line_of(file.text, offset),
      )
    })
  })
}

/// What a function's expressions are read against: the names that stand for an
/// imported module in it, and the names that stand for `gleam/list`.
type Names {
  Names(modules: List(String), lists: List(String))
}

/// The names the file's imports go by, except a name the function binds
/// itself: `objective.type_` is the row when `objective` is a parameter, a
/// `let` or a closure's parameter.
fn names_of(module: glance.Module, function: glance.Function) -> Names {
  let bound = syntax.bound_names(function)
  let imported =
    list.filter_map(module.imports, fn(definition) {
      case syntax.import_name(definition.definition) {
        Some(name) ->
          case list.contains(bound, name) {
            True -> Error(Nil)
            False -> Ok(#(definition.definition.module, name))
          }
        None -> Error(Nil)
      }
    })
  Names(
    modules: list.map(imported, fn(import_) { import_.1 }),
    lists: imported
      |> list.filter(fn(import_) { import_.0 == "gleam/list" })
      |> list.map(fn(import_) { import_.1 }),
  )
}

/// The start of the expression when it is a raw-type site.
fn site_offsets(expression: glance.Expression, names: Names) -> List(Int) {
  case expression {
    glance.Case(location:, subjects:, clauses:) ->
      starts_when(location, dispatches(subjects:, clauses:, names:))
    glance.BinaryOperator(name: glance.Pipe, location:, left:, right:) ->
      starts_when(location, pipes_into_contains(left:, right:, names:))
    glance.BinaryOperator(name:, location:, left:, right:) ->
      starts_when(
        location,
        compares(name)
          && compares_with_a_number(left:, right:, modules: names.modules),
      )
    glance.Call(location:, function:, arguments:) ->
      starts_when(location, calls_contains(function:, arguments:, names:))
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
    | glance.FieldAccess(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Echo(..) -> []
  }
}

fn starts_when(location: glance.Span, site: Bool) -> List(Int) {
  case site {
    True -> [location.start]
    False -> []
  }
}

/// A `case` with a type field among its subjects and an integer pattern (or a
/// guarded name) for it in some clause.
fn dispatches(
  subjects subjects: List(glance.Expression),
  clauses clauses: List(glance.Clause),
  names names: Names,
) -> Bool {
  list.index_map(subjects, fn(subject, index) {
    option.is_some(type_column(subject, names.modules))
    && list.any(clauses, clause_names_a_number(_, index))
  })
  |> list.any(fn(dispatches) { dispatches })
}

/// The operators that compare two values: equality and the four orderings.
fn compares(operator: glance.BinaryOperator) -> Bool {
  case operator {
    glance.Eq
    | glance.NotEq
    | glance.LtInt
    | glance.LtEqInt
    | glance.GtInt
    | glance.GtEqInt -> True
    glance.And
    | glance.Or
    | glance.LtFloat
    | glance.LtEqFloat
    | glance.GtEqFloat
    | glance.GtFloat
    | glance.Pipe
    | glance.AddInt
    | glance.AddFloat
    | glance.SubInt
    | glance.SubFloat
    | glance.MultInt
    | glance.MultFloat
    | glance.DivInt
    | glance.DivFloat
    | glance.RemainderInt
    | glance.Concatenate -> False
  }
}

/// `list.contains(numbers, row.type_)`, in either argument order or with
/// labels: the list holds raw numbers.
fn calls_contains(
  function function: glance.Expression,
  arguments arguments: List(glance.Field(glance.Expression)),
  names names: Names,
) -> Bool {
  case is_list_contains(function, names.lists), arguments {
    True, [first, second] ->
      compares_with_a_number(
        left: field_item(first),
        right: field_item(second),
        modules: names.modules,
      )
    True, _ | False, _ -> False
  }
}

/// `row.type_ |> list.contains(numbers, _)`.
fn pipes_into_contains(
  left left: glance.Expression,
  right right: glance.Expression,
  names names: Names,
) -> Bool {
  case right {
    glance.FnCapture(function:, arguments_before:, arguments_after:, ..) ->
      case is_list_contains(function, names.lists) {
        True ->
          case list.append(arguments_before, arguments_after) {
            [other] ->
              compares_with_a_number(
                left:,
                right: field_item(other),
                modules: names.modules,
              )
            _ -> False
          }
        False -> False
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
    | glance.FieldAccess(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.BitString(..)
    | glance.Case(..)
    | glance.BinaryOperator(..)
    | glance.Echo(..) -> False
  }
}

fn is_list_contains(function: glance.Expression, lists: List(String)) -> Bool {
  case function {
    glance.FieldAccess(
      container: glance.Variable(name:, ..),
      label: "contains",
      ..,
    ) -> list.contains(lists, name)
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

fn field_item(field: glance.Field(glance.Expression)) -> glance.Expression {
  case field {
    glance.LabelledField(item:, ..) | glance.UnlabelledField(item) -> item
    glance.ShorthandField(label:, location:) ->
      glance.Variable(location:, name: label)
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
    glance.Int(..) -> True
    glance.Variable(name:, ..) -> !is_constructor(name)
    glance.FieldAccess(label:, ..) -> !is_constructor(label)
    glance.List(elements:, ..) -> list.any(elements, is_a_number)
    glance.Float(..)
    | glance.String(..)
    | glance.NegateInt(..)
    | glance.NegateBool(..)
    | glance.Block(..)
    | glance.Panic(..)
    | glance.Todo(..)
    | glance.Tuple(..)
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
