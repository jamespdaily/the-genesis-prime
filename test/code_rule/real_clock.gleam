//// The real-clock rule: a test file under `test/` names no source of real time
//// and sets no short deadline in a setting a process runs by, unless it is on
//// the exception list with its reason. A test on the real clock fails by the
//// machine's load, not by its code (the writing-tests skill), so a new one is
//// refused where it is written.
////
//// ```
//// test file ──► Part A: a source of real time      ┐
////          ──► Part B: a literal deadline < 30 s   ├─► breaches
//// .erl file ──► a timer, a sleep, a timed receive  ┘      │
////                                                          ▼
//// exception list ──► a listed file with a breach is clean; a listed file
////                    with none left (or none at all) is itself a breach
//// ```
////
//// Part A, the sources of real time, in any file under `test/` (a support
//// module too, so a helper cannot hide one):
//// - a reference to `service_shell.real_time`, `script.operating_system`,
////   `script.operating_system_timer`, `process.send_after`, `process.sleep` or
////   the dashboard's `subscribers.send_after`, each of which runs a process on
////   the operating system's timers or sleeps;
//// - a `process.receive` or `process.selector_receive` whose bound is not the
////   literal 0, and a `socket_read.Within`, which wait a real time;
//// - an import of `serving_node`, `fresh_node` or `real_start_node`, which
////   start the release's own processes on the node's clock.
////
//// An Erlang file under `test/` that calls `erlang:send_after`,
//// `erlang:start_timer`, `timer:sleep` or `timer:send_after`, or has a receive
//// with a timeout other than 0, is a breach too.
////
//// Part B, short real deadlines: in the settings whose fields a process takes
//// as a deadline at run time (`server.Settings`' send deadline, `server.World`'s
//// Maps call, `readiness.Settings`' two waits, `world_map_registry.find_or_start`'s
//// deadline, and the ask deadline of each connection's settings in a file that
//// builds a `server.Served` listener), a literal below the test's own deadline
//// of 30 s (`owned_test.run`'s) can pass while the test runs. A millisecond
//// number that a rule takes as data (an idle stop, a respawn time, the ask
//// deadline in a pure rule test) is no deadline and is not read.
////
//// The exception list has two parts. `genuine_real_time` holds the files that
//// check real time itself, each with its reason. `still_on_the_real_clock` is
//// the gap: the test files whose tests still run on the real clock, which the
//// coverage measure lists and each step that moves a file deletes it from; a
//// listed file with nothing left is a breach, so the list cannot go stale.

import code_rule/erlang_calls
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// A file the rule does not read, and why.
pub type Exception {
  Exception(path: String, reason: String)
}

/// The test's own deadline, `owned_test.run`'s upper limit: a deadline below it
/// can pass while the test runs.
const test_deadline_ms = 30_000

/// A function (or constructor) of a module, as `module` and `name`.
const sources_of_real_time = [
  #("genesis_prime/service/shell", "real_time"),
  #("genesis_prime/connection/script", "operating_system"),
  #("genesis_prime/connection/script", "operating_system_timer"),
  #("gleam/erlang/process", "send_after"),
  #("gleam/erlang/process", "sleep"),
  #("genesis_prime/dashboard/subscribers", "send_after"),
  #("socket_read", "Within"),
]

/// The functions that wait for a message a bounded time, whose last argument,
/// or `within:`, is the bound.
const bounded_receives = ["receive", "selector_receive"]

/// The test modules that start the release's own processes.
const node_modules = ["serving_node", "fresh_node", "real_start_node"]

/// A constructor or function of a module, the fields or arguments of it that a
/// process takes as a deadline, and where they are read: in any file, or only in
/// a file that names `server.Served`, which is where a connection's settings
/// reach a running listener. A pure rule test builds the same settings and
/// takes the deadline as data, with no timer.
type Deadline {
  Deadline(module: String, name: String, fields: List(String), where: Where)
}

type Where {
  Anywhere
  WithAServedListener
}

const deadlines = [
  Deadline("genesis_prime/server", "Settings", ["send_deadline_ms"], Anywhere),
  Deadline("genesis_prime/server", "World", ["maps_call_ms"], Anywhere),
  Deadline(
    "genesis_prime/readiness",
    "Settings",
    ["within_ms", "attempt_ms"],
    Anywhere,
  ),
  Deadline(
    "genesis_prime/login/sts_connection",
    "Settings",
    ["ask_deadline_ms"],
    WithAServedListener,
  ),
  Deadline(
    "genesis_prime/login/auth_connection",
    "Settings",
    ["ask_deadline_ms"],
    WithAServedListener,
  ),
  Deadline(
    "genesis_prime/game/connection/state",
    "Settings",
    ["ask_deadline_ms"],
    WithAServedListener,
  ),
  Deadline(
    "genesis_prime/world_map/registry",
    "find_or_start",
    ["deadline_ms"],
    Anywhere,
  ),
]

