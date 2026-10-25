//// No catch-all clause over a type that can gain variants.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// Constructors of types that cannot gain variants, so a catch-all beside
/// them is fine.
const fixed_constructors = [
  "True",
  "False",
  "Ok",
  "Error",
  "Some",
  "None",
  "Nil",
]

/// Each case clause that is a catch-all beside a constructor of a type that can grow.
pub fn breaches(file: SourceFile) -> List(Breach) {
  syntax.expressions(syntax.parse(file))
  |> list.flat_map(fn(expression) {
    case expression {
      glance.Case(clauses:, ..) -> clause_breaches(file, clauses)
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
      | glance.FnCapture(..)
      | glance.BitString(..)
      | glance.BinaryOperator(..)
      | glance.Echo(..) -> []
    }
  })
  |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
}

fn clause_breaches(
  file: SourceFile,
  clauses: List(glance.Clause),
) -> List(Breach) {
  let patterns =
    clauses
    |> list.flat_map(fn(clause) { clause.patterns })
    |> list.flatten
  case list.any(patterns, names_a_growing_constructor) {
    False -> []
    True ->
      list.flat_map(clauses, fn(clause) {
        case clause.guard {
          Some(_) -> []
          None -> catch_all_starts(clause.patterns)
        }
      })
      |> list.map(fn(offset) {
        Breach(
          path: file.path,
          line: syntax.line_of(file.text, offset),
          rule: "a catch-all beside a constructor of a type that can gain variants",
        )
      })
  }
}

/// The start of each alternative of a clause whose patterns all match
/// anything.
fn catch_all_starts(alternatives: List(List(glance.Pattern))) -> List(Int) {
  list.filter_map(alternatives, fn(alternative) {
    case list.all(alternative, matches_anything), alternative {
      True, [first, ..] -> Ok(pattern_start(first))
      True, [] | False, _ -> Error(Nil)
    }
  })
}

fn pattern_start(pattern: glance.Pattern) -> Int {
  pattern.location.start
}

fn matches_anything(pattern: glance.Pattern) -> Bool {
  case pattern {
    glance.PatternDiscard(..) | glance.PatternVariable(..) -> True
    glance.PatternAssignment(pattern: inner, ..) -> matches_anything(inner)
    glance.PatternInt(..)
    | glance.PatternFloat(..)
    | glance.PatternString(..)
    | glance.PatternTuple(..)
    | glance.PatternList(..)
    | glance.PatternConcatenate(..)
    | glance.PatternBitString(..)
    | glance.PatternVariant(..) -> False
  }
}

fn names_a_growing_constructor(pattern: glance.Pattern) -> Bool {
  case pattern {
    glance.PatternVariant(constructor:, ..) ->
      !list.contains(fixed_constructors, constructor)
    glance.PatternAssignment(pattern: inner, ..) ->
      names_a_growing_constructor(inner)
    glance.PatternDiscard(..)
    | glance.PatternVariable(..)
    | glance.PatternInt(..)
    | glance.PatternFloat(..)
    | glance.PatternString(..)
    | glance.PatternTuple(..)
    | glance.PatternList(..)
    | glance.PatternConcatenate(..)
    | glance.PatternBitString(..) -> False
  }
}
