//// The real-clock rule: a test file under `test/` names no source of real time
//// and sets no short deadline in a setting a process runs by, unless it is on
//// the exception list with its reason. A test on the real clock fails by the
//// machine's load, not by its code (the writing-tests skill), so a new one is
//// refused where it is written.
////
//// ```
//// test file ──► Part A: a source of real time, or a call  ┐
////                       of a support function that starts │
////                       one (`entry_points`)              │
////          ──► Part B: a literal deadline < 30 s          ├─► breaches
//// .erl file ──► a timer, a sleep, a timed receive         ┘      │
////                                                                 ▼
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
////   start the release's own processes on the node's clock;
//// - a call of a function in `entry_points`: the functions of `login_support`
////   that hand out the server's own settings, which carry the operating system's
////   script, real service time and production deadlines. A file that calls one
////   is on the real clock though its own text names no source, so it is listed
////   like a file that names one.
////
//// An Erlang file under `test/` that calls `erlang:send_after`,
//// `erlang:start_timer`, `timer:sleep`, `timer:send_after`,
//// `timer:send_interval`, `timer:apply_after` or `timer:apply_interval`, or has
//// a receive with a timeout other than 0 or `infinity`, is a breach too.
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
//// The exception list (`genuine_real_time`) holds the files that check real time
//// itself, each with its reason. A listed file with nothing left is a breach, so
//// the list cannot go stale.
////
//// What the rule does not catch:
//// - A support function that starts the real clock and is not in
////   `entry_points`. A support module that names a source itself is read (and
////   is listed), but a test that calls it is caught only for the functions
////   named. The waits of `event_wait`, `readiness_support` and `owned_test`
////   are not named: each ends by its own condition or by the test's deadline.
//// - An ask whose wait the node's own time counts. The shells count an ask's
////   deadline from the node's time, which the driven clock leaves alone, so a
////   test of an ask that passes its deadline waits that time in real
////   milliseconds, given as the byte of a command, not as a source: the three
////   deadline tests of `ask_test` and `world_map_registry_test`'s wait 300 ms
////   and 1 s, `account_store_test`'s waits 300 ms and `wire_replay_test`'s
////   ask of 200 ms ends at its deadline. Each asserts only that at least that
////   long has passed, or the bytes the outcome gives, against a target that
////   never answers.
//// - The replay's wait. Every replay takes the bound of its waits as a setting
////   (`wire_replay.replay`'s `wait_ms`, a labelled argument, not read here).
////   The tests pass `ask_support.beyond_the_test_ms`, which no test reaches, and
////   five tests of `wire_replay_test` pass `wire_replay_support.give_up_wait_ms`,
////   5 s of real time, through `run_giving_up` and `run_giving_up_with`; each
////   fails by that bound, against a target that never answers, and asserts no
////   time. `wire_replay_test` is not listed, since it names no source, so a
////   new test that calls those two functions is not caught.
//// - The database client's own timers. `account_store_test`'s test with no
////   database gives pog a queue target of 50 ms and a queue interval of 100 ms,
////   which count the node's time and which no rule reads; its outcome
////   (`unavailable`) is the same on a slow machine.
//// - A shutdown deadline: Part B reads no `shutdown_ms` literal. The driven
////   listeners take their shutdown from `ask_support.driven_settings`, and a test
////   that must end a child as a supervisor's timer does sends the exit itself.
//// - A file on `genuine_real_time` is exempt as a whole. `application_test` and
////   `readiness_test` also hold tests on the real clock that the reason does
////   not name, and a new real-clock test added to one of them, or to any listed
////   file, is not caught.
//// - Part B reads a literal. A short deadline given through a variable, a
////   module constant or a punned label is not read, and neither is a time given
////   to `process.call` or `actor.call`.

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

/// A function of a support module under `test/` that starts something on the
/// real clock, and what makes it real time.
pub type EntryPoint {
  EntryPoint(module: String, function: String, because: String)
}

/// The functions of the support modules that hand out the settings of the
/// server's own start, with what makes them real time. A test file that calls
/// one is on the real clock, whatever its own text names.
pub fn entry_points() -> List(EntryPoint) {
  let settings =
    "its settings serve on the operating system's script with real service time and the server's own deadlines"
  [
    EntryPoint("login_support", "servers_settings", settings),
    EntryPoint("login_support", "servers_settings_over", settings),
  ]
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
  #("timer", "send_interval"),
  #("timer", "apply_after"),
  #("timer", "apply_interval"),
]

/// Each source of real time and each short deadline a Gleam file names, at its
/// line, in line order.
pub fn breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  list.flatten([
    named_sources(module),
    unbounded_receives(module),
    node_imports(module),
    entry_point_calls(module),
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
    syntax.calls(module)
    |> list.filter_map(fn(call) {
      case
        syntax.argument(
          arguments: call.arguments,
          label: "within",
          position: syntax.LastArgument,
        )
      {
        Some(glance.Int(value: "0", ..)) -> Ok(call.function.start)
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

/// The offset of each reference to an entry point of a support module, with its
/// rule.
fn entry_point_calls(module: glance.Module) -> List(#(Int, String)) {
  list.flat_map(entry_points(), fn(entry) {
    let EntryPoint(module: from, function:, because:) = entry
    syntax.references_to(module:, from: [from], named: [function])
    |> list.map(fn(reference) {
      #(
        syntax.location_of(reference).start,
        "names real time ("
          <> from
          <> "."
          <> function
          <> ", which "
          <> because
          <> ")",
      )
    })
  })
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
      "serves the tree on a node of its own, on the operating system's script and real service time with short deadlines (real_settings), and the readiness settings the release's start gives",
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
      "the wait for the database that every tree start makes (login_support.started_from) and the readiness tests use: its window, attempts and pauses count the node's monotonic clock, since the database is a process outside the tree that no driven clock reaches",
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
      "test/second_login.gleam",
      "the live check's second login, run by hand against the running server on its default ports: its reads of the game server's bytes are bounded by real time, since no driven clock reaches a server in another node",
    ),
    Exception(
      "test/connection_script_test.gleam",
      "its four tests of the server's own script check the system seed, the node's monotonic reading, the operating system's timer and the readings the script gives the wire recorder",
    ),
    Exception(
      "test/world_map_registry_test.gleam",
      "checks Maps' deadlines passing on the node's time against a Maps that never answers",
    ),
    Exception(
      "test/server_test.gleam",
      "its settings tests read the server's own settings (login_support.servers_settings), which carry the operating system's script, real service time and production deadlines by design; they start no process",
    ),
    Exception(
      "test/sitting_test.gleam",
      "its settings tests read the server's own settings (login_support.servers_settings) to check what a sitting changes in them; they start no process",
    ),
    Exception(
      "test/literal_area_ffi.erl",
      "samples the VM's literal allocator on a process of its own; no test waits on it",
    ),
  ]
}

/// Every listed file.
pub fn exceptions() -> List(Exception) {
  genuine_real_time()
}
