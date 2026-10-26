//// Gleam source as the code rules read it: parsed, with every expression
//// found and every byte offset turned into a line number.

import code_rule/source.{type SourceFile}
import database_support
import glance.{type Expression, type Statement}
import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
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

/// The module's name from its path: `src/genesis_prime/server.gleam` is
/// `genesis_prime/server`, and `test/owned_test.gleam` is `owned_test`.
pub fn module_name(path: String) -> String {
  path
  |> string.remove_prefix("src/")
  |> string.remove_prefix("test/")
  |> string.remove_suffix(".gleam")
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
  references_in(expressions(module))
}

/// Every named reference in the module's constants, in the order the
/// expressions are found.
pub fn constant_references(module: glance.Module) -> List(Reference) {
  references_in(
    list.flat_map(module.constants, fn(definition) {
      from_expression(definition.definition.value)
    }),
  )
}

fn references_in(expressions: List(Expression)) -> List(Reference) {
  list.flat_map(expressions, fn(expression) {
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

/// The line, counted from 1, that holds the byte at the offset.
pub fn line_of(text text: String, byte_offset byte_offset: Int) -> Int {
  let assert Ok(before) = bit_array.slice(<<text:utf8>>, 0, byte_offset)
    as "the offset is outside the text"
  1 + count_newlines(before, 0)
}

fn count_newlines(bytes: BitArray, count: Int) -> Int {
  case bytes {
    <<10, rest:bits>> -> count_newlines(rest, count + 1)
    <<_, rest:bits>> -> count_newlines(rest, count)
    _ -> count
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
