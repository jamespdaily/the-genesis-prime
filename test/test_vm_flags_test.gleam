//// The flags of the VM `./check` starts for the built tests (the `run_built` function of
//// the `check` script).
//// - OTP: `+hmqd off_heap` makes every new process keep its message queue off its heap,
////   read back by `process_info(Pid, message_queue_data)` (`mailbox_support.kept_off_heap`).
////   The VM aborts in `major_collection` after `move_msgs_to_heap`, a step that only a
////   process with an on-heap queue takes.

import gleam/erlang/process
import mailbox_support
import owned_test

pub fn a_test_process_keeps_its_messages_off_its_heap_test() -> Nil {
  use <- owned_test.run(30_000)
  let started = process.new_subject()
  let release = process.new_subject()
  let pid =
    process.spawn(fn() {
      process.send(started, Nil)
      process.receive_forever(release)
    })
  let assert Ok(Nil) = process.receive(started, 30_000)
  let off_heap = mailbox_support.kept_off_heap(pid)
  process.send(release, Nil)
  assert off_heap
    as "a process the test spawns keeps its message queue off its heap"
}
