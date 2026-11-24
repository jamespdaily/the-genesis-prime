//// Gleam source as the code rules read it: parsed, with every expression
//// found and every byte offset turned into a line number.

import code_rule/source.{type SourceFile}
import database_support
import glance.{type Expression, type Statement}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The parsed module. A file that does not parse stops the test with the
/// file's path, because every rule reads a parsed module. The parse is kept
/// for the run under the file's path and given again to every rule that asks
/// for the same text, so the repository's files are parsed once however many
/// rules read them.
pub fn parse(file: SourceFile) -> glance.Module {
  let #(text, module) =
    database_support.once("parsed:" <> file.path, fn() {
      #(file.text, parse_text(file))
    })
  case text == file.text {
    True -> module
    False -> parse_text(file)
  }
}

fn parse_text(file: SourceFile) -> glance.Module {
  let assert Ok(module) = glance.module(file.text)
    as { "the source does not parse: " <> file.path }
  module
}

/// The name of every module the file imports, as written in its imports.
pub fn imported_modules(file: SourceFile) -> List(String) {
  list.map(parse(file).imports, fn(definition) { definition.definition.module })
}

/// The module's name from its path: `src/genesis_prime/server.gleam` is
/// `genesis_prime/server`, and `test/owned_test.gleam` is `owned_test`.
pub fn module_name(path: String) -> String {
  path
  |> string.remove_prefix("src/")
  |> string.remove_prefix("test/")
  |> string.remove_suffix(".gleam")
  |> string.remove_suffix(".erl")
}

