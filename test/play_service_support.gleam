//// Scenes for the tests of the play service's shell scripts (`dev/play_service`):
//// a folder of its own holding a planted `GENESIS_HOME` and a folder of fake
//// `podman` and `lsof` (`play_service_fake_tool.sh`), and a run of a script or
//// of a `lib.sh` function through `/usr/bin/env -i` with a `PATH` of the fakes
//// then `/usr/bin:/bin` only. The real `podman` and `lsof` are not on that
//// path, so a call a test did not plan fails closed and CI needs no Podman.
////
//// `state.sh` waits for a bounded call by looks; each run's `look` is the fake
//// `play_service_fake_look.sh`, so a call that answers never outlasts its bound
//// and a blocked call is ended after its counted looks, whatever the load.
////
//// Real `ps`, `sed`, `find`, `kill` and `touch` run: a lock owner is a real
//// process, and its `started` text is read by `ps`.

import envoy
import filepath
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import planted_table
import shellout
import simplifile

/// A test's own folder: `home` is the planted `GENESIS_HOME`, `fakes` holds the
/// fake tools, their `answers` and their `calls` log.
pub type Scene {
  Scene(folder: String, home: String, fakes: String)
}

/// What a fake tool does on a call: the exit statuses in turn (the last one
/// stands for later calls), and what it prints.
pub type Answer {
  Answer(exits: List(Int), output: String, error: String)
}

/// One run of a script or function: everything it printed (standard error
/// included) and its exit status.
pub type Ran {
  Ran(output: String, status: Int)
}

/// An answer that exits 0 and prints nothing.
pub const quiet = Answer(exits: [0], output: "", error: "")

/// Runs the body with a scene of its own, removed afterwards.
pub fn with_scene(body body: fn(Scene) -> a) -> a {
  use folder <- planted_table.with_folder(result.unwrap(
    envoy.get("TMPDIR"),
    "/tmp",
  ))
  let scene = Scene(folder:, home: folder <> "/home", fakes: folder <> "/fakes")
  let assert Ok(Nil) = simplifile.create_directory_all(scene.home)
  let assert Ok(Nil) =
    simplifile.create_directory_all(scene.fakes <> "/answers")
  let assert Ok(tool) = simplifile.read("test/play_service_fake_tool.sh")
    as "the fake tool's script is in the repository"
  list.each(["podman", "lsof"], fn(name) {
    let path = scene.fakes <> "/" <> name
    let assert Ok(Nil) = simplifile.write(path, tool)
    let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o755)
  })
  let assert Ok(look) = simplifile.read("test/play_service_fake_look.sh")
    as "the fake look's script is in the repository"
  let look_path = scene.fakes <> "/look"
  let assert Ok(Nil) = simplifile.write(look_path, look)
  let assert Ok(Nil) = simplifile.set_permissions_octal(look_path, 0o755)
  body(scene)
}

/// Plants what the fake tools answer to the call `key` names (see
/// `play_service_fake_tool.sh`).
pub fn plant(
  scene scene: Scene,
  key key: String,
  answer answer: Answer,
) -> Nil {
  let base = scene.fakes <> "/answers/" <> key
  let exits = list.map(answer.exits, int.to_string)
  let assert Ok(Nil) =
    simplifile.write(base <> ".exit", string.join(exits, "\n") <> "\n")
  let assert Ok(Nil) = simplifile.write(base <> ".out", answer.output)
  case answer.error {
    "" -> Nil
    error -> {
      let assert Ok(Nil) = simplifile.write(base <> ".err", error)
      Nil
    }
  }
}

/// Makes the call `key` names wait until its caller ends it, and record its
/// process id.
pub fn plant_block(scene scene: Scene, key key: String) -> Nil {
  let assert Ok(Nil) =
    simplifile.write(scene.fakes <> "/answers/" <> key <> ".block", "")
  Nil
}

/// The process ids the blocked call `key` recorded, one per call.
pub fn blocked_pids(scene scene: Scene, key key: String) -> List(Int) {
  result.unwrap(simplifile.read(blocked_pid_path(scene:, key:)), "")
  |> string.split("\n")
  |> list.filter_map(fn(line) { int.parse(string.trim(line)) })
}

/// The file whose presence holds every look of a bounded call; a test's shell
/// removes it to let the looks go on.
pub fn look_hold_path(scene scene: Scene) -> String {
  scene.fakes <> "/look.hold"
}

/// Holds every look of a bounded call until the file at `look_hold_path` is
/// removed; the first look records the process id of the shell that waits for
/// the call.
pub fn hold_looks(scene scene: Scene) -> Nil {
  let assert Ok(Nil) = simplifile.write(look_hold_path(scene:), "")
  Nil
}

