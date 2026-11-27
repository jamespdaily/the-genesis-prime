//// The flags of every VM that runs the tests, set by ERL_AFLAGS in
//// `setup_check/environment.sh`.
//// - OTP: `+hmqd off_heap` makes every new process keep its message queue off its heap,
////   read back by `process_info(Pid, message_queue_data)` (`mailbox_support.kept_off_heap`).
////   The VM aborts in `major_collection` after `move_msgs_to_heap`, a step that only a
////   process with an on-heap queue takes.

import gleam/erlang/process
import mailbox_support
import owned_test

pub fn a_test_process_keeps_its_messages_off_its_heap_test() -> Nil {
  use <- owned_test.run(10_000)
  let release = process.new_subject()
  let pid = process.spawn(fn() { process.receive_forever(release) })
  let off_heap = mailbox_support.kept_off_heap(pid)
  process.send(release, Nil)
  assert off_heap
    as "a process the test spawns keeps its message queue off its heap"
}
