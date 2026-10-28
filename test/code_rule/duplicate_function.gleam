//// No two modules hold a function with the same body: a copy is moved to the
//// module both callers share (the writing-gleam skill, Modules).

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance.{type Expression, type Pattern, type Span, type Statement}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string

/// The fewest source lines a body spans before the rule compares it. The
/// rule run over the repository found 19 groups of copies at 2 lines, 18 at 3
/// lines, 11 at 4 lines and 10 at 5 lines. From 3 lines down it flags
/// delegations that the formatter split over more lines because their string
/// is long (`message_support.hex("...")`), and at 2 lines the two-line
/// `answer` helpers of the connection tests too; at 5 it misses the
/// little-endian number reader, whose four-line copy has a three-line twin.
/// So 4 is the smallest that flags no delegation.
pub const minimum_lines = 4

/// A function of a module, with what the comparison needs.
type Candidate {
  Candidate(
    path: String,
    name: String,
    line: Int,
    lines: Int,
    body: List(Statement),
  )
}

/// An allow-list entry: the path of a module, the name of one of its
/// functions, and the one-line reason the copy stays.
pub type Allowed =
  #(String, String, String)

/// Each function whose body is the same as the body of a function in another
/// module, and each allow-list entry that names no such function.
///
/// Two bodies are the same when their statements are equal after every source
/// location is erased, every string literal's value is replaced by one
/// placeholder and every type annotation is dropped, so a copy that differs
/// only in a name written as a string is found. Function names, parameter
/// names and parameter types are not compared. A body that spans fewer than
/// `minimum_lines` lines is not compared, and neither is a function of a
/// generated module: one whose leading `////` lines say `Generated ` (the
/// table and message generators) or `was generated automatically` (squirrel).
/// An allowed function is left out of the comparison, so its twin is not a
/// breach either. Breaches are in order of path and line.
pub fn breaches(
  files files: List(SourceFile),
  allowed allowed: List(Allowed),
) -> List(Breach) {
  let candidates =
    files
    |> list.filter(fn(file) { !generated(file) })
    |> list.flat_map(candidates)
  let twins = by_body(candidates)
  let compared =
    list.filter(candidates, fn(candidate) {
      !list.any(allowed, fn(entry) {
        entry.0 == candidate.path && entry.1 == candidate.name
      })
    })
  let copies =
    by_body(compared)
    |> dict.to_list
    |> list.flat_map(fn(group) { copy_breaches(group.1) })
  let stale =
    list.filter_map(allowed, fn(entry) {
      let has_twin =
        list.any(candidates, fn(candidate) {
          candidate.path == entry.0
          && candidate.name == entry.1
          && has_twin_elsewhere(candidate, twins)
        })
      case has_twin {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: "test/code_rule/duplicate_function_test.gleam",
            line: 1,
            rule: "an allow-list entry that names no function with a copy in another module: "
              <> entry.0
              <> " "
              <> entry.1,
          ))
      }
    })
  list.append(
    list.sort(copies, fn(first, second) {
      order.break_tie(
        string.compare(first.path, second.path),
        int.compare(first.line, second.line),
      )
    }),
    stale,
  )
}

fn has_twin_elsewhere(
  candidate: Candidate,
  twins: dict.Dict(List(Statement), List(Candidate)),
) -> Bool {
  case dict.get(twins, candidate.body) {
    Ok(group) -> list.any(group, fn(other) { other.path != candidate.path })
    Error(Nil) -> False
  }
}

/// The candidates grouped by body, so every group is a set of equal bodies,
/// keeping the groups whose longest member spans `minimum_lines` lines. The
/// longest decides because the formatter splits the same body over more lines
/// when a string in it is longer.
fn by_body(
  candidates: List(Candidate),
) -> dict.Dict(List(Statement), List(Candidate)) {
  list.fold(candidates, dict.new(), fn(groups, candidate) {
    dict.upsert(groups, candidate.body, fn(existing) {
      case existing {
        option.Some(members) -> [candidate, ..members]
        option.None -> [candidate]
      }
    })
  })
  |> dict.filter(fn(_body, members) {
    list.any(members, fn(member) { member.lines >= minimum_lines })
  })
}

/// One breach for each member of a group that has a copy in another module.
fn copy_breaches(group: List(Candidate)) -> List(Breach) {
  list.filter_map(group, fn(member) {
    let others =
      group
      |> list.filter(fn(other) { other.path != member.path })
      |> list.sort(fn(first, second) {
        order.break_tie(
          string.compare(first.path, second.path),
          string.compare(first.name, second.name),
        )
      })
    case others {
      [] -> Error(Nil)
      [_, ..] ->
        Ok(Breach(
          path: member.path,
          line: member.line,
          rule: "`"
            <> member.name
            <> "` has the same body as "
            <> string.join(
            list.map(others, fn(other) { other.path <> " " <> other.name }),
            ", ",
          )
            <> "; move it to a module both share",
        ))
    }
  })
}