/// An Erlang function that starts a timer or sleeps.
const erlang_timers = [
  #("erlang", "send_after"),
  #("erlang", "start_timer"),
  #("timer", "sleep"),
  #("timer", "send_after"),
]

/// Each source of real time and each short deadline a Gleam file names, at its
/// line, in line order.
pub fn breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  list.flatten([
    named_sources(module),
    unbounded_receives(module),
    node_imports(module),
    short_deadlines(module),
  ])
  |> list.map(fn(found) {
    let #(offset, rule) = found
    Breach(path: file.path, line: syntax.line_of(file.text, offset), rule:)
  })
  |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
}

/// Each timer, sleep or timed receive an Erlang file names, at its line.
pub fn erlang_breaches(file: SourceFile) -> List(Breach) {
  let timers =
    list.flat_map(erlang_timers, fn(timer) {
      let #(module, function) = timer
      erlang_calls.lines(file.text, [erlang_calls.Target(module, function)])
      |> list.map(fn(line) { #(line, module <> ":" <> function) })
    })
  let receives =
    list.map(erlang_calls.timed_receive_lines(file.text), fn(line) {
      #(line, "a receive with a timeout other than 0")
    })
  list.append(timers, receives)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(found) {
    Breach(
      path: file.path,
      line: found.0,
      rule: "names real time (" <> found.1 <> ")",
    )
  })
}

/// Each file that breaks the rule and is not listed, each listed file that
/// holds no breach, and each listed path that is no file under `test/`.
pub fn breaches_outside(
  listed listed: List(Exception),
  gleam_files gleam_files: List(SourceFile),
  erlang_files erlang_files: List(SourceFile),
) -> List(Breach) {
  let found =
    list.append(
      list.map(gleam_files, fn(file) { #(file.path, breaches(file)) }),
      list.map(erlang_files, fn(file) { #(file.path, erlang_breaches(file)) }),
    )
  let listed_paths = list.map(listed, fn(exception) { exception.path })
  let by_file =
    list.flat_map(found, fn(entry) {
      let #(path, file_breaches) = entry
      case list.contains(listed_paths, path), file_breaches {
        True, [] -> [
          Breach(
            path:,
            line: 1,
            rule: "is on the exception list and holds no source of real time",
          ),
        ]
        True, [_, ..] -> []
        False, _ -> file_breaches
      }
    })
  let missing =
    list.filter_map(listed_paths, fn(path) {
      case list.any(found, fn(entry) { entry.0 == path }) {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path:,
            line: 1,
            rule: "is on the exception list and is not a file under test/",
          ))
      }
    })
  list.append(by_file, missing)
}

/// The offset of each reference to a named source of real time, with its rule.
fn named_sources(module: glance.Module) -> List(#(Int, String)) {
  list.flat_map(sources_of_real_time, fn(source) {
    let #(from, name) = source
    syntax.references_to(module:, from: [from], named: [name])
    |> list.map(fn(reference) {
      #(
        syntax.location_of(reference).start,
        "names real time (" <> short_name(from) <> "." <> name <> ")",
      )
    })
  })
}

fn short_name(module: String) -> String {
  module
  |> string.split("/")
  |> list.last
  |> option.from_result
  |> option.unwrap(module)
}

/// The offset of each reference to `process.receive` or
/// `process.selector_receive` that is not the function of a call whose bound is
/// the literal 0.
fn unbounded_receives(module: glance.Module) -> List(#(Int, String)) {
  let looks =
    syntax.expressions(module)
    |> list.filter_map(fn(expression) {
      case expression {
        glance.Call(function:, arguments:, ..) ->
          Ok(#(syntax.span_of(function), arguments))
        glance.FnCapture(function:, arguments_before:, arguments_after:, ..) ->
          Ok(#(
            syntax.span_of(function),
            list.append(arguments_before, arguments_after),
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
    |> list.filter_map(fn(call) {
      let #(function, arguments) = call
      case bound_of(arguments) {
        Some(glance.Int(value: "0", ..)) -> Ok(function.start)
        Some(_) | None -> Error(Nil)
      }
    })
  syntax.references_to(
    module:,
    from: ["gleam/erlang/process"],
    named: bounded_receives,
  )
  |> list.map(syntax.location_of)
  |> list.filter(fn(location) { !list.contains(looks, location.start) })
  |> list.map(fn(location) {
    #(
      location.start,
      "names real time (a receive whose bound is not the literal 0)",
    )
  })
}

/// The bound a receive is given: the argument labelled `within`, or the last.
fn bound_of(
  arguments: List(glance.Field(glance.Expression)),
) -> option.Option(glance.Expression) {
  let labelled =
    list.find_map(arguments, fn(argument) {
      case argument {
        glance.LabelledField(label: "within", item:, ..) -> Ok(item)
        glance.LabelledField(..)
        | glance.UnlabelledField(..)
        | glance.ShorthandField(..) -> Error(Nil)
      }
    })
  case labelled, list.last(arguments) {
    Ok(item), _ -> Some(item)
    Error(Nil), Ok(glance.UnlabelledField(item)) -> Some(item)
    Error(Nil), Ok(_) | Error(Nil), Error(Nil) -> None
  }
}

/// The offset of each import of a module that starts the release's processes.
fn node_imports(module: glance.Module) -> List(#(Int, String)) {
  list.filter_map(module.imports, fn(definition) {
    let import_ = definition.definition
    case list.contains(node_modules, import_.module) {
      True ->
        Ok(#(
          import_.location.start,
          "names real time (the import of " <> import_.module <> ")",
        ))
      False -> Error(Nil)
    }
  })
}

/// The offset of each literal deadline below the test's own, in a call or a
/// record update of a constructor or function that takes a deadline.
fn short_deadlines(module: glance.Module) -> List(#(Int, String)) {
  let expressions = syntax.expressions(module)
  let serves =
    syntax.references_to(module:, from: ["genesis_prime/server"], named: [
      "Served",
    ])
    != []
  let read =
    list.filter(deadlines, fn(deadline) {
      case deadline.where {
        Anywhere -> True
        WithAServedListener -> serves
      }
    })
  list.flat_map(read, fn(deadline) {
    let Deadline(module: from, name:, fields:, ..) = deadline
    let function_spans =
      syntax.references_to(module:, from: [from], named: [name])
      |> list.map(syntax.location_of)
    let qualifiers =
      list.filter_map(module.imports, fn(definition) {
        case definition.definition.module == from {
          True ->
            option.to_result(syntax.import_name(definition.definition), Nil)
          False -> Error(Nil)
        }
      })
    list.flat_map(expressions, fn(expression) {
      case expression {
        glance.Call(function:, arguments:, ..) ->
          case list.contains(function_spans, syntax.span_of(function)) {
            True -> short_in_arguments(arguments, fields)
            False -> []
          }
        glance.RecordUpdate(
          module: Some(qualifier),
          constructor:,
          fields: set,
          ..,
        ) ->
          case constructor == name && list.contains(qualifiers, qualifier) {
            True -> short_in_updates(set, fields)
            False -> []
          }
        glance.RecordUpdate(module: None, constructor:, fields: set, ..) ->
          case
            constructor == name && imported_unqualified(module:, from:, name:)
          {
            True -> short_in_updates(set, fields)
            False -> []
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
        | glance.FieldAccess(..)
        | glance.TupleIndex(..)
        | glance.FnCapture(..)
        | glance.BitString(..)
        | glance.Case(..)
        | glance.BinaryOperator(..)
        | glance.Echo(..) -> []
      }
    })
  })
}

fn imported_unqualified(
  module module: glance.Module,
  from from: String,
  name name: String,
) -> Bool {
  list.any(module.imports, fn(definition) {
    definition.definition.module == from
    && list.any(definition.definition.unqualified_values, fn(value) {
      value.name == name && value.alias == None
    })
  })
}

fn short_in_arguments(
  arguments: List(glance.Field(glance.Expression)),
  fields: List(String),
) -> List(#(Int, String)) {
  list.filter_map(arguments, fn(argument) {
    case argument {
      glance.LabelledField(label:, item:, ..) ->
        short_deadline(label:, item:, fields:)
      glance.UnlabelledField(..) | glance.ShorthandField(..) -> Error(Nil)
    }
  })
}

fn short_in_updates(
  updates: List(glance.RecordUpdateField(glance.Expression)),
  fields: List(String),
) -> List(#(Int, String)) {
  list.filter_map(updates, fn(update) {
    case update.item {
      Some(item) -> short_deadline(label: update.label, item:, fields:)
      None -> Error(Nil)
    }
  })
}

/// The offset and rule of a field that is one of the deadline fields and given
/// a literal below the test's deadline, or that is a literal this rule cannot
/// read as a plain number.
fn short_deadline(
  label label: String,
  item item: glance.Expression,
  fields fields: List(String),
) -> Result(#(Int, String), Nil) {
  case list.contains(fields, label), item {
    True, glance.Int(location:, value:) ->
      case int.parse(string.replace(value, "_", "")) {
        Ok(milliseconds) if milliseconds >= test_deadline_ms -> Error(Nil)
        Ok(_) | Error(Nil) ->
          Ok(#(
            location.start,
            "sets "
              <> label
              <> " to the literal "
              <> value
              <> ", below the test's deadline of "
              <> int.to_string(test_deadline_ms)
              <> " ms",
          ))
      }
    True, _ | False, _ -> Error(Nil)
  }
}

/// The files that check real time itself, or run the release's own start,
/// each with its reason. They stay on the list for good.
pub fn genuine_real_time() -> List(Exception) {
  [
    Exception(
      "test/migration_start_test.gleam",
      "starts the release's own node, whose processes cannot take the test's clock",
    ),
    Exception(
      "test/sigterm_test.gleam",
      "starts the release's own node, whose processes cannot take the test's clock",
    ),
    Exception(
      "test/real_start_test.gleam",
      "starts the release's own node, whose processes cannot take the test's clock",
    ),
    Exception(
      "test/server_table_test.gleam",
      "starts a node of its own, whose processes cannot take the test's clock",
    ),
    Exception(
      "test/table_load_test.gleam",
      "starts a node of its own, whose processes cannot take the test's clock",
    ),
    Exception(
      "test/table_value_test.gleam",
      "starts a node of its own, whose processes cannot take the test's clock",
    ),
    Exception(
      "test/fixed_seed_test.gleam",
      "starts a node of its own, whose connections' seeds the test reads",
    ),
    Exception(
      "test/serving_node.gleam",
      "serves the tree on a node of its own, with the readiness settings the release's start gives",
    ),
    Exception(
      "test/application_test.gleam",
      "its root-application test starts the node's application on a node of its own",
    ),
    Exception(
      "test/readiness_test.gleam",
      "checks the wait for the database, which counts the monotonic clock (genesis_prime/readiness)",
    ),
    Exception(
      "test/readiness_support.gleam",
      "the settings of the tests of the wait for the database",
    ),
    Exception(
      "test/content_load_test.gleam",
      "checks that the content load asks again after a window with no answer passes, a real wait of the readiness ask",
    ),
    Exception(
      "test/owned_test.gleam",
      "the test runner's own deadline, which waits a real time for the test's body",
    ),
    Exception(
      "test/event_wait.gleam",
      "the wait for an event no clock causes, such as a pool's first connection",
    ),
    Exception(
      "test/connection_script_test.gleam",
      "its three tests of the server's own script check the system seed, the node's monotonic reading and the operating system's timer",
    ),
    Exception(
      "test/ask_test.gleam",
      "checks an ask's deadline passing on the node's time against a target that never answers",
    ),
    Exception(
      "test/world_map_registry_test.gleam",
      "checks Maps' deadlines passing on the node's time against a Maps that never answers",
    ),
    Exception(
      "test/literal_area_ffi.erl",
      "samples the VM's literal allocator on a process of its own; no test waits on it",
    ),
  ]
}

/// The test files whose tests still run on the real clock: a connection on the
/// operating system's script, a service on its real time, or a setting that
/// gives a process a deadline the test can pass. The coverage measure lists
/// each. A file listed here that names none is a breach, so its entry is
/// deleted with its last real-clock test; the part is empty when every test runs
/// on the driven clock.
pub fn still_on_the_real_clock() -> List(Exception) {
  [
    Exception(
      "test/login_support.gleam",
      "starts the tree on the operating system's script and real service time, with a send deadline of 300 ms, a Maps call of 2 s and an ask of 5 s",
    ),
    Exception(
      "test/second_login.gleam",
      "reads the second login's socket for a bounded real time",
    ),
    Exception(
      "test/game_wire_test.gleam",
      "its content load asks the database under a wait of 5 s",
    ),
    Exception(
      "test/world_support.gleam",
      "starts the world with a Maps call of 1 s",
    ),
    Exception(
      "test/ask_support.gleam",
      "asks through the operating system's script, real service time and a sleep",
    ),
    Exception(
      "test/connection_actor_test.gleam",
      "runs connections on the operating system's script",
    ),
    Exception(
      "test/connection_closing_test.gleam",
      "runs connections on the operating system's script",
    ),
    Exception(
      "test/connection_shell_test.gleam",
      "runs a connection on the operating system's script",
    ),
    Exception(
      "test/connection_signal_test.gleam",
      "runs connections on the operating system's script, so its timers fire on the operating system's scheduler",
    ),
    Exception(
      "test/owned_test_test.gleam",
      "its listener-seed tests serve connections on the operating system's script",
    ),
    Exception(
      "test/wire_recorder_test.gleam",
      "records a connection run on the operating system's script",
    ),
    Exception(
      "test/service_shell_test.gleam",
      "starts service shells on their real time",
    ),
    Exception(
      "test/content_support.gleam",
      "loads the content under a database wait of 1 s",
    ),
    Exception(
      "test/world_data_counts_test.gleam",
      "loads the world database under a wait of 5 s",
    ),
  ]
}

/// Every listed file, the genuine ones first.
pub fn exceptions() -> List(Exception) {
  list.append(genuine_real_time(), still_on_the_real_clock())
}
