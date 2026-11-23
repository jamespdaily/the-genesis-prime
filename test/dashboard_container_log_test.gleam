//// What a container's log read is made of: podman's output split into lines
//// and its own words, the cursor that keeps a line from showing twice, the
//// container's id that tells a continued container from a replaced one, and the
//// one reason each failure of podman gives. The rules are pure and run on rows
//// of the texts podman printed (`test/fixture/otp_log`, and the measured error
//// texts); the follower's rules run with a reader the test answers, and the
//// real reader runs the planted fake `podman` of the play service's tests. No
//// test waits on a clock: the interval is a day and a tick is a message.

import genesis_prime/dashboard/container_log
import genesis_prime/dashboard/log_lines.{DatabaseLog, ServerLog}
import gleam/list
import gleam/string
import owned_test
import simplifile

// ---------------------------------------------------------------------------
// The two containers are the two the scripts name.

pub fn the_followed_containers_are_the_two_the_scripts_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(library) = simplifile.read("dev/play_service/lib.sh")
    as "the play service's library is in the repository"
  let value_of = fn(name) {
    let assert [assignment] =
      string.split(library, "\n")
      |> list.filter(string.starts_with(_, name <> "="))
      as { "lib.sh sets " <> name <> " once" }
    string.drop_start(assignment, string.length(name) + 1)
  }
  assert container_log.server_container == value_of("server_container")
  assert container_log.database_container == value_of("postgres_container")
  assert container_log.container_name(ServerLog)
    == Ok(container_log.server_container)
  assert container_log.container_name(DatabaseLog)
    == Ok(container_log.database_container)
  assert container_log.container_name(log_lines.UpdaterLog) == Error(Nil)
  assert container_log.container_name(log_lines.LaunchdLog) == Error(Nil)
  assert !string.starts_with(container_log.server_container, "-")
  assert !string.starts_with(container_log.database_container, "-")
}