/// Whether the file's leading `////` lines say that a generator wrote it.
fn generated(file: SourceFile) -> Bool {
  file.text
  |> string.split("\n")
  |> list.take_while(string.starts_with(_, "////"))
  |> list.any(fn(line) {
    string.starts_with(line, "//// Generated ")
    || string.contains(line, "was generated automatically")
  })
}

/// Every function of the file that has a body, with the body normalised and
/// the lines it spans.
fn candidates(file: SourceFile) -> List(Candidate) {
  syntax.parse(file).functions
  |> list.filter_map(fn(definition) {
    let function = definition.definition
    case function.body {
      [] -> Error(Nil)
      [first, ..] -> {
        let assert Ok(last) = list.last(function.body)
          as "a body with a first statement has a last one"
        let lines =
          syntax.line_of(file.text, statement_span(last).end)
          - syntax.line_of(file.text, statement_span(first).start)
          + 1
        Ok(Candidate(
          path: file.path,
          name: function.name,
          line: syntax.line_of(file.text, function.location.start),
          lines:,
          body: statements(function.body),
        ))
      }
    }
  })
}

fn statement_span(original: Statement) -> Span {
  case original {
    glance.Use(location:, ..)
    | glance.Assignment(location:, ..)
    | glance.Assert(location:, ..) -> location
    glance.Expression(expression) -> expression_span(expression)
  }
}

fn expression_span(original: Expression) -> Span {
  case original {
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
    | glance.FieldAccess(location:, ..)
    | glance.Call(location:, ..)
    | glance.TupleIndex(location:, ..)
    | glance.FnCapture(location:, ..)
    | glance.BitString(location:, ..)
    | glance.Case(location:, ..)
    | glance.BinaryOperator(location:, ..)
    | glance.Echo(location:, ..) -> location
  }
}

const no_span = glance.Span(0, 0)

const placeholder = "_"

fn statements(list: List(Statement)) -> List(Statement) {
  list.map(list, statement)
}

fn statement(original: Statement) -> Statement {
  case original {
    glance.Use(patterns:, function:, ..) ->
      glance.Use(
        no_span,
        list.map(patterns, fn(use_pattern) {
          glance.UsePattern(pattern(use_pattern.pattern), option.None)
        }),
        expression(function),
      )
    glance.Assignment(kind:, pattern: assigned, value:, ..) ->
      glance.Assignment(
        no_span,
        case kind {
          glance.Let -> glance.Let
          glance.LetAssert(message:) ->
            glance.LetAssert(option.map(message, expression))
        },
        pattern(assigned),
        option.None,
        expression(value),
      )
    glance.Assert(expression: asserted, message:, ..) ->
      glance.Assert(
        no_span,
        expression(asserted),
        option.map(message, expression),
      )
    glance.Expression(inner) -> glance.Expression(expression(inner))
  }
}

