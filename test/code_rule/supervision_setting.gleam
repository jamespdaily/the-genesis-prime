//// The supervision-setting rules: every supervisor in `src/` states its
//// restart limit, and every worker states its shutdown time, so no setting
//// is a library default nobody chose.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance.{type Expression}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// One thing a pipeline must state: the functions of one module that start
/// it, and the function of that module that states the setting.
type Kind {
  Kind(module: String, starts: List(String), states: String)
}

/// Each supervisor builder in the file whose pipeline does not set a restart
/// limit. A builder is a call of `static_supervisor.new`, or of
/// `factory_supervisor.worker_child` or `factory_supervisor.supervisor_child`;
/// its pipeline states the limit with the same module's `restart_tolerance`.
pub fn missing_restart_limit(file: SourceFile) -> List(Breach) {
  unstated(file, [
    Kind(
      module: "gleam/otp/static_supervisor",
      starts: ["new"],
      states: "restart_tolerance",
    ),
    Kind(
      module: "gleam/otp/factory_supervisor",
      starts: ["worker_child", "supervisor_child"],
      states: "restart_tolerance",
    ),
  ])
}

/// Each worker in the file whose pipeline does not set a shutdown time. A
/// worker is a call of `supervision.worker` or of
/// `factory_supervisor.worker_child`; its pipeline states the time with
/// `supervision.timeout` or `factory_supervisor.timeout` of the same kind.
pub fn missing_shutdown_time(file: SourceFile) -> List(Breach) {
  unstated(file, [
    Kind(module: "gleam/otp/supervision", starts: ["worker"], states: "timeout"),
    Kind(
      module: "gleam/otp/factory_supervisor",
      starts: ["worker_child"],
      states: "timeout",
    ),
  ])
}

/// Each call that starts a pipeline of one of the kinds and whose pipeline
/// holds no call that states the setting, in line order. A call that is not at
/// the head of a pipeline has no pipeline, so it breaches.
fn unstated(file: SourceFile, kinds: List(Kind)) -> List(Breach) {
  let module = syntax.parse(file)
  let expressions = syntax.expressions(module)
  list.flat_map(kinds, fn(kind) {
    let qualifiers = qualifiers(module, kind.module)
    let pipelines = list.filter_map(expressions, pipeline)
    list.filter_map(expressions, fn(expression) {
      use #(location, function) <- result.try(callee(expression))
      case
        calls(function:, qualifiers:, names: kind.starts),
        stated(pipelines:, start: location, qualifiers:, states: kind.states)
      {
        True, False ->
          Ok(#(
            location.start,
            Breach(
              path: file.path,
              line: syntax.line_of(file.text, location.start),
              rule: "a call of "
                <> string.join(kind.starts, " or ")
                <> " in "
                <> kind.module
                <> " with no "
                <> kind.states
                <> " in its pipeline",
            ),
          ))
        True, True | False, _ -> Error(Nil)
      }
    })
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(found) { found.1 })
}

/// The names the file gives a module it imports: its own last segment, or its
/// alias. A module imported under a discarded alias cannot be called.
fn qualifiers(module: glance.Module, name: String) -> List(String) {
  list.filter_map(module.imports, fn(definition) {
    let import_ = definition.definition
    case import_.module == name, import_.alias {
      True, None -> Ok(last_segment(name))
      True, Some(glance.Named(alias)) -> Ok(alias)
      True, Some(glance.Discarded(_)) | False, _ -> Error(Nil)
    }
  })
}

fn last_segment(module: String) -> String {
  case list.last(string.split(module, "/")) {
    Ok(segment) -> segment
    Error(Nil) -> module
  }
}

/// The location and the function of a call or a capture.
fn callee(expression: Expression) -> Result(#(glance.Span, Expression), Nil) {
  case expression {
    glance.Call(location:, function:, ..)
    | glance.FnCapture(location:, function:, ..) -> Ok(#(location, function))
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
}

/// Whether a function expression names one of the functions of a module
/// imported under one of the qualifiers, as in `static_supervisor.new`.
fn calls(
  function function: Expression,
  qualifiers qualifiers: List(String),
  names names: List(String),
) -> Bool {
  case function {
    glance.FieldAccess(
      container: glance.Variable(name: qualifier, ..),
      label:,
      ..,
    ) -> list.contains(qualifiers, qualifier) && list.contains(names, label)
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

/// A pipeline written with `|>`: the expression at its head, and the stage
/// expressions that follow it.
type Pipeline {
  Pipeline(head: Expression, stages: List(Expression))
}

/// The pipeline an expression is, when it is a `|>` of a head and stages; a
/// prefix of a longer pipeline is a pipeline too.
fn pipeline(expression: Expression) -> Result(Pipeline, Nil) {
  case expression {
    glance.BinaryOperator(name:, left:, right:, ..) if name == glance.Pipe ->
      case pipeline(left) {
        Ok(Pipeline(head:, stages:)) ->
          Ok(Pipeline(head:, stages: [right, ..stages]))
        Error(Nil) -> Ok(Pipeline(head: left, stages: [right]))
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
    | glance.Case(..)
    | glance.Echo(..) -> Error(Nil)
  }
}

/// Whether some pipeline starts with the call at this location and holds a
/// stage that calls the function that states the setting.
fn stated(
  pipelines pipelines: List(Pipeline),
  start start: glance.Span,
  qualifiers qualifiers: List(String),
  states states: String,
) -> Bool {
  list.any(pipelines, fn(pipeline) {
    starts_at(pipeline.head, start)
    && list.any(pipeline.stages, fn(stage) {
      case callee(stage) {
        Ok(#(_, function)) -> calls(function:, qualifiers:, names: [states])
        Error(Nil) -> False
      }
    })
  })
}

fn starts_at(head: Expression, start: glance.Span) -> Bool {
  case callee(head) {
    Ok(#(location, _)) -> location == start
    Error(Nil) -> False
  }
}