/// The path of the file that holds the process id of the shell that waits for
/// a call whose looks are held.
pub fn look_waiter_path(scene: Scene) -> String {
  scene.fakes <> "/look.waiter"
}

/// The path of the file the blocked call `key` records its process id in.
pub fn blocked_pid_path(scene scene: Scene, key key: String) -> String {
  scene.fakes <> "/answers/" <> key <> ".pid"
}

/// The key of `podman info`.
pub const info = "info"

/// The key of `podman container exists NAME`.
pub fn exists(name: String) -> String {
  "exists." <> name
}

/// The key of the status inspect of container `name`.
pub fn status(name: String) -> String {
  "status." <> name
}

/// The key of the labels inspect of container `name`.
pub fn labels(name: String) -> String {
  "labels." <> name
}

/// The key of `podman exec ... pg_isready`.
pub const ready = "ready"

/// The key of `podman machine start`.
pub const machine_start = "machine.start"

/// The key of `lsof`.
pub const connections = "connections"

/// Plants a container that exists with this status.
pub fn plant_status(
  scene scene: Scene,
  name name: String,
  status word: String,
) -> Nil {
  plant(scene:, key: exists(name), answer: quiet)
  plant(
    scene:,
    key: status(name),
    answer: Answer(..quiet, output: word <> "\n"),
  )
}

/// Plants a container that exists with this status and these labels
/// (`REVISION ADDRESS RUNNING`, as `server_state` reads them).
pub fn plant_container(
  scene scene: Scene,
  name name: String,
  status word: String,
  labels line: String,
) -> Nil {
  plant_status(scene:, name:, status: word)
  plant(
    scene:,
    key: labels(name),
    answer: Answer(..quiet, output: line <> "\n"),
  )
}

/// Every call the fake tools recorded, in order, as `TOOL ARGUMENTS`.
pub fn calls(scene: Scene) -> List(String) {
  result.unwrap(simplifile.read(scene.fakes <> "/calls"), "")
  |> string.split("\n")
  |> list.filter(fn(line) { line != "" })
}

/// The shell the scripts run in: `/bin/bash` (3.2 on a Mac, which launchd
/// runs) where it exists.
fn bash() -> String {
  case simplifile.is_file("/bin/bash") {
    Ok(True) -> "/bin/bash"
    _ -> "bash"
  }
}