fn expression(original: Expression) -> Expression {
  case original {
    glance.Int(value:, ..) -> glance.Int(no_span, value)
    glance.Float(value:, ..) -> glance.Float(no_span, value)
    glance.String(..) -> glance.String(no_span, placeholder)
    glance.Variable(name:, ..) -> glance.Variable(no_span, name)
    glance.NegateInt(value:, ..) -> glance.NegateInt(no_span, expression(value))
    glance.NegateBool(value:, ..) ->
      glance.NegateBool(no_span, expression(value))
    glance.Block(statements: inside, ..) ->
      glance.Block(no_span, statements(inside))
    glance.Panic(message:, ..) ->
      glance.Panic(no_span, option.map(message, expression))
    glance.Todo(message:, ..) ->
      glance.Todo(no_span, option.map(message, expression))
    glance.Tuple(elements:, ..) ->
      glance.Tuple(no_span, list.map(elements, expression))
    glance.List(elements:, rest:, ..) ->
      glance.List(
        no_span,
        list.map(elements, expression),
        option.map(rest, expression),
      )
    glance.Fn(arguments:, body:, ..) ->
      glance.Fn(
        no_span,
        list.map(arguments, fn(argument) {
          glance.FnParameter(argument.name, option.None)
        }),
        option.None,
        statements(body),
      )
    glance.RecordUpdate(module:, constructor:, record:, fields:, ..) ->
      glance.RecordUpdate(
        no_span,
        module,
        constructor,
        expression(record),
        list.map(fields, fn(field) {
          glance.RecordUpdateField(
            field.label,
            option.map(field.item, expression),
          )
        }),
      )
    glance.FieldAccess(container:, label:, ..) ->
      glance.FieldAccess(no_span, expression(container), label)
    glance.Call(function:, arguments:, ..) ->
      glance.Call(
        no_span,
        expression(function),
        list.map(arguments, fn(argument) { field(argument, expression) }),
      )
    glance.TupleIndex(tuple:, index:, ..) ->
      glance.TupleIndex(no_span, expression(tuple), index)
    glance.FnCapture(label:, function:, arguments_before:, arguments_after:, ..) ->
      glance.FnCapture(
        no_span,
        label,
        expression(function),
        list.map(arguments_before, fn(argument) { field(argument, expression) }),
        list.map(arguments_after, fn(argument) { field(argument, expression) }),
      )
    glance.BitString(segments:, ..) ->
      glance.BitString(
        no_span,
        list.map(segments, fn(segment) {
          #(
            expression(segment.0),
            list.map(segment.1, fn(segment_option) {
              bit_option(segment_option, expression)
            }),
          )
        }),
      )
    glance.Case(subjects:, clauses:, ..) ->
      glance.Case(
        no_span,
        list.map(subjects, expression),
        list.map(clauses, fn(clause) {
          glance.Clause(
            list.map(clause.patterns, fn(alternative) {
              list.map(alternative, pattern)
            }),
            option.map(clause.guard, expression),
            expression(clause.body),
          )
        }),
      )
    glance.BinaryOperator(name:, left:, right:, ..) ->
      glance.BinaryOperator(no_span, name, expression(left), expression(right))
    glance.Echo(expression: subject, message:, ..) ->
      glance.Echo(
        no_span,
        option.map(subject, expression),
        option.map(message, expression),
      )
  }
}

fn pattern(original: Pattern) -> Pattern {
  case original {
    glance.PatternInt(value:, ..) -> glance.PatternInt(no_span, value)
    glance.PatternFloat(value:, ..) -> glance.PatternFloat(no_span, value)
    glance.PatternString(..) -> glance.PatternString(no_span, placeholder)
    glance.PatternDiscard(name:, ..) -> glance.PatternDiscard(no_span, name)
    glance.PatternVariable(name:, ..) -> glance.PatternVariable(no_span, name)
    glance.PatternTuple(elements:, ..) ->
      glance.PatternTuple(no_span, list.map(elements, pattern))
    glance.PatternList(elements:, tail:, ..) ->
      glance.PatternList(
        no_span,
        list.map(elements, pattern),
        option.map(tail, pattern),
      )
    glance.PatternAssignment(pattern: inner, name:, ..) ->
      glance.PatternAssignment(no_span, pattern(inner), name)
    glance.PatternConcatenate(prefix_name:, rest_name:, ..) ->
      glance.PatternConcatenate(no_span, placeholder, prefix_name, rest_name)
    glance.PatternBitString(segments:, ..) ->
      glance.PatternBitString(
        no_span,
        list.map(segments, fn(segment) {
          #(
            pattern(segment.0),
            list.map(segment.1, fn(segment_option) {
              bit_option(segment_option, bit_size)
            }),
          )
        }),
      )
    glance.PatternVariant(module:, constructor:, arguments:, with_spread:, ..) ->
      glance.PatternVariant(
        no_span,
        module,
        constructor,
        list.map(arguments, fn(argument) { field(argument, pattern) }),
        with_spread,
      )
  }
}

fn field(original: glance.Field(a), item: fn(a) -> a) -> glance.Field(a) {
  case original {
    glance.LabelledField(label:, item: value, ..) ->
      glance.LabelledField(label, no_span, item(value))
    glance.ShorthandField(label:, ..) -> glance.ShorthandField(label, no_span)
    glance.UnlabelledField(value) -> glance.UnlabelledField(item(value))
  }
}

fn bit_option(
  original: glance.BitStringSegmentOption(a),
  item: fn(a) -> a,
) -> glance.BitStringSegmentOption(a) {
  case original {
    glance.SizeValueOption(size) -> glance.SizeValueOption(item(size))
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
    | glance.UnitOption(_) -> original
  }
}

fn bit_size(original: glance.BitArraySize) -> glance.BitArraySize {
  case original {
    glance.BitArraySizeInt(value:, ..) -> glance.BitArraySizeInt(no_span, value)
    glance.BitArraySizeVariable(name:, ..) ->
      glance.BitArraySizeVariable(no_span, name)
    glance.BitArraySizeBinaryOperator(operator:, left:, right:, ..) ->
      glance.BitArraySizeBinaryOperator(
        no_span,
        operator,
        bit_size(left),
        bit_size(right),
      )
    glance.BitArraySizeBlock(inner:, ..) ->
      glance.BitArraySizeBlock(no_span, bit_size(inner))
  }
}