/// The Erlang module and function each `@external(erlang, ...)` attribute
/// names.
pub fn erlang_externals(
  attributes: List(glance.Attribute),
) -> List(#(String, String)) {
  list.filter_map(attributes, fn(attribute) {
    case attribute {
      glance.Attribute(
        name: "external",
        arguments: [
          glance.Variable(name: "erlang", ..),
          glance.String(value: module, ..),
          glance.String(value: function, ..),
        ],
      ) -> Ok(#(module, function))
      glance.Attribute(..) -> Error(Nil)
    }
  })
}

/// A name an expression refers to.
pub type Reference {
  /// `module.name`, written with the module's name as the qualifier.
  Qualified(location: glance.Span, qualifier: String, name: String)
  /// A bare name.
  Unqualified(location: glance.Span, name: String)
}

/// Every named reference in the module's functions, in the order the
/// expressions are found.
pub fn references(module: glance.Module) -> List(Reference) {
  list.flat_map(expressions(module), fn(expression) {
    case expression {
      glance.FieldAccess(
        location:,
        container: glance.Variable(name: qualifier, ..),
        label:,
      ) -> [Qualified(location:, qualifier:, name: label)]
      glance.Variable(location:, name:) -> [Unqualified(location:, name:)]
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
      | glance.Echo(..) -> []
    }
  })
}

/// Where the reference is written.
pub fn location_of(reference: Reference) -> glance.Span {
  case reference {
    Qualified(location:, ..) -> location
    Unqualified(location:, ..) -> location
  }
}

/// Where the expression is written.
pub fn span_of(expression: Expression) -> glance.Span {
  case expression {
    glance.FieldAccess(location:, ..) -> location
    glance.Int(location:, ..)
    | glance.Float(location:, ..)
    | glance.String(location:, ..)
    | glance.Variable(location:, ..)
    | glance.NegateInt(location:, ..)
    | glance.NegateBool(location:, ..)
    | glance.Block(location:, ..)
    | glance.Panic(location:, ..)
    | glance.Todo(location:, ..)
    | glance.Tuple(location:, ..)
    | glance.List(location:, ..)
    | glance.Fn(location:, ..)
    | glance.RecordUpdate(location:, ..)
    | glance.Call(location:, ..)
    | glance.TupleIndex(location:, ..)
    | glance.FnCapture(location:, ..)
    | glance.BitString(location:, ..)
    | glance.Case(location:, ..)
    | glance.BinaryOperator(location:, ..)
    | glance.Echo(location:, ..) -> location
  }
}

/// The name a module's qualified references go by in the file that imports
/// it: its alias, or the last segment of its path. A module imported `as _`
/// goes by no name, since nothing can refer to it.
pub fn import_name(import_: glance.Import) -> Option(String) {
  case import_.alias {
    Some(glance.Named(alias)) -> Some(alias)
    Some(glance.Discarded(_)) -> None
    None ->
      import_.module
      |> string.split("/")
      |> list.last
      |> result.unwrap(import_.module)
      |> Some
  }
}

/// Every reference in the module's functions to one of the named functions of
/// the named modules, however the module imports them: through the module's
/// last segment or its alias, or by an unqualified import (under its alias if
/// it has one). A module imported `as _` is named no way.
pub fn references_to(
  module module: glance.Module,
  from modules: List(String),
  named functions: List(String),
) -> List(Reference) {
  let imports =
    list.filter_map(module.imports, fn(definition) {
      case list.contains(modules, definition.definition.module) {
        True -> Ok(definition.definition)
        False -> Error(Nil)
      }
    })
  let qualifiers =
    list.filter_map(imports, fn(import_) {
      option.to_result(import_name(import_), Nil)
    })
  let unqualified =
    imports
    |> list.flat_map(fn(import_) { import_.unqualified_values })
    |> list.filter(fn(value) { list.contains(functions, value.name) })
    |> list.map(fn(value) { option.unwrap(value.alias, value.name) })
  list.filter(references(module), fn(reference) {
    case reference {
      Qualified(qualifier:, name:, ..) ->
        list.contains(qualifiers, qualifier) && list.contains(functions, name)
      Unqualified(name:, ..) -> list.contains(unqualified, name)
    }
  })
}

/// Every name the function binds anywhere in it: its parameters, `let` and
/// `use` patterns, closure parameters and `case` clause patterns. A name
/// bound anywhere in the function is a local for the whole function, so a
/// local named like an imported module is not read as the module.
pub fn bound_names(function: glance.Function) -> List(String) {
  let parameters =
    list.filter_map(function.parameters, fn(parameter) {
      assigned_name(parameter.name)
    })
  let nested =
    list.flat_map(from_statements(function.body), fn(expression) {
      case expression {
        glance.Block(statements:, ..) -> statement_names(statements)
        glance.Fn(arguments:, body:, ..) ->
          list.append(
            list.filter_map(arguments, fn(argument) {
              assigned_name(argument.name)
            }),
            statement_names(body),
          )
        glance.Case(clauses:, ..) ->
          clauses
          |> list.flat_map(fn(clause) { list.flatten(clause.patterns) })
          |> list.flat_map(pattern_names)
        glance.Int(..)
        | glance.Float(..)
        | glance.String(..)
        | glance.Variable(..)
        | glance.NegateInt(..)
        | glance.NegateBool(..)
        | glance.Panic(..)
        | glance.Todo(..)
        | glance.Tuple(..)
        | glance.List(..)
        | glance.RecordUpdate(..)
        | glance.FieldAccess(..)
        | glance.Call(..)
        | glance.TupleIndex(..)
        | glance.FnCapture(..)
        | glance.BitString(..)
        | glance.BinaryOperator(..)
        | glance.Echo(..) -> []
      }
    })
  list.flatten([parameters, statement_names(function.body), nested])
}

fn assigned_name(name: glance.AssignmentName) -> Result(String, Nil) {
  case name {
    glance.Named(name) -> Ok(name)
    glance.Discarded(_) -> Error(Nil)
  }
}

fn statement_names(statements: List(Statement)) -> List(String) {
  list.flat_map(statements, fn(statement) {
    case statement {
      glance.Use(patterns:, ..) ->
        list.flat_map(patterns, fn(use_pattern) {
          pattern_names(use_pattern.pattern)
        })
      glance.Assignment(pattern:, ..) -> pattern_names(pattern)
      glance.Assert(..) | glance.Expression(..) -> []
    }
  })
}

fn pattern_names(pattern: glance.Pattern) -> List(String) {
  case pattern {
    glance.PatternVariable(name:, ..) -> [name]
    glance.PatternAssignment(pattern: inner, name:, ..) -> [
      name,
      ..pattern_names(inner)
    ]
    glance.PatternTuple(elements:, ..) -> list.flat_map(elements, pattern_names)
    glance.PatternList(elements:, tail:, ..) ->
      list.append(
        list.flat_map(elements, pattern_names),
        option.map(tail, pattern_names) |> option.unwrap([]),
      )
    glance.PatternConcatenate(prefix_name:, rest_name:, ..) ->
      list.filter_map(
        [rest_name, ..option.values([prefix_name])],
        assigned_name,
      )
    glance.PatternBitString(segments:, ..) ->
      list.flat_map(segments, fn(segment) { pattern_names(segment.0) })
    glance.PatternVariant(arguments:, ..) ->
      list.flat_map(arguments, fn(argument) {
        case argument {
          glance.LabelledField(item:, ..) | glance.UnlabelledField(item) ->
            pattern_names(item)
          glance.ShorthandField(label:, ..) -> [label]
        }
      })
    glance.PatternInt(..)
    | glance.PatternFloat(..)
    | glance.PatternString(..)
    | glance.PatternDiscard(..) -> []
  }
}

/// Every string literal in the module's functions, each with the byte offset
/// where it starts, in the order the expressions are found.
pub fn strings(module: glance.Module) -> List(#(Int, String)) {
  list.flat_map(expressions(module), fn(expression) {
    case expression {
      glance.String(location:, value:) -> [#(location.start, value)]
      glance.Variable(..)
      | glance.FieldAccess(..)
      | glance.Int(..)
      | glance.Float(..)
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
      | glance.Echo(..) -> []
    }
  })
}

/// The tag names a test body's statement gives its test, as unitest reads them:
/// the string of `unitest.tag("x")` and each string literal of
/// `unitest.tags(["x", "y"])`, whether the call is the function of a `use <-` or
/// a statement of its own. A call with another argument shape, any other
/// statement, and a tag that is not a string literal give none.
pub fn tags_of(statement: Statement) -> List(String) {
  case statement {
    glance.Use(function:, ..) -> tags_of_call(function)
    glance.Expression(expression) -> tags_of_call(expression)
    glance.Assignment(..) | glance.Assert(..) -> []
  }
}

fn tags_of_call(expression: Expression) -> List(String) {
  case expression {
    glance.Call(
      function: glance.FieldAccess(
        container: glance.Variable(name: "unitest", ..),
        label: "tag",
        ..,
      ),
      arguments: [glance.UnlabelledField(glance.String(value:, ..))],
      ..,
    ) -> [value]
    glance.Call(
      function: glance.FieldAccess(
        container: glance.Variable(name: "unitest", ..),
        label: "tags",
        ..,
      ),
      arguments: [glance.UnlabelledField(glance.List(elements:, ..))],
      ..,
    ) ->
      list.filter_map(elements, fn(element) {
        case element {
          glance.String(value:, ..) -> Ok(value)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }
}

/// The line, counted from 1, that holds the byte at the offset.
pub fn line_of(text text: String, byte_offset byte_offset: Int) -> Int {
  let assert [line] = lines_of(text:, byte_offsets: [byte_offset])
  line
}

/// The line of each byte offset, counted from 1, in the order the offsets are
/// given. A newline byte belongs to the line it ends. The text is read once
/// and the offsets are sorted and walked once along the text's newlines, so
/// the cost is the text's length plus sorting the offsets. An offset outside
/// the text stops the test.
pub fn lines_of(
  text text: String,
  byte_offsets byte_offsets: List(Int),
) -> List(Int) {
  let bytes = <<text:utf8>>
  let size = bit_array.byte_size(bytes)
  assert list.all(byte_offsets, fn(offset) { offset >= 0 && offset <= size })
    as "the offset is outside the text"
  let newlines = newline_offsets(bytes:, offset: 0, found: [])
  byte_offsets
  |> list.index_map(fn(offset, index) { #(offset, index) })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> lines_along(newlines:, line: 1, found: [])
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) { entry.1 })
}

/// The line of each `#(offset, index)`, offsets ascending, as `#(index, line)`:
/// `newlines` are the ascending offsets of the newline bytes not yet passed.
fn lines_along(
  offsets offsets: List(#(Int, Int)),
  newlines newlines: List(Int),
  line line: Int,
  found found: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case offsets, newlines {
    [], _ -> found
    [#(offset, _), ..], [newline, ..later] if newline < offset ->
      lines_along(offsets:, newlines: later, line: line + 1, found:)
    [#(_, index), ..rest], _ ->
      lines_along(offsets: rest, newlines:, line:, found: [
        #(index, line),
        ..found
      ])
  }
}

fn newline_offsets(
  bytes bytes: BitArray,
  offset offset: Int,
  found found: List(Int),
) -> List(Int) {
  case bytes {
    <<10, rest:bits>> ->
      newline_offsets(bytes: rest, offset: offset + 1, found: [offset, ..found])
    <<_, rest:bits>> -> newline_offsets(bytes: rest, offset: offset + 1, found:)
    _ -> list.reverse(found)
  }
}

/// What a call names as its function: `f(...)` names a variable, `m.f(...)`
/// names a function `f` of a variable `m` (an imported module, or a value with
/// a field), and any other function expression is another.
pub type Called {
  CalledByName(name: String)
  CalledThroughVariable(variable: String, label: String)
  CalledOtherwise
}

/// A call in a module: where its function is written, what it names, and its
/// arguments. A capture such as `f(1, _)` is a call whose arguments are those
/// before and after the hole.
pub type Call {
  Call(
    function: glance.Span,
    called: Called,
    arguments: List(glance.Field(Expression)),
  )
}

/// Every call and capture in the module's functions, in the order
/// `expressions` finds them.
pub fn calls(module: glance.Module) -> List(Call) {
  list.filter_map(expressions(module), fn(expression) {
    case expression {
      glance.Call(function:, arguments:, ..) ->
        Ok(Call(
          function: span_of(function),
          called: called(function),
          arguments:,
        ))
      glance.FnCapture(function:, arguments_before:, arguments_after:, ..) ->
        Ok(Call(
          function: span_of(function),
          called: called(function),
          arguments: list.append(arguments_before, arguments_after),
        ))
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
      | glance.BitString(..)
      | glance.Case(..)
      | glance.BinaryOperator(..)
      | glance.Echo(..) -> Error(Nil)
    }
  })
}

fn called(function: Expression) -> Called {
  case function {
    glance.Variable(name:, ..) -> CalledByName(name)
    glance.FieldAccess(
      container: glance.Variable(name: variable, ..),
      label:,
      ..,
    ) -> CalledThroughVariable(variable:, label:)
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
    | glance.Echo(..) -> CalledOtherwise
  }
}

/// Which unlabelled argument stands for a value a call may give by label.
pub type Position {
  FirstArgument
  LastArgument
}

/// The expression a call gives for a value: the argument labelled `label`, or
/// else the first or last argument of the call when that one has no label. A
/// punned `label:` has no expression of its own, and none is given for it.
pub fn argument(
  arguments arguments: List(glance.Field(Expression)),
  label label: String,
  position position: Position,
) -> Option(Expression) {
  let labelled =
    list.find_map(arguments, fn(argument) {
      case argument {
        glance.LabelledField(label: found, item:, ..) if found == label ->
          Ok(Some(item))
        glance.ShorthandField(label: found, ..) if found == label -> Ok(None)
        glance.LabelledField(..)
        | glance.ShorthandField(..)
        | glance.UnlabelledField(..) -> Error(Nil)
      }
    })
  let positional = case position {
    FirstArgument -> list.first(arguments)
    LastArgument -> list.last(arguments)
  }
  case labelled, positional {
    Ok(found), _ -> found
    Error(Nil), Ok(glance.UnlabelledField(item)) -> Some(item)
    Error(Nil), Ok(_) | Error(Nil), Error(Nil) -> None
  }
}

/// Every expression in the module's functions, each followed by the
/// expressions inside it.
pub fn expressions(module: glance.Module) -> List(Expression) {
  list.flat_map(module.functions, fn(definition) {
    from_statements(definition.definition.body)
  })
}

fn from_statements(statements: List(Statement)) -> List(Expression) {
  list.flat_map(statements, from_statement)
}

fn from_statement(statement: Statement) -> List(Expression) {
  case statement {
    glance.Use(function:, ..) -> from_expression(function)
    glance.Assignment(kind: glance.Let, value:, ..) -> from_expression(value)
    glance.Assignment(kind: glance.LetAssert(message:), value:, ..) ->
      list.append(from_expression(value), from_optional(message))
    glance.Assert(expression:, message:, ..) ->
      list.append(from_expression(expression), from_optional(message))
    glance.Expression(expression) -> from_expression(expression)
  }
}

fn from_optional(expression: Option(Expression)) -> List(Expression) {
  case expression {
    Some(expression) -> from_expression(expression)
    None -> []
  }
}

fn from_fields(fields: List(glance.Field(Expression))) -> List(Expression) {
  list.flat_map(fields, fn(field) {
    case field {
      glance.LabelledField(item:, ..) -> from_expression(item)
      glance.UnlabelledField(item) -> from_expression(item)
      glance.ShorthandField(..) -> []
    }
  })
}

fn from_expression(expression: Expression) -> List(Expression) {
  let inside = case expression {
    glance.Int(..)
    | glance.Float(..)
    | glance.String(..)
    | glance.Variable(..) -> []
    glance.NegateInt(value:, ..) | glance.NegateBool(value:, ..) ->
      from_expression(value)
    glance.Block(statements:, ..) -> from_statements(statements)
    glance.Panic(message:, ..) | glance.Todo(message:, ..) ->
      from_optional(message)
    glance.Tuple(elements:, ..) -> list.flat_map(elements, from_expression)
    glance.List(elements:, rest:, ..) ->
      list.append(list.flat_map(elements, from_expression), from_optional(rest))
    glance.Fn(body:, ..) -> from_statements(body)
    glance.RecordUpdate(record:, fields:, ..) ->
      list.append(
        from_expression(record),
        list.flat_map(fields, fn(field) { from_optional(field.item) }),
      )
    glance.FieldAccess(container:, ..) -> from_expression(container)
    glance.Call(function:, arguments:, ..) ->
      list.append(from_expression(function), from_fields(arguments))
    glance.TupleIndex(tuple:, ..) -> from_expression(tuple)
    glance.FnCapture(function:, arguments_before:, arguments_after:, ..) ->
      list.flatten([
        from_expression(function),
        from_fields(arguments_before),
        from_fields(arguments_after),
      ])
    glance.BitString(segments:, ..) ->
      list.flat_map(segments, fn(segment) {
        let #(value, options) = segment
        list.append(
          from_expression(value),
          list.flat_map(options, from_bit_option),
        )
      })
    glance.Case(subjects:, clauses:, ..) ->
      list.append(
        list.flat_map(subjects, from_expression),
        list.flat_map(clauses, fn(clause) {
          list.append(from_optional(clause.guard), from_expression(clause.body))
        }),
      )
    glance.BinaryOperator(left:, right:, ..) ->
      list.append(from_expression(left), from_expression(right))
    glance.Echo(expression: subject, message:, ..) ->
      list.append(from_optional(subject), from_optional(message))
  }
  [expression, ..inside]
}

fn from_bit_option(
  option: glance.BitStringSegmentOption(Expression),
) -> List(Expression) {
  case option {
    glance.SizeValueOption(size) -> from_expression(size)
    glance.BytesOption
    | glance.IntOption
    | glance.FloatOption
    | glance.BitsOption
    | glance.Utf8Option
    | glance.Utf16Option
    | glance.Utf32Option
    | glance.Utf8CodepointOption
    | glance.Utf16CodepointOption
    | glance.Utf32CodepointOption
    | glance.SignedOption
    | glance.UnsignedOption
    | glance.BigOption
    | glance.LittleOption
    | glance.NativeOption
    | glance.SizeOption(_)
    | glance.UnitOption(_) -> []
  }
}
