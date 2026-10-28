//// Writes the message codec from the schema, run as
//// `gleam run -m genesis_prime/generate_messages`. With `check` after `--` it
//// writes nothing and exits non-zero naming each committed file that differs
//// from what the schema generates; the full check runs it that way.

import argv
import genesis_prime/message_generator.{
  type GeneratedFile, type Mismatch, Edited, Missing, Stale,
}
import gleam/int
import gleam/io
import gleam/list
import simplifile

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Generates the codec, or checks the committed one.
pub fn main() -> Nil {
  case argv.load().arguments {
    [] -> generate()
    ["check"] -> check()
    _ -> {
      io.println_error(
        "usage: gleam run -m genesis_prime/generate_messages [-- check]",
      )
      halt(2)
    }
  }
}

fn generate() -> Nil {
  let generated = generated_files()
  list.each(generated, fn(file) { write(file.path, file.text) })
  let stale =
    message_generator.mismatches(generated, committed_files())
    |> list.filter_map(fn(mismatch) {
      case mismatch {
        Stale(path) -> Ok(path)
        Edited(_) | Missing(_) -> Error(Nil)
      }
    })
  list.each(stale, fn(path) {
    case simplifile.delete(path) {
      Ok(Nil) -> io.println("removed " <> path)
      Error(error) ->
        stop(
          "could not remove "
          <> path
          <> ": "
          <> simplifile.describe_error(error),
        )
    }
  })
  io.println(
    "wrote "
    <> int.to_string(list.length(generated))
    <> " message modules from "
    <> message_generator.schema_path,
  )
}

fn check() -> Nil {
  case message_generator.mismatches(generated_files(), committed_files()) {
    [] -> io.println("the committed message codec is what the schema generates")
    mismatches -> {
      list.each(mismatches, fn(mismatch) {
        io.println_error(describe(mismatch))
      })
      io.println_error(
        "run `gleam run -m genesis_prime/generate_messages` and commit the result",
      )
      halt(1)
    }
  }
}

fn describe(mismatch: Mismatch) -> String {
  case mismatch {
    Edited(path:) -> path <> " differs from what the schema generates"
    Missing(path:) -> path <> " is generated from the schema and not committed"
    Stale(path:) -> path <> " is generated but the schema no longer has it"
  }
}

fn generated_files() -> List(GeneratedFile) {
  case message_generator.generated_files() {
    Ok(files) -> files
    Error(failure) -> stop(message_generator.describe_failure(failure))
  }
}

fn committed_files() -> List(GeneratedFile) {
  case message_generator.committed_files() {
    Ok(files) -> files
    Error(failure) -> stop(message_generator.describe_failure(failure))
  }
}

fn write(path: String, text: String) -> Nil {
  case simplifile.write(path, text) {
    Ok(Nil) -> Nil
    Error(error) ->
      stop(
        "could not write " <> path <> ": " <> simplifile.describe_error(error),
      )
  }
}

/// Prints a problem and ends the program with status 1. It never returns, and
/// has the type of whatever the caller needed.
fn stop(problem: String) -> a {
  io.println_error(problem)
  halt(1)
  panic as "the program ended with halt"
}
