//// Runs a test body in a process the test owns, so a hung test fails and
//// what a test started stops with it. Every test body runs inside `run`.

import gleam/erlang/process

pub type Outcome(a) {
  Returned(a)
  Crashed
}

/// Runs a test body in its own process, with a deadline. When the body
/// returns, crashes or runs past the deadline, that process is killed, so
/// every process linked to it stops too.
pub fn run(timeout_ms: Int, body: fn() -> a) -> a {
  let reply = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      process.send(reply, body())
      process.sleep_forever()
    })
  let monitor = process.monitor(worker)
  let outcome =
    process.new_selector()
    |> process.select_map(reply, Returned)
    |> process.select_specific_monitor(monitor, fn(_down) { Crashed })
    |> process.selector_receive(within: timeout_ms)
  process.kill(worker)
  case outcome {
    Ok(Returned(value)) -> value
    Ok(Crashed) -> panic as "the test body crashed"
    Error(Nil) -> panic as "the test ran past its deadline"
  }
}
