//// A shell is handed only the effects its kind carries out: a rule that
//// returns a service's effect to the connection shell, or a connection's
//// effect to the service shell, does not compile. The real shells, with the
//// modules they import and the Erlang files those call, are copied into a
//// scratch Gleam project beside a planted module that hands each shell a rule,
//// and `gleam build` builds it. Each shell is first given a rule of its own
//// kind, which builds, so a failure of the other rule is the effect's and not
//// the scratch project's. Expected values come from these places.
//// - The shells' carry code (`genesis_prime/connection/shell` `carry`,
////   `genesis_prime/service/shell` `carry`): the connection shell carries
////   `Write`, the service shell `Reply`, and neither the other's.
//// - The compiler: a rule whose step returns an effect type other than the
////   shell's own is a type mismatch, whose message names both types.
//// - The scratch project depends on the project's own copies of the packages
////   the shells use (`build/packages`) by path, so no package is fetched.

import filepath
import gleam/list
import gleam/string
import owned_test
import recording_support
import shellout
import simplifile

/// The project's modules and Erlang files the two shells need, as paths under
/// `src`.
const sources = [
  "genesis_prime/step.gleam",
  "genesis_prime/step/runtime.gleam",
  "genesis_prime/step/watch.gleam",
  "genesis_prime/world_map/map_id.gleam",
  "genesis_prime/rule_recording.gleam",
  "genesis_prime/rule_recording_ffi.erl",
  "genesis_prime/rule_recording/file.gleam",
  "genesis_prime/service.gleam",
  "genesis_prime/service_ffi.erl",
  "genesis_prime/service/shell.gleam",
  "genesis_prime/connection/shell.gleam",
  "genesis_prime/connection/connection_shell_ffi.erl",
  "genesis_prime/connection/registry.gleam",
  "genesis_prime/connection/connection_registry_ffi.erl",
  "step_runtime_ffi.erl",
]

/// The packages the shells import, found in `build/packages`.
const packages = [
  "gleam_stdlib", "gleam_erlang", "gleam_otp", "gleam_crypto", "simplifile",
  "filepath",
]

pub fn a_rule_that_answers_a_caller_does_not_compile_against_the_connection_shell_test() -> Nil {
  use <- owned_test.run(180_000)
  use folder <- recording_support.in_folder
  let project = scratch_project(folder)
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
  let project = scratch_project(folder)
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

/// Writes the scratch project's `gleam.toml` and a copy of every source the
/// shells need into `folder`, and gives its path.
fn scratch_project(folder: String) -> String {
  let assert Ok(root) = simplifile.current_directory()
    as "the working directory is known"
  let project = root <> "/" <> folder
  let dependencies =
    list.map(packages, fn(package) {
      package
      <> " = { path = \""
      <> root
      <> "/build/packages/"
      <> package
      <> "\" }"
    })
  write(
    project <> "/gleam.toml",
    "name = \"planted_shell\"\nversion = \"0.1.0\"\n\n[dependencies]\n"
      <> string.join(dependencies, "\n")
      <> "\n",
  )
  list.each(sources, fn(source) {
    let assert Ok(text) = simplifile.read("src/" <> source)
      as { "the source " <> source <> " reads" }
    write(project <> "/src/" <> source, text)
  })
  project
}

/// Makes the scratch project's one planted module the file `name`, in
/// `test/planted_shell`; the module before it is replaced.
fn planted(project: String, name: String) -> Nil {
  let assert Ok(text) =
    simplifile.read("test/planted_shell/" <> name <> ".gleam.txt")
    as "the planted module reads"
  write(project <> "/src/planted_shell.gleam", text)
}

fn write(path: String, text: String) -> Nil {
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.directory_name(path))
    as "the project's folder was made"
  let assert Ok(Nil) = simplifile.write(path, text)
    as "the project's file was written"
  Nil
}

/// Builds the scratch project, with the compiler's whole output on either
/// side.
fn build(project: String) -> Result(String, #(Int, String)) {
  shellout.command(run: "gleam", with: ["build"], in: project, opt: [])
}
