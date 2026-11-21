//// The real-clock rule. Expected values are the rule of the writing-tests
//// skill: a test never depends on the real clock (a process on the operating
//// system's timers, a sleep, a wait bounded by a real time) and never runs under
//// a production time limit shorter than its own deadline, 30 s
//// (`owned_test.run`'s). A breach is a source of real time named in a test file,
//// or a literal deadline below 30 s in a setting a process runs by, reported at
//// its line; a file on the exception list is no breach, and a listed file with
//// none left is one. Every case is planted in a made-up file.

import code_rule/planted
import code_rule/real_clock.{Exception}
import code_rule/repository
import code_rule/source
import code_rule/syntax
import glance
import gleam/list
import gleam/string
import owned_test
import unitest

/// The planted test file: the imports, then the body's lines inside one
/// function, so each case states only what differs. The first body line is
/// line 15.
fn planted_lines(body: List(String)) -> List(String) {
  list.flatten([
    [
      "import genesis_prime/connection/script",
      "import genesis_prime/dashboard/subscribers",
      "import genesis_prime/game/connection/state as connection_state",
      "import genesis_prime/login/auth_connection",
      "import genesis_prime/login/sts_connection",
      "import genesis_prime/readiness",
      "import genesis_prime/server",
      "import genesis_prime/service/shell as service_shell",
      "import genesis_prime/world_map/registry as world_map_registry",
      "import gleam/erlang/process",
      "import other",
      "import socket_read",
      "",
      "pub fn planted() {",
    ],
    body,
    ["}"],
  ])
}

fn breach_lines(source_lines: List(String)) -> List(Int) {
  planted.file("test/planted_test.gleam", source_lines)
  |> real_clock.breaches
  |> planted.lines
}

/// Each row: the body's lines (the first is line 15), the breach lines, and why.
fn check_rows(rows: List(#(List(String), List(Int), String))) -> Nil {
  list.each(rows, fn(row) {
    let #(body, lines, reason) = row
    assert breach_lines(planted_lines(body)) == lines as reason
  })
}

pub fn a_reference_to_the_operating_system_script_in_a_test_file_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(["  let scripts = script.operating_system"], [15], "the script"),
    #(
      [
        "  script.operating_system_timer(subject:, timer:, reference:, after_ms:)",
      ],
      [15],
      "the script's timer",
    ),
    #(["  service_shell.real_time()"], [15], "the service shells' real time"),
    #(
      ["  process.send_after(subject, 100, Nil)"],
      [15],
      "a timer on the operating system's scheduler",
    ),
    #(["  let arm = subscribers.send_after"], [15], "the dashboard's real arm"),
    #(["  socket_read.Within(100)"], [15], "a read bounded by a real time"),
    #(
      ["  let scripts = script.operating_system", "  service_shell.real_time()"],
      [15, 16],
      "each reference, at its own line",
    ),
    #(
      [
        "  list.map(rows, fn(row) {",
        "    server.Served(..row, scripts: script.operating_system)",
        "  })",
      ],
      [16],
      "a reference inside a closure",
    ),
    #(
      ["  assert other.operating_system() == Nil"],
      [],
      "a function of the same name in another module",
    ),
    #(
      ["  script.issued(seed: 1)"],
      [],
      "another function of the script's module",
    ),
    #(
      ["  assert operating_system() == Nil"],
      [],
      "a function of the file's own",
    ),
    #(
      ["  other.send_after(subject, 100)"],
      [],
      "send_after of a module that is not the operating system's",
    ),
  ])
  // Each row: the whole planted file's lines, the breach lines, and why.
  let files = [
    #(
      [
        "import genesis_prime/connection/script as os_script",
        "",
        "pub fn planted() {",
        "  os_script.operating_system",
        "}",
      ],
      [4],
      "the module imported under an alias",
    ),
    #(
      [
        "import genesis_prime/connection/script.{operating_system}",
        "",
        "pub fn planted() {",
        "  operating_system",
        "}",
      ],
      [4],
      "the function imported unqualified",
    ),
    #(
      [
        "import genesis_prime/connection/script.{operating_system as os}",
        "",
        "pub fn planted() {",
        "  os",
        "}",
      ],
      [4],
      "the function imported unqualified under an alias",
    ),
    #(
      ["import fresh_node", "", "pub fn planted() {", "  Nil", "}"],
      [1],
      "a separate node of the test's, at its import",
    ),
    #(
      ["import serving_node", "", "pub fn planted() {", "  Nil", "}"],
      [1],
      "a serving node",
    ),
    #(
      ["import real_start_node", "", "pub fn planted() {", "  Nil", "}"],
      [1],
      "a real start node",
    ),
  ]
  list.each(files, fn(row) {
    let #(lines, breaches, reason) = row
    assert breach_lines(lines) == breaches as reason
  })
}

