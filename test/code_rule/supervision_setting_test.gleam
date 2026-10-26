//// The supervision-setting rules. Expected values are the plan and test list
//// of the supervision issue (tests 1 and 2) and gleam_otp's own text: a
//// `static_supervisor` or `factory_supervisor` builder that is not given
//// `restart_tolerance` has "Intensity defaults to 2 and period defaults to
//// 5", and a worker that is not given `timeout` has "The default shutdown
//// timeout is 5000ms" (`static_supervisor.gleam`, `factory_supervisor.gleam`
//// and `supervision.gleam` of gleam_otp). The designing-processes skill,
//// Restarts and shutdown, requires each supervisor to state its restart
//// intensity, period and shutdown timeouts. A builder or worker is a breach
//// unless the pipeline that starts with it states the setting, so the
//// setting sits where the supervisor is built. A supervisor child or a
//// factory supervisor child has no shutdown time to state: its supervisor
//// waits for its children. Every breach is planted in a made-up file, and
//// each rule is then run over the real source under `src/`.

import code_rule/planted
import code_rule/repository
import code_rule/supervision_setting
import gleam/list
import owned_test

/// A planted module whose one function, `tree`, has the body given. Its body
/// starts on line 7.
fn static_module(body: List(String)) -> List(String) {
  list.flatten([
    [
      "//// A planted module.",
      "",
      "import gleam/otp/static_supervisor",
      "import gleam/otp/supervision",
      "",
      "pub fn tree() -> static_supervisor.Builder {",
    ],
    body,
    ["}"],
  ])
}

/// A planted module whose one function, `connections`, has the body given. Its
/// body starts on line 6.
fn factory_module(body: List(String)) -> List(String) {
  list.flatten([
    [
      "//// A planted module.",
      "",
      "import gleam/otp/factory_supervisor",
      "",
      "pub fn connections() -> factory_supervisor.Builder(Int, Int) {",
    ],
    body,
    ["}"],
  ])
}

// Rule 1: every supervisor states its restart limit.

pub fn a_static_supervisor_with_no_restart_limit_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.add(supervision.worker(start))",
      ]),
    )
  let assert [breach] = supervision_setting.missing_restart_limit(file)
    as "expected exactly one breach"
  assert breach.path == "src/genesis_prime/login.gleam"
  assert breach.line == 7
}

pub fn a_static_supervisor_that_states_its_restart_limit_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(supervision.worker(start))",
      ]),
    )
  assert supervision_setting.missing_restart_limit(file) == []
}

pub fn a_restart_limit_stated_late_in_the_pipeline_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.add(supervision.worker(start))",
        "  |> static_supervisor.auto_shutdown(static_supervisor.Never)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
      ]),
    )
  assert supervision_setting.missing_restart_limit(file) == []
}

pub fn a_factory_supervisor_with_no_restart_limit_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/connection.gleam",
      list.flatten([
        factory_module([
          "  factory_supervisor.worker_child(start)",
          "  |> factory_supervisor.timeout(ms: 1000)",
        ]),
        [
          "",
          "pub fn maps() -> factory_supervisor.Builder(Int, Int) {",
          "  factory_supervisor.supervisor_child(start)",
          "}",
        ],
      ]),
    )
  assert planted.lines(supervision_setting.missing_restart_limit(file))
    == [6, 11]
}

pub fn a_factory_supervisor_that_states_its_restart_limit_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/connection.gleam",
      list.flatten([
        factory_module([
          "  factory_supervisor.worker_child(start)",
          "  |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)",
          "  |> factory_supervisor.timeout(ms: 1000)",
        ]),
        [
          "",
          "pub fn maps() -> factory_supervisor.Builder(Int, Int) {",
          "  factory_supervisor.supervisor_child(start)",
          "  |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)",
          "}",
        ],
      ]),
    )
  assert supervision_setting.missing_restart_limit(file) == []
}

pub fn the_restart_limit_of_another_pipeline_does_not_excuse_a_builder_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(static_supervisor.supervised(other()))",
        "}",
        "",
        "fn other() -> static_supervisor.Builder {",
        "  static_supervisor.new(static_supervisor.RestForOne)",
        "  |> static_supervisor.add(supervision.worker(start))",
      ]),
    )
  assert planted.lines(supervision_setting.missing_restart_limit(file)) == [13]
}

pub fn a_builder_whose_limit_is_set_outside_its_pipeline_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  let builder = static_supervisor.new(static_supervisor.OneForOne)",
        "  static_supervisor.restart_tolerance(builder, intensity: 3, period: 5)",
      ]),
    )
  assert planted.lines(supervision_setting.missing_restart_limit(file)) == [7]
}

