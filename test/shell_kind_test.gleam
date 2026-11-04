//// A shell is handed only the effects its kind carries out: a rule that
//// returns a service's effect to the connection shell, or a connection's
//// effect to the service shell, does not compile. The real shells, with the
//// modules they import and the Erlang files those call, are copied into a
//// scratch Gleam project beside a planted module that hands each shell a rule,
//// and `gleam build` builds it. Each shell is first given a rule of its own
//// kind, which builds, so a failure of the other rule is the effect's and not
//// the scratch project's. Expected values come from these places.
//// - The shells' carry code (`genesis_prime/connection/shell` `carry_effect`,
////   `genesis_prime/service/shell` `carry`): the connection shell carries
////   `Write`, the service shell `Reply`, and neither the other's.
//// - The compiler: a rule whose step returns an effect type other than the
////   shell's own is a type mismatch, whose message names both types.
//// - The scratch project depends on the project's own copies of the packages
////   the shells use (`build/packages`) by path, so no package is fetched.

import gleam/list
import gleam/string
import owned_test
import recording_support
import scratch_project
import simplifile

/// The project's modules and Erlang files the two shells need, as paths under
/// `src`.
const sources = [
  "genesis_prime/seed.gleam",
  "genesis_prime/step.gleam",
  "genesis_prime/step/runtime.gleam",
  "genesis_prime/step/timer.gleam",
  "genesis_prime/step/watch.gleam",
  "genesis_prime/world_map/map_id.gleam",
  "genesis_prime/world_map/spawn.gleam",
  "genesis_prime/world_map/spawn_id.gleam",
  "genesis_prime/world_map/warfare_woods.gleam",
  "genesis_prime/game/start_place.gleam",
  "genesis_prime/message/float32.gleam",
  "genesis_prime/table/id.gleam",
  "genesis_prime/table/creature2.gleam",
  "genesis_prime/table/creature2_arche_type.gleam",
  "genesis_prime/table/creature2_difficulty.gleam",
  "genesis_prime/table/creature2_display_group_entry.gleam",
  "genesis_prime/table/creature2_display_info.gleam",
  "genesis_prime/table/creature2_override_properties.gleam",
  "genesis_prime/table/creature2_resist.gleam",
  "genesis_prime/table/creature2_tier.gleam",
  "genesis_prime/table/creature_level.gleam",
  "genesis_prime/table/world_location2.gleam",
  "genesis_prime/table/loader/store.gleam",
  "genesis_prime/table/loader/tbl_file.gleam",
  "genesis_prime_tbl_file_ffi.erl",
  "genesis_prime/wire_recording.gleam",
  "genesis_prime/wire_recording/recorder.gleam",
  "genesis_prime/service.gleam",
  "genesis_prime/genesis_prime_service_ffi.erl",
  "genesis_prime/group_registry.gleam",
  "genesis_prime/genesis_prime_group_registry_ffi.erl",
  "genesis_prime/service/shell.gleam",
  "genesis_prime/connection/frame.gleam",
  "genesis_prime/connection/script.gleam",
  "genesis_prime/connection/shell.gleam",
  "genesis_prime/connection/genesis_prime_connection_shell_ffi.erl",
  "genesis_prime/connection/registry.gleam",
  "genesis_prime_step_runtime_ffi.erl",
]

/// The packages the shells import, found in `build/packages`.
const packages = [
  "gleam_stdlib", "gleam_erlang", "gleam_otp", "gleam_crypto", "gleam_json",
  "simplifile", "filepath", "gleam_community_maths",
]

pub fn a_rule_that_answers_a_caller_does_not_compile_against_the_connection_shell_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let project = shells_project(folder)
  planted(project, "connection_writes")
  let assert Ok(_built) = build(project)
    as "a connection rule that writes builds against the connection shell"
  planted(project, "connection_replies")
  let assert Error(#(_status, output)) = build(project)
    as "a connection rule that answers a caller does not build"
  assert string.contains(output, "Type mismatch")
    && string.contains(output, "ConnectionEffect")
    && string.contains(output, "ServiceEffect")
    as { "the compiler names both effect types; it said: " <> output }
}

pub fn a_rule_that_writes_to_a_socket_does_not_compile_against_the_service_shell_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let project = shells_project(folder)
  planted(project, "service_replies")
  let assert Ok(_built) = build(project)
    as "a service rule that answers a caller builds against the service shell"
  planted(project, "service_writes")
  let assert Error(#(_status, output)) = build(project)
    as "a service rule that writes does not build"
  assert string.contains(output, "Type mismatch")
    && string.contains(output, "ConnectionEffect")
    && string.contains(output, "ServiceEffect")
    as { "the compiler names both effect types; it said: " <> output }
}

/// A scratch project in `folder` that holds a copy of every source the shells
/// need, and its path.
fn shells_project(folder: String) -> String {
  let project =
    scratch_project.create(folder:, name: "planted_shell", packages:)
  list.each(sources, fn(source) {
    let assert Ok(text) = simplifile.read("src/" <> source)
      as { "the source " <> source <> " reads" }
    scratch_project.write_file(project:, path: "src/" <> source, text:)
  })
  project
}

/// Makes the scratch project's one planted module the file `name`, in
/// `test/planted_shell`; the module before it is replaced.
fn planted(project: String, name: String) -> Nil {
  let assert Ok(text) =
    simplifile.read("test/planted_shell/" <> name <> ".gleam.txt")
    as "the planted module reads"
  scratch_project.write_file(project:, path: "src/planted_shell.gleam", text:)
}

/// Builds the scratch project, with the compiler's whole output on either
/// side.
fn build(project: String) -> Result(String, #(Int, String)) {
  scratch_project.gleam(project:, arguments: ["build"])
}