pub fn process_sleep_is_a_breach_and_sleep_forever_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(["  process.sleep(1)"], [15], "a sleep of 1 ms"),
    #(["  process.sleep(wait_ms)"], [15], "a sleep of a variable time"),
    #(
      ["  process.spawn_unlinked(process.sleep_forever)"],
      [],
      "a process that sleeps for ever has no time to depend on",
    ),
    #(["  process.sleep_forever()"], [], "sleep_forever called"),
  ])
  let imported = [
    "import gleam/erlang/process.{sleep}",
    "",
    "pub fn planted() {",
    "  sleep(1)",
    "}",
  ]
  assert breach_lines(imported) == [4] as "sleep imported unqualified"
}

pub fn a_receive_bounded_above_0_is_a_breach_and_one_bounded_at_0_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(["  process.receive(subject, 100)"], [15], "receive, positional"),
    #(
      ["  process.receive(from: subject, within: 5000)"],
      [15],
      "receive, labelled",
    ),
    #(
      ["  process.selector_receive(selector, within: wait_ms)"],
      [15],
      "selector_receive of a variable time, which may not be 0",
    ),
    #(
      ["  selector |> process.selector_receive(within: 1000)"],
      [15],
      "selector_receive in a pipe",
    ),
    #(
      ["  list.map(subjects, process.receive(_, 10))"],
      [15],
      "receive as a function capture",
    ),
    #(
      ["  list.map(subjects, process.receive)"],
      [15],
      "receive passed as a function: its bound is not stated",
    ),
    #(["  process.receive(subject, within: 0)"], [], "receive at 0"),
    #(["  process.receive(subject, 0)"], [], "receive at 0, positional"),
    #(
      ["  process.selector_receive(from: selector, within: 0)"],
      [],
      "selector_receive at 0",
    ),
    #(
      ["  selector |> process.selector_receive(within: 0)"],
      [],
      "selector_receive at 0 in a pipe",
    ),
    #(["  process.receive_forever(subject)"], [], "receive_forever"),
    #(
      ["  process.selector_receive_forever(selector)"],
      [],
      "selector_receive_forever",
    ),
    #(["  other.receive(subject, 100)"], [], "receive of another module"),
  ])
}

pub fn a_helper_in_a_support_module_that_names_real_time_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // A support module holds no test, so the rule reads every file under `test/`.
  let file =
    planted.file("test/planted_support.gleam", [
      "import genesis_prime/connection/script",
      "",
      "pub fn scripts() {",
      "  script.operating_system",
      "}",
    ])
  let assert [breach] = real_clock.breaches(file)
    as "expected exactly one breach"
  assert breach.path == "test/planted_support.gleam"
  assert breach.line == 4
  assert string.contains(breach.rule, "script.operating_system")
}

/// A planted test file that imports the support modules, then the body inside
/// one function. The first body line is line 7.
fn support_caller(body: List(String)) -> List(String) {
  list.flatten([
    [
      "import ask_support",
      "import content_support",
      "import login_support",
      "import world_support",
      "",
      "pub fn planted() {",
    ],
    body,
    ["}"],
  ])
}