pub fn a_supervisor_module_imported_under_another_name_is_still_read_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/genesis_prime/login.gleam", [
      "//// A planted module.",
      "",
      "import gleam/otp/static_supervisor as tree",
      "",
      "pub fn bare() -> tree.Builder {",
      "  tree.new(tree.OneForOne)",
      "  |> tree.add(child())",
      "}",
      "",
      "pub fn stated() -> tree.Builder {",
      "  tree.new(tree.OneForOne)",
      "  |> tree.restart_tolerance(intensity: 3, period: 5)",
      "}",
    ])
  assert planted.lines(supervision_setting.missing_restart_limit(file)) == [6]
}

pub fn a_file_that_builds_no_supervisor_has_no_restart_limit_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/genesis_prime/login.gleam", [
      "//// A planted module.",
      "",
      "import genesis_prime/server",
      "",
      "pub fn tree() -> Int {",
      "  server.supervisor()",
      "  |> server.size",
      "}",
    ])
  assert supervision_setting.missing_restart_limit(file) == []
}

pub fn every_supervisor_under_src_states_its_restart_limit_test() -> Nil {
  use <- owned_test.run(5000)
  let breaches =
    repository.sources(["src"])
    |> list.flat_map(supervision_setting.missing_restart_limit)
  assert breaches == []
}

// Rule 2: every worker states its shutdown time.

pub fn a_worker_with_no_shutdown_time_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(supervision.worker(start))",
      ]),
    )
  let assert [breach] = supervision_setting.missing_shutdown_time(file)
    as "expected exactly one breach"
  assert breach.path == "src/genesis_prime/login.gleam"
  assert breach.line == 9
}

pub fn a_worker_that_states_its_shutdown_time_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  let listener =",
        "    supervision.worker(start)",
        "    |> supervision.timeout(ms: 1000)",
        "  let writer =",
        "    supervision.worker(start)",
        "    |> supervision.restart(supervision.Transient)",
        "    |> supervision.timeout(ms: 2000)",
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(listener)",
        "  |> static_supervisor.add(writer)",
      ]),
    )
  assert supervision_setting.missing_shutdown_time(file) == []
}

pub fn a_worker_written_as_an_argument_with_a_shutdown_time_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(",
        "    supervision.worker(start) |> supervision.timeout(ms: 1000),",
        "  )",
      ]),
    )
  assert supervision_setting.missing_shutdown_time(file) == []
}

pub fn a_worker_whose_shutdown_time_is_in_another_pipeline_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  let first = supervision.worker(start)",
        "  let second =",
        "    supervision.worker(start)",
        "    |> supervision.timeout(ms: 1000)",
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(first)",
        "  |> static_supervisor.add(second)",
      ]),
    )
  assert planted.lines(supervision_setting.missing_shutdown_time(file)) == [7]
}

pub fn a_supervisor_child_has_no_shutdown_time_to_state_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/login.gleam",
      static_module([
        "  static_supervisor.new(static_supervisor.OneForOne)",
        "  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)",
        "  |> static_supervisor.add(supervision.supervisor(start))",
        "  |> static_supervisor.add(static_supervisor.supervised(other()))",
      ]),
    )
  assert supervision_setting.missing_shutdown_time(file) == []
}

pub fn a_factory_worker_with_no_shutdown_time_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file(
      "src/genesis_prime/connection.gleam",
      list.flatten([
        factory_module([
          "  factory_supervisor.worker_child(start)",
          "  |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)",
        ]),
        [
          "",
          "pub fn stated() -> factory_supervisor.Builder(Int, Int) {",
          "  factory_supervisor.worker_child(start)",
          "  |> factory_supervisor.timeout(ms: 1000)",
          "  |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)",
          "}",
          "",
          "pub fn maps() -> factory_supervisor.Builder(Int, Int) {",
          "  factory_supervisor.supervisor_child(start)",
          "  |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)",
          "}",
        ],
      ]),
    )
  assert planted.lines(supervision_setting.missing_shutdown_time(file)) == [6]
}

pub fn a_supervision_module_imported_under_another_name_is_still_read_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted.file("src/genesis_prime/login.gleam", [
      "//// A planted module.",
      "",
      "import gleam/otp/supervision as child",
      "",
      "pub fn bare() -> child.ChildSpecification(Int) {",
      "  child.worker(start)",
      "}",
      "",
      "pub fn stated() -> child.ChildSpecification(Int) {",
      "  child.worker(start) |> child.timeout(ms: 1000)",
      "}",
    ])
  assert planted.lines(supervision_setting.missing_shutdown_time(file)) == [6]
}

pub fn every_worker_under_src_states_its_shutdown_time_test() -> Nil {
  use <- owned_test.run(5000)
  let breaches =
    repository.sources(["src"])
    |> list.flat_map(supervision_setting.missing_shutdown_time)
  assert breaches == []
}
