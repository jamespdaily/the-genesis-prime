//// The script runner that the dashboard's pollers and controls share, run on
//// real operating-system processes and planted scripts. Expected values are
//// the runner's contract (`dashboard/script`): the output and the status of a
//// script that ends, the reason for one that cannot run, one stream for the
//// standard output and the standard error (an Erlang port has no separate
//// stream), and a script past its deadline ended and gone.

import dashboard_support
import genesis_prime/dashboard/script.{
  DeadlineReached, Finished, NotExecutable, NotFound,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import owned_test
import simplifile

/// A row: the script planted (its text and permissions, or none), what it is
/// run with, and what the run must give for the path it was planted at.
type Row {
  Row(
    name: String,
    planted: Option(#(String, Int)),
    environment: List(#(String, String)),
    expected: fn(String) -> Result(script.Finished, script.Failure),
  )
}

fn ends_with(
  output: String,
  status: Int,
) -> fn(String) -> Result(script.Finished, a) {
  fn(_path) {
    Ok(Finished(output: bit_array.from_string(output), status: status))
  }
}

fn planted(text: String) -> Option(#(String, Int)) {
  Some(#("#!/bin/bash\n" <> text, 0o755))
}

pub fn a_script_gives_its_output_and_status_or_why_it_could_not_run_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [
    Row(
      "exit 0 with output",
      planted("printf 'hello\\nworld\\n'"),
      [],
      ends_with("hello\nworld\n", 0),
    ),
    Row(
      "exit 3 with output",
      planted("printf 'boom\\n'; exit 3"),
      [],
      ends_with("boom\n", 3),
    ),
    Row("no output", planted("exit 0"), [], ends_with("", 0)),
    Row(
      "the standard error lands in the output",
      planted("echo out; echo err >&2; echo again"),
      [],
      ends_with("out\nerr\nagain\n", 0),
    ),
    Row(
      "the environment is added to the script's",
      planted("printf '%s' \"$GENESIS_HOME\""),
      [#("GENESIS_HOME", "/planted/home")],
      ends_with("/planted/home", 0),
    ),
    Row(
      "200 KB of output arrives whole",
      planted("head -c 204800 /dev/zero | tr '\\0' x"),
      [],
      fn(_path) {
        Ok(Finished(
          output: bit_array.from_string(string.repeat("x", 204_800)),
          status: 0,
        ))
      },
    ),
    Row("a path that does not exist", None, [], fn(path) {
      Error(NotFound(path))
    }),
    Row(
      "a file that is not executable",
      Some(#("#!/bin/bash\necho no\n", 0o644)),
      [],
      fn(path) { Error(NotExecutable(path)) },
    ),
  ]
  list.each(rows, fn(row) {
    use home <- dashboard_support.with_home
    let path = home <> "/script.sh"
    case row.planted {
      Some(#(text, mode)) -> {
        let assert Ok(Nil) = simplifile.write(path, text)
        let assert Ok(Nil) = simplifile.set_permissions_octal(path, mode)
        Nil
      }
      None -> Nil
    }
    // The deadline never comes in these rows: every script ends at once.
    assert script.run(path:, environment: row.environment, deadline_ms: 600_000)
      == row.expected(path)
      as row.name
  })
}

pub fn a_script_past_its_deadline_is_ended_and_gone_test() -> Nil {
  use <- owned_test.run(60_000)

  // The script writes its process id and then becomes a `sleep`, keeping the id.
  use home <- dashboard_support.with_home
  let path = home <> "/sleeper.sh"
  let pid_file = home <> "/pid"
  let assert Ok(Nil) =
    simplifile.write(
      path,
      "#!/bin/bash\necho $$ > " <> pid_file <> "\nexec sleep 600\n",
    )
  let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o755)
  // A script that has not yet written its id when the deadline comes (a cold
  // start of the interpreter) shows nothing about being ended, so the run is
  // repeated with twice the deadline until the id is there.
  let pid =
    ended_after_writing_its_pid(
      path:,
      arguments: [],
      pid_file:,
      deadline_ms: 200,
    )
  assert !dashboard_support.process_alive(pid)
    as "the script is still running after the runner returned"

  // A script that ends before its deadline is not ended by it.
  let quick = home <> "/quick.sh"
  let assert Ok(Nil) = simplifile.write(quick, "#!/bin/bash\necho done\n")
  let assert Ok(Nil) = simplifile.set_permissions_octal(quick, 0o755)
  assert script.run(path: quick, environment: [], deadline_ms: 600_000)
    == Ok(Finished(output: <<"done\n":utf8>>, status: 0))
}

/// Runs the program with `arguments` until a run reaches its deadline after the
/// program wrote its process id to `pid_file`; gives that id. Every run must end
/// with the deadline's failure.
fn ended_after_writing_its_pid(
  path path: String,
  arguments arguments: List(String),
  pid_file pid_file: String,
  deadline_ms deadline_ms: Int,
) -> Int {
  let #(Nil, pid) =
    dashboard_support.until_pid_recorded(
      run: fn(deadline_ms) {
        let _removed = simplifile.delete(pid_file)
        assert script.run_with(path:, arguments:, environment: [], deadline_ms:)
          == Error(DeadlineReached(deadline_ms))
      },
      recorded: fn() { written_pid(pid_file) },
      deadline_ms:,
    )
  pid
}

/// The process id in the file, or none when the program has not written it.
fn written_pid(pid_file: String) -> List(Int) {
  case simplifile.read(pid_file) {
    Ok(text) -> {
      let assert Ok(pid) = int.parse(string.trim(text))
        as "the program wrote something other than its id"
      [pid]
    }
    Error(reason) -> {
      assert reason == simplifile.Enoent as "the id file could not be read"
      []
    }
  }
}

/// What the program planted by `printf_arguments` prints: each argument it was
/// given on a line of its own, between angle brackets.
fn printf_arguments(path: String) -> Nil {
  let assert Ok(Nil) =
    simplifile.write(
      path,
      "#!/bin/bash\nfor argument in \"$@\"; do printf '<%s>\\n' \"$argument\"; done\n",
    )
  let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o755)
  Nil
}

pub fn a_program_gets_its_arguments_whole_and_one_that_passes_its_deadline_is_gone_test() -> Nil {
  use <- owned_test.run(60_000)
  use home <- dashboard_support.with_home

  // Arguments reach the program as given: a space, a leading dash, quotes and
  // a dollar sign stay inside one argument, and no shell reads them.
  let path = home <> "/arguments.sh"
  printf_arguments(path)
  assert script.run_with(
      path:,
      arguments: [
        "a b",
        "-x",
        "--since",
        "it's \"quoted\"",
        "$HOME `id` ;",
        "",
      ],
      environment: [],
      deadline_ms: 600_000,
    )
    == Ok(Finished(
      output: bit_array.from_string(
        "<a b>\n<-x>\n<--since>\n<it's \"quoted\">\n<$HOME `id` ;>\n<>\n",
      ),
      status: 0,
    ))

  // The output is merged as `run`'s is: the standard error lands in it.
  let merged = home <> "/merged.sh"
  let assert Ok(Nil) =
    simplifile.write(
      merged,
      "#!/bin/bash\necho \"out $1\"; echo \"err $1\" >&2; exit 125\n",
    )
  let assert Ok(Nil) = simplifile.set_permissions_octal(merged, 0o755)
  assert script.run_with(
      path: merged,
      arguments: ["one"],
      environment: [],
      deadline_ms: 600_000,
    )
    == Ok(Finished(output: <<"out one\nerr one\n":utf8>>, status: 125))

  // A program that cannot run is refused as `run` refuses it.
  assert script.run_with(
      path: home <> "/missing",
      arguments: ["a"],
      environment: [],
      deadline_ms: 600_000,
    )
    == Error(NotFound(home <> "/missing"))

  // A program that blocks is ended at the deadline, and its recorded process id
  // is not alive when `run_with` returns.
  let sleeper = home <> "/sleeper.sh"
  let pid_file = home <> "/pid"
  let assert Ok(Nil) =
    simplifile.write(sleeper, "#!/bin/bash\necho $$ > \"$1\"\nexec sleep 600\n")
  let assert Ok(Nil) = simplifile.set_permissions_octal(sleeper, 0o755)
  let pid =
    ended_after_writing_its_pid(
      path: sleeper,
      arguments: [pid_file],
      pid_file:,
      deadline_ms: 200,
    )
  assert !dashboard_support.process_alive(pid)
    as "the program is still running after run_with returned"

  // A program on the search path is found by its name, and one that is not
  // there is not.
  assert script.find_on_path("sh") |> result.map(string.ends_with(_, "/sh"))
    == Ok(True)
  assert script.find_on_path("no-such-program-for-the-dashboard") == Error(Nil)

  // `run` with no arguments answers as before.
  assert script.run(path:, environment: [], deadline_ms: 600_000)
    == Ok(Finished(output: <<"":utf8>>, status: 0))
}