pub fn a_call_of_a_support_function_that_runs_the_real_clock_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the body's lines (the first is line 7), the breach lines, and why.
  let rows = [
    #(
      ["  let settings = login_support.servers_settings()"],
      [7],
      "the server's own settings",
    ),
    #(
      ["  login_support.servers_settings_over(spawns:)"],
      [7],
      "the server's own settings over a content load",
    ),
    #(
      [
        "  login_support.servers_settings()",
        "  login_support.servers_settings_over(spawns:)",
      ],
      [7, 8],
      "each call, at its own line",
    ),
    #(["  login_support.stop(started)"], [], "the stop of a tree"),
    #(
      ["  login_support.on_the_clock(settings:, time:)"],
      [],
      "the driven clock's own setting",
    ),
    #(["  login_support.start(time:)"], [], "the tree on the driven clock"),
    #(
      ["  login_support.settings(pool:, time:)"],
      [],
      "the settings of a tree on the driven clock",
    ),
    #(
      ["  login_support.servers_settings_on(time:)"],
      [],
      "the server's own settings on the driven clock",
    ),
    #(
      ["  ask_support.gate(name:, shutdown_ms: 1000, time:)"],
      [],
      "a gate on the driven clock",
    ),
    #(
      ["  ask_support.start_on(time:, rule:, directory:, with:)"],
      [],
      "a listener on the driven clock",
    ),
    #(
      [
        "  world_support.start(time:, spawns:, respawn_ms: 1, idle_stop_ms: 1, sweep_ms: 1)",
      ],
      [],
      "a world on the driven clock",
    ),
    #(
      ["  ask_support.start_tree(child)"],
      [],
      "a tree whose child decides its clock",
    ),
    #(
      ["  content_support.load(database:)"],
      [],
      "a load whose attempts end by no time of their own",
    ),
    #(
      ["  content_support.load_asking(database:, ask:, probe:)"],
      [],
      "a load whose wait the caller gives",
    ),
    #(["  world_support.stop(world:)"], [], "the stop of a world"),
    #(["  other.start()"], [], "start of another module"),
  ]
  list.each(rows, fn(row) {
    let #(body, lines, reason) = row
    assert breach_lines(support_caller(body)) == lines as reason
  })
  // Each row: the whole file's lines, the breach lines, and why.
  let files = [
    #(
      [
        "import login_support as logins",
        "",
        "pub fn planted() {",
        "  logins.servers_settings()",
        "}",
      ],
      [4],
      "the support module imported under an alias",
    ),
    #(
      [
        "import login_support.{servers_settings}",
        "",
        "pub fn planted() {",
        "  servers_settings()",
        "}",
      ],
      [4],
      "the function imported unqualified",
    ),
  ]
  list.each(files, fn(row) {
    let #(lines, expected, reason) = row
    assert breach_lines(lines) == expected as reason
  })
}

pub fn a_new_test_that_reaches_real_time_through_login_support_servers_settings_is_a_breach_outside_the_list_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_test =
    planted.file("test/planted_via_support_test.gleam", [
      "import login_support",
      "import owned_test",
      "",
      "pub fn a_new_test() {",
      "  use <- owned_test.run(5000)",
      "  login_support.servers_settings()",
      "}",
    ])
  // The repository's own files are absent here, so each listed path is also
  // reported as no file; only the planted file's breach is read.
  let found =
    real_clock.breaches_outside(
      listed: real_clock.exceptions(),
      gleam_files: [planted_test],
      erlang_files: [],
    )
    |> list.filter(fn(breach: source.Breach) {
      breach.path == planted_test.path
    })
  let assert [breach] = found as "expected exactly one breach"
  assert breach.path == "test/planted_via_support_test.gleam"
  assert breach.line == 6
  assert string.contains(breach.rule, "login_support.servers_settings")
}

pub fn each_entry_point_is_a_public_function_of_its_support_module_and_a_breach_when_called_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let sources = repository.sources(["test"])
  assert real_clock.entry_points() != [] as "the rule names its entry points"
  list.each(real_clock.entry_points(), fn(entry) {
    let path = "test/" <> entry.module <> ".gleam"
    let assert Ok(file) = list.find(sources, fn(file) { file.path == path })
      as { path <> " is a support module under test/" }
    let module = syntax.parse(file)
    assert list.any(module.functions, fn(definition) {
      definition.definition.name == entry.function
      && definition.definition.publicity == glance.Public
    })
      as { entry.module <> "." <> entry.function <> " is a public function" }
    assert entry.because != "" as "each entry says what makes it real time"
    let caller =
      planted.file("test/planted_test.gleam", [
        "import " <> entry.module,
        "",
        "pub fn planted() {",
        "  " <> entry.module <> "." <> entry.function <> "()",
        "}",
      ])
    assert planted.lines(real_clock.breaches(caller)) == [4]
      as { entry.module <> "." <> entry.function <> " called is a breach" }
  })
}

/// An Erlang file's breach lines.
fn erlang_lines(source_lines: List(String)) -> List(Int) {
  planted.file("test/planted_ffi.erl", source_lines)
  |> real_clock.erlang_breaches
  |> planted.lines
}