fn environment(
  scene scene: Scene,
  extra extra: List(#(String, String)),
) -> List(String) {
  list.flatten([
    [
      "-i",
      "PATH=" <> scene.fakes <> ":/usr/bin:/bin",
      "GENESIS_HOME=" <> scene.home,
      "FAKE_DIR=" <> scene.fakes,
      "TMPDIR=" <> scene.folder,
      "GENESIS_PLAY_LOOK_COMMAND=" <> scene.fakes <> "/look",
    ],
    list.map(extra, fn(pair) { pair.0 <> "=" <> pair.1 }),
  ])
}

fn ran(result: Result(String, #(Int, String))) -> Ran {
  case result {
    Ok(output) -> Ran(output:, status: 0)
    Error(#(status, output)) -> Ran(output:, status:)
  }
}

/// Runs the repository's script `path` with the scene's environment and these
/// extra variables.
pub fn run_script(
  scene scene: Scene,
  script path: String,
  extra extra: List(#(String, String)),
) -> Ran {
  ran(
    shellout.command(
      run: "/usr/bin/env",
      with: list.append(environment(scene:, extra:), [bash(), path]),
      in: ".",
      opt: [],
    ),
  )
}

/// Runs `commands` in a shell that has sourced `lib.sh`, so a function of it is
/// called as the scripts call it. The run ends by printing `returned N` with
/// the last command's exit status.
pub fn run_library(
  scene scene: Scene,
  commands commands: String,
  extra extra: List(#(String, String)),
) -> Ran {
  run_shell(
    scene:,
    commands: ". dev/play_service/lib.sh; "
      <> commands
      <> "; echo \"returned $?\"",
    extra:,
  )
}

/// Runs `commands` in a shell with the scene's environment.
pub fn run_shell(
  scene scene: Scene,
  commands commands: String,
  extra extra: List(#(String, String)),
) -> Ran {
  ran(
    shellout.command(
      run: "/usr/bin/env",
      with: list.append(environment(scene:, extra:), [bash(), "-c", commands]),
      in: ".",
      opt: [],
    ),
  )
}

/// The `key=value` lines of a report, by key; a line with no `=` is left out.
pub fn report(ran ran: Ran) -> Dict(String, String) {
  ran.output
  |> string.split("\n")
  |> list.filter_map(string.split_once(_, "="))
  |> dict.from_list
}

/// The operating-system process id of the test's own VM: a live lock owner.
@external(erlang, "play_service_support_ffi", "os_pid")
pub fn os_pid() -> Int

/// The process id of a process that has ended: no process holds it now.
pub fn ended_pid() -> Int {
  let assert Ok(output) =
    shellout.command(run: "/bin/sh", with: ["-c", "echo $$"], in: ".", opt: [])
    as "the shell ran"
  let assert Ok(pid) = int.parse(string.trim(output))
  pid
}

/// Whether a process with this id exists.
pub fn alive(pid pid: Int) -> Bool {
  result.is_ok(
    shellout.command(
      run: "kill",
      with: ["-0", int.to_string(pid)],
      in: ".",
      opt: [],
    ),
  )
}

/// The text `ps` gives for when process `pid` started, as the lock's owner
/// record keeps it (blanks collapsed); empty when no such process exists.
pub fn started_text(pid pid: Int) -> String {
  let text =
    shellout.command(
      run: "ps",
      with: ["-o", "lstart=", "-p", int.to_string(pid)],
      in: ".",
      opt: [],
    )
    |> result.unwrap("")
  text
  |> string.split(" ")
  |> list.map(string.trim)
  |> list.filter(fn(word) { word != "" })
  |> string.join(" ")
}

/// Makes the file or folder at `path` over a minute old.
pub fn make_old(path path: String) -> Nil {
  let assert Ok(_) =
    shellout.command(
      run: "touch",
      with: ["-t", "200001010000", path],
      in: ".",
      opt: [],
    )
  Nil
}

/// Makes the file or folder at `path` newer than any minute the test can take:
/// its time is far ahead, so it is under a minute old whatever the load.
pub fn make_young(path path: String) -> Nil {
  let assert Ok(_) =
    shellout.command(
      run: "touch",
      with: ["-t", "209901010000", path],
      in: ".",
      opt: [],
    )
  Nil
}

/// An owner record as `live_lock.sh` writes it: one `key=value` line per field.
pub fn owner_record(
  kind kind: String,
  folder folder: String,
  pid pid: Int,
  started started: String,
) -> String {
  "token=planted\nkind="
  <> kind
  <> "\nfolder="
  <> folder
  <> "\npid="
  <> int.to_string(pid)
  <> "\nstarted="
  <> started
  <> "\ncommit=planted\n"
}

/// The path of the live lock's folder.
pub fn live_lock_path(scene: Scene) -> String {
  scene.home <> "/live.lock"
}

/// The path of the update lock's folder.
pub fn update_lock_path(scene: Scene) -> String {
  scene.home <> "/play-service/update.lock"
}

/// Plants the live lock: its folder, and its owner record when there is one.
pub fn plant_live_lock(
  scene scene: Scene,
  record record: Option(String),
) -> Nil {
  plant_lock(live_lock_path(scene), record)
}

/// Plants the update lock: its folder, and its owner file (a process id) when
/// there is one.
pub fn plant_update_lock(scene scene: Scene, owner owner: Option(Int)) -> Nil {
  plant_lock(
    update_lock_path(scene),
    option.map(owner, fn(pid) { int.to_string(pid) <> "\n" }),
  )
}

fn plant_lock(folder: String, record: Option(String)) -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
  case record {
    Some(text) -> {
      let assert Ok(Nil) = simplifile.write(folder <> "/owner", text)
      Nil
    }
    None -> Nil
  }
}

/// Writes `text` to the file `name` under the home, with its folders made.
pub fn plant_home_file(
  scene scene: Scene,
  name name: String,
  text text: String,
) -> Nil {
  let path = scene.home <> "/" <> name
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.directory_name(path))
  let assert Ok(Nil) = simplifile.write(path, text)
  Nil
}

/// The hold the way `stop.sh --hold` makes it.
pub fn plant_hold(scene: Scene) -> Nil {
  plant_home_file(scene:, name: "play-service/held", text: "")
}

/// The status a `run_library` run ended with, from its last line.
pub fn returned(ran ran: Ran) -> Result(Int, Nil) {
  let lines = list.filter(string.split(ran.output, "\n"), fn(l) { l != "" })
  case list.last(lines) {
    Ok(line) ->
      case string.split_once(line, "returned ") {
        Ok(#("", number)) -> int.parse(number)
        _ -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}
