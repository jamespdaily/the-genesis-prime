//// A planted test for the repeat job's proof: it passes alone and depends on timing.

import ask_support
import gleam/erlang/process

pub fn fifty_milliseconds_of_work_ends_within_sixty_test() {
  let started = ask_support.monotonic_ms()
  process.sleep(50)
  assert ask_support.monotonic_ms() - started < 60
}