pub fn a_send_after_in_a_test_erlang_file_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the file's lines, the breach lines, and why.
  let rows = [
    #(["f() ->", "    erlang:send_after(10, self(), tick)."], [2], "send_after"),
    #(
      ["f() ->", "    erlang:start_timer(10, self(), tick)."],
      [2],
      "start_timer",
    ),
    #(["f() ->", "    timer:sleep(20)."], [2], "timer:sleep"),
    #(["f() ->", "    timer:send_after(20, tick)."], [2], "timer:send_after"),
    #(
      ["f() ->", "    receive tick -> ok after 100 -> late end."],
      [2],
      "a receive that gives up after 100 ms",
    ),
    #(
      [
        "f(T) ->",
        "    receive",
        "        tick -> ok",
        "    after T -> late",
        "    end.",
      ],
      [4],
      "a receive that gives up after a variable time",
    ),
    #(
      [
        "f() ->",
        "    try",
        "        receive tick -> ok after 5 -> late end",
        "    after",
        "        cleanup()",
        "    end.",
      ],
      [3],
      "a receive inside a try with an after",
    ),
    #(
      ["f() ->", "    timer:apply_after(20, m, f, [])."],
      [2],
      "timer:apply_after",
    ),
    #(
      ["f() ->", "    timer:apply_interval(20, m, f, [])."],
      [2],
      "timer:apply_interval",
    ),
    #(
      ["f() ->", "    timer:send_interval(20, tick)."],
      [2],
      "timer:send_interval",
    ),
    #(
      ["f() ->", "    receive tick -> ok after 0 -> none end."],
      [],
      "a receive that looks and gives up at once",
    ),
    #(
      ["f() ->", "    receive tick -> ok after infinity -> never end."],
      [],
      "a receive that waits for ever has no time bound",
    ),
    #(
      [
        "f() ->",
        "    receive",
        "        tick ->",
        "            maybe",
        "                ok ?= work()",
        "            else",
        "                _ -> failed",
        "            end",
        "    after 5 -> late",
        "    end.",
      ],
      [9],
      "a maybe block in a receive's clause, which has its own end",
    ),
    #(
      ["f() ->", "    receive tick -> ok end."],
      [],
      "a receive with no time bound",
    ),
    #(
      ["f() ->", "    try work()", "    after", "        cleanup()", "    end."],
      [],
      "an after of a try is no timeout",
    ),
    #(
      [
        "f() ->",
        "    Fun = fun() -> ok end,",
        "    try Fun()",
        "    after",
        "        cleanup()",
        "    end.",
      ],
      [],
      "a try after a fun that has its own end",
    ),
    #(
      [
        "%% erlang:send_after(10, self(), tick) and timer:sleep(20)",
        "f() ->",
        "    \"timer:sleep(20)\".",
      ],
      [],
      "a comment and a string",
    ),
    #(
      ["f() ->", "    other:send_after(10, self(), tick)."],
      [],
      "send_after of another module",
    ),
  ]
  list.each(rows, fn(row) {
    let #(lines, breaches, reason) = row
    assert erlang_lines(lines) == breaches as reason
  })
}

pub fn a_send_deadline_below_the_tests_deadline_in_server_settings_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      ["  server.Settings(send_deadline_ms: 300, other: 1)"],
      [15],
      "the send deadline of the server's settings",
    ),
    #(
      ["  server.Settings(..settings, send_deadline_ms: 300)"],
      [15],
      "the send deadline in a record update",
    ),
    #(
      ["  server.World(maps_call_ms: 1000, other: 1)"],
      [15],
      "the Maps call of the world",
    ),
    #(
      ["  server.World(..world, maps_call_ms: 2000)"],
      [15],
      "the Maps call in a record update",
    ),
    #(
      ["  readiness.Settings(within_ms: 250, attempt_ms: 100, pause_ms: 20)"],
      [15, 15],
      "both deadlines of the readiness settings, a line for each",
    ),
    #(
      ["  readiness.Settings(within_ms: 30_000, attempt_ms: 20, pause_ms: 100)"],
      [15],
      "one short deadline of two",
    ),
    #(
      ["  world_map_registry.find_or_start(maps:, map:, deadline_ms: 100)"],
      [15],
      "the deadline of a find or start",
    ),
    #(
      [
        "  server.Served(settings: sts_connection.Settings(ask_deadline_ms: 5000))",
      ],
      [15],
      "the ask deadline of the sts connection, in a listener",
    ),
    #(
      [
        "  server.Served(settings: auth_connection.Settings(ask_deadline_ms: 5000))",
      ],
      [15],
      "the ask deadline of the auth connection, in a listener",
    ),
    #(
      [
        "  server.Served(settings: connection_state.Settings(ask_deadline_ms: 5000))",
      ],
      [15],
      "the ask deadline of the game connection, in a listener",
    ),
    #(
      [
        "  let settings = connection_state.Settings(ask_deadline_ms: 5000)",
        "  server.Served(settings:)",
      ],
      [15],
      "the settings built apart from the listener that takes them",
    ),
    #(
      ["  connection_state.Settings(ask_deadline_ms: 4000, rate:)"],
      [],
      "the ask deadline of a pure rule test, which is data",
    ),
    #(
      ["  server.Settings(send_deadline_ms: 29_999)"],
      [15],
      "just under the test's deadline",
    ),
    #(
      ["  server.Settings(send_deadline_ms: 30_000)"],
      [],
      "the test's deadline itself",
    ),
    #(
      ["  server.Settings(send_deadline_ms: 86_400_000)"],
      [],
      "a deadline far beyond the test's",
    ),
    #(
      ["  server.Settings(send_deadline_ms: deadline_ms)"],
      [],
      "a deadline held in a variable",
    ),
    #(
      ["  server.Settings(send_deadline_ms:)"],
      [],
      "a deadline given by its label",
    ),
    #(
      ["  server.World(idle_stop_ms: 300, sweep_ms: 100, respawn_ms: 50)"],
      [],
      "a millisecond field that is rule data, not a deadline",
    ),
    #(
      ["  other.Settings(send_deadline_ms: 300)"],
      [],
      "the field of another module's settings",
    ),
    #(
      ["  world_map_registry.find(maps:, map:, deadline_ms: 100)"],
      [],
      "another function of the registry",
    ),
  ])
}

