//// When the updater's deploy waits for a game connection and when it does not
//// (`game_connection_open`, `deploy_waits`, `forget_closed_wait` and
//// `image_inputs` of `dev/play_service/lib.sh`), run against planted recordings
//// and a planted bare repository (`play_service_support`). Expected values are
//// `update.sh`'s header: a stopped server has no connection to wait for, a wait
//// is counted from its first run and starts again after a run that found no
//// connection open, a recording the server stopped writing is not a connection,
//// and a Containerfile form the reader does not know is never taken as "no
//// change". The 5-minute freshness is checked against the game recordings in
//// `~/.genesis-prime/sittings`: the longest gap between two read lines of a live
//// connection in them is 10 seconds (the client pings every 30 seconds).

import gleam/list
import gleam/string
import owned_test
import play_service_support.{type Scene} as support
import simplifile

const deployed = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const main = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const read_line = "{\"sequence\":2,\"in\":\"read\"}"

const closed_line = "{\"sequence\":3,\"closed\":\"client\"}"

fn recording_name() -> String {
  "sittings/2026-11-28-100000-play-"
  <> deployed
  <> "/genesis_prime.game.connection-1.jsonl"
}

/// A recording of the deployed commit's server: `last` is its last line.
fn plant_recording(scene: Scene, last last: String) -> Nil {
  support.plant_home_file(
    scene:,
    name: recording_name(),
    text: "{\"sequence\":1,\"in\":\"accepted\"}\n" <> last <> "\n",
  )
}

fn returns(scene: Scene, commands: String) -> Result(Int, Nil) {
  support.returned(support.run_library(scene:, commands:, extra: []))
}

/// A `deploy_waits` of the main commit with the deployed commit's server
/// `running` (`true` or `false`).
fn wait(running: String) -> String {
  "mkdir -p \"$state\"; deployed_commit="
  <> deployed
  <> " running="
  <> running
  <> "; deploy_waits "
  <> main
}

fn wait_clock_path(scene: Scene) -> String {
  scene.home <> "/play-service/waiting_since"
}

pub fn a_recording_the_server_stopped_writing_is_no_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let open = "game_connection_open " <> deployed
  {
    use scene <- support.with_scene
    plant_recording(scene, last: read_line)
    assert returns(scene, open) == Ok(0) as "a recording being written is open"
  }
  {
    use scene <- support.with_scene
    plant_recording(scene, last: read_line)
    support.make_old(scene.home <> "/" <> recording_name())
    assert returns(scene, open) == Ok(1)
      as "a crashed connection's recording, untouched for minutes, is not open"
  }
  {
    use scene <- support.with_scene
    plant_recording(scene, last: closed_line)
    assert returns(scene, open) == Ok(1) as "a closed recording is not open"
  }
}

pub fn a_stopped_server_is_not_waited_for_test() -> Nil {
  use <- owned_test.run(10_000)
  use scene <- support.with_scene
  plant_recording(scene, last: read_line)
  assert returns(scene, wait("true")) == Ok(0)
    as "a running server with a connection open is waited for"
  assert returns(scene, wait("false")) == Ok(1)
    as "a stopped server's recording is no connection to wait for"
}

pub fn a_wait_starts_again_after_a_run_that_found_no_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  use scene <- support.with_scene
  // A wait that began long ago, then a connection that closed.
  support.plant_home_file(
    scene:,
    name: "play-service/waiting_since",
    text: deployed <> " 1\n",
  )
  plant_recording(scene, last: closed_line)
  assert returns(scene, "forget_closed_wait") == Ok(0)
  assert simplifile.is_file(wait_clock_path(scene)) == Ok(False)
    as "a run that finds no connection open forgets the wait"
  // Another player connects; the next wait is counted from now.
  plant_recording(scene, last: read_line)
  assert returns(scene, wait("true")) == Ok(0)
    as "a later commit waits afresh, it does not deploy at once"
}

pub fn a_wait_goes_on_while_the_connection_stays_open_test() -> Nil {
  use <- owned_test.run(10_000)
  use scene <- support.with_scene
  support.plant_home_file(
    scene:,
    name: "play-service/waiting_since",
    text: deployed <> " 1\n",
  )
  plant_recording(scene, last: read_line)
  assert returns(scene, "forget_closed_wait") == Ok(0)
  assert simplifile.is_file(wait_clock_path(scene)) == Ok(True)
    as "an open connection keeps its wait's clock"
  assert returns(scene, wait("true")) == Ok(1)
    as "a wait past its limit deploys"
}

/// Shell that makes a bare repository in `$state/repository.git` of one commit
/// holding the Containerfile `containerfile`, `src/a` and `priv/migrations/1.sql`,
/// and sets `commit` to it.
fn repository(containerfile: String) -> String {
  "rm -rf \"$state/repository.git\"; git init -q --bare \"$state/repository.git\"; "
  <> "w=$(mktemp -d); cd \"$w\"; git init -q .; mkdir -p release src priv/migrations; "
  <> "printf '%s\\n' '"
  <> containerfile
  <> "' >release/Containerfile; echo a >src/a; echo m >priv/migrations/1.sql; "
  <> "git add -A; git -c user.name=t -c user.email=t@t commit -q -m c; "
  <> "git push -q \"$state/repository.git\" HEAD:refs/heads/main; cd - >/dev/null; "
  <> "commit=$(git -C \"$state/repository.git\" rev-parse main); "
}

pub fn an_image_input_form_the_reader_does_not_know_is_not_taken_as_no_change_test() -> Nil {
  use <- owned_test.run(10_000)
  let rows = [
    #("a plain COPY", "FROM x\nCOPY src src\nRUN true", True),
    #(
      "a source named by two COPY lines",
      "FROM x\nCOPY src src\nCOPY src s2",
      True,
    ),
    #("a COPY from ./", "FROM x\nCOPY ./src src", True),
    #("an ADD", "FROM x\nADD src src", False),
    #("a continued COPY", "FROM x\nCOPY src \\\n  src", False),
    #("the JSON form", "FROM x\nCOPY [\"src\", \"src\"]", False),
    #("a source no file matches", "FROM x\nCOPY nothing /n", False),
    #("a variable in a source", "FROM x\nCOPY $dir /n", False),
  ]
  list.each(rows, fn(row) {
    let #(name, containerfile, reads) = row
    use scene <- support.with_scene
    let ran =
      support.run_library(
        scene:,
        commands: repository(containerfile) <> "image_inputs \"$commit\"",
        extra: [],
      )
    let expected = case reads {
      True -> Ok(0)
      False -> Ok(1)
    }
    assert support.returned(ran) == expected as { name <> ": " <> ran.output }
    assert reads || string.contains(support.log_of(scene), "image inputs")
      as { name <> ": the log says why: " <> support.log_of(scene) }
  })
}

pub fn the_containerfile_is_an_image_input_test() -> Nil {
  use <- owned_test.run(10_000)
  use scene <- support.with_scene
  let both =
    repository("FROM x\nCOPY src src\nRUN one")
    <> "first=$(image_inputs \"$commit\"); "
    <> repository("FROM x\nCOPY src src\nRUN two")
    <> "second=$(image_inputs \"$commit\"); "
    <> "[ -n \"$first\" ] && [ \"$first\" != \"$second\" ]"
  let ran = support.run_library(scene:, commands: both, extra: [])
  assert support.returned(ran) == Ok(0)
    as { "a RUN line of the Containerfile changes the inputs: " <> ran.output }
}