pub fn a_listed_file_is_no_breach_and_a_listed_file_with_none_left_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let sleeping =
    planted.file("test/sleeping_test.gleam", [
      "import gleam/erlang/process",
      "",
      "pub fn planted() {",
      "  process.sleep(1)",
      "}",
    ])
  let clean =
    planted.file("test/clean_test.gleam", ["pub fn planted() {", "  Nil", "}"])
  let ticking =
    planted.file("test/ticking_ffi.erl", ["f() ->", "    timer:sleep(20)."])
  let listed = fn(path) { Exception(path:, reason: "a planted reason") }
  // Each row: the listed files, the Gleam and the Erlang files, the (path, line,
  // text of the rule) of each breach in the order reported, and why.
  let rows = [
    #(
      [],
      [sleeping, clean],
      [ticking],
      [
        #("test/sleeping_test.gleam", 4, "process.sleep"),
        #("test/ticking_ffi.erl", 2, "timer:sleep"),
      ],
      "a file that names real time and is not listed",
    ),
    #(
      [listed("test/sleeping_test.gleam"), listed("test/ticking_ffi.erl")],
      [sleeping, clean],
      [ticking],
      [],
      "listed files are no breach",
    ),
    #(
      [
        listed("test/sleeping_test.gleam"),
        listed("test/clean_test.gleam"),
        listed("test/ticking_ffi.erl"),
      ],
      [sleeping, clean],
      [ticking],
      [#("test/clean_test.gleam", 1, "holds no source of real time")],
      "a listed file with none left",
    ),
    #(
      [listed("test/gone_test.gleam")],
      [clean],
      [],
      [#("test/gone_test.gleam", 1, "is not a file under test/")],
      "a listed file that does not exist",
    ),
    #(
      [listed("test/sleeping_test.gleam")],
      [sleeping, clean],
      [ticking],
      [#("test/ticking_ffi.erl", 2, "timer:sleep")],
      "a listing covers its own file only",
    ),
  ]
  list.each(rows, fn(row) {
    let #(listed_files, files, erlang_files, expected, reason) = row
    let found =
      real_clock.breaches_outside(
        listed: listed_files,
        gleam_files: files,
        erlang_files:,
      )
      |> list.map(fn(breach: source.Breach) {
        #(breach.path, breach.line, breach.rule)
      })
    assert list.length(found) == list.length(expected) as reason
    list.each(list.zip(found, expected), fn(pair) {
      let #(#(path, line, rule), #(want_path, want_line, want_rule)) = pair
      assert path == want_path as reason
      assert line == want_line as reason
      assert string.contains(rule, want_rule) as reason
    })
  })
}

pub fn the_repository_has_no_breach_test() -> Nil {
  // Deadline: the body parses the test directory once for the whole run; the
  // whole file took 1 s in three runs alone, so 20 s is far more than 3 times
  // that, for a run that waits on the parse other rules share.
  use <- owned_test.run(20_000)
  use <- unitest.tag("code_rule")
  let breaches =
    real_clock.breaches_outside(
      listed: real_clock.exceptions(),
      gleam_files: repository.sources(["test"]),
      erlang_files: repository.erlang_sources(["test"]),
    )
  assert breaches == []
}
